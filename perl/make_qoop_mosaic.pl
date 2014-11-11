#!/usr/bin/perl

# make photo mosaic tailored for QOOP service.
#
# sub-sampling photo mosaic - Jim Bumgardner
#
# this script uses a subset of images from a larger set
# to make a mosaic against a target image
#
# work on reducing globals - store shared variables in an object...

use Image::Mosaic;
use Image::FlickrSet;

$syntax = <<EOT;
make_pmosaic.pl [options] <photolist> <basepic> [<max_images>]

Options:
  -dupesOK      Allow duplicate tiles (or noDupes)
  -minDupeDist \# Min Duplicate Dist
  -mixin \#      Mix background in (percentage)
  -tint         Use low-memory version of mixin (which shades tiles).
  -strip        Output image in strips.
  -png          Output PNG version of image.
  -noborders    Reject images with solid-color borders or over 2:1 aspect ratio
  -noflops       Images may not be swapped horizontally
  -reso \#      Subsamples per photo - default = 7
  -cellsize \#   Size of tiles - default = 20
  -d imagedir   (Default=tiles)
  -load         Render from previous run (used to make -big versions)  
  -outputSize   (normal, 8x10, letter, poster)
  -tileShape    (square, 3x4 5x7, 4x6, 7x9, 8x10,   portrait: 3x4p 5x7p, 4x6p, 7x9p, 8x10p)
  -tileDensity  (extracourse, course, medium, fine, superfine, microfine)
  -vars         Use image anchoring variations (or novars)
  -o filename   Output image filename 
  -final        Output high-res (usually combined with -load)
  
EOT

my $resoX = 7;
my $resoY = 0;
my $cellsize = 0;
my $doflops = 1;
my $verbose = 1;
my $accurate = 0; # doesn't use index to shorten color search...SLOW...
my $dupesOK = 1;
my $minDupeDist = 8;
my $mixin = 0;
my $imageDir = '';
my $lab = 0;
my $tint = 0;
my $strip = 0;
my $png = 0;
my $crop = 0;
my $outputSize = 'normal';
my $tileShape = 'square';
my $tileDensity = 'medium';
my $minWidth = 0;
my $minHeight= 0;
my $final = 0;
my $dpi = 72;
my $oname = '';
my $useVars = 0;

my $load = 0;     # cause previously saved file to be used for rendering

# will generating cellsizes/cropping to meet these sizes...
my %outputSizes = (
    'normal' =>   {wInches=>8.5, hInches=>11, bleed => .1, finalDPI=>300, previewDPI=>72, crop=>0},
    # standard QOOP sizes
    '8x10'   =>   {wInches=>8, hInches=>10, bleed => .1, finalDPI=>300, previewDPI=>72, crop=>1},
    'letter' =>   {wInches=>8.5, hInches=>11, bleed => .1, finalDPI=>300, previewDPI=>72, crop=>1},
    'poster' =>   {wInches=>13.5, hInches=>19, bleed => .1, finalDPI=>300, previewDPI=>72, crop=>1},
    'tshirt' =>   {wInches=>11, hInches=>11, bleed => 0, finalDPI=>300, previewDPI=>72, crop=>1},
    );

my %tileDensities = (
  'extracourse' => 400,   # extra course
  'course'    => 600,   # course
  'medium'    => 900,   # medium
  'normal'    => 900,   
  'fine'      => 1350,  # fine
  'superfine' => 2025,  # superfine
  'microfine' => 4000); # microfine
  
my %tileShapes = (
    'square'  => {resoX=>7, resoY=>7},
    # landscape
    '4x6'     => {resoX=>6, resoY=>4},  # 1.5
    '5x7'     => {resoX=>7, resoY=>5},  # 1.4
    '3x4'     => {resoX=>4, resoY=>3},  # 1.333
    '7x9'     => {resoX=>9, resoY=>7},  # 1.285...
    '8x10'    => {resoX=>10, resoY=>8},  # 1.25
    # portrait
    '4x6p'      => {resoX=>4, resoY=>6}, # .66
    '5x7p'      => {resoX=>5, resoY=>7}, # .714
    '3x4p'      => {resoX=>3, resoY=>4}, # .75
    '7x9p'      => {resoX=>7, resoY=>9}, # .77
    '8x10p'     => {resoX=>8, resoY=>10}); # .8



