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

  it 'contains only self-signed roots' do
    certificates.each do |certificate|
      expect(certificate.verify(certificate.public_key)).to be(true), "#{certificate.subject} is not self-signed"
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
