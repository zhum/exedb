require 'minitest/autorun'
require "exedb"

TEST_DIR='/tmp/exedb_test'
TEST_FILE='abc_file'
TEST_FILE2='efg_file'

describe Exedb do
  before do
    # clean up...
    FileUtils.rm_rf Exedb::DEF_DIR

    @db=Exedb.new
    FileUtils.rm_rf TEST_DIR
    Dir.mkdir TEST_DIR
    File.open(File.join(TEST_DIR,TEST_FILE), "w") { |io| io.puts "ok" }

    @db.update_method="sleep 1;ls -la #{TEST_DIR}"
  end

  it 'do update by default' do
    @db.get.must_match TEST_FILE
  end

  it 'updates state' do
    File.open(File.join(TEST_DIR,TEST_FILE2), "w") { |io| io.puts "ok" }
    @db.update
    @db.get.must_match TEST_FILE2
  end

  describe 'cache' do
    before do
      @db.update
      File.open(File.join(TEST_DIR,TEST_FILE2), "w") { |io| io.puts "ok" }
    end
    it 'caches last result' do
      @db.get.wont_match TEST_FILE2
    end

    it 'updates cache' do
      @db.update
      @db.get.must_match TEST_FILE2
    end
  end

  describe 'parallel istances' do
    before do
      #!!!warn "BEFORE 2>>>>>>>"
      @db2=Exedb.new
      @db2.update_method="sleep 1;ls -la #{TEST_DIR}"
      @db.update
    end

    it 'reads last cached result' do
      sleep 2;
      #!!!warn ">>>>>>>>>>>>>>>>>>"
      @db2.get.must_match TEST_FILE
    end

    it 'not updates cache second time' do
      sleep 2;
      @time=Time.now
      @db2.get
      (Time.now-@time).must_be :<, 0.1
    end

    it 'updates cache after timeout' do
      @db2.cache_timeout=3
      sleep 4;
      @time=Time.now
      @db2.get
      (Time.now-@time).must_be :>, 1
    end
  end

  describe 'return code' do
    it 'can be read' do
      @db.code.must_be :==, 0
    end

    it 'must be -1 if command cannnot be ran' do
      @db=Exedb.new
      @db.code.must_be :==, -1
    end

    it 'must read cached value' do
      @db=Exedb.new('x=`cat /tmp/mytestcode`; echo ">>$x<<"; exit $x')
      @db2=Exedb.new('x=`cat /tmp/mytestcode`; echo ">>$x<<"; exit $x')
      File.open("/tmp/mytestcode",'w'){|f| f.puts '1'}
      @db.code
      File.open("/tmp/mytestcode",'w'){|f| f.puts '2'}
      @db2.update

      @db.code.must_be :==, 2
    end
  end
end
