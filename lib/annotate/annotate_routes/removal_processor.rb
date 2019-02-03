require_relative './helpers'

module AnnotateRoutes
  module RemovalProcessor
    class << self
      # @param routes_file [String]
      # @param existing_text [String]
      # @param _options [Hash]
      def update(routes_file, existing_text, _options)
        content, header_position = Helpers.strip_annotations(existing_text)
        new_content = strip_on_removal(content, header_position)
        new_text = new_content.join("\n")
        rewrite_contents(routes_file, existing_text, new_text)
      end

      private

      def strip_on_removal(content, header_position)
        if header_position == :before
          content.shift while content.first == ''
        elsif header_position == :after
          content.pop while content.last == ''
        end

        # Make sure we end on a trailing newline.
        content << '' unless content.last == ''

        # TODO: If the user buried it in the middle, we should probably see about
        # TODO: preserving a single line of space between the content above and
        # TODO: below...
        content
      end

      # @param routes_file [String]
      # @param existing_text [String]
      # @param new_text [String]
      # @return [Boolean]
      def rewrite_contents(routes_file, existing_text, new_text)
        if existing_text == new_text
          false
        else
          File.open(routes_file, 'wb') { |f| f.puts(new_text) }
          true
        end
      end
    end
  end
end
