# -*- coding: utf-8 -*-
require 'helper'

class TestRegressionComment07 < Test::Unit::TestCase
  def setup
    setup_dir_var
  end

  def teardown
    File.delete(@xlsx) if File.exist?(@xlsx)
  end

  def test_comment07
    @xlsx = 'comment07.xlsx'
    workbook  = WriteXLSX.new(@xlsx)
    worksheet = workbook.add_worksheet

    worksheet.write_comment('A1', 'Some text')
    worksheet.write_comment('A2', 'Some text')
    worksheet.write_comment('A3', 'Some text')
    worksheet.write_comment('A4', 'Some text')
    worksheet.write_comment('A5', 'Some text')

    worksheet.show_comments

    # Set the author to match the target XLSX file.
    worksheet.set_comments_author('John')

    workbook.close
    compare_xlsx_for_regression(
                                File.join(@regression_output, @xlsx),
                                @xlsx,
                                nil,
                                { 'xl/workbook.xml' => ['<workbookView'] })
  end
end
