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
    File.open(@path, File::RDWR|File::CREAT, 0644) { |file|
      if file.flock(File::LOCK_EX|File::LOCK_NB)
        begin
          @content=`#{@update_method}`
          @code=$?.exitstatus
          #warn "UPDATED: #{@content}"
        rescue
          @content=''
          @code=-1
        end
        file.write @content
        file.flush
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
    return Digest::SHA256.hexdigest u
  end

  def read_cache
    File.open(@path, File::RDONLY) { |file|
      file.flock(File::LOCK_EX)
      @content=file.read
      File.open("#{@path}.code", File::RDONLY) { |code_file|
        c=code_file.gets
        c =~ /([0-9-]+)/
        @code=$1.to_i
      }
      file.flock(File::LOCK_UN)
    }
  end
end
