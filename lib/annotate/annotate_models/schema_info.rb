require_relative './schema_info/column'
require_relative './schema_info/index'
require_relative './schema_info/foreign_key'

module AnnotateModels
  class SchemaInfo
    END_MARK = '== Schema Information End'.freeze

    class << self
      # Use the column information in an ActiveRecord class
      # to create a comment block containing a line for
      # each column. The line contains the column name,
      # the type (and length), and any optional attributes
      def generate(klass, header, options = {})
        new(klass, header, options).generate
      end

      private :new
    end

    def initialize(klass, header, options)
      @klass = klass
      @header = header
      @options = options
    end

    attr_reader :klass, :header, :options

    def generate
      info = "# #{header}\n"
      info << get_schema_header_text

      info << Column.generate(klass, options)

      if table_exists?
        info << Index.generate(klass, options) if show_indexes?
        info << ForeignKey.generate(klass, options) if show_foreign_keys?
      end

      info << get_schema_footer_text
    end

    private

    def get_schema_header_text
      info = "#\n"
      if markdown?
        info << "# Table name: `#{table_name}`\n"
        info << "#\n"
        info << "# ### Columns\n"
      else
        info << "# Table name: #{table_name}\n"
      end
      info << "#\n"
    end

    def get_schema_footer_text
      info = ''
      if rdoc?
        info << "#--\n"
        info << "# #{END_MARK}\n"
        info << "#++\n"
      else
        info << "#\n"
      end
    end

    def table_exists?
      klass.table_exists?
    end

    def show_indexes?
      options[:show_indexes]
    end

    def show_foreign_keys?
      options[:show_foreign_keys]
    end

    def markdown?
      options[:format_markdown]
    end

    def rdoc?
      options[:format_rdoc]
    end

    def table_name
      klass.table_name
    end
  end
end
