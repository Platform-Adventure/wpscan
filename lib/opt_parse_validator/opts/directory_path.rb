# frozen_string_literal: true

module OptParseValidator
  # Implemetantion of the DirectoryPath Option
  class OptDirectoryPath < OptPath
    def initialize(option, attrs = {})
      super

      @attrs.merge!(directory: true)
    end

    # Uses attrs[:mode], if set, as the mode of the created directories
    #
    # @param [ Pathname ] path
    def check_create(path)
      FileUtils.mkdir_p(path.to_s, **attrs.slice(:mode))
    end
  end
end
