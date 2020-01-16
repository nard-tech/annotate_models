module AnnotateModels
  module SchemaInfo
    module Column
      # Don't show default value for these column types
      NO_DEFAULT_COL_TYPES = %w[json jsonb hstore].freeze

      # Don't show limit (#) on these column types
      # Example: show "integer" instead of "integer(4)"
      NO_LIMIT_COL_TYPES = %w[integer bigint boolean].freeze

      class << self
        def generate_for_each_col(klass, options, max_size, col, md_type_allowance)
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
            type_remainder = (md_type_allowance - 2) - col_type.length
            info << format("# **`%s`**%#{name_remainder}s | `%s`%#{type_remainder}s | `%s`",
                           col_name,
                           ' ',
                           col_type,
                           ' ',
                           attrs.join(', ').rstrip).gsub('``', '  ').rstrip + "\n"
          else
            bare_type_allowance = 16
            info << format_default(col_name, max_size, col_type, bare_type_allowance, attrs)
          end

          info
        end

        private

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

        def with_comments?(klass, options)
          options[:with_comment] &&
            klass.columns.first.respond_to?(:comment) &&
            klass.columns.any? { |col| !col.comment.nil? }
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

        def format_default(col_name, max_size, col_type, bare_type_allowance, attrs)
          format('#  %s:%s %s',
                 mb_chars_ljust(col_name, max_size),
                 mb_chars_ljust(col_type, bare_type_allowance),
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
