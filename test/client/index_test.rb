require File.expand_path('../../test_helper', __FILE__)

describe Elastomer::Client::Index do

  before do
    @name  = 'elastomer-index-test'
    @index = $client.index @name
    @index.delete if @index.exists?
  end

  after do
    @index.delete if @index.exists?
  end

  it 'requires an index name' do
    assert_raises(ArgumentError) { $client.index }
  end

  it 'determines if an index exists' do
    assert !@index.exists?, 'the index should not yet exist'
  end

  describe 'when creating an index' do
    it 'creates an index' do
      @index.create :settings => { :number_of_shards => 3, :number_of_replicas => 0 }
      assert @index.exists?, 'the index should now exist'

      settings = @index.settings[@name]['settings']

      # COMPATIBILITY
      # ES 1.0 changed the default return format of index settings to always
      # expand nested properties, e.g.
      # {"index.number_of_replicas": "1"} changed to
      # {"index": {"number_of_replicas":"1"}}

      # To support both versions, we check for either return format.
      value = settings['index.number_of_shards'] ||
              settings['index']['number_of_shards']
      assert_equal '3', value
      value = settings['index.number_of_replicas'] ||
              settings['index']['number_of_replicas']
      assert_equal '0', value
    end

    it 'adds mappings for document types' do
      @index.create(
        :settings => { :number_of_shards => 1, :number_of_replicas => 0 },
        :mappings => {
          :doco => {
            :_source => { :enabled => false },
            :_all    => { :enabled => false },
            :properties => {
              :title  => { :type => 'string', :analyzer => 'standard' },
              :author => { :type => 'string', :index => 'not_analyzed' }
            }
          }
        }
      )

      assert @index.exists?, 'the index should now exist'
      assert_mapping_exists @index.mapping[@name], 'doco'
    end
  end

  it 'updates index settings' do
    @index.create :settings => { :number_of_shards => 1, :number_of_replicas => 0 }

    @index.update_settings 'index.number_of_replicas' => 1
    settings = @index.settings[@name]['settings']

    # COMPATIBILITY
    # ES 1.0 changed the default return format of index settings to always
    # expand nested properties, e.g.
    # {"index.number_of_replicas": "1"} changed to
    # {"index": {"number_of_replicas":"1"}}

    # To support both versions, we check for either return format.
    value = settings['index.number_of_replicas'] ||
            settings['index']['number_of_replicas']
    assert_equal '1', value
  end

  it 'updates document mappings' do
    @index.create(
      :mappings => {
        :doco => {
          :_source => { :enabled => false },
          :_all    => { :enabled => false },
          :properties => {:title  => { :type => 'string', :analyzer => 'standard' }}
        }
      }
    )

    assert_property_exists @index.mapping[@name], 'doco', 'title'

    @index.update_mapping 'doco', { :doco => { :properties => {
      :author => { :type => 'string', :index => 'not_analyzed' }
    }}}

    assert_property_exists @index.mapping[@name], 'doco', 'author'
    assert_property_exists @index.mapping[@name], 'doco', 'title'

    @index.update_mapping 'mux_mool', { :mux_mool => { :properties => {
      :song => { :type => 'string', :index => 'not_analyzed' }
    }}}

    assert_property_exists @index.mapping[@name], 'mux_mool', 'song'
  end

  it 'deletes document mappings' do
    @index.create(
      :mappings => {
        :doco => {
          :_source => { :enabled => false },
          :_all    => { :enabled => false },
          :properties => {:title  => { :type => 'string', :analyzer => 'standard' }}
        }
      }
    )
    assert_mapping_exists @index.mapping[@name], 'doco'

    response = @index.delete_mapping 'doco'
    assert_acknowledged response
    assert @index.mapping == {} || @index.mapping[@name] == {}
  end

  it 'lists all aliases to the index' do
    @index.create(nil)
    assert_equal({@name => {'aliases' => {}}}, @index.get_aliases)

    $client.cluster.update_aliases :add => {:index => @name, :alias => 'foofaloo'}
    assert_equal({@name => {'aliases' => {'foofaloo' => {}}}}, @index.get_aliases)
  end

  # COMPATIBILITY ES 1.x removed English stopwords from the default analyzers,
  # so create a custom one with the English stopwords added.
  if es_version_1_x?
    it 'analyzes text and returns tokens' do
      tokens = @index.analyze 'Just a few words to analyze.', :analyzer => 'standard', :index => nil
      tokens = tokens['tokens'].map { |h| h['token'] }
      assert_equal %w[just a few words to analyze], tokens

      @index.create(
        :settings => {
          :number_of_shards => 1,
          :number_of_replicas => 0,
          :analysis => {
            :analyzer => {
              :english_standard => {
                :type => :standard,
                :stopwords => "_english_"
              }
            }
          }
        }
      )
      wait_for_index(@name)

      tokens = @index.analyze 'Just a few words to analyze.', :analyzer => 'english_standard'
      tokens = tokens['tokens'].map { |h| h['token'] }
      assert_equal %w[just few words analyze], tokens
    end
  else
    it 'analyzes text and returns tokens' do
      tokens = @index.analyze 'Just a few words to analyze.', :index => nil
      tokens = tokens['tokens'].map { |h| h['token'] }
      assert_equal %w[just few words analyze], tokens

      tokens = @index.analyze 'Just a few words to analyze.', :analyzer => 'simple', :index => nil
      tokens = tokens['tokens'].map { |h| h['token'] }
      assert_equal %w[just a few words to analyze], tokens
    end
  end

  describe "when an index exists" do
    before do
      @index.create(nil)
      wait_for_index(@name)
    end

    #TODO assert this only hits the desired index
    it 'deletes' do
      response = @index.delete
      assert_acknowledged response
    end

    it 'opens' do
      response = @index.open
      assert_acknowledged response
    end

    it 'closes' do
      response = @index.close
      assert_acknowledged response
    end

    it 'refreshes' do
      response = @index.refresh
      assert_equal 0, response["_shards"]["failed"]
    end

    it 'flushes' do
      response = @index.flush
      assert_equal 0, response["_shards"]["failed"]
    end

    it 'optimizes' do
      response = @index.optimize
      assert_equal 0, response["_shards"]["failed"]
    end

    # COMPATIBILITY ES 1.2 removed support for the gateway snapshot API.
    if es_version_supports_gateway_snapshots?
      it 'snapshots' do
        response = @index.snapshot
        assert_equal 0, response["_shards"]["failed"]
      end
    end

    it 'clears caches' do
      response = @index.clear_cache
      assert_equal 0, response["_shards"]["failed"]
    end

    it 'gets stats' do
      response = @index.stats
      if response.key? 'indices'
        assert_includes response["indices"], "elastomer-index-test"
      else
        assert_includes response["_all"]["indices"], "elastomer-index-test"
      end
    end

    it 'gets status' do
      response = @index.status
      assert_includes response["indices"], "elastomer-index-test"
    end

    it 'gets segments' do
      @index.docs('foo').index("foo" => "bar")
      response = @index.segments
      assert_includes response["indices"], "elastomer-index-test"
    end
  end
end
