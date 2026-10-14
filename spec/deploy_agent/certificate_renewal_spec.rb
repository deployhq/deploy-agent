# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'openssl'
require 'tmpdir'

# RSA key generation is slow and none of these fixtures depend on per-example
# state, so they are built once for the whole file.
module CertificateRenewalFixtures
  TEN_YEARS = 10 * 365 * 86_400
  KEY_BITS = 2048 # production uses 4096; key size is irrelevant to what is under test

  module_function

  def key(name)
    cache[:"key_#{name}"] ||= OpenSSL::PKey::RSA.new(KEY_BITS)
  end

  # Mirrors deployhq's lib/certificate_authority.rb.
  def authority(name)
    cache[:"ca_#{name}"] ||= begin
      subject = OpenSSL::X509::Name.new([['CN', "Deploy Test CA (#{name})"]])
      certificate = OpenSSL::X509::Certificate.new
      certificate.not_before = Time.now - 60
      certificate.not_after = Time.now + TEN_YEARS
      certificate.serial = 1
      certificate.version = 2
      certificate.subject = subject
      certificate.issuer = subject
      certificate.public_key = key("ca_#{name}").public_key
      factory = OpenSSL::X509::ExtensionFactory.new
      factory.subject_certificate = certificate
      factory.issuer_certificate = certificate
      certificate.add_extension(factory.create_extension('basicConstraints', 'CA:TRUE', true))
      certificate.add_extension(factory.create_extension('keyUsage', 'cRLSign,keyCertSign', true))
      certificate.sign(key("ca_#{name}"), OpenSSL::Digest.new('SHA256'))
      certificate
    end
  end

  # Mirrors deployhq's Agent#generate_crypto: no extensions, serial = agent id.
  # +extensions+ is only used to build the certificates a renewal must refuse.
  def agent_certificate(authority_name, public_key, serial: 42, common_name: 'Deploy Agent #42', extensions: [])
    certificate = OpenSSL::X509::Certificate.new
    certificate.not_before = Time.now - 60
    certificate.not_after = Time.now + TEN_YEARS
    certificate.subject = OpenSSL::X509::Name.new([['CN', common_name]])
    certificate.serial = serial
    certificate.version = 2
    certificate.public_key = public_key
    certificate.issuer = authority(authority_name).subject
    add_extensions(certificate, authority_name, extensions)
    certificate.sign(key("ca_#{authority_name}"), OpenSSL::Digest.new('SHA256'))
    certificate
  end

  def add_extensions(certificate, authority_name, extensions)
    return if extensions.empty?

    factory = OpenSSL::X509::ExtensionFactory.new
    factory.subject_certificate = certificate
    factory.issuer_certificate = authority(authority_name)
    extensions.each do |oid, value, critical|
      certificate.add_extension(factory.create_extension(oid, value, critical))
    end
  end

  def cache
    @cache ||= {}
  end
end

