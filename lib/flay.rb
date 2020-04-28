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

TMP_DIR = '/tmp'
DEVICE_SAMPLE_RATE = 48_000 # default aucat rate

QUEUE = Queue.new

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
  print s + ("\e[D" * s.length)
  print "\n" if ln
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

  pos = ((ctx.delete(:position) || 0).to_f * DEVICE_SAMPLE_RATE).to_i

  prompt "  > #{fn}"

  ctx[:wav] = decode(path)

  t0 = monow

  pid = ctx[:aucat_pid] = spawn("aucat -g #{pos} -i #{ctx[:wav]}")

  Thread.new do
    Process.wait2(pid)
    ctx[:elapsed] = monow - t0
    QUEUE << :over
  end
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

  if ctx[:position]
    ctx[:position] = ctx.delete(:elapsed)
  elsif ctx[:index]
    play(ctx)
  else
    exit 0
  end
end

def do_next(ctx)

  ctx[:index] += 1
  stop(ctx)
end

def do_pause_or_play(ctx)

  if ctx[:position]
    play(ctx)
  else
    ctx[:position] = -1
    stop(ctx)
  end
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
  when 'p', ' ' then QUEUE << :pause_or_play
  end
end

