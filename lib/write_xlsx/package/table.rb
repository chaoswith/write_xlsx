# -*- coding: utf-8 -*-

require 'write_xlsx/package/xml_writer_simple'
require 'write_xlsx/utility'

module Writexlsx
  module Package
    class Table
      include Writexlsx::Utility

      class ColumnData
        attr_reader :id
        attr_accessor :name, :format, :formula
        attr_accessor :total_string, :total_function

        def initialize(id, param = {})
          @id             = id
          @name           = "Column#{id}"
          @total_string   = ''
          @total_function = ''
          @formula        = ''
          @format         = nil
          @user_data      = param[id-1] if param
        end
      end

      def initialize(worksheet, id, *args)
        @worksheet = worksheet
        @writer  = Package::XMLWriterSimple.new
        @id      = id

        @row1, @row2, @col1, @col2, @param = handle_args(*args)
        @columns = []
        @col_formats = []

        # Set the data range rows (without the header and footer).
        @first_data_row = @row1
        @first_data_row += 1 if ptrue?(@param[:header_row])
        @last_data_row  = @row2
        @last_data_row  -= 1 if @param[:total_row]

        set_the_table_options
        set_the_table_style
        set_the_table_name
        set_the_table_and_autofilter_ranges
        set_the_autofilter_range

        add_the_table_columns
        write_the_cell_data_if_supplied
      end

      def set_xml_writer(filename)
        @writer.set_xml_writer(filename)
      end

      #
      # Assemble and writes the XML file.
      #
      def assemble_xml_file
        write_xml_declaration do
          # Write the table element.
          @writer.tag_elements('table', write_table_attributes) do
            write_auto_filter
            write_table_columns
            write_table_style_info
          end
        end
      end

      def add_the_table_columns
        col_id = 0
        (@col1..@col2).each do |col_num|
          # Set up the default column data.
          col_data = Package::Table::ColumnData.new(col_id + 1, @param[:columns])

          overrite_the_defaults_with_any_use_defined_values(col_id, col_data, col_num)

          # Store the column data.
          @columns << col_data

          write_the_column_headers_to_the_worksheet(col_num, col_data)

          col_id += 1
        end    # Table columns.
      end

      def overrite_the_defaults_with_any_use_defined_values(col_id, col_data, col_num)
        if @param[:columns]
          # Check if there are user defined values for this column.
          if user_data = @param[:columns][col_id]
            # Map user defined values to internal values.
            if user_data[:header] && !user_data[:header].empty?
              col_data.name = user_data[:header]
            end
            # Handle the column formula.
            handle_the_column_formula(
                                      col_data, col_num, user_data[:formula], user_data[:format]
                                      )

            # Handle the function for the total row.
            if user_data[:total_function]
              handle_the_function_for_the_table_row(
                                                    @row2, col_data, col_num,
                                                    user_data[:total_function],
                                                    user_data[:format]
                                                    )
            elsif user_data[:total_string]
              total_label_only(
                               @row2, col_num, col_data, user_data[:total_string], user_data[:format]
                               )
            end

            # Get the dxf format index.
            if user_data[:format]
              col_data.format = user_data[:format].get_dxf_index
            end

            # Store the column format for writing the cell data.
            # It doesn't matter if it is undefined.
            @col_formats[col_id] = user_data[:format]
          end
        end
      end

      def write_the_column_headers_to_the_worksheet(col_num, col_data)
        if @param[:header_row] != 0
          @worksheet.write_string(@row1, col_num, col_data.name)
        end
      end

      def write_the_cell_data_if_supplied
        return unless @param[:data]

        data = @param[:data]
        i = 0    # For indexing the row data.
        (@first_data_row..@last_data_row).each do |row|
          next unless data[i]

          j = 0    # For indexing the col data.
          (@col1..@col2).each do |col|
            token = data[i][j]
            @worksheet.write(row, col, token, @col_formats[j]) if token
            j += 1
          end
          i += 1
        end
      end

      private

      def handle_args(*args)
        # Check for a cell reference in A1 notation and substitute row and column
        row1, col1, row2, col2, param = row_col_notation(args)

        # Check for a valid number of args.
        raise "Not enough parameters to add_table()" if [row1, col1, row2, col2].include?(nil)

        # Check that row and col are valid without storing the values.
        check_dimensions_and_update_max_min_values(row1, col1, 1, 1)
        check_dimensions_and_update_max_min_values(row2, col2, 1, 1)

        # Swap last row/col for first row/col as necessary.
        row1, row2 = row2, row1 if row1 > row2
        col1, col2 = col2, col1 if col1 > col2

      # The final hash contains the validation parameters.
        param ||= {}

        # Turn on Excel's defaults.
        param[:banded_rows] ||= 1
        param[:header_row]  ||= 1
        param[:autofilter]  ||= 1

        # If the header row if off the default is to turn autofilter off.
        param[:autofilter] = 0 if param[:header_row] == 0

        check_parameter(param, valid_table_parameter, 'add_table')

        [row1, row2, col1, col2, param]
      end

      # List of valid input parameters.
      def valid_table_parameter
        [
         :autofilter,
         :banded_columns,
         :banded_rows,
         :columns,
         :data,
         :first_column,
         :header_row,
         :last_column,
         :name,
         :style,
         :total_row
        ]
      end

      def handle_the_column_formula(col_data, col_num, formula, format)
        return unless formula

        col_data.formula = formula.sub(/^=/, '').gsub(/@/,'[#This Row],')

        (@first_data_row..@last_data_row).each do |row|
          @worksheet.write_formula(row, col_num, col_data.formula, format)
        end
      end

      def handle_the_function_for_the_table_row(row2, col_data, col_num, total_function, format)
        function = total_function.downcase.gsub(/[_\s]/, '')

        function = 'countNums' if function == 'countnums'
        function = 'stdDev'    if function == 'stddev'

        col_data.total_function = function

        formula = table_function_to_formula(function, col_data.name)
        @worksheet.write_formula(row2, col_num, formula, format)
      end

      #
      # Convert a table total function to a worksheet formula.
      #
      def table_function_to_formula(function, col_name)
        subtotals = {
          :average   => 101,
          :countNums => 102,
          :count     => 103,
          :max       => 104,
          :min       => 105,
          :stdDev    => 107,
          :sum       => 109,
          :var       => 110
        }

        unless func_num = subtotals[function.to_sym]
          raise "Unsupported function '#{function}' in add_table()"
        end
        "SUBTOTAL(#{func_num},[#{col_name}])"
      end

      # Total label only (not a function).
      def total_label_only(row2, col_num, col_data, total_string, format)
        col_data.total_string = total_string

        @worksheet.write_string(row2, col_num, total_string, format)
      end

      def set_the_table_options
        @show_first_col   = ptrue?(@param[:first_column])   ? 1 : 0
        @show_last_col    = ptrue?(@param[:last_column])    ? 1 : 0
        @show_row_stripes = ptrue?(@param[:banded_rows])    ? 1 : 0
        @show_col_stripes = ptrue?(@param[:banded_columns]) ? 1 : 0
        @header_row_count = ptrue?(@param[:header_row])     ? 1 : 0
        @totals_row_shown = ptrue?(@param[:total_row])      ? 1 : 0
      end

      def set_the_table_style
        if @param[:style]
          @style = @param[:style].gsub(/\s/, '')
        else
          @style = "TableStyleMedium9"
        end
      end

      def set_the_table_name
        if @param[:name]
          @name = @param[:name]
        else
          # Set a default name.
          @name = "Table#{@id}"
        end
      end

      def set_the_table_and_autofilter_ranges
        @range   = xl_range(@row1, @row2,          @col1, @col2)
        @a_range = xl_range(@row1, @last_data_row, @col1, @col2)
      end

      def set_the_autofilter_range
        @autofilter = @a_range if ptrue?(@param[:autofilter])
      end

      def write_table_attributes
        schema           = 'http://schemas.openxmlformats.org/'
        xmlns            = "#{schema}spreadsheetml/2006/main"

        attributes = [
                      'xmlns',       xmlns,
                      'id',          @id,
                      'name',        @name,
                      'displayName', @name,
                      'ref',         @range
                     ]

        unless ptrue?(@header_row_count)
          attributes << 'headerRowCount' << 0
        end

        if ptrue?(@totals_row_shown)
          attributes << 'totalsRowCount' << 1
        else
          attributes << 'totalsRowShown' << 0
        end
      end

      #
      # Write the <autoFilter> element.
      #
      def write_auto_filter
        return unless ptrue?(@autofilter)

        attributes = ['ref', @autofilter]

        @writer.empty_tag('autoFilter', attributes)
      end

      #
      # Write the <tableColumns> element.
      #
      def write_table_columns
        count = @columns.size

        attributes = ['count', count]

        @writer.tag_elements('tableColumns', attributes) do
          @columns.each {|col_data| write_table_column(col_data)}
        end
      end

      #
      # Write the <tableColumn> element.
      #
      def write_table_column(col_data)
        attributes = [
                      'id',   col_data.id,
                      'name', col_data.name
                     ]

        if ptrue?(col_data.total_string)
          attributes << :totalsRowLabel << col_data.total_string
        elsif ptrue?(col_data.total_function)
          attributes << :totalsRowFunction << col_data.total_function
        end

        if col_data.format
          attributes << :dataDxfId << col_data.format
        end

        if ptrue?(col_data.formula)
          @writer.tag_elements('tableColumn', attributes) do
            # Write the calculatedColumnFormula element.
            write_calculated_column_formula(col_data.formula)
          end
        else
          @writer.empty_tag('tableColumn', attributes)
        end
      end

      #
      # Write the <tableStyleInfo> element.
      #
      def write_table_style_info
        attributes = [
                      'name',              @style,
                      'showFirstColumn',   @show_first_col,
                      'showLastColumn',    @show_last_col,
                      'showRowStripes',    @show_row_stripes,
                      'showColumnStripes', @show_col_stripes
                     ]

        @writer.empty_tag('tableStyleInfo', attributes)
      end

      #
      # Write the <calculatedColumnFormula> element.
      #
      def write_calculated_column_formula(formula)
        @writer.data_element('calculatedColumnFormula', formula)
      end
    end
  end
end
