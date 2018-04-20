# Adapted from code orinially Copyright (c) 2013 Jonathan Stott

require 'reel'
require 'reel/rack/handler'

module Reel
  module Rack
    class Server < Reel::Server::HTTP
      include Celluloid::Internals::Logger

      def initialize(app, options)
        raise ArgumentError, "no host given" unless options[:Host]
        raise ArgumentError, "no port given" unless options[:Port]

        info  "A Reel good HTTP server! (Codename \"#{::Reel::CODENAME}\")"
        info "Listening on http://#{options[:Host]}:#{options[:Port]}"

        if options[:Async]
          super(options[:Host], options[:Port]) do |connection|
            connection.detach
            Reel::Rack::Handler.on_connection(app, connection)
          end
        else
          handler = Reel::Rack::Handler.new(app)
          super(options[:Host], options[:Port]) do |connection|
            handler.on_connection(connection)
          end
        end
      end

      def on_connection(connection)
        connection.each_request do |request|
          if request.websocket?
            request.respond :bad_request, "WebSockets not supported"
          else
            route_request request
          end
        end
      end

      # Compile the regex once
      CONTENT_LENGTH_HEADER = %r{^content-length$}i

      def route_request(request)
        options = {
          :method       => request.method,
          :input        => request.body.to_s,
          "REMOTE_ADDR" => request.remote_addr
        }.merge(convert_headers(request.headers))

        normalize_env(options)

        status, headers, body = app.call ::Rack::MockRequest.env_for(request.url, options)

        if body.respond_to? :each
          # If Content-Length was specified we can send the response all at once
          if headers.keys.detect { |h| h =~ CONTENT_LENGTH_HEADER }
            # Can't use collect here because Rack::BodyProxy/Rack::Lint isn't a real Enumerable
            full_body = ''
            body.each { |b| full_body << b }
            request.respond status_symbol(status), headers, full_body
          else
            request.respond status_symbol(status), headers.merge(:transfer_encoding => :chunked)
            body.each { |chunk| request << chunk }
            request.finish_response
          end
        end
      end
    end
  end
end
