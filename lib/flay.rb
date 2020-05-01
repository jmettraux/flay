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
CUU = "\e[A" # cursot up
CUD = "\e[B" # cursot down
CUL = "\e[D" # cursot left
CUG = "\e[G" # cursot home

DEVICE_SAMPLE_RATE = 48_000 # default aucat rate

QUEUE = Queue.new


#
# helper methods

def monow; Process.clock_gettime(Process::CLOCK_MONOTONIC); end
def space(s); s.gsub(/__+/, ' '); end

def wav_info(wav)

  d = `aucat -d -n -i #{wav} -o /dev/null 2>&1`

  size = File.size(wav)
  m = d.match(/ (alaw|mulaw|s8|u8|[fsu](16|24|32|64)[bl]e),/)
  format = m[1]
  depth = (m[2] || 8).to_i
  rate = d.match(/(\d+)Hz/)[1].to_i
  channels = 2 # stereo

  duration = size.to_f / (rate * channels * (depth / 8))

  [ rate, duration, size, format, depth ]
end

def decode(ctx)

  path = ctx[:path]
  fn1 = File.basename(path, '.flac')
  wav = ctx[:wav] = File.join(TMP_DIR, fn1 + '.wav')

  ctx[:aad] = '(aad)'
  ctx[:trackn] = -1
  ctx[:title] = '(title)'
    #
  if m = fn1.match(/^(.+)__(\d+)___*\d+m\d+s\d+__(.+)$/)
    ctx[:aad] = space(m[1])
    ctx[:trackn] = m[2].to_i
    ctx[:title] = space(m[3])
  end

  system("flac -d #{path} -o #{wav} > /dev/null 2>&1")

  ctx[:rate], ctx[:duration] = wav_info(wav)
end

def s_to_ms(n);
  n = n || 0
  "%3dm%02ds" % [ (n / 60).to_i, n.to_i % 60 ]
end
def s_to_mss(n);
  n = n || 0
  "%3dm%02ds%02d" % [ (n / 60).to_i, n.to_i % 60, (n % 1 * 1000).to_i ]
end

def echoa(as); as.each { |a| print a.is_a?(String) ? a : a.inspect }; end
def echon(*as); echoa(as); end
def echo(*as); echoa(as + [ "\r\n" ]); end

def prompt(ctx)

  cols = ctx[:cols]

  du = s_to_ms(ctx[:duration])
  ed = s_to_ms(ctx[:elapsed])

  print(CUG + CUU)
  print(
    ("    %-#{cols - 4}s" % ctx[:aad]
      )[0, cols])
  print(CUG + CUD)
  print(
    ("  > %-#{cols - 4}s" % "#{ctx[:trackn]} #{ed} / #{du}  #{ctx[:title]}"
      )[0, cols - 1])
end

def determine_next(ctx, dir)

  ctx[:next] = (ctx[:index] || 0) + dir

  if ctx[:next] < 0
    ctx[:next] = ctx[:tracks].length - 1
  elsif ctx[:next] >= ctx[:tracks].length
    ctx[:next] = 0
  end
end

def play(ctx)

  ctx[:cols] = (`tput cols`.to_i rescue 80)

  index = ctx[:index] = ctx[:position] ? ctx[:index] : ctx.delete(:next)
  determine_next(ctx, 1)
  path = ctx[:path] = ctx[:tracks][index]
  fn = ctx[:fname] = File.basename(path)

  pos = (
    (ctx.delete(:position) || 0).to_f *
    (ctx[:rate] || DEVICE_SAMPLE_RATE)
      ).to_i

  prompt(ctx)

  decode(ctx)

  pid = ctx[:aucat_pid] = spawn("aucat -g #{pos} -i #{ctx[:wav]}")
  t0 = monow

  Thread.new do
    loop do
      ctx[:elapsed] = monow - t0
      break if Process.wait2(pid, Process::WNOHANG)
      sleep 0.42
      prompt(ctx)
    end
    QUEUE << :over
  end
end

def stop(ctx)

  prompt(ctx)

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
  elsif ctx[:next]
    play(ctx)
  else
    exit 0
  end
end

def do_back(ctx)

  determine_next(ctx, -1)
  stop(ctx)
end

def do_next(ctx)

  determine_next(ctx, 1)
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

  ctx[:next] = 0
  stop(ctx)
end

def do_again(ctx)

  ctx[:next] = ctx[:index]
  stop(ctx)
end

def do_sunset(ctx)

  # TODO
end

def do_context(ctx)

  echo '{'
  ctx.each do |k, v|
    echon "  #{k}: "
    if k == :tracks
      echo "(#{v.size} tracks)"
    else
      echo v
    end
  end
  echo '}'
  echo
end

def do_tracks(ctx)

  i = ctx[:index]
  n = ctx[:next]

  ctx[:tracks].each_with_index do |t, j|
    pre = '    '
    pre[1] = 'n' if n == j
    pre[2] = '>' if i == j
    echo [ '%03d' % j, pre, t ].join('')
  end
  echo
end

def do_exit(ctx)

  ctx.delete(:next)
  stop(ctx)
end

#
# our work loop

def work(ctx)

  loop { send("do_#{QUEUE.pop}", ctx) }

rescue => err

  stop(ctx) rescue nil

  echo err
  (err.backtrace[0, 7] + [ '...' ]).each { |l| echo l }
  exit 1
end

#
# establish list of tracks

tracks = (args.empty? ? [ '.' ] : args)
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

#
# launch work thread on target list

echo ''

QUEUE << :over
Thread.new { work(tracks: tracks, opts: opts, next: 0) }

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
  when 'S' then QUEUE << :sunset
  when 'C' then QUEUE << :context
  when 'T' then QUEUE << :tracks
  #else print(a)
  end
end

