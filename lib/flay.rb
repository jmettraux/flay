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
CL = "\e[D" # cursot left

QUEUE = Queue.new


#
# helper methods

def monow; Process.clock_gettime(Process::CLOCK_MONOTONIC); end
def space(s); s.gsub(/__+/, ' '); end

def decode(path, &block)

  fn1 = File.basename(path, '.flac')
  wav = File.join(TMP_DIR, fn1 + '.wav')
  system("flac -d #{path} -o #{wav} > /dev/null 2>&1")

  wav
end

def elapsed(ctx)
  ed = (ctx[:elapsed] || 0).to_i
  s = ed % 60
  m = (ed / 60).to_i
  #"#{m}#{s}s"
  "%3dm%02ds" % [ m, s ]
end

def prompt(s, ctx)

  fn = ctx[:fname]

  if m = fn.match(/^(.+)__(\d+)___*(\d+)m(\d+)s(\d+)__(.+)\.flac$/)

    artist_and_disk, track, title = space(m[1]), m[2], space(m[6])
    duration = "#{m[3]}m#{m[4]}s#{m[5]}"
    ed = elapsed(ctx)
    print "     #{artist_and_disk}\r\n" if artist_and_disk != ctx[:aad]
    print "  #{s}  #{track} #{ed} / #{duration} #{title}\r\n"

    ctx[:aad] = artist_and_disk
  else

    puts "  #{s} #{fn}"
  end
end

def play(ctx)

  path = ctx[:path] = ctx[:targets][ctx[:index]]
  fn = ctx[:fname] = File.basename(path)

  pos = ((ctx.delete(:position) || 0).to_f * DEVICE_SAMPLE_RATE).to_i

  prompt('>', ctx)

  ctx[:wav] = decode(path)

  t0 = monow

  pid = ctx[:aucat_pid] = spawn("aucat -g #{pos} -i #{ctx[:wav]}")

  Thread.new do
    loop do
      ctx[:elapsed] = monow - t0
      break if Process.wait2(pid, Process::WNOHANG)
      sleep 0.42
      prompt('>', ctx)
    end
    QUEUE << :over
  end
end

def stop(ctx)

  prompt('o', ctx)

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

def do_back(ctx)

  ctx[:index] -= 1
  ctx[:index] = ctx[:targets].length - 1 if ctx[:index] < 0
  stop(ctx)
end

def do_next(ctx)

  ctx[:index] += 1
  ctx[:index] = 0 if ctx[:index] >= ctx[:targets].length
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

def do_rewind(ctx)

  ctx[:index] = 0
  stop(ctx)
end

def do_again(ctx)

  stop(ctx)
end

def do_exit(ctx)

  ctx.delete(:index)
  stop(ctx)
end

def work(ctx)

  loop { send("do_#{QUEUE.pop}", ctx) }

rescue => err

  stop(ctx) rescue nil

  print err.inspect + "\r\n"
  (err.backtrace[0, 7] + [ '...' ]).each { |l| print l + "\r\n" }
  exit 1
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
  when 'q', "\u0003" then QUEUE << :exit  # q and CTRL-c
  when 'b' then QUEUE << :back
  when 'n' then QUEUE << :next
  when 'r' then QUEUE << :rewind
  when 'a' then QUEUE << :again
  when 'p', ' ' then QUEUE << :pause_or_play
  #else print(a)
  end
end

