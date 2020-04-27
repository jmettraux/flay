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
  print s
  s.length.times { print "\e[D" }
  print "\n" if ln
end

#def play_wave(path)
#  fn0 = File.basename(path)
#  prompt ">   #{fn0}"
#  aucat_id = fork { system("aucat -i #{path}") }
#  Process.wait2(aucat_id)
#end
#
#def play(i, path)
#  wav = decode(path)
#  play_wave(wav)
#  i + 1
#ensure
#  FileUtils.rm(wav, force: true)
#end

def do_play(com, args, ctx)

  index = args[:index]
  targets = ctx[:targets]

  index =
    if index < 0
      targets.length + index
    elsif index >= targets.length
      exit(0) unless ctx[:opts].include?('--loop')
      0
    else
      index
    end

  path = ctx[:path] = targets[index]
  fn = ctx[:fname] = File.basename(path)

  prompt "  > #{fn}"

  ctx[:wav] = decode(path)

  pid = ctx[:aucat_pid] = spawn("aucat -i #{ctx[:wav]}")

  Thread.new do
    pid, status = Process.wait2(pid)
    QUEUE << [ :end, { index: index, pid: pid, status: status } ]
  end
end

def do_end(com, args, ctx)

  FileUtils.rm(ctx.delete(:wav)) rescue nil

  QUEUE << [ :play, { index: args[:index] + 1 } ]
end

def do_quit(com, args, ctx)

  Process.kill('TERM', ctx[:aucat_pid])
  FileUtils.rm(ctx.delete(:wav)) rescue nil

  print "  o #{ctx[:fname]}"

  exit 0
end

def work(context)

  loop do
    com = QUEUE.pop
#puts "---"
#p com
#p context
    send("do_#{com.first}", *com, context)
  end
end

#
# main

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

context = { targets: targets }
QUEUE << [ :play, { index: 0 } ]

Thread.new { work(context) }

loop do
  case a = STDIN.getch
  when 'q', "\u0003" then QUEUE << [ :quit, {} ]
  end
end

