
opts, args = ARGV.partition { |a| a[0, 1] == '-' }

TMP_DIR = '/tmp'

def play(path)
  fn0 = File.basename(path)
  fn1 = File.basename(path, '.flac')
  out = File.join(TMP_DIR, fn1 + '.wav')
  system("flac -d #{path} -o #{out} > /dev/null 2>&1")
  puts "#{fn0} ..."
  system("aucat -i #{out}")
  #system("aucat -d -i #{out}")
ensure
  system("rm #{out} > /dev/null 2>&1") rescue nil
end

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

