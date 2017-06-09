module Bosh::Director
  # Remote procedure call client wrapping NATS
  class NatsRpc

    def initialize(nats_uri, nats_server_ca_path)
      @nats_uri = nats_uri
      @nats_server_ca_path = nats_server_ca_path
      @logger = Config.logger
      @lock = Mutex.new
      @inbox_name = "director.#{Config.process_uuid}"
      @requests = {}
    end

    # Publishes a payload (encoded as JSON) without expecting a response
    def send_message(client, payload)
      message = JSON.generate(payload)
      @logger.debug("SENT: #{client} #{message}")

      EM.schedule do
        nats.publish(client, message)
      end
    end

    # Sends a request (encoded as JSON) and listens for the response
    def send_request(client, request, &callback)
      request_id = generate_request_id
      request["reply_to"] = "#{@inbox_name}.#{request_id}"
      @lock.synchronize do
        @requests[request_id] = callback
      end
      message = JSON.generate(request)
      @logger.debug("SENT: #{client} #{message}")

      EM.schedule do
        was_unsubscribed = @subject_id.nil?
        if was_unsubscribed
          subscribe_inbox
          nats.flush do
            nats.publish(client, message)
          end
        else
          nats.publish(client, message)
        end
      end
      request_id
    end

    # Stops listening for a response
    def cancel_request(request_id)
      @lock.synchronize { @requests.delete(request_id) }
    end

    private

    def generate_request_id
      SecureRandom.uuid
    end

    # Returns a lazily connected NATS client
    def nats
      begin
        @nats ||= connect
      rescue Exception => e
        raise "An error has occurred while connecting to NATS: #{e}"
      end
    end

    def connect
      if @nats.nil?
        NATS.on_error do |e|
          password = @nats_uri[/nats:\/\/.*:(.*)@/, 1]
          redacted_message = password.nil? ? "NATS client error: #{e}" : "NATS client error: #{e}".gsub(password, '*******')
          @logger.error(redacted_message)
        end
        @nats = NATS.connect(uri: @nats_uri, ssl: true, tls: {ca_file: @nats_server_ca_path} )
      end
      @nats
    end

    # subscribe to an inbox, if not already subscribed
    def subscribe_inbox
      if @subject_id.nil?
        client = nats
        @subject_id = client.subscribe("#{@inbox_name}.>") do |message, _, subject|
          handle_response(message, subject)
        end
      end
    end

    def handle_response(message, subject)
      @logger.debug("RECEIVED: #{subject} #{message}")
      begin
        request_id = subject.split(".").last
        callback = @lock.synchronize { @requests.delete(request_id) }
        if callback
          message = message.empty? ? nil : JSON.parse(message)
          callback.call(message)
        end
      rescue Exception => e
        @logger.warn(e.message)
      end
    end

  end
end
