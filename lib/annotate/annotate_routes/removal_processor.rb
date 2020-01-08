require_relative './base_processor'

module AnnotateRoutes
  class RemovalProcessor < BaseProcessor
    private

    def generate_new_content_array(content, header_position)
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
  end
end
