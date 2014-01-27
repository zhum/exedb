require 'digest'
require 'time'

class Exedb

  SLEEP_TIME=1
  DEF_DIR='/tmp/Exedb'
  DEF_CACHE_TIMEOUT=60

  attr_accessor :cache_timeout, :cache_dir
  attr_reader :update_time

  def initialize
    @update_time=Time.parse("1970-01-01")
    @cache_timeout=DEF_CACHE_TIMEOUT
    @cache_dir=DEF_DIR
    Dir.mkdir DEF_DIR unless File.directory? DEF_DIR
  end

  def generate_key u
    return Digest::SHA256.hexdigest u
  end

  def update
    File.open(@path, File::RDWR|File::CREAT, 0644) { |file|
      if file.flock(File::LOCK_EX|File::LOCK_NB)
        @content=`#{@update_method}`
        file.write @content
        file.flush
        file.flock(File::LOCK_UN)
      else
        read_cache
      end
      @update_time=Time.now
    }
    #!!!warn "UPDATED!'"
    @content
  end

  def update_method= str
    @update_method=str
    @key=generate_key str
    @path=File.join DEF_DIR, @key
  end

  def read_cache
    File.open(@path, File::RDONLY) { |file|
      file.flock(File::LOCK_EX)
      @content=file.read
      file.flock(File::LOCK_UN)
    }
  end

  def get
    state=cache_state
    #warn "CACHED: #{state}"
    case state
    when :need_update
      update
    when :need_reread
      #!!!warn "read cached"
      read_cache
    end
    @content
  end

#  def get
#    return get_cached
#    #warn "Get: #{@update_time}+#{@cache_timeout}>#{Time.now}"
#    if @update_time+@cache_timeout>Time.now
#      # not need to update cache
#      get_cached
#    else
#      update
#    end
#  end

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
end