# encoding: utf-8
require "cases/helper"

class PostgresqlArrayTest < ActiveRecord::TestCase
  class PgArray < ActiveRecord::Base
    self.table_name = 'pg_arrays'
  end

  def setup
    @connection = ActiveRecord::Base.connection
    @connection.transaction do
      @connection.create_table('pg_arrays') do |t|
        t.string 'tags', array: true
        t.integer 'ratings', array: true
      end
    end
    @column = PgArray.columns_hash['tags']
  end

  teardown do
    @connection.execute 'drop table if exists pg_arrays'
  end

  def test_column
    assert_equal :string, @column.type
    assert_equal "character varying", @column.sql_type
    assert @column.array
    assert_not @column.text?
    assert_not @column.number?
    assert_not @column.binary?

    ratings_column = PgArray.columns_hash['ratings']
    assert_equal :integer, ratings_column.type
    assert ratings_column.array
    assert_not ratings_column.number?
  end

  def test_default
    @connection.add_column 'pg_arrays', 'score', :integer, array: true, default: [4, 4, 2]
    PgArray.reset_column_information
    column = PgArray.columns_hash["score"]

    assert_equal([4, 4, 2], PgArray.new.score)
  ensure
    PgArray.reset_column_information
  end

  def test_default_strings
    @connection.add_column 'pg_arrays', 'names', :string, array: true, default: ["foo", "bar"]
    PgArray.reset_column_information
    column = PgArray.columns_hash["names"]

    assert_equal(["foo", "bar"], PgArray.new.names)
  ensure
    PgArray.reset_column_information
  end

  def test_change_column_with_array
    @connection.add_column :pg_arrays, :snippets, :string, array: true, default: []
    @connection.change_column :pg_arrays, :snippets, :text, array: true, default: []

    PgArray.reset_column_information
    column = PgArray.columns_hash['snippets']

    assert_equal :text, column.type
    assert_equal [], column.default
    assert column.array
  end

  def test_change_column_cant_make_non_array_column_to_array
    @connection.add_column :pg_arrays, :a_string, :string
    assert_raises ActiveRecord::StatementInvalid do
      @connection.transaction do
        @connection.change_column :pg_arrays, :a_string, :string, array: true
      end
    end
  end

  def test_change_column_default_with_array
    @connection.change_column_default :pg_arrays, :tags, []

    PgArray.reset_column_information
    column = PgArray.columns_hash['tags']
    assert_equal [], column.default
  end

  def test_type_cast_array
    assert_equal(['1', '2', '3'], @column.type_cast('{1,2,3}'))
    assert_equal([], @column.type_cast('{}'))
    assert_equal([nil], @column.type_cast('{NULL}'))
  end

  def test_type_cast_integers
    x = PgArray.new(ratings: ['1', '2'])
    assert x.save!
    assert_equal(['1', '2'], x.ratings)
  end

  def test_select_with_strings
    @connection.execute "insert into pg_arrays (tags) VALUES ('{1,2,3}')"
    x = PgArray.first
    assert_equal(['1','2','3'], x.tags)
  end

  def test_rewrite_with_strings
    @connection.execute "insert into pg_arrays (tags) VALUES ('{1,2,3}')"
    x = PgArray.first
    x.tags = ['1','2','3','4']
    x.save!
    assert_equal ['1','2','3','4'], x.reload.tags
  end

  def test_select_with_integers
    @connection.execute "insert into pg_arrays (ratings) VALUES ('{1,2,3}')"
    x = PgArray.first
    assert_equal([1, 2, 3], x.ratings)
  end

  def test_rewrite_with_integers
    @connection.execute "insert into pg_arrays (ratings) VALUES ('{1,2,3}')"
    x = PgArray.first
    x.ratings = [2, '3', 4]
    x.save!
    assert_equal [2, 3, 4], x.reload.ratings
  end

  def test_multi_dimensional_with_strings
    assert_cycle(:tags, [[['1'], ['2']], [['2'], ['3']]])
  end

  def test_with_empty_strings
    assert_cycle(:tags, [ '1', '2', '', '4', '', '5' ])
  end

  def test_with_multi_dimensional_empty_strings
    assert_cycle(:tags, [[['1', '2'], ['', '4'], ['', '5']]])
  end

  def test_with_arbitrary_whitespace
    assert_cycle(:tags, [[['1', '2'], ['    ', '4'], ['    ', '5']]])
  end

  def test_multi_dimensional_with_integers
    assert_cycle(:ratings, [[[1], [7]], [[8], [10]]])
  end

  def test_strings_with_quotes
    assert_cycle(:tags, ['this has','some "s that need to be escaped"'])
  end

  def test_strings_with_commas
    assert_cycle(:tags, ['this,has','many,values'])
  end

  def test_strings_with_array_delimiters
    assert_cycle(:tags, ['{','}'])
  end

  def test_strings_with_null_strings
    assert_cycle(:tags, ['NULL','NULL'])
  end

  def test_contains_nils
    assert_cycle(:tags, ['1',nil,nil])
  end

  def test_insert_fixture
    tag_values = ["val1", "val2", "val3_with_'_multiple_quote_'_chars"]
    @connection.insert_fixture({"tags" => tag_values}, "pg_arrays" )
    assert_equal(PgArray.last.tags, tag_values)
  end

  def test_attribute_for_inspect_for_array_field
    record = PgArray.new { |a| a.ratings = (1..11).to_a }
    assert_equal("[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, ...]", record.attribute_for_inspect(:ratings))
  end

  def test_update_all
    pg_array = PgArray.create! tags: ["one", "two", "three"]

    PgArray.update_all tags: ["four", "five"]
    assert_equal ["four", "five"], pg_array.reload.tags

    PgArray.update_all tags: []
    assert_equal [], pg_array.reload.tags
  end

  def test_escaping
    unknown = 'foo\\",bar,baz,\\'
    tags = ["hello_#{unknown}"]
    ar = PgArray.create!(tags: tags)
    ar.reload
    assert_equal tags, ar.tags
  end

  private
  def assert_cycle field, array
    # test creation
    x = PgArray.create!(field => array)
    x.reload
    assert_equal(array, x.public_send(field))

    # test updating
    x = PgArray.create!(field => [])
    x.public_send("#{field}=", array)
    x.save!
    x.reload
    assert_equal(array, x.public_send(field))
  end
end
