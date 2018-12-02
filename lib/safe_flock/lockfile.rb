require "time"

module SafeFlock

  class Lockfile

    class Error < RuntimeError; end
    class Locked < RuntimeError; end

    @@global_mutex = Mutex.new unless defined?(@@global_mutex)
    @@path_mutex = {} unless defined?(@@path_mutex)

    # +path+ full pathname of mutually agreed lock file.
    #
    # +options+
    # * +max_wait+ seconds to retry acquiring lock before giving up and raising +Error+ (+5.0+)
    #
    def initialize(path, max_wait: 5.0)
      @pid = $$
      @thread_id = Thread.current.object_id
      @path = path
      @max_wait = max_wait
      @wait_per_try = 0.1
      @mlocked = false
      @lockfd = nil
    end

    def lock
      deadline = Time.now.to_f + @max_wait
      while !(is_locked = try_lock)
        if Time.now.to_f < deadline
          sleep @wait_per_try
        else
          break
        end
      end
      is_locked
    end

    # If the lock is inherited by a forked child process, it will hold the lock until
    # the child calls +unlock+ (or terminates) _and_ the parent's +Lockfile.create+
    # block terminates. The parent should not call +unlock+.
    #
    def unlock
      if @lockfd
        @lockfd.close
        @lockfd = nil
      end
      if @mlocked && @pid == $$ and @thread_id == Thread.current.object_id
        mutex_unlock
      end
    end

    attr_reader :path, :pid, :thread_id

    private

    def try_lock
      begin
        if try_mutex_lock
          @lockfd = File.new(@path, "a")
          @lockfd.flock(File::LOCK_EX | File::LOCK_NB)
        end
      rescue
        @lockfd.close if @lockfd and !@lockfd.closed?
        @lockfd = nil
        mutex_unlock
        raise
      end
    end

    def try_mutex_lock
      @@global_mutex.synchronize do
        @@path_mutex[@path] = Mutex.new unless @@path_mutex[@path]
        @mlocked = @@path_mutex[@path].try_lock
      end
    end

    def mutex_unlock
      @@global_mutex.synchronize do
        if @mlocked
          @@path_mutex[@path].unlock
          @@path_mutex.delete(@path)
          @mlocked = false
        end
      end
    end

    def debug(*args)
      #$stderr.puts "DEBUG: LOCKFILE: [#{$$}]<#{"0x%x" % Thread.current.object_id}>: " + args.join(": ")
    end

  end

end
