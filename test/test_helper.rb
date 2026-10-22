require "minitest/autorun"
require "json"
require "socket"

$LOAD_PATH.unshift File.expand_path("../sdk/lib", __dir__)

# An HTTP server that answers each request with the next scripted reply, so a
# test sees exactly what the SDK sent and controls exactly what it gets back.
class FakeEngine
  Request = Data.define(:path, :headers, :body) do
    def query = JSON.parse(body)["query"]
  end

  attr_reader :requests, :port

  def initialize(replies)
    @replies = replies.dup
    @requests = []
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @thread = Thread.new { serve }
  end

  def self.data(data) = { status: 200, body: JSON.generate(data: data) }

  def self.errors(*errors) = { status: 200, body: JSON.generate(errors: errors, data: nil) }

  def close
    @server.close
    @thread.kill
  end

  private

  def serve
    loop do
      socket = @server.accept
      Thread.new(socket) { handle(it) }
    end
  rescue IOError
    nil
  end

  def handle(socket)
    while (request = read_request(socket))
      @requests << request
      reply = @replies.shift || raise("no reply left for #{request.body}")
      if reply == :drop
        socket.close
        return
      end
      body = reply.fetch(:body)
      socket.write("HTTP/1.1 #{reply.fetch(:status)} X\r\nContent-Type: application/json\r\n" \
                   "Content-Length: #{body.bytesize}\r\n\r\n#{body}")
    end
  rescue IOError, SystemCallError
    nil
  ensure
    socket.close unless socket.closed?
  end

  def read_request(socket)
    line = socket.gets or return nil
    headers = {}
    while (header = socket.gets) && header != "\r\n"
      name, value = header.split(":", 2)
      headers[name.downcase] = value.strip
    end
    Request.new(path: line.split[1], headers:, body: socket.read(headers.fetch("content-length").to_i))
  end
end
