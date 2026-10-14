# frozen_string_literal: true

require 'spec_helper'

# Exercises the real rx_data packet-dispatch loop with a pre-filled receive
# buffer, so the renewal command can be driven without a socket, a TLS handshake
# or a Deploy server. The connection is allocated rather than constructed for the
# same reason: #initialize opens a TCP socket.
RSpec.describe DeployAgent::ServerConnection do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:agent) { instance_double(DeployAgent::Agent, logger: logger) }
  let(:nio_selector) { double('nio_selector', deregister: nil) }
  let(:nio_monitor) { double('nio_monitor') }
  let(:tcp_socket) { double('tcp_socket', close: nil) }

  let(:socket) do
    socket = double('socket', close: nil)
    allow(socket).to receive(:read_nonblock) do
      error = StandardError.new('would block')
      error.extend(IO::WaitReadable)
      raise error
    end
    socket
  end

  let(:connection) do
    connection = described_class.allocate
    connection.instance_variable_set(:@agent, agent)
    connection.instance_variable_set(:@destination_connections, {})
    connection.instance_variable_set(:@nio_selector, nio_selector)
    connection.instance_variable_set(:@nio_monitor, nio_monitor)
    connection.instance_variable_set(:@socket, socket)
    connection.instance_variable_set(:@tcp_socket, tcp_socket)
    connection.instance_variable_set(:@tx_buffer, String.new.force_encoding('BINARY'))
    connection.instance_variable_set(:@rx_buffer, String.new.force_encoding('BINARY'))
    connection
  end

  let(:renewal) { instance_double(DeployAgent::CertificateRenewal) }

  let(:certificate_pem) { "-----BEGIN CERTIFICATE-----\nrenewed\n-----END CERTIFICATE-----\n" }

  before do
    allow(nio_monitor).to receive(:interests=)
    allow(DeployAgent::CertificateRenewal).to receive(:new).and_return(renewal)
  end

  # Wire frame: [total length including these two bytes][payload]. Mirrors send_packet.
  def frame(payload)
    [payload.bytesize + 2, payload].pack('na*')
  end

  def renewal_response(status, body = '')
    frame([described_class::COMMAND_RENEW_RESPONSE, status, body].pack('CCa*'))
  end

  # Command 3 for an id that was never opened: logs and no-ops. Used as a trailing
  # frame to prove the preceding one left the stream in sync.
  def benign_frame
    frame([3, 999].pack('Cn'))
  end

  def benign_frame_processed?
    begin
      expect(logger).to have_received(:info).with('[999] Close requested by server, not open')
    rescue RSpec::Expectations::ExpectationNotMetError
      return false
    end
    true
  end

  def deliver(*frames)
    connection.instance_variable_set(:@rx_buffer, frames.join.force_encoding('BINARY'))
    connection.rx_data
  end

  describe 'protocol constants' do
    it 'matches the contract shared with the backend and the Go agent' do
      expect(described_class::COMMAND_RENEW_REQUEST).to eq(8)
      expect(described_class::COMMAND_RENEW_RESPONSE).to eq(9)
      expect(described_class::RENEW_STATUS_RENEWED).to eq(0)
      expect(described_class::RENEW_STATUS_CURRENT).to eq(1)
      expect(described_class::RENEW_STATUS_ERROR).to eq(2)
    end
  end

  describe '#request_certificate_renewal' do
    it 'queues command 8 carrying the agent implementation and version' do
      connection.send(:request_certificate_renewal)

      expect(connection.instance_variable_get(:@tx_buffer))
        .to eq(frame([8, "ruby/#{DeployAgent::VERSION}"].pack('Ca*')))
    end

    it 'arms the monitor for writing' do
      connection.send(:request_certificate_renewal)

      expect(nio_monitor).to have_received(:interests=).with(:rw)
    end

    it 'logs and continues when the request cannot be queued' do
      connection.instance_variable_set(:@nio_monitor, nil)

      expect { connection.send(:request_certificate_renewal) }.not_to raise_error
      expect(logger).to have_received(:warn).with(/Could not request certificate renewal/)
    end
  end

  describe '#rx_data' do
    context 'with a renewal response of status 0 (renewed)' do
      let(:certificate) { double('certificate', issuer: 'CN=Deploy CA (new)') }

      before do
        allow(renewal).to receive(:install).and_return(certificate)
      end

      it 'installs the certificate it was sent' do
        begin
          deliver(renewal_response(0, certificate_pem))
        rescue described_class::ServerDisconnected
          nil
        end

        expect(renewal).to have_received(:install).with(certificate_pem)
      end

      it 'disconnects so the new certificate is presented on reconnect' do
        expect { deliver(renewal_response(0, certificate_pem)) }
          .to raise_error(described_class::ServerDisconnected)
      end

      it 'logs the new issuer' do
        begin
          deliver(renewal_response(0, certificate_pem))
        rescue described_class::ServerDisconnected
          nil
        end

        expect(logger).to have_received(:info).with('Certificate renewed (issuer=CN=Deploy CA (new))')
      end
    end

    context 'with a renewal response of status 0 offering the certificate already held' do
      before do
        allow(renewal).to receive(:install).and_return(nil)
      end

      it 'stays connected' do
        expect { deliver(renewal_response(0, certificate_pem)) }.not_to raise_error
      end

      it 'keeps processing the stream' do
        deliver(renewal_response(0, certificate_pem), benign_frame)

        expect(benign_frame_processed?).to be(true)
      end
    end

    context 'with a renewal response of status 1 (current)' do
      it 'does not attempt an install' do
        deliver(renewal_response(1))

        expect(DeployAgent::CertificateRenewal).not_to have_received(:new)
      end

      it 'stays connected and keeps processing the stream' do
        expect { deliver(renewal_response(1), benign_frame) }.not_to raise_error
        expect(benign_frame_processed?).to be(true)
      end
    end

    context 'with a renewal response of status 2 (error)' do
      it 'logs the server message without attempting an install' do
        deliver(renewal_response(2, 'no replacement available'))

        expect(logger).to have_received(:warn).with('Server could not renew our certificate: no replacement available')
        expect(DeployAgent::CertificateRenewal).not_to have_received(:new)
      end

      it 'stays connected and keeps processing the stream' do
        expect { deliver(renewal_response(2, 'boom'), benign_frame) }.not_to raise_error
        expect(benign_frame_processed?).to be(true)
      end
    end

    context 'with a renewal response carrying an unknown status' do
      it 'logs and stays connected' do
        expect { deliver(renewal_response(200), benign_frame) }.not_to raise_error
        expect(logger).to have_received(:warn).with(/Unknown certificate renewal status/)
        expect(benign_frame_processed?).to be(true)
      end
    end

    context 'when the offered certificate is rejected' do
      before do
        allow(renewal).to receive(:install)
          .and_raise(DeployAgent::CertificateRenewal::InvalidCertificate, 'offered certificate has a different serial')
      end

      it 'keeps the working certificate and stays connected' do
        expect { deliver(renewal_response(0, certificate_pem)) }.not_to raise_error
        expect(logger)
          .to have_received(:warn).with('Certificate renewal failed: offered certificate has a different serial')
      end

      it 'keeps processing the stream' do
        deliver(renewal_response(0, certificate_pem), benign_frame)

        expect(benign_frame_processed?).to be(true)
      end
    end

    context 'when the renewal handler hits an unexpected error' do
      before do
        allow(renewal).to receive(:install).and_raise(Errno::EACCES, 'agent.crt')
      end

      it 'never lets it escape rx_data' do
        expect { deliver(renewal_response(0, certificate_pem), benign_frame) }.not_to raise_error
        expect(logger).to have_received(:warn).with(/Certificate renewal failed/)
        expect(benign_frame_processed?).to be(true)
      end
    end

    context 'with a command this version does not know' do
      it 'ignores it without desynchronising the stream' do
        expect { deliver(frame([200].pack('C')), benign_frame) }.not_to raise_error
        expect(benign_frame_processed?).to be(true)
      end
    end
  end
end
