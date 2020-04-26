#!/usr/bin/env ruby

require 'fileutils'

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
    16 * 1024
  end

OUT = open('| aucat -i -', 'wb')

TMP_DIR = '/tmp'

#
# helper methods

def decode(path)
  fn1 = File.basename(path, '.flac')
  out = File.join(TMP_DIR, fn1 + '.wav')
  system("flac -d #{path} -o #{out} > /dev/null 2>&1")
  out
end

def play_wave(path)
  fn0 = File.basename(path)
  puts ">  #{fn0}"
  i = File.open(path)
  loop do
    b = i.read(BLOCK)
    break unless b && b.size > 0
    OUT.write(b)
  end
rescue
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

targets.each do |t|
  play(t)
end

