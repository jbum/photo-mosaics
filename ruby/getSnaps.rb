# port of getSnapsDir.pl - Jim Bumgardner
#

require 'json'
require 'pp'
require 'flickraw-cached'
require 'optparse'

def makeFlickrPath(photo, suffix)
  return sprintf "http://farm%s.static.flickr.com/%d/%s_%s%s.jpg", 
              photo['farm'],photo['server'],photo['id'],photo['secret'],suffix
end

def makeDirName(id)
  id = id.to_i
  return sprintf 'flickrcache/%03d/%03d/', (id/1000000)%1000, (id/1000)%1000;
end

def makeLocalPath(photo, suffix)
  return makeDirName(photo['id']) + photo['id'] + suffix + ".jpg";
end

def buildDirs(lname)
  dirs = lname.split(/\//)
  dirs.pop
  ldir = '';
  dirs.each do |d|
    break if d =~ /\.jpg/i
    ldir += '/' if ldir != ''
    ldir += d
    `mkdir #{ldir}` if !File.exists?(ldir)
  end
end

$suffix = '_t'
$ifname = 'untitled'
$big = true
$verbose = false
$reverse = false

OptionParser.new do |o|
  o.banner = 'getSnaps.rb [<options>] listfile[.json]'
  o.separator ''
  o.on('-b', '--big', 'Get larger photos') { |b| $big = b; $suffix = '' if $big }
  o.on('-r', '--reverse', 'Reverse order of photos') { |b| $reverse = b; }
  o.on('-v', '--verbose','Verbose messages') { |b| $verbose = b }
  o.on('-h', '--help', 'Display this screen') { puts o; exit }
  o.parse!
end


if (ARGV.length > 0)
  $ifname = ARGV[0]
end
$ifname += ".json" if not $ifname =~ /\.json$/

if !File.exists?($ifname)
  puts "File #{$ifname} does not exist"
  exit
end

puts "Photolist #{$ifname}" if $verbose
photos = JSON.parse(File.read($ifname))
photos.reverse! if $reverse
n = 0
ne = 0
photos.each do |p|
  url_b = makeFlickrPath(p, $suffix)
  l_path = makeLocalPath(p, $suffix)
  if File.exists?(l_path) and File.size(l_path) > 100
    ne += 1
    next
  end
  puts(url_b + " --> " + l_path) if $verbose
  buildDirs(l_path)
  # use curl to capture these...
  `curl -s #{url_b} >#{l_path}`
  n += 1
end
puts "Downloaded #{n} thumbnails" if n > 0 and $verbose
puts "#{ne} thumbs already exist" if ne > 0 and $verbose


