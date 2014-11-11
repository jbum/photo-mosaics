require 'mosaick'
require 'optparse'
require 'json'

$verbose = false
$ifname = 'untitled'


$resoX = 7
$resoY = 0
$cellsize = 20
$doflops = true
$verbose = true
$accurate = false
$draft = false
$dupesOK = true
$noDupeOwners = false
$mixin = 0
$imageDir = ''
$lab = false
$tint = false
$hmode = false  # heatmap style, with overlapping cells
$hlimit = 0 # limit for photos in HMAP
$hbase = ''
$strip = false
$png = false
$speckle = false
$cspace = 0
$noborders = false
$ofilename = ''
$minDupeDist = 8
$load = false
$basepic = ''
$max_images = 0
$heatmap = false
$usevars = false
$quality = 90
$anno = false
$grayscale = false

OptionParser.new do |o|
  o.banner = 'build_fmosaic [<options>] <photolist> [<target-image> [<max-tiles>]]'
  o.separator ''
  o.on('-x', '--resox X',Integer,'Resolution X') { |rx| $resoX = rx }
  o.on('-y', '--resoy Y',Integer,'Resolution Y') { |ry| $resoY = ry }
  o.on('-r', '--reso XxY','Resolution X x Y') { |reso| 
    if (reso =~ /(\d+)x(\d+)/)
      $resoX = $1.to_i
      $resoY = $2.to_i
    else
      $resoX = $resoY = reso.to_i
    end
  }
  o.on('-o', '--ofname o','Output filename') { |ofn| $ofilename = ofn }
  o.on('-p', '--png','Produce image in PNG format instead of JPG') { |b| $png = b }
  o.on('-q', '--quality q',Integer,'JPEG quality (default=90)') { |q| $quality = q }
  o.on('-c', '--cellsize C',Integer,'Cell size, default=20') { |c| $cellsize = c }
  o.on('-b', '--big','Force large cell size cellsize=100') { |b| $cellsize = 100 }
  o.on('-l', '--load','Load tile placement data from previous run (use to render alternate sizes)') { |b| $load = b }
  o.on('-n', '--[no-]borders','Reject images with solid-color borders or over 2:1 aspect ratio (def=false)') { |b| $noborders = !b }
  o.on('-f', '--[no-]flops','Images may be swapped horizontally for better matching (def=true)') { |b| $doflops = b }
  o.on('-o', '--[no-]ownerdupes','Allow duplicate owner photos near each other (def=true)') { |b| $ownerdupesok = b }
  o.on('-o', '--[no-]variations','Try variations in cropping for better matches (def=false) 3X slower') { |b| $usevars = b }

  o.on('-m', '--mindupedist M',Integer,'Min duplicate distance') { |m| $minDupeDist = m }
  o.on('-m', '--mixin M',Integer,'Mix-in amount (0-100)') { |m| $mixin = m }
  o.on('-c', '--cspace C',Integer,'Color space, 0 = normalized 8=8 bits, 4=4 bits UNSUPPORTED') { |c| $cspace = c }
  o.on('-h', '--hmode','Heatmap mode, experimental') { |b| $hmode = b }
  o.on('-h', '--hlimit L',Integer,'Heatmap limit (number of images to map)') { |l| $hlimit = l }
  o.on('-h', '--hbase h','Heatmap base image (file or color)') { |h| $hbase = h }
  o.on('-s', '--strip','Produce image in strips to conserve memory UNSUPPORTED') { |b| $stripe = b }
  o.on('-l', '--lab','Put labels on cells') { |b| $lab = b }
  o.on('-a', '--accurate','2x slower than normal, slightly better results') { |b| $accurate = b }
  o.on('-a', '--draft','3x faster than normal, slightly worse results') { |b| $draft = b }
  o.on('-h', '--heatmap','Generate a heat map') { |b| $heatmap = b }
  o.on('-q', '--anno','Adds cell labels') { |b| $anno = b }
  o.on('-g', '--grayscale','Convert output to grayscale') { |b| $grayscale = b }

  o.on('-q', '--quick','Only use 1000 images or so (for debugging)') { |b| $quick = b }

  o.on('-v', '--verbose','Verbose messages') { |b| $verbose = b }
  o.on('-h', '--help', 'Display this screen') { puts o; exit }
  o.parse!
end

if (ARGV.length > 3)
  puts("Too many arguments, use -h for help")
  exit
end
if (ARGV.length > 2)
  $max_images = ARGV[2].to_i
end
if (ARGV.length > 1)
  $basepic = ARGV[1]
end
if (ARGV.length > 0)
  $ifname = ARGV[0].dup
  $photolistName = ARGV[0].dup
end

if (!$basepic)
  puts("Not enough arguments, use -h for help")
  exit
end

$ifname += ".json" if not $ifname =~ /\.json$/

if !File.exists?($ifname)
  puts "File #{$ifname} does not exist"
  exit
end
$resoY = $resoX if $resoY == 0
puts "#{$resoX} x #{$resoY}"
puts "Photolist #{$ifname}" if $verbose
photos = JSON.parse(File.read($ifname))


$max_images = photos.length / 4 if $max_images == 0
if !$imageDir
  $imageDir = $photolistName.dup
  $imageDir.sub!(/(_nb)?\.\w+$/,'')
end

imageSet = FlickrSet.new( :photos => photos, 
                          :cacheRoot => $imageDir,
                          :downloadOK => true,
                          :verbose => true,
                          :dupeOwnersOK => !$noDupeOwners )

$rootname = $photolistName.dup
puts "rootName = #{$rootname}"
$rootname.sub!(/\.\w+$/,'')

moz = Mosaick.new(:resoX => $resoX,
                  :resoY => $resoY,
                  :max_images => $max_images,
                  :imageset => imageSet,
                  :basepic => $basepic,
                  :noborders => $noborders,
                  :doflops => $doflops,
                  :rootname => $rootname,
                  :cellsize => $cellsize,
                  :dupesOK => $dupesOK,
                  :lab => $lab,
                  :mixin => $mixin,
                  :speckle => $speckle,
                  :tint => $tint,
                  :accurate => $accurate,
                  :draft => $draft,
                  :usevars => $usevars,
                  :load => $load,
                  :cspace => $cspace,
                  :hmode => $hmode,
                  :hlimit => $hlimit,
                  :hbase => $hbase,
                  :strip => $strip,
                  :minDupeDist => $minDupeDist,
                  :verbose => $verbose,
                  :png => $png,
                  :filename => $ofilename,
                  :quality => $quality,
                  :anno => $anno,
                  :grayscale => $grayscale)
if ($heatmap)
  moz.make_heatmap("heatmap.png")
  puts("Done making heatmap") # !! include timing info
  exit
end

moz.generate_mosaic()
puts "Done making mosaic" # !! include timing info
