#!/usr/bin/env ruby

require 'fileutils'
require 'io/console'

#
# arg shuffling

opts, args = ARGV.partition { |a| a[0, 1] == '-' }

if opts.include?('-h') || opts.include?('--help')
  puts '    ruby flay path/to/file.flac'
  puts 'OR  ruby flay path/to/dir_of_flac_files/'
  exit 0
end

QUEUE = Queue.new
TMP_DIR = '/tmp'

#aucat_id = -1

#
# helper methods

def monow; Process.clock_gettime(Process::CLOCK_MONOTONIC); end

def decode(path, &block)
  fn1 = File.basename(path, '.flac')
  wav = File.join(TMP_DIR, fn1 + '.wav')
  system("flac -d #{path} -o #{wav} > /dev/null 2>&1")
  wav
end

def prompt(s, ln=false)
  #print s
  #s.length.times { print "\e[D" }
  #print "\n" if ln
  puts s
end

#def increment(ctx, delta)
#
#  tc = ctx[:targets].count
#  i = i0 = ctx[:index] || 0
#  i = i + delta
#  i = i - tc while i > tc
#  i = i + tc while i < 0
#
#  ctx[:index] = index
#
#  i0
#end

def play(ctx)

  path = ctx[:path] = ctx[:targets][ctx[:index]]
  fn = ctx[:fname] = File.basename(path)

  prompt "  > #{fn}"

  ctx[:wav] = decode(path)

  pid = ctx[:aucat_pid] = spawn("aucat -i #{ctx[:wav]}")

  Thread.new { Process.wait2(pid); QUEUE << :over }
end

def stop(ctx)

  pid = ctx[:aucat_pid]
  (Process.kill('TERM', pid) rescue nil) if pid && pid > 0

  wav = ctx.delete(:wav)
  FileUtils.rm(wav, force: true) if wav

  ctx[:aucat_pid] = -1
end

#
# commands

def do_over(ctx)

  if ctx[:index]
    play(ctx)
  else
    exit 0
  end
end

def do_next(ctx)

  ctx[:index] += 1
  stop(ctx)
end

def do_exit(ctx)

  ctx.delete(:index)
  stop(ctx)
end

def work(context)

  loop do
    send("do_#{QUEUE.pop}", context)
  end
end

#
# launch work thread on target list

targets = (args.empty? ? [ '.' ] : args)
  .collect { |t|
    if t.index('*')
      Dir[t]
    elsif File.directory?(t)
      Dir[File.join(t, '**', '*.flac')]
    else
      t
    end }
  .flatten
  .select { |t| t.match(/\.flac$/) }
  .sort

QUEUE << :over
Thread.new { work(targets: targets, opts: opts, index: 0) }

#
# command loop

loop do
  case a = STDIN.getch
  when 'q', "\u0003" then QUEUE << :exit
  when 'b' then QUEUE << :back
  when 'n' then QUEUE << :next
  when 'r' then QUEUE << :rewind
  end
end

