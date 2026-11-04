# frozen_string_literal: true

require 'wpscan/cache/file_store'

module WPScan
  module Cache
    # Cache implementation for Typhoeus
    class Typhoeus < FileStore
      # Response informations (as mirrored by Ethon) with a scalar value, that are kept in the cache
      SCALAR_OPTIONS = Ethon::Easy::Informations::AVAILABLE_INFORMATIONS.keys.freeze

      # Response options with a String value which may not be valid UTF-8, stored Base64 encoded
      BINARY_OPTIONS = %i[response_headers response_body].freeze

      # @param [ Typhoeus::Request ] request
      #
      # @return [ Typhoeus::Response ]
      def get(request)
        read_entry(request.hash.to_s)
      end

      # @param [ Typhoeus::Request ] request
      # @param [ Typhoeus::Response ] response
      def set(request, response)
        return if response.timed_out? || response.code&.zero?

        write_entry(request.hash.to_s, response, request.cache_ttl)
      end

      protected

      # @param [ Typhoeus::Response ] response
      #
      # @return [ Hash ]
      def serialize(response)
        data = { 'return_code' => response.return_code&.to_s }

        # The accessors are used (rather than the options) as mocked responses use aliases (e.g. :code, :body)
        (SCALAR_OPTIONS + BINARY_OPTIONS).each do |option|
          next unless response.respond_to?(option)

          value = response.public_send(option)

          if BINARY_OPTIONS.include?(option)
            next unless value.is_a?(String)

            data[option.to_s] = { 'encoding' => value.encoding.name, 'data' => [value].pack('m0') }
          elsif value.is_a?(String) || value.is_a?(Numeric)
            data[option.to_s] = value
          end
        end

        data
      end

      # @param [ Hash ] data
      #
      # @return [ Typhoeus::Response ]
      def deserialize(data)
        options = { return_code: data['return_code']&.to_sym }

        SCALAR_OPTIONS.each do |option|
          value = data[option.to_s]

          options[option] = value if value.is_a?(String) || value.is_a?(Numeric)
        end

        BINARY_OPTIONS.each do |option|
          value = data[option.to_s]
          next unless value.is_a?(Hash)

          options[option] = value.fetch('data').unpack1('m0').force_encoding(Encoding.find(value.fetch('encoding')))
        end

        ::Typhoeus::Response.new(options)
      end
    end
  end
end
