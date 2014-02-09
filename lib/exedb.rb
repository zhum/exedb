require 'digest'
require 'time'

#
# Database-like interface for long-running tasks.
#
# Each instance can run single command (get).
# If two or more instances with the same command do 'get', then only first
# will really execute command, all others will wait
# for result (flock is used).
#
# Results of command execution (stdout) is cached. Next 'get'
# will return cached results (unless cache timeout happened).
#
# You can force execution, calling 'update' method.
#
# Exit code is available via 'code' method
#
class Exedb

  SLEEP_TIME=1
  DEF_DIR='/tmp/Exedb'
  DEF_CACHE_TIMEOUT=60

  attr_accessor :cache_timeout, :cache_dir
  attr_reader :update_time

  # Constructor
  # @str - command to be executed
  #
  def initialize(str='')
    @update_time=Time.parse("1970-01-01")
    @cache_timeout=DEF_CACHE_TIMEOUT
    @cache_dir=DEF_DIR
    @code=-1
    Dir.mkdir DEF_DIR unless File.directory? DEF_DIR
    self.update_method=(str)
  end

  # Force command execution. If another instance with
  # the same command is in progress, no new execution
  # will be started
  def update
    @content=''

    # create file if needed
    unless File.file?(@path)
      File.open(@path,File::RDWR|File::CREAT,0644){|f|}
    end

    File.open(@path, "r+:UTF-8") { |file|
      if file.flock(File::LOCK_EX|File::LOCK_NB)
        begin
          IO.popen(@update_method){|pipe|
            line=pipe.gets
            while line
              line=@transform.call(line) if @transform
              if line
                file.puts line
                file.flush
                @content = @content+line
              end
              line=pipe.gets
            end
          }
          @code=$?.exitstatus
        rescue
          @content=''
          @code=-1
        end
        if @alltransform
          @content=@alltransform.call(@content,@code)
          file.seek(0,IO::SEEK_SET)
          file.write @content
          file.truncate(@content.size)
          file.flush
        end
        File.open("#{@path}.code",File::RDWR|File::CREAT, 0644){|code_file|
          code_file.puts @code
        }
        file.flock(File::LOCK_UN)
      else
        read_cache
      end
      @update_time=Time.now
    }
    #!!!warn "UPDATED!'"
    @content
  end

  #
  # transform each line in command output
  # if nil is returned, line is skipped
  #
  def line_transform(&block)
    if block
      obj = Object.new
      obj.define_singleton_method(:_, &block)
      @transform=obj.method(:_).to_proc
    else
      @transform=nil
    end
  end

  #
  # cancel transformation each line
  #
  def no_line_transform
    @transform=nil    
  end

  #
  # transform all command output at end of execution
  # block is called with parameters: content, return code
  # returned content replaces original output
  #
  def all_transform(&block)
    if block
      obj = Object.new
      obj.define_singleton_method(:_, &block)
      @alltransform=obj.method(:_).to_proc
    else
      @alltransform=nil
    end
  end

  def no_all_transform
    @alltransform=nil
  end
  #
  # Replace executing command
  #
  def update_method=(str)
    @update_method=str
    @key=generate_key str
    @path=File.join(DEF_DIR, @key)
#    warn "key=#{@key}; path=#{@path}; u=#{str}"
  end

  # Just alias for update_method=
  def put(str)
    self.update_method=(str)
  end

  #
  # Get last execution result (stdout), or start new
  # command execution and return result if cache is
  # invalid.
  #
  def get
    actualize
    @content
  end

  #
  # Get last execution return code.
  # NOTE!!! It is also cached, even on error.
  #
  def code
    actualize
    @code
  end

  #
  # Do not execute command - just peek in cache file...
  # Usefull for intermediate command output peeking
  #
  def peek
    begin
      File.read(@path)      
    rescue
      ''
    end
  end

  #
  # Returns symbol of cache state:
  # - updated = actual
  # - need_update = new command execution needed
  # - need_reread = just cache file reread is neede
  #
  def cache_state
    if File.exists? @path
      mtime=File.mtime(@path)
      return :need_update if mtime+@cache_timeout<Time.now
      return :need_reread if @update_time<mtime
      return :updated
    end
    :need_update
  end

  def update_in_progress?
    if File.exists? @path
      File.open(@path, File::RDONLY) { |file|
        if file.flock(File::LOCK_EX|File::LOCK_NB)
          file.flock(File::LOCK_UN)
          return false
        end
      }
      return true
    end
    return false
  end

protected

  def actualize
    case cache_state
    when :need_update
      update
    when :need_reread
      read_cache
    end
  end

  def generate_key u
    f=u.tr('^qwertyuiopasdfghjklzxcvbnm_-','')
    d=Digest::SHA256.hexdigest(u)
    return f[0,60]+'..'+f[-60,60]+d if f.size>128
    return f+d
  end

  def read_cache
    File.open(@path, File::RDONLY) { |file|
      file.flock(File::LOCK_EX)
      @content=file.read
      warn "CACHE READ: #{@content}"
      File.open("#{@path}.code", File::RDONLY) { |code_file|
        c=code_file.gets
        c =~ /([0-9-]+)/
        @code=$1.to_i
      }
      file.flock(File::LOCK_UN)
    }
  end

end
