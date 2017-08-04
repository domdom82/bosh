require 'bosh/director/api/controllers/base_controller'

module Bosh::Director
  module Api::Controllers
    class ConfigsController < BaseController

      get '/', scope: :read do
        if params['latest'].nil? || params['latest'].empty?
          raise ValidationMissingField, "'latest' is required"
        end

        unless ['true', 'false'].include?(params['latest'])
          raise ValidationInvalidValue, "'latest' must be 'true' or 'false'"
        end

        configs = Bosh::Director::Api::ConfigManager.new.find(
          type: params['type'],
          name: params['name'],
          latest: params['latest']
        )

        result = configs.map {|config| sql_to_hash(config)}

        return json_encode(result)
      end

      post '/', :consumes => :yaml do
        if params['type'].nil? || params['type'].empty?
          raise ValidationMissingField, "'type' is required"
        end
        if params['name'].nil? || params['name'].empty?
          raise ValidationMissingField, "'name' is required"
        end

        manifest_text = request.body.read
        begin
          validate_manifest_yml(manifest_text, nil)
          config = Bosh::Director::Api::ConfigManager.new.create(params['type'], params['name'], manifest_text)
          create_event(params['type'], params['name'])
        rescue => e
          create_event(params['type'], params['name'], e)
          raise e
        end

        status(201)
        return json_encode(sql_to_hash(config))
      end

      private

      def create_event(type, name, error = nil)
        @event_manager.create_event({
          user:        current_user,
          action:      'create',
          object_type: "config/#{type}",
          object_name: name,
          error:       error
        })
      end

      def sql_to_hash(config)
        {
            content: config.content,
            id: config.id,
            type: config.type,
            name: config.name
        }
      end
    end
  end
end
