require "safe_flock/lockfile"
require "safe_flock/version"

##
# Thread-safe, transferable, flock-based lock file
#
module SafeFlock

  ##
  # Raised when the file can't be locked in time
  #
  class Locked < RuntimeError; end

  ##
  # Ensure mutual exclusion of a block with +flock+
  #
  # * The block is only executed if the lock can be acquired.
  # * The lock is held for the duration of the block.
  # * Any child process forked within the block holds the lock
  #   until it terminates or explicitly releases the lock
  #   (see SafeFlock::Lockfile#unlock}).
  # * No other thread may enter the block while the lock is held.
  # * The lock file _may_ be left in place after the lock is released,
  #   but this behaviour should not be relied upon.
  #
  # @param [String] path
  #   path of file to flock (created if necessary).
  #   Absolute pathname (see {Pathname#realpath}) recommended for per-path thread mutex
  #   and for processes in which the present working directory (see {Dir.chdir}) changes.
  # @option options [Float] :max_wait
  #   approximate maximum seconds to wait for the lock.
  #   A zero +max_wait+ requests a non-blocking attempt
  #   (i.e. give up immediately if file already locked).
  #
  # @return [Object] the value of the block
  #
  # @raise [SafeFlock::Locked] if the lock could not be acquired.
  #   If +max_wait is zero, the file was already locked.
  #   Otherwise, timed out waiting for the lock.
  # @raise [Exception] if an IO error occurs opening the lock file
  #   e.g. +Errno::EACCES+
  #
  # TODO implement configurable retry
  #
  def self.create(path, max_wait: 5.0)
    raise(ArgumentError, "Block required") unless block_given?
    lockfile = Lockfile.new(path, max_wait: max_wait)
    begin
      if lockfile.lock
        begin
          yield lockfile
        ensure
          lockfile.unlock
        end
      else
        raise Locked, "Timed out waiting for lock"
      end
    end
  end

end
