require "time"

module SafeFlock

  ##
  # Thread-safe, transferable, flock-based lock file implementation
  #
  # See {SafeFlock.create} for a safe way to wrap the creation, locking and unlocking of the lock file.
  #
  class Lockfile

    @@global_mutex = Mutex.new unless defined?(@@global_mutex)
    @@path_mutex = {} unless defined?(@@path_mutex)

    ##
    # Initialize (but do not lock)
    #
    # See {SafeFlock.create} for a safe way to wrap the creation, locking and unlocking of the lock file.
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

    ##
    # Lock the lock file
    #
    # See {SafeFlock.create} for a safe way to wrap the creation, locking and unlocking of the lock file.
    #
    # Attempt to {File#flock} the lock file, creating it if necessary.
    #
    # If +max_wait+ is zero, the attempt is non-blocking: if the file
    # is already locked, give up immediately. Otherwise, continue
    # trying to lock the file for approximately +max_wait+ seconds.
    #
    # The operation is performed under a per-path thread mutex to
    # preserve mutual exclusion across threads.
    #
    # @return [true|false] whether the lock was acquired
    #
    # @raise [Exception] if an IO error occurs opening the lock file
    #   e.g. +Errno::EACCES+
    #
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

    ##
    # Unlock the lock file
    #
    # See {SafeFlock.create} for a safe way to wrap the creation, locking and unlocking of the lock file.
    #
    # Unlock the lock file in the current process.
    #
    # The only intended use case for this method is in a forked child process that does significant work
    # after the mutually exclusive work for which it required the lock. In such cases, the process may
    # call +unlock+ after the mutually exclusive work is complete.
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

    ##
    # The path to the lock file
    #
    attr_reader :path

    ##
    # The process that created the lock file
    #
    attr_reader :pid

    ##
    # A unique identifier for the thread that created the lock file
    #
    attr_reader :thread_id

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
