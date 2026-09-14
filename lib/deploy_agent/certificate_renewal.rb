# frozen_string_literal: true

require 'openssl'

module DeployAgent
  # Validates and atomically installs a replacement client certificate offered by
  # the Deploy server over the tunnel (see ServerConnection::COMMAND_RENEW_RESPONSE).
  #
  # A renewal is a re-signature of the certificate we already hold: the server
  # re-signs our stored public key under a different CA, keeping the subject and
  # the serial. Our private key is never involved, so a renewed certificate must
  # still pair with the agent.key already on disk.
  #
  # Every check runs before anything touches the filesystem, and the replacement
  # is swapped in with rename(2). A bad agent.crt is not a recoverable state: the
  # agent would fail the TLS handshake on every reconnect and Agent#run gives up
  # and exits the process after four consecutive SSL errors.
  class CertificateRenewal

    class InvalidCertificate < StandardError; end

    def initialize(certificate_path: CERTIFICATE_PATH, key_path: KEY_PATH, ca_path: CA_PATH)
      @certificate_path = certificate_path
      @key_path = key_path
      @ca_path = ca_path
    end

    # Validate a PEM-encoded replacement certificate and install it.
    #
    # Returns the installed OpenSSL::X509::Certificate, or nil when the server
    # offered the certificate we are already using (in which case nothing is
    # written and there is no reason to reconnect).
    #
    # Raises InvalidCertificate - having written nothing at all - if any check
    # fails. The caller keeps its working certificate.
    def install(pem)
      new_certificate = parse(pem)
      validate!(new_certificate)
      return nil if new_certificate.to_der == current_certificate.to_der

      write(new_certificate)
      new_certificate
    end

    private

    def parse(pem)
      raise InvalidCertificate, 'renewal response contained no certificate' if pem.nil? || pem.empty?

      OpenSSL::X509::Certificate.new(pem)
    rescue OpenSSL::OpenSSLError => e
      raise InvalidCertificate, "could not parse the offered certificate: #{e.message}"
    end

    def validate!(new_certificate)
      # Renewal re-signs our public key, it never re-keys us, so the replacement
      # has to pair with the private key we already hold.
      unless new_certificate.check_private_key(private_key)
        raise InvalidCertificate, 'offered certificate does not match the agent private key'
      end

      # The backend identifies this agent by the certificate serial, and the
      # subject carries the agent name. Neither may change across a renewal.
      unless new_certificate.subject == current_certificate.subject
        raise InvalidCertificate,
              "offered certificate has a different subject (#{current_certificate.subject} -> #{new_certificate.subject})"
      end

      unless new_certificate.serial == current_certificate.serial
        raise InvalidCertificate,
              "offered certificate has a different serial (#{current_certificate.serial} -> #{new_certificate.serial})"
      end

      # And it has to chain to a CA we ship *as a TLS client certificate*, or we
      # would be trading a working certificate for one the server refuses on the
      # next handshake - and every handshake after it.
      store = certificate_store
      return if store.verify(new_certificate)

      raise InvalidCertificate, "offered certificate is not a usable client certificate (#{store.error_string})"
    end

    # Write to a private temporary file in the same directory, flush it all the
    # way to disk, then rename over agent.crt so a reader never sees a partial
    # certificate and a crash mid-write cannot destroy the working one.
    def write(certificate)
      temp_path = temporary_path
      begin
        File.open(temp_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(certificate.to_pem)
          file.flush
          file.fsync
        end
        File.rename(temp_path, @certificate_path)
      rescue StandardError
        File.unlink(temp_path) if File.file?(temp_path)
        raise
      end
    end

    def temporary_path
      directory = File.dirname(@certificate_path)
      basename = File.basename(@certificate_path)
      File.join(directory, ".#{basename}.#{Process.pid}.#{rand(0xffffffff).to_s(16)}")
    end

    def current_certificate
      @current_certificate ||= OpenSSL::X509::Certificate.new(File.read(@certificate_path))
    rescue SystemCallError, OpenSSL::OpenSSLError => e
      raise InvalidCertificate, "could not read the current certificate: #{e.message}"
    end

    def private_key
      @private_key ||= OpenSSL::PKey::RSA.new(File.read(@key_path))
    rescue SystemCallError, OpenSSL::OpenSSLError => e
      raise InvalidCertificate, "could not read the agent private key: #{e.message}"
    end

    def certificate_store
      @certificate_store ||= OpenSSL::X509::Store.new.tap do |store|
        store.add_file(@ca_path)
        # The agent presents this certificate for TLS client authentication, so
        # verify it for that purpose rather than the store's default, which
        # accepts anything that merely chains. Real agent certificates carry no
        # extensions at all and this purpose accepts them; what it rejects is a
        # certificate whose keyUsage or extendedKeyUsage rules client auth out
        # (a serverAuth-only certificate, say), which would otherwise install
        # cleanly and then be refused by the server on every reconnect.
        store.purpose = OpenSSL::X509::PURPOSE_SSL_CLIENT
      end
    rescue SystemCallError, OpenSSL::OpenSSLError => e
      raise InvalidCertificate, "could not read the CA bundle: #{e.message}"
    end

  end
end
