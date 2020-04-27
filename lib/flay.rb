#!/usr/bin/env ruby

require 'fileutils'
require 'io/console'

#
# arg shuffling

opts, args = ARGV.partition { |a| a[0, 1] == '-' }

if opts.include?('-h') || opts.include?('--help')
  puts '    ruby flay path/to/file.flac'
  puts 'OR  ruby flay path/to/dir_of_flac_files/'
  puts
  puts '    ruby flay -b2048 path/to/file.flac    # block size 2048'
  exit 0
end

BLOCK =
  if bs = opts.find { |o| o.match(/^-bs?(\d+)$/) }
    $1.to_i
  else
    7_680
  end

TMP_DIR = '/tmp'
QUEUE = Queue.new
OUT = open('| aucat -i -', 'wb')

#
# helper methods

def decode(path)
  fn1 = File.basename(path, '.flac')
  out = File.join(TMP_DIR, fn1 + '.wav')
  system("flac -d #{path} -o #{out} > /dev/null 2>&1")
  out
end

def prompt(s, ln=false)
  print s
  s.length.times { print "\e[D" }
  print "\n" if ln
end

def play_wave(path)
  fn0 = File.basename(path)
  prompt ">   #{fn0}"
  i = File.open(path)
  paused = false
  loop do
    if QUEUE.size > 0
      case QUEUE.pop
      when :quit
        prompt "o   #{fn0}", true
        exit 0
      when :pause
        if paused
          prompt ">   #{fn0}"
        else
          prompt "||  #{fn0}"
        end
        paused = ! paused
      when :rewind
        paused = false
        i.rewind
        prompt ">   #{fn0}"
      when :next
        return
      end
    end
    if paused
      sleep 0.490
      next
    end
    b = i.read(BLOCK)
    break unless b && b.size > 0
    OUT.write(b)
  end
ensure
  i.close rescue nil
end

def play(path)
  wav = decode(path)
  play_wave(wav)
ensure
  FileUtils.rm(wav, force: true)
end

#
# main

target = args[0] || './'

targets =
  if File.directory?(target)
    Dir[File.join(target, '*.flac')]
  else
    [ target ]
  end

Thread.new do
  targets.each do |t|
    play(t)
  end
end

loop do
  QUEUE <<
    case c = STDIN.getch
    when 'q' then :quit
    when 'p', ' ' then :pause
    when 'r' then :rewind
    when 'n' then :next
    when "\u0003" then exit 1
    else nil
    end
end

