require "safe_flock/lockfile"
require "safe_flock/version"

module SafeFlock

  class Error < RuntimeError; end
  class Locked < RuntimeError; end

  def self.create(path, options = {})
    raise(ArgumentError, "Block required") unless block_given?
    lockfile = Lockfile.new(path, options)
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
