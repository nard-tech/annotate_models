module AnnotateModels
  class SchemaInfo
    module Column
      # Don't show default value for these column types
      NO_DEFAULT_COL_TYPES = %w[json jsonb hstore].freeze

      # Don't show limit (#) on these column types
      # Example: show "integer" instead of "integer(4)"
      NO_LIMIT_COL_TYPES = %w[integer bigint boolean].freeze

      MD_NAMES_OVERHEAD = 6
      MD_TYPE_ALLOWANCE = 18
      BARE_TYPE_ALLOWANCE = 16

      class << self
        def generate(klass, options)
          info = ''

          max_size = max_schema_info_width(klass, options)

          if options[:format_markdown]
            info << format("# %-#{max_size + MD_NAMES_OVERHEAD}.#{max_size + MD_NAMES_OVERHEAD}s | %-#{MD_TYPE_ALLOWANCE}.#{MD_TYPE_ALLOWANCE}s | %s\n",
                           'Name',
                           'Type',
                           'Attributes')
            info << "# #{'-' * (max_size + MD_NAMES_OVERHEAD)} | #{'-' * MD_TYPE_ALLOWANCE} | #{'-' * 27}\n"
          end

          cols = columns(klass, options)
          cols.each do |col|
            info << generate_for_each_col(klass, options, max_size, col)
          end

          info
        end

        def generate_for_each_col(klass, options, max_size, col)
          col_type = get_col_type(col)

          attrs = []
          info = ''

          attrs << "default(#{schema_default(klass, col)})" unless col.default.nil? || hide_default?(col_type, options)
          attrs << 'unsigned' if col.respond_to?(:unsigned?) && col.unsigned?
          attrs << 'not null' unless col.null
          attrs << 'primary key' if klass.primary_key && (klass.primary_key.is_a?(Array) ? klass.primary_key.collect(&:to_sym).include?(col.name.to_sym) : col.name.to_sym == klass.primary_key.to_sym)

          if col_type == 'decimal'
            col_type << "(#{col.precision}, #{col.scale})"
          elsif !%w[spatial geometry geography].include?(col_type)
            if col.limit && !options[:format_yard]
              if col.limit.is_a? Array
                attrs << "(#{col.limit.join(', ')})"
              else
                col_type << "(#{col.limit})" unless hide_limit?(col_type, options)
              end
            end
          end

          # Check out if we got an array column
          attrs << 'is an Array' if col.respond_to?(:array) && col.array

          # Check out if we got a geometric column
          # and print the type and SRID
          if col.respond_to?(:geometry_type)
            attrs << "#{col.geometry_type}, #{col.srid}"
          elsif col.respond_to?(:geometric_type) && col.geometric_type.present?
            attrs << "#{col.geometric_type.to_s.downcase}, #{col.srid}"
          end

          # Check if the column has indices and print "indexed" if true
          # If the index includes another column, print it too.
          if options[:simple_indexes] && klass.table_exists? # Check out if this column is indexed
            indices = Index.retrieve_indexes_from_table(klass).select { |ind| ind.columns.include? col.name }
            if indices
              indices.sort_by(&:name).each do |ind|
                next if ind.columns.is_a?(String)

                ind = ind.columns.reject! { |i| i == col.name }
                attrs << (ind.empty? ? 'indexed' : "indexed => [#{ind.join(', ')}]")
              end
            end
          end
          col_name = if with_comments?(klass, options) && col.comment
                       "#{col.name}(#{col.comment})"
                     else
                       col.name
                     end
          if options[:format_rdoc]
            info << format("# %-#{max_size}.#{max_size}s<tt>%s</tt>",
                           "*#{col_name}*::",
                           attrs.unshift(col_type).join(', ')).rstrip + "\n"
          elsif options[:format_yard]
            info << sprintf("# @!attribute #{col_name}") + "\n"
            ruby_class = col.respond_to?(:array) && col.array ? "Array<#{map_col_type_to_ruby_classes(col_type)}>" : map_col_type_to_ruby_classes(col_type)
            info << sprintf("#   @return [#{ruby_class}]") + "\n"
          elsif options[:format_markdown]
            name_remainder = max_size - col_name.length - non_ascii_length(col_name)
            type_remainder = (MD_TYPE_ALLOWANCE - 2) - col_type.length
            info << format("# **`%s`**%#{name_remainder}s | `%s`%#{type_remainder}s | `%s`",
                           col_name,
                           ' ',
                           col_type,
                           ' ',
                           attrs.join(', ').rstrip).gsub('``', '  ').rstrip + "\n"
          else
            info << format_default(col_name, max_size, col_type, attrs)
          end

          info
        end

        private

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

        def with_comments?(klass, options)
          options[:with_comment] &&
            klass.columns.first.respond_to?(:comment) &&
            klass.columns.map(&:comment).any? { |comment| !comment.nil? }
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

        def get_col_type(col)
          if (col.respond_to?(:bigint?) && col.bigint?) || /\Abigint\b/ =~ col.sql_type
            'bigint'
          else
            (col.type || col.sql_type).to_s
          end
        end

        def schema_default(klass, column)
          quote(klass.columns.find { |x| x.name.to_s == column.name.to_s }.try(:default))
        end

        # Simple quoting for the default column value
        def quote(value)
          case value
          when NilClass                 then 'NULL'
          when TrueClass                then 'TRUE'
          when FalseClass               then 'FALSE'
          when Float, Integer           then value.to_s
            # BigDecimals need to be output in a non-normalized form and quoted.
          when BigDecimal               then value.to_s('F')
          when Array                    then value.map { |v| quote(v) }
          else
            value.inspect
          end
        end

        def hide_default?(col_type, options)
          excludes =
            if options[:hide_default_column_types].blank?
              NO_DEFAULT_COL_TYPES
            else
              options[:hide_default_column_types].split(',')
            end

          excludes.include?(col_type)
        end

        def hide_limit?(col_type, options)
          excludes =
            if options[:hide_limit_column_types].blank?
              NO_LIMIT_COL_TYPES
            else
              options[:hide_limit_column_types].split(',')
            end

          excludes.include?(col_type)
        end

        def map_col_type_to_ruby_classes(col_type)
          case col_type
          when 'integer'                                       then Integer.to_s
          when 'float'                                         then Float.to_s
          when 'decimal'                                       then BigDecimal.to_s
          when 'datetime', 'timestamp', 'time'                 then Time.to_s
          when 'date'                                          then Date.to_s
          when 'text', 'string', 'binary', 'inet', 'uuid'      then String.to_s
          when 'json', 'jsonb'                                 then Hash.to_s
          when 'boolean'                                       then 'Boolean'
          end
        end

        def non_ascii_length(string)
          string.to_s.chars.reject(&:ascii_only?).length
        end

        def format_default(col_name, max_size, col_type, attrs)
          format('#  %s:%s %s',
                 mb_chars_ljust(col_name, max_size),
                 mb_chars_ljust(col_type, BARE_TYPE_ALLOWANCE),
                 attrs.join(', ')).rstrip + "\n"
        end

        def mb_chars_ljust(string, length)
          string = string.to_s
          padding = length - width(string)
          if padding.positive?
            string + (' ' * padding)
          else
            string[0..(length - 1)]
          end
        end

        def width(string)
          string.chars.inject(0) { |acc, elem| acc + (elem.bytesize == 3 ? 2 : 1) }
        end
      end
    end
  end
end
