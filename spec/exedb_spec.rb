require 'minitest/autorun'
require "exedb"

TEST_DIR='/tmp/exedb_test'
TEST_CACHE_DIR='/tmp/exedb_test_cache'
TEST_FILE='abc_file'
TEST_FILE2='efg_file'

describe Exedb do
  before do
    # clean up...
    FileUtils.rm_rf Exedb::DEF_DIR

    @db=Exedb.new
    @db.cache_dir=TEST_CACHE_DIR
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
      @db2=Exedb.new
      @db2.cache_dir=TEST_CACHE_DIR
      @db2.update_method="sleep 1;ls -la #{TEST_DIR}"
      @db.update
    end

    it 'reads last cached result' do
      sleep 2;
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
      @db.cache_dir=TEST_CACHE_DIR
      @db2.cache_dir=TEST_CACHE_DIR
      File.open("/tmp/mytestcode",'w'){|f| f.puts '1'}
      @db.code
      File.open("/tmp/mytestcode",'w'){|f| f.puts '2'}
      @db2.update

      @db.code.must_be :==, 2
    end
  end

  describe 'intermediate output' do
    it 'cam be read while command is in progress' do
      CMD4='for i in 1 2 3 4; do echo x; sleep 1; done'
      @db=Exedb.new(CMD4)
      @db2=Exedb.new(CMD4)
      @db.cache_dir=TEST_CACHE_DIR
      @db2.cache_dir=TEST_CACHE_DIR
      t=Thread.new {
        @db.get
      }
      sleep 3
      x=@db2.peek
      x.must_match /^x\nx(\nx?)$/m
      t.join
    end
  end

  describe "transforms output" do
    before do
      @db.line_transform do |str|
        return nil unless str =~ /^([d-])/
        type=$1
        str =~ /(\S+)$/
        prefix= type=='-' ? 'FILE: ' : 'DIR:  '
        return "#{prefix}#{$1}"
      end
    end

    it 'transforms output' do
      @db.get.must_match 'FILE: abc_file'
    end

    it 'deletes lines in output' do
      x=@db.get
      x.lines.count.must_equal 1
    end

    it 'cancels transformation' do
      @db.no_line_transform
      x=@db.get
      x.lines.count.must_equal 4
    end

    it 'transforms each line and all output' do
      @db.all_transform {|str,code| n=str.lines.count; "#{n} lines (#{code})"}
      @db.get.must_equal "1 lines (0)"
    end

    it 'transforms all raw output' do
      @db.no_line_transform
      @db.all_transform {|str,code| n=str.lines.count; "#{n} lines (#{code})"}
      @db.get.must_equal "4 lines (0)"
    end
  end
end
