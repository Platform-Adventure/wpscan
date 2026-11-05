# frozen_string_literal: true

module WPScan
  module Cache
    # Cache Implementation using files
    #
    # Entries are stored as JSON, which can only be loaded back into plain data (Hash, Array, String, Numeric etc),
    # so a planted entry can not instantiate arbitrary objects (as Marshal or YAML could).
    #
    # The storage directory (and its parents) must not be writable by other users, see #ensure_secure_storage_path!
    class FileStore
      attr_reader :storage_path

      # @param [ String ] storage_path
      def initialize(storage_path)
        @storage_path = File.expand_path(storage_path)

        FileUtils.mkdir_p(@storage_path, mode: 0o700)
        ensure_secure_storage_path!
      end

      # TODO: rename this to clear ?
      def clean
        Dir[File.join(storage_path, '*')].each do |f|
          File.delete(f) unless File.symlink?(f)
        end
      end

      # @param [ String ] key
      #
      # @return [ Mixed ]
      def read_entry(key)
        return if expired_entry?(key)

        deserialize(JSON.parse(File.read(entry_path(key))))
      rescue StandardError
        nil
      end

      # @param [ String ] key
      # @param [ Mixed ] data_to_store
      # @param [ Integer ] cache_ttl
      def write_entry(key, data_to_store, cache_ttl)
        return unless cache_ttl.to_i.positive?

        File.write(entry_path(key), JSON.generate(serialize(data_to_store)))
        File.write(entry_expiration_path(key), Time.now.to_i + cache_ttl)
      end

      # @param [ String ] key
      #
      # @return [ String ] The file path associated to the key
      def entry_path(key)
        File.join(storage_path, key)
      end

      # @param [ String ] key
      #
      # @return [ String ] The expiration file path associated to the key
      def entry_expiration_path(key)
        "#{entry_path(key)}.expiration"
      end

      protected

      # @param [ Mixed ] data The data to store
      #
      # @return [ Mixed ] A JSON compatible representation of the data
      def serialize(data)
        data
      end

      # @param [ Mixed ] data The parsed JSON of an entry
      #
      # @return [ Mixed ]
      def deserialize(data)
        data
      end

      private

      # @param [ String ] key
      #
      # @return [ Boolean ]
      def expired_entry?(key)
        File.read(entry_expiration_path(key)).to_i <= Time.now.to_i
      rescue StandardError
        true
      end

      # The storage directory must be owned by the current user and not be writable by group/others.
      # Its parents must be owned by the current user or root, and not be writable by others unless the
      # sticky bit is set (like /tmp), otherwise another user could swap the storage directory.
      # Group writable parents are allowed, as they are common with user private groups (umask 002).
      #
      # @raise [ Error::InsecureCacheDirectory ]
      def ensure_secure_storage_path!
        return if Gem.win_platform?

        path = Pathname.new(File.realpath(storage_path))
        stat = path.stat

        check_storage_path_owner!(path, stat)
        check_storage_path_mode!(path, stat)

        path.ascend.drop(1).each { |parent| check_parent_directory!(parent, parent.stat) }
      end

      def check_storage_path_owner!(path, stat)
        return if stat.uid == Process.euid

        raise Error::InsecureCacheDirectory.new(path, 'is not owned by the current user')
      end

      def check_storage_path_mode!(path, stat)
        return if stat.mode.nobits?(0o022)

        raise Error::InsecureCacheDirectory.new(path, 'is writable by group or others')
      end

      def check_parent_directory!(path, stat)
        unless [Process.euid, 0].include?(stat.uid)
          raise Error::InsecureCacheDirectory.new(path, 'is not owned by the current user or root')
        end

        return unless stat.world_writable? && !stat.sticky?

        raise Error::InsecureCacheDirectory.new(path, 'is writable by others and does not have the sticky bit')
      end
    end
  end
end
