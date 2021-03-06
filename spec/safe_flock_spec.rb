require "spec_helper"
require "fileutils"
require "tmpdir"

require "safe_flock"

RSpec.describe SafeFlock do

  let(:tmpdir) { Dir.mktmpdir("rspec") }
  let(:lockfile) { File.join(tmpdir, "lockfile") }
  let(:lockfile1) { "#{lockfile}1" }
  let(:lockfile2) { "#{lockfile}2" }
  let(:stale_lockfile) do
    lockfile.tap do |lf|
      child = fork { subject.create(lf) { Process.kill("KILL", Process.pid) } }
      Process.wait(child)
    end
  end
  let(:threads) { [] }

  before(:each) { lockfile }
  after(:each) { FileUtils.rm_rf(tmpdir) if File.exist?(tmpdir) }
  after(:each) { threads.each { |thr| thr.join } }

  subject { described_class }

  it "wraps a block" do
    subject.create(lockfile) { @ran = true }
    expect( @ran ).to be true
  end

  it "demands a block" do
    expect { subject.create(lockfile) }.to raise_error ArgumentError
  end

  it "returns the value of the workload block on success" do
    expect( subject.create(lockfile, max_wait: 0) { "payload" } ).to eql "payload"
  end

  it "does not rescue workload exceptions" do
    expect { subject.create(lockfile) { raise "workload error" } }.to raise_error("workload error")
  end

  it "provides mutual exclusion of concurrent processing" do
    subject.create(lockfile) do
      expect {
        subject.create(lockfile, max_wait: 0) { @ran = true }
      }.to raise_error(SafeFlock::Locked, /Timed out waiting for lock/)
    end
    expect( @ran ).to_not be true
  end

  it "supports multiple, independent locks" do
    subject.create(lockfile1) do
      subject.create(lockfile2) do
        expect { subject.create(lockfile2, max_wait: 0) { @ran = true } }.
          to raise_error(SafeFlock::Locked, /Timed out waiting for lock/)
      end
    end
    expect( @ran ).to_not be true
  end

  it "can wait to acquire a lock" do
    threads << Thread.new { subject.create(lockfile) { sleep 0.2 } }
    sleep 0.1
    subject.create(lockfile, max_wait: 0.5) { @ran = true }
    expect( @ran ).to be true
  end

  it "can time out waiting to acquire a lock" do
    threads << Thread.new { subject.create(lockfile) { sleep 0.3 } }
    sleep 0.1
    expect { subject.create(lockfile, max_wait: 0.1) { @ran = true } }.
      to raise_error(SafeFlock::Locked, /Timed out waiting for lock/)
    expect( @ran ).to_not be true
  end

  it "can ignore a stale lock left behind by a terminated process" do
    expect( File ).to be_exist(stale_lockfile) # precondition
    subject.create(stale_lockfile) { @ran = true }
    expect( @ran ).to be true
  end

  # This spec is inherited from a previous implementation using lock file hitching posts
  # (File.link).
  #
  it "protects against stale lock race condition" do
    expect( File ).to be_exist(stale_lockfile) # precondition
    @ran = []
    (1..1024).each do
      threads << Thread.new do
        sleep(rand(0.0001))
        subject.create(lockfile, max_wait: 1) { sleep 3; @ran << :ran } rescue nil
      end
    end
    threads.each { |thr| thr.join }
    expect( @ran.size ).to eql 1
  end

  it "supports lock transfer to a child process" do
    payload_file = File.join(tmpdir, "payload")

    subject.create(lockfile) do |lock|
      child = fork do
        File.write(payload_file, "child payload")
        sleep(3)
      end
      Process.detach(child)
    end

    # Lockfile is now unlocked in the parent process

    subject.create(lockfile, max_wait: 0) { File.write(payload_file, "contender payload") } rescue nil
    sleep(5)
    expect( File.read(payload_file) ).to eql "child payload"
  end

  # This is not a sensible use case: it just proves thread-safety.
  it "supports lock transfer to a child thread" do
    payload_file = File.join(tmpdir, "payload")

    subject.create(lockfile) do |lock|
      thread = Thread.new do
        begin
          sleep(2)
          File.write(payload_file, "child payload")
        end
      end
      sleep(1)
      subject.create(lockfile, max_wait: 0) { File.write(payload_file, "contender payload") } rescue nil
      thread.join
    end

    expect( File.read(payload_file) ).to eql "child payload"
  end

  it "supports explicit unlock call" do
    subject.create(lockfile) do |lock|
      lock.unlock
      subject.create(lockfile) { @ran = true }
    end
    expect( @ran ).to be true
  end

  it "ignores unlock on a lock file that is not locked" do
    subject.create(lockfile) do |lock|
      lock.unlock
      lock.unlock
      subject.create(lockfile) { @ran = true }
    end
    expect( @ran ).to be true
  end

  it "demonstrates fidelity under load", speed: "slow" do
    payload_file = File.join(tmpdir, "payload")
    line_length = 80
    num_iterations = 8
    num_processes = 16
    num_threads = 128

    children = (0..(num_processes - 1)).map do |i|
      fork do
        num_iterations.times do
          workers = (0..(num_threads - 1)).map do
            Thread.new do
              my_char = rand(10).to_s
              sleep(rand(0.001))
              begin
                subject.create(lockfile, max_wait: 5) do
                  line_length.times do
                    File.open(payload_file, "a") { |io| io.write(my_char) }
                  end
                  File.open(payload_file, "a") { |io| io.puts }
                end
              rescue described_class::Locked
                Thread.current.kill
              end
            end
          end
          workers.each { |worker| worker.join }
        end
      end
    end
    children.each { |child| Process.wait(child) }

    lines = File.readlines(payload_file)
    expect( lines.size ).to be > 1
    expect( lines ).to be_all { |line| line == line[0] * line_length + "\n" }
  end

end
