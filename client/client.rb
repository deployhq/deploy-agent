require 'socket'

class TCPSocket
  alias_method :initialize_without_proxy, :initialize
  def initialize(remote_host, remote_port, local_host=nil, local_port=nil)
    if self.class.proxy_host && self.class.proxy_port && self.class.proxy_cn
      initialize_without_proxy(self.class.proxy_host, self.class.proxy_port)
      command = "#{self.class.proxy_cn}/#{remote_host}/#{remote_port}"
      self.write([command.bytesize + 2].pack('n') + command)
      length = self.read(2).unpack('n')[0]
      state = self.read(1).unpack('C')[0]
      if length > 3
        raise self.read(length-3)
      end
    else
      initialize_without_proxy(remote_host, remote_port, local_host, local_port)
    end
  end
  class << self
    attr_accessor :proxy_host, :proxy_port, :proxy_cn
    def enable_proxy(proxy_host, proxy_port, proxy_cn)
      TCPSocket.proxy_host = proxy_host
      TCPSocket.proxy_port = proxy_port
      TCPSocket.proxy_cn = proxy_cn
    end
    def disable_proxy
      TCPSocket.proxy_host = nil
      TCPSocket.proxy_port = nil
      TCPSocket.proxy_cn = nil
    end
  end
end

TCPSocket.enable_proxy('127.0.0.1', 7766, 'charlie.office.atech.io')

sock = TCPSocket.new('216.58.212.110', 80)
sock.write("GET / HTTP/1.1\r\nHost: google.com\r\nConnection: close\r\n\r\n")
puts sock.read
sock.close

sock = TCPSocket.new('127.0.0.1', 9999)

TCPSocket.disable_proxy
