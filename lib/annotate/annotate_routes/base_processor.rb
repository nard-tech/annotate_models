module AnnotateRoutes
  class BaseProcessor
    def initialize(options, routes_file)
      @options = options
      @routes_file = routes_file
    end

    def routes_file_exist?
      File.exist?(routes_file)
    end

    private

    attr_reader :options, :routes_file

    def existing_text
      @existing_text ||= File.read(routes_file)
    end

    # @param new_text [String]
    # @return [Boolean]
    def rewrite_contents(new_text)
      if existing_text == new_text
        false
      else
        write(new_text)
        true
      end
    end

    def write(text)
      File.open(routes_file, 'wb') { |f| f.puts(text) }
    end
  end
end
