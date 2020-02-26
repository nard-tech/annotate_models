require_relative './schema_info/column'
require_relative './schema_info/index'
require_relative './schema_info/foreign_key'

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

        if klass.table_exists?
          info << Index.generate(klass, options) if options[:show_indexes]
          info << ForeignKey.generate(klass, options) if options[:show_foreign_keys]
        end

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
