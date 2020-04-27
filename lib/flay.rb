#!/usr/bin/env ruby

require 'fileutils'

#
# arg shuffling

opts, args = ARGV.partition { |a| a[0, 1] == '-' }

if opts.include?('-h') || opts.include?('--help')
  puts '    ruby flay path/to/file.flac'
  puts 'OR  ruby flay path/to/dir_of_flac_files/'
  exit 0
end

TMP_DIR = '/tmp'

aucat_id = -1

#
# helper methods

def monow; Process.clock_gettime(Process::CLOCK_MONOTONIC); end


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
  aucat_id = fork { system("aucat -i #{path}") }
  Process.wait2(aucat_id)
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

