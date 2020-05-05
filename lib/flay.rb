#!/usr/bin/env ruby

require 'digest'
require 'fileutils'
require 'io/console'

#
# arg shuffling

args = ARGV.dup
argrs = []
while i = args.index('-r')
  argrs <<
    Regexp.new(
      args.slice!(i, 2)[1],
      Regexp::IGNORECASE)
end

opts, args = args.partition { |a| a[0, 1] == '-' }
argis, args = args.partition { |a| a.match(/^\d+$/) }
argi = argis.collect { |a| a.to_i }.last

if opts.include?('-h') || opts.include?('--help')
  puts '    ruby flay path/to/file.flac'
  puts 'OR  ruby flay path/to/dir_of_flac_files/'
  exit 0
end

TMP_DIR = '/tmp'

CUU = "\e[A" # cursor up
CUD = "\e[B" # cursor down
CUL = "\e[D" # cursor left
CUG = "\e[G" # cursor home
CUHIDE = "\e[?25l"
CUSHOW = "\e[?25h"
print CUHIDE
at_exit { print CUSHOW }
  #
  # https://en.wikipedia.org/wiki/ANSI_escape_code#Terminal_output_sequences
  #
#system('tput civis') # hide cursor
#system('tput norm')  # show cursor

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

def decode_flac(ctx)

  path = ctx[:path]

  if m = path.match(/^(.+)__(\d+)___*\d+m\d+s\d+__(.+)\.flac$/)
    ctx[:aad] = space(m[1])
    ctx[:trackn] = m[2].to_i
    ctx[:title] = space(m[3])
  end

  system("flac -d \"#{path}\" -o #{ctx[:wav]} > /dev/null 2>&1")
end

def decode_mp3(ctx)

  system("mpg123 -w #{ctx[:wav]} \"#{ctx[:path]}\" > /dev/null 2>&1")
end

def decode_m4a(ctx)

  system("faad -o #{ctx[:wav]} \"#{ctx[:path]}\" > /dev/null 2>&1")
end
#alias decode_aac decode_m4a

def decode(ctx)

  pa = ctx[:path]
  ps = pa.split('/')
  fn = ps.last
  dpa = Digest::SHA256.hexdigest(ps[0..-2].join('/'))[0, 14]
  suf = "i#{ctx[:index].to_s}__#{dpa}__#{fn.gsub(/[^a-zA-Z0-9]/, '_')}"

  ctx[:aad] = [ ps[-3], ps[-2] ].join(' ')
  ctx[:trackn] = (fn.match(/(?!d)(\d{1,3})/) || [ nil, '-1' ])[1].to_i
  ctx[:title] = File.basename(fn, File.extname(fn))
  ctx[:wav] = wav = File.join(TMP_DIR, "flay__#{Process.pid}__#{suf}.wav")

  send("decode_#{File.extname(ctx[:path])[1..-1]}", ctx)

  ctx[:rate], ctx[:duration] = wav_info(wav)
end

def s_to_ms(n);
  n = n || 0
  na = n.abs
  d = n < 0 ? 4 : 3
  "%#{d}dm%02ds" % [ (n / 60).to_i, na.to_i % 60 ]
end
#def s_to_mss(n);
#  n = n || 0
#  "%3dm%02ds%02d" % [ (n / 60).to_i, n.to_i % 60, (n % 1 * 1000).to_i ]
#end

def echoa(as); as.each { |a| print a.is_a?(String) ? a : a.inspect }; end
def echon(*as); echoa(as); end
def echo(*as); echoa(as + [ "\r\n" ]); end

def prompt(ctx)

  cols = ctx[:cols]

  du = s_to_ms(ctx[:duration])
  ed = s_to_ms(ctx[:elapsed])
  tn = '%02d' % ctx[:trackn]
  ix = ctx[:index]

  st = ctx[:position] ? '|' : '>'
  re = s_to_ms(-(ctx[:duration] || 0) + (ctx[:elapsed] || 0))

  li = '-' * 40
  li[((ctx[:elapsed] / ctx[:duration]) * li.size).to_i] = st

  print(CUG + CUU)
  print(("  %-#{cols - 2}s" %
    ctx[:aad]
      )[0, cols])
  print(CUG + CUD)
  print(("  %-#{cols - 2}s" %
    "#{ix} #{ed} #{li} #{re} #{du}  #{tn} #{ctx[:title]}"[0, cols - 2]
      )[0, cols])
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

  index = ctx[:index] = (ctx[:position] ? ctx[:index] : ctx.delete(:next))
  determine_next(ctx, 1)
  path = ctx[:path] = ctx[:tracks][index]
  fn = ctx[:fname] = File.basename(path)

  pos = (ctx.delete(:position) || 0).to_f
  g = (pos * (ctx[:rate] || DEVICE_SAMPLE_RATE)).to_i

  decode(ctx)

  cmd = ctx[:cmd]= "aucat -g #{g} -i #{ctx[:wav]}"
  pid = ctx[:aucat_pid] = spawn(cmd)
  t0 = monow

  Thread.new do
    loop do
      ctx[:elapsed] = pos + monow - t0
      break if Process.wait2(pid, Process::WNOHANG)
      sleep 0.42
      prompt(ctx)
    end
    QUEUE << :over
  end
end

def stop(ctx)

  pid = ctx[:aucat_pid]

  (Process.kill('TERM', pid) rescue nil) if pid && pid > 0

  FileUtils.rm(
    Dir[File.join(TMP_DIR, "flay__#{Process.pid}__*.wav")],
    force: true)

  ctx.delete(:wav)
  ctx.delete(:cmd)
  ctx[:aucat_pid] = -1

  exit 0 unless ctx[:next]
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

def do_pause_or_play(ctx)

  if ctx[:position]
    play(ctx)
  else
    ctx[:position] = -1
    stop(ctx)
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

def do_rewind(ctx)

  ctx[:next] = 0
  stop(ctx)
end

def do_again(ctx)

  ctx[:next] = ctx[:index]
  stop(ctx)
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

def do_random(ctx)

  r = File.open('/dev/urandom', 'rb') { |f| f.read(7) }.codepoints
    .collect(&:to_s).join.to_i
      # This is OpenBSD!
  ctx[:next] = r % ctx[:tracks].length
  stop(ctx)
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
      Dir[File.join(t, '**', '*.{flac,mp3,m4a}')]
    else
      t
    end }
  .flatten
  .select { |t| t.match(/\.(flac|mp3|m4a)$/i) }
  .select { |t| argrs.empty? || argrs.find { |r| File.basename(t).match?(r) } }
  .sort

if tracks.empty?
  puts 'found no tracks.'
  exit 1
end

#
# launch work thread on target list

echo ''

QUEUE << :over
Thread.new { work(tracks: tracks, opts: opts, next: argi || 0) }

#
# command loop

loop do
  case a = STDIN.getch

  when 'b' then QUEUE << :back
  when 'n' then QUEUE << :next
  when 'r' then QUEUE << :rewind
  when 'a' then QUEUE << :again
  when 'p', ' ' then QUEUE << :pause_or_play
  when '@' then QUEUE << :random

  when 'C' then QUEUE << :context
  when 'T' then QUEUE << :tracks

  when 'q', "\u0003" then QUEUE << :exit  # q and CTRL-c
  #else print(a)
  end
end

