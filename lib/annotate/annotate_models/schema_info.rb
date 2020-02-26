require_relative './schema_info/column'
require_relative './schema_info/index'

module AnnotateModels
  module SchemaInfo
    END_MARK = '== Schema Information End'.freeze

    class << self
      # Use the column information in an ActiveRecord class
      # to create a comment block containing a line for
      # each column. The line contains the column name,
      # the type (and length), and any optional attributes
      def generate(klass, header, options = {})
        info = "# #{header}\n"
        info << get_schema_header_text(klass, options)

        info << Column.generate(klass, options)

        info << Index.generate(klass, options) if options[:show_indexes] && klass.table_exists?

        info << get_foreign_key_info(klass, options) if options[:show_foreign_keys] && klass.table_exists?

        info << get_schema_footer_text(klass, options)
      end

      private

      def get_schema_header_text(klass, options = {})
        info = "#\n"
        if options[:format_markdown]
          info << "# Table name: `#{klass.table_name}`\n"
          info << "#\n"
          info << "# ### Columns\n"
        else
          info << "# Table name: #{klass.table_name}\n"
        end
        info << "#\n"
      end

      def get_foreign_key_info(klass, options = {})
        fk_info = if options[:format_markdown]
                    "#\n# ### Foreign Keys\n#\n"
                  else
                    "#\n# Foreign Keys\n#\n"
                  end

        return '' unless klass.connection.respond_to?(:supports_foreign_keys?) &&
                         klass.connection.supports_foreign_keys? && klass.connection.respond_to?(:foreign_keys)

        foreign_keys = klass.connection.foreign_keys(klass.table_name)
        return '' if foreign_keys.empty?

        format_name = lambda do |fk|
          return fk.options[:column] if fk.name.blank?

          options[:show_complete_foreign_keys] ? fk.name : fk.name.gsub(/(?<=^fk_rails_)[0-9a-f]{10}$/, '...')
        end

        max_size = foreign_keys.map(&format_name).map(&:size).max + 1
        foreign_keys.sort_by { |fk| [format_name.call(fk), fk.column] }.each do |fk|
          ref_info = "#{fk.column} => #{fk.to_table}.#{fk.primary_key}"
          constraints_info = ''
          constraints_info += "ON DELETE => #{fk.on_delete} " if fk.on_delete
          constraints_info += "ON UPDATE => #{fk.on_update} " if fk.on_update
          constraints_info.strip!

          fk_info << if options[:format_markdown]
                       format("# * `%s`%s:\n#     * **`%s`**\n",
                              format_name.call(fk),
                              constraints_info.blank? ? '' : " (_#{constraints_info}_)",
                              ref_info)
                     else
                       format("#  %-#{max_size}.#{max_size}s %s %s",
                              format_name.call(fk),
                              "(#{ref_info})",
                              constraints_info).rstrip + "\n"
                     end
        end

        fk_info
      end

      def get_schema_footer_text(_klass, options = {})
        info = ''
        if options[:format_rdoc]
          info << "#--\n"
          info << "# #{END_MARK}\n"
          info << "#++\n"
        else
          info << "#\n"
        end
      end
    end
  end
end
