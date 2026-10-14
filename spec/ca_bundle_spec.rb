# frozen_string_literal: true

require 'spec_helper'
require 'openssl'

# ca.crt is the trust anchor the agent verifies the Deploy server against. It is
# loaded with SSLContext#ca_file, which reads *every* certificate in the file, so
# it may hold more than one during a CA rotation - an old root and its
# replacement - and the order does not matter. Nothing in this gem ever calls
# OpenSSL::X509::Certificate.new on it (that would silently read only the first
# certificate), and nothing should start.
RSpec.describe 'the bundled CA file' do
  let(:pem) { File.read(DeployAgent::CA_PATH) }

  let(:certificates) do
    pem.scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m)
       .map { |block| OpenSSL::X509::Certificate.new(block) }
  end

  it 'ships at least one certificate' do
    expect(certificates.length).to be >= 1
  end

  it 'loads as a trust bundle' do
    store = OpenSSL::X509::Store.new
    expect { store.add_file(DeployAgent::CA_PATH) }.not_to raise_error
  end

  # A valid self-signature proves the key matches, but says nothing about what
  # the certificate is allowed to be. A trust anchor here must also be issued to
  # itself and actually assert CA:TRUE, or it cannot sign the agent and server
  # certificates this file exists to verify.
  it 'contains only self-signed certificate authorities' do
    certificates.each do |certificate|
      subject = certificate.subject.to_s
      basic_constraints = certificate.extensions.find { |extension| extension.oid == 'basicConstraints' }&.value

      expect(certificate.issuer.to_s).to eq(subject), "#{subject} is not issued to itself"
      expect(certificate.verify(certificate.public_key)).to be(true), "#{subject} is not self-signed"
      expect(basic_constraints).to include('CA:TRUE'),
                                   "#{subject} is not marked as a CA (basicConstraints=#{basic_constraints.inspect})"
    end
  end

  it 'reports what is bundled' do
    certificates.each_with_index do |certificate, index|
      puts format('    ca.crt[%<index>d] subject=%<subject>s expires=%<expiry>s',
                  index: index,
                  subject: certificate.subject.to_s,
                  expiry: certificate.not_after.utc.strftime('%Y-%m-%d %H:%M:%S UTC'))
    end

    expect(certificates).to all(be_a(OpenSSL::X509::Certificate))
  end
end
