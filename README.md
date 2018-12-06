[![Gem Version](https://badge.fury.io/rb/safe_flock.svg)](http://badge.fury.io/rb/safe_flock) [![Build Status](https://travis-ci.org/starjuice/safe_flock.svg?branch=master)](https://travis-ci.org/starjuice/safe_flock) [![Inline docs](http://inch-ci.org/github/starjuice/safe_flock.svg?branch=master)](http://inch-ci.org/github/starjuice/safe_flock)

# SafeFlock

Thread-safe, transferable, flock-based file lock.

This helper solves mutual exclusion within niche constraints:

* A parent process must acquire a lock and transfer it to a child process.
* The parent may terminate before the child.
* Locks may be created within threads within the parent.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'safe_flock'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install safe_flock

## Documentation

For documentation of the released gem, see [rubydoc.info](http://www.rubydoc.info/gems/safe_flock).

## Usage

Simple example:

```
require "safe_flock"

SafeFlock.create("/var/run/myapp/myapp.lck") do
  # ... mutually excluded processing
end
```

The use case for which the helper was created:

```
require "safe_flock"

SafeFlock.create("/var/run/myapp/myapp.lck") do |lock|
  child = fork do

    # ... mutually excluded processing

    lock.unlock

    # ... non-critical processing

  end
end
Process.detach(child)
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To run the test suite, run `bundle exec rake spec`.

If you would like to test compatibility with your NFS implementation, create a directory in the NFS filesystem and run the slow test in the same 
directory on multiple clients. Feedback appreciated.

```
rm -f /mnt/nfs/mytestdir/payload
TEST_TMPDIR=/mnt/nfs/mytestdir \
  TEST_ITERATIONS=100 \
  TEST_PROCESSES=3 \
  TEST_THREADS=3 \
  TEST_SECS_GAP=2 \
  bundle exec rspec --tag speed:slow
```

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/starjuice/safe_flock.
