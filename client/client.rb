require 'socket'

sock = TCPSocket.new('127.0.0.1', 7766)
command = "charlie.office.atech.io/127.0.0.1/3333"
sock.write([command.bytesize + 2].pack('n') + command)
length = sock.read(2).unpack('n')[0]
state = sock.read(1).unpack('C')[0]
if length > 3
  puts sock.read(length-3)
end
sock.close

sock = TCPSocket.new('127.0.0.1', 7766)
command = "charlie.office.atech.io/google.com/80"
sock.write([command.bytesize + 2].pack('n') + command)
length = sock.read(2).unpack('n')[0]
state = sock.read(1).unpack('C')[0]
if length > 3
  puts sock.read(length-3)
end

while sock.read(9999)
end