while ($_ = shift)
{
  if (/^-reso$/i) {
    $resoX = $resoY = shift;
  }
  elsif (/^-resoX$/i) {
    $resoX = shift;
    $tileShape = '';
  }
  elsif (/^-resoY$/i) {
    $resoY = shift;
  }
  elsif (/^-mixin$/i) {
    $mixin = shift;
  }
  elsif (/^-mindupedist$/i) {
    $minDupeDist = shift;
  }
  elsif (/^-cellsize/) {
    $cellsize = shift;
  }
  elsif (/^-(verbose|v)$/) {
    $verbose = shift;
  }
  elsif (/^-(big|final)/) {
    $final = 1;
  }
  elsif (/^-tint/) {
    $tint = 1;
  }
  elsif (/^-strip/) {
    $strip = 1;
  }
  elsif (/^-png/) {
    $png = 1;
  }
  elsif (/^-lab/) {
    $lab = 1;
  }
  elsif (/^-dupesok/i) {
    $dupesOK = 1;
  }
  elsif (/^-nodupes/i) {
    $dupesOK = 0;
  }
  elsif (/^-load/i) {
    $load = 1;
  }
  elsif (/^-accurate/i) {
    $accurate = 1;
  }
  elsif (/^-noborders/i) {
    $noborders = 1;
  }
  elsif (/^-heatmap/i) {
    $heatmap = 1;
  }
  elsif (/^-d$/) {
    $imagedir = shift;
  }
  elsif (/^-nofl(i|o)ps/) {
    $doflops = 0;
  }
  elsif (/^-vars$/) {
    $useVars = 1;
  }
  elsif (/^-novars$/) {
    $useVars = 0;
  }
  elsif (/^-tileshape/i) {
    $tileShape = shift;
  }
  elsif (/^-tiledensity/i) {
    $tileDensity = shift;
  }
  elsif (/^-outputsize/i) {
    $outputSize = shift;
  }
  elsif (/^-o$/i) {
    $oname = shift;
  }
  elsif (/^-/) {
    die "unknown option: $syntax\n";
  }
  elsif ($max_images) {
    die "too many args: $syntax\n";
  }
  elsif ($basepic) {
    $max_images = $_;
  }
  elsif ($photolist) {
    $basepic = $_;
  }
  else {
    $photolist = $_;
  }
}

die "$syntax\n" if !$basepic;
print "Requiring $photolist\n";
require "${photolist}";

$max_images = scalar(keys %photos)/4 if !$max_images;

my $sTime = time();

if (!$imageDir) {
  $imageDir = $photolist; 
  $imageDir =~ s/(_nb)?\.ph//;
}

my $imageset = Image::FlickrSet->new(\@photos, {cacheRoot => $imageDir, noDownload=>0, verbose=>1});

my $rootname = $photolist;
$rootname =~ s/\.ph//;

if ($tileShape) 
{
  die ("Unsupported tile shape: $tileShape\n") if !(defined $tileShapes{$tileShape});
  $resoX = $tileShapes{$tileShape}->{resoX};
  $resoY = $tileShapes{$tileShape}->{resoY};
  print "Tilewidth: $resoX x $resoY\n";
}

if ($outputSize) 
{

  die ("Unsupported output size: $outputSize\n") if !(defined $outputSizes{$outputSize});
  $dpi = $final? $outputSizes{$outputSize}->{finalDPI} : $outputSizes{$outputSize}->{previewDPI};
  $minWidth = int(($outputSizes{$outputSize}->{wInches}+$outputSizes{$outputSize}->{bleed}*2)*$dpi + .5);
  $minHeight = int(($outputSizes{$outputSize}->{hInches}+$outputSizes{$outputSize}->{bleed}*2)*$dpi + .5);
  $crop = $outputSizes{$outputSize}->{wInches}->{crop};
  print "Minwidth: $minWidth MinHeight: $minHeight Crop: $crop\n";
}

if ($tileDensity) 
{
  if (int($tileDensity) > 0)
  {
    $max_images = $tileDensity;
  }
  else {
    die ("Unsupported tile density: $tileDensity\n") if !(defined $tileDensities{$tileDensity});
    $max_images = $tileDensities{$tileDensity};
  }
  print "Tile Density: about $max_images images\n";
}

my $args = {resoX=>$resoX,
            resoY=>$resoY,
            max_images=>$max_images,
            imageset=>$imageset,
            basepic=>$basepic,
            noborders=>$noborders,
            doflops=>$doflops,
            rootname=>$rootname,
            cellsize=>$cellsize,
            dupesOK=>$dupesOK,
            minDupeDist=>$minDupeDist,
            lab=>$lab,
            mixin=>$mixin,
            tint=>$tint,
            accurate=>$accurate,
            load=>$load,
            strip=>$strip,
            verbose=>$verbose,
            png=>$png,
            minWidth=>$minWidth,
            minHeight=>$minHeight,
            crop=>$crop,
            useVars=>$useVars,
            };

if ($oname ne '') 
{
  print "Setting args filename to $oname...\n";
  $args->{filename} = $oname;
}

my $moz = Image::Mosaic->new($args);

if ($heatmap)
{
  $moz->make_heatmap("test.png");
  printf("DONE heatpmap: Elapsed = %d secs\n", time() - $sTime);
  exit;
}

$moz->generate_mosaic();

printf("DONE: Elapsed = %d secs\nCopying $moz->{filename}...\n", time() - $sTime);

# `cp $moz->{filename} ../www/`;
# `chmod a+r ../www/$moz->{filename}`;