RSpec.describe DeployAgent::CertificateRenewal do
  fixtures = CertificateRenewalFixtures

  # The agent's own key pair, which a renewal must never change.
  let(:agent_key) { fixtures.key('agent') }

  # What the agent holds today, and what the backend would send back after
  # re-signing the same public key under the new CA.
  let(:current_certificate) { fixtures.agent_certificate('old', agent_key.public_key) }
  let(:renewed_certificate) { fixtures.agent_certificate('new', agent_key.public_key) }

  let(:config_dir) { Dir.mktmpdir('deploy-agent-renewal') }
  let(:certificate_path) { File.join(config_dir, 'agent.crt') }
  let(:key_path) { File.join(config_dir, 'agent.key') }
  let(:ca_path) { File.join(config_dir, 'ca.crt') }

  let(:renewal) do
    described_class.new(certificate_path: certificate_path, key_path: key_path, ca_path: ca_path)
  end

  before do
    File.write(certificate_path, current_certificate.to_pem)
    File.write(key_path, agent_key.to_pem)
    # The shipped bundle during the migration window: both roots are trusted.
    File.write(ca_path, fixtures.authority('old').to_pem + fixtures.authority('new').to_pem)
  end

  after do
    FileUtils.remove_entry(config_dir)
  end

  # Swallow the rejection so the example can assert on the side effects instead.
  def attempt(renewal, pem)
    renewal.install(pem)
  rescue DeployAgent::CertificateRenewal::InvalidCertificate
    nil
  end

  describe '#install' do
    context 'with a certificate re-signed under the new CA' do
      it 'returns the installed certificate' do
        expect(renewal.install(renewed_certificate.to_pem).to_der).to eq(renewed_certificate.to_der)
      end

      # Real agent certificates carry no extensions at all, so the client-auth
      # purpose the trust store is pinned to must not reject them.
      it 'accepts a certificate with no extensions, which is what the backend issues' do
        expect(renewed_certificate.extensions).to be_empty
        expect(renewal.install(renewed_certificate.to_pem)).not_to be_nil
      end

      it 'accepts a certificate that explicitly allows client authentication' do
        offered = fixtures.agent_certificate('new', agent_key.public_key,
                                             extensions: [['extendedKeyUsage', 'clientAuth', false]])

        expect(renewal.install(offered.to_pem)).not_to be_nil
      end

      it 'writes it to the certificate path' do
        renewal.install(renewed_certificate.to_pem)

        installed = OpenSSL::X509::Certificate.new(File.read(certificate_path))
        expect(installed.to_der).to eq(renewed_certificate.to_der)
      end

      it 'preserves the identity the backend keys off' do
        renewal.install(renewed_certificate.to_pem)

        installed = OpenSSL::X509::Certificate.new(File.read(certificate_path))
        expect(installed.serial).to eq(current_certificate.serial)
        expect(installed.subject.to_s).to eq(current_certificate.subject.to_s)
      end

      it 'installs a certificate issued by the new CA' do
        renewal.install(renewed_certificate.to_pem)

        installed = OpenSSL::X509::Certificate.new(File.read(certificate_path))
        expect(installed.issuer.to_s).to eq(fixtures.authority('new').subject.to_s)
        expect(installed.issuer.to_s).not_to eq(current_certificate.issuer.to_s)
      end

      it 'still pairs with the untouched agent private key' do
        key_before = File.binread(key_path)
        renewal.install(renewed_certificate.to_pem)

        installed = OpenSSL::X509::Certificate.new(File.read(certificate_path))
        expect(installed.check_private_key(agent_key)).to be(true)
        expect(File.binread(key_path)).to eq(key_before)
      end

      it 'writes a file that is not readable by group or other' do
        renewal.install(renewed_certificate.to_pem)

        expect(File.stat(certificate_path).mode & 0o077).to eq(0)
      end

      it 'leaves no temporary files behind' do
        renewal.install(renewed_certificate.to_pem)

        expect(Dir.children(config_dir).sort).to eq(['agent.crt', 'agent.key', 'ca.crt'])
      end
    end

    context 'when the server offers the certificate already installed' do
      it 'returns nil' do
        expect(renewal.install(current_certificate.to_pem)).to be_nil
      end

      it 'does not rewrite the file' do
        before_bytes = File.binread(certificate_path)
        renewal.install(current_certificate.to_pem)

        expect(File.binread(certificate_path)).to eq(before_bytes)
      end
    end

    shared_examples 'a rejected renewal' do |message|
      it 'raises InvalidCertificate' do
        expect { renewal.install(offered_pem) }
          .to raise_error(DeployAgent::CertificateRenewal::InvalidCertificate, message)
      end

      it 'leaves the existing certificate byte-identical' do
        before_bytes = File.binread(certificate_path)
        attempt(renewal, offered_pem)

        expect(File.binread(certificate_path)).to eq(before_bytes)
      end

      it 'leaves no temporary files behind' do
        attempt(renewal, offered_pem)

        expect(Dir.children(config_dir).sort).to eq(['agent.crt', 'agent.key', 'ca.crt'])
      end
    end

    context 'when the certificate does not match the agent private key' do
      let(:offered_pem) { fixtures.agent_certificate('new', fixtures.key('impostor').public_key).to_pem }

      include_examples 'a rejected renewal', /does not match the agent private key/
    end

    context 'when the serial has changed' do
      let(:offered_pem) { fixtures.agent_certificate('new', agent_key.public_key, serial: 99).to_pem }

      include_examples 'a rejected renewal', /different serial/
    end

    context 'when the subject has changed' do
      let(:offered_pem) do
        fixtures.agent_certificate('new', agent_key.public_key, common_name: 'Deploy Agent #99').to_pem
      end

      include_examples 'a rejected renewal', /different subject/
    end

    context 'when the issuer is not in the bundled CA file' do
      let(:offered_pem) { fixtures.agent_certificate('rogue', agent_key.public_key).to_pem }

      include_examples 'a rejected renewal', /not a usable client certificate/
    end

    # These chain to the trusted new CA and keep subject, serial and public key,
    # so they clear every other check. Only the trust store's client-auth purpose
    # catches them - and if it did not, the agent would install a certificate the
    # server then refuses on every single reconnect.
    context 'when the extended key usage rules out client authentication' do
      let(:offered_pem) do
        fixtures.agent_certificate('new', agent_key.public_key,
                                   extensions: [['extendedKeyUsage', 'serverAuth', true]]).to_pem
      end

      include_examples 'a rejected renewal', /not a usable client certificate/
    end

    context 'when the key usage rules out client authentication' do
      let(:offered_pem) do
        fixtures.agent_certificate('new', agent_key.public_key,
                                   extensions: [['keyUsage', 'keyEncipherment', true]]).to_pem
      end

      include_examples 'a rejected renewal', /not a usable client certificate/
    end

    context 'when the payload is not a certificate' do
      let(:offered_pem) { "-----BEGIN CERTIFICATE-----\nnot base64 at all\n-----END CERTIFICATE-----\n" }

      include_examples 'a rejected renewal', /could not parse the offered certificate/
    end

    context 'when the payload is empty' do
      let(:offered_pem) { '' }

      include_examples 'a rejected renewal', /contained no certificate/
    end

    context 'when the payload is nil' do
      let(:offered_pem) { nil }

      include_examples 'a rejected renewal', /contained no certificate/
    end
  end
end
