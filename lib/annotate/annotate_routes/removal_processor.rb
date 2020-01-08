require_relative './base_processor'
require_relative './helpers'

module AnnotateRoutes
  class RemovalProcessor < BaseProcessor
    # @return [Boolean]
    def update
      content, header_position = Helpers.strip_annotations(existing_text)
      new_content = strip_on_removal(content, header_position)
      new_text = new_content.join("\n")
      rewrite_contents(new_text)
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
  end
end
