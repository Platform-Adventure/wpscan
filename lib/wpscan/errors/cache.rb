# frozen_string_literal: true

module WPScan
  module Error
    # Error raised when the cache directory, or one of its parents, could be tampered with by another user
    class InsecureCacheDirectory < Standard
      attr_reader :path, :reason

      def initialize(path, reason)
        @path   = path
        @reason = reason
        super()
      end

      def to_s
        "Refusing to use the cache directory: #{path} #{reason}. " \
          'Fix its ownership/permissions or use another one via --cache-dir.'
      end
    end
  end
end
