require 'socket'

sock = TCPSocket.new('127.0.0.1', 7766)
command = "charlie.office.atech.io/127.0.0.1/3000"
sock.write([command.bytesize + 2].pack('n') + command)
sleep
