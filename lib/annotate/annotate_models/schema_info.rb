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

        max_size = max_schema_info_width(klass, options)
        md_names_overhead = 6
        md_type_allowance = 18

        if options[:format_markdown]
          info << format("# %-#{max_size + md_names_overhead}.#{max_size + md_names_overhead}s | %-#{md_type_allowance}.#{md_type_allowance}s | %s\n",
                         'Name',
                         'Type',
                         'Attributes')
          info << "# #{'-' * (max_size + md_names_overhead)} | #{'-' * md_type_allowance} | #{'-' * 27}\n"
        end

        cols = columns(klass, options)
        cols.each do |col|
          info << Column.generate_for_each_col(klass, options, max_size, col, md_type_allowance)
        end

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

      def max_schema_info_width(klass, options)
        cols = columns(klass, options)

        if with_comments?(klass, options)
          max_size = cols.map do |column|
            column.name.size + (column.comment ? width(column.comment) : 0)
          end.max || 0
          max_size += 2
        else
          max_size = cols.map(&:name).map(&:size).max
        end
        max_size += options[:format_rdoc] ? 5 : 1

        max_size
      end

      def with_comments?(klass, options)
        options[:with_comment] &&
          klass.columns.first.respond_to?(:comment) &&
          klass.columns.map(&:comment).any? { |comment| !comment.nil? }
      end

      def classified_sort(cols)
        rest_cols = []
        timestamps = []
        associations = []
        id = nil

        cols.each do |c|
          if c.name.eql?('id')
            id = c
          elsif c.name.eql?('created_at') || c.name.eql?('updated_at')
            timestamps << c
          elsif c.name[-3, 3].eql?('_id')
            associations << c
          else
            rest_cols << c
          end
        end
        [rest_cols, timestamps, associations].each { |a| a.sort_by!(&:name) }

        ([id] << rest_cols << timestamps << associations).flatten.compact
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

      def width(string)
        string.chars.inject(0) { |acc, elem| acc + (elem.bytesize == 3 ? 2 : 1) }
      end

      def columns(klass, options)
        cols = klass.columns
        cols += translated_columns(klass)

        ignore_columns = options[:ignore_columns]
        if ignore_columns
          cols = cols.reject do |col|
            col.name.match(/#{ignore_columns}/)
          end
        end

        cols = cols.sort_by(&:name) if options[:sort]
        cols = classified_sort(cols) if options[:classified_sort]

        cols
      end

      ##
      # Add columns managed by the globalize gem if this gem is being used.
      def translated_columns(klass)
        return [] unless klass.respond_to? :translation_class

        ignored_cols = ignored_translation_table_colums(klass)
        klass.translation_class.columns.reject do |col|
          ignored_cols.include? col.name.to_sym
        end
      end

      ##
      # These are the columns that the globalize gem needs to work but
      # are not necessary for the models to be displayed as annotations.
      def ignored_translation_table_colums(klass)
        # Construct the foreign column name in the translations table
        # eg. Model: Car, foreign column name: car_id
        foreign_column_name = [
          klass.translation_class.to_s
               .gsub('::Translation', '').gsub('::', '_')
               .downcase,
          '_id'
        ].join.to_sym

        [
          :id,
          :created_at,
          :updated_at,
          :locale,
          foreign_column_name
        ]
      end
    end
  end
end
