# port of getPhotoList.pl - Jim Bumgardner

require 'flickraw-cached'
require 'yaml'
require 'pp'
require 'optparse'
require 'json'
require 'pry'

# todo: support setting limit via -l
# figure out how to convert results...

tags = ''
$limit = 4500
$ofname = 'untitled.json'
$extras = ''
$verbose = false

OptionParser.new do |o|
  o.banner = 'getPhotoList.rb [<options>] tag [tag [...]]'
  o.separator ''
  o.on('-l', '--limit LIMIT', 'Maximum number of photos') { |lim| $limit = lim.to_i }
  o.on('-o', '--outfile FILE','Output filename') { |fname| $ofname = fname }
  o.on('-e', '--extras extras','Extra fields to include, comma delimited') { |extras| $extras = extras }
  o.on('-v', '--verbose','Verbose messages') { |b| $verbose = b }
  o.on('-h', '--help', 'Display this screen') { puts o; exit }
  o.parse!
end

$tags = ARGV.join(',')

if $ofname == "untitled.json" and $tags != ""
  $ofname = $tags + ".json"
  $ofname.gsub!(",","_")
end

p :limit => $limit, :ofname => $ofname, :tags => $tags, :extras => $extras

yml = YAML.load_file 'flickr_apikey.yml'

FlickRaw.api_key=yml['api_key']
FlickRaw.shared_secret=yml['sharedsecret']
$auth_token = yml['hipbot']['auth_token']

# puts "auth_token = " + auth_token
nbrPages = 0
photos= []

begin
  puts "Page #{nbrPages+1}"
  begin
    pphotos = flickr.photos.search :per_page => 500, :page => nbrPages+1,
              :tags => $tags, :auth_token => $auth_token, :format => 'json'
    pphotos.each do |p|
      photos <<= p.to_hash
    end
    nbrPages += 1
    puts "Got #{pphotos.length} photos total #{photos.length}"
  rescue FlickRaw::FailedResponse => e
    puts "Authentication failed : #{e.msg}"
  end
end while pphotos.length > 0 and photos.length < $limit

# binding.pry

File.open($ofname,"w") do |f|
  # dump = PP.pp(photos,"")
  # f.write("photos = " + dump)
  f.write(JSON.pretty_generate(photos))
end
puts "Wrote #{photos.length} photos to #{$ofname}"

