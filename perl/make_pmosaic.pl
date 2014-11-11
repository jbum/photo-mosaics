#!/usr/local/bin/perl

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
  -quick        Only use 1000 images or so...
  -dupesOK      Allow duplicate tiles (default = 1)
  -ownerdupesOK Allow duplicate owner photos nearby each other (default = 0)
  -minDupeDist \# Min Duplicate Dist
  -mixin \#      Mix background in (percentage)
  -tint         Use low-memory version of mixin (which shades tiles).
  -strip        Output image in strips.
  -png          Output PNG version of image.
  -noborders    Reject images with solid-color borders or over 2:1 aspect ratio
  -noflops       Images may not be swapped horizontally
  -reso \#      Subsamples per photo (use \#x\# or \#) - default = 7
  -resox \#     Subsamples per photo (X only) - default = 7
  -resoy \#     Subsamples per photo (Y only) - default = 7
  -cellsize \#  Size of tiles - default = 20
  -cspace       Color space (0=default (normalized) 8=8-bits per component, 4=4-bits, etc.) (new)
  -hmode        Heatmap Mode, with overlapping cells - uses cspace=3 by default (new)
  -hlimit       Heatmap Limit
  -hbase        Heatmap Base Image (defaults to target)
  -d imagedir   (Default=tiles)
  -load         Render from previous run (used to make -big versions)  
  
EOT

my $resoX = 7;
my $resoY = 0;
my $cellsize = 20;
my $doflops = 1;
my $verbose = 1;
my $accurate = 0; # doesn't use index to shorten color search...SLOW...
my $dupesOK = 1;
my $noDupeOwners = 1;
my $mixin = 0;
my $imageDir = '';
my $lab = 0;
my $tint = 0;
my $hmode = 0;  # heatmap style, with overlapping cells
my $hlimit = 0; # limit for photos in HMAP
my $hbase = '';
my $strip = 0;
my $png = 0;
my $speckle = 0;
my $cspace = 0;
my $noborders = 0;
my $ofilename = '';

my $minDupeDist = 8;
my $load = 0;	    # cause previously saved file to be used for rendering

# will generating cellsizes/cropping to meet these sizes...
my %outputSize = {
		'8x10'   =>   {wInches=>8, hInches=>10, bleed => .1, finalDPI=>300, previewDPI=>72},
		'letter' => 	{wInches=>8.5, hInches=>11, bleed => .1, finalDPI=>300, previewDPI=>72},
		'poster' => 	{wInches=>13.5, hInches=>19, bleed => .1, finalDPI=>300, previewDPI=>72}};


while ($_ = shift)
{
	if (/^-reso$/i) {
	  my $resStr = shift;
	  if ($resStr =~ /(\d+)x(\d+)/) {
	  	($resoX,$resoY) = ($1,$2);
	  }
	  else {
			$resoX = $resoY = $resStr;
	  }
	}
	elsif (/^-resoX$/i) {
		$resoX = shift;
	}
	elsif (/^-resoY$/i) {
		$resoY = shift;
	}
	elsif (/^-mixin$/i) {
		$mixin = shift;
	}
	elsif (/^-speckle$/i) {
		$speckle = 1;
	}
	elsif (/^-mindupedist$/i) {
		$minDupeDist = shift;
	}
	elsif (/^-cellsize/i) {
		$cellsize = shift;
	}
	elsif (/^-cspace/i) {
		$cspace = shift;
	}
	elsif (/^-hm?mode/i) {
		$hmode = 1;
	}
	elsif (/^-hlimit/i) {
		$hlimit = shift;
	}
	elsif (/^-hbase/i) {
		$hbase = shift;
	}
	elsif (/^-(verbose|v)$/) {
		$verbose = shift;
	}
	elsif (/^-big/) {
		$cellsize = 100;
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
	elsif (/^-(quick|q)$/i) {
		$quick = 1;
	}
	elsif (/^-d$/) {
		$imagedir = shift;
	}
	elsif (/^-nofl(i|o)ps/) {
		$doflops = 0;
	}
	elsif (/^-ownerdupesok/i) {
		$noDupeOwners = 0;
	}
	elsif (/^-o$/) {
		$ofilename = shift;
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

require "${photolist}";

$max_images = scalar(keys %photos)/4 if !$max_images;

my $sTime = time();

if (!$imageDir) {
	$imageDir = $photolist; 
	$imageDir =~ s/(_nb)?\.ph//;
}

my $imageset = Image::FlickrSet->new(\@photos, {cacheRoot => $imageDir, noDownload=>0, verbose=>1, noDupeOwners=>$noDupeOwners});

my $rootname = $photolist;
$rootname =~ s/\.ph//;

my $moz = Image::Mosaic->new({resoX=>$resoX,
															resoY=>$resoY,
                              max_images=>$max_images,
                              imageset=>$imageset,
                              basepic=>$basepic,
                              noborders=>$noborders,
                              doflops=>$doflops,
                              rootname=>$rootname,
                              cellsize=>$cellsize,
                              dupesOK=>$dupesOK,
                              lab=>$lab,
                              mixin=>$mixin,
                              speckle=>$speckle,
                              tint=>$tint,
                              accurate=>$accurate,
                              load=>$load,
                              cspace=>$cspace,
                              hmode=>$hmode,
                              hlimit=>$hlimit,
                              hbase=>$hbase,
                              strip=>$strip,
                              minDupeDist=>$minDupeDist,
                              verbose=>$verbose,
                              png=>$png,
                              filename=>$ofilename,
															});
if ($heatmap)
{
	$moz->make_heatmap("test.png");
	printf("DONE heatpmap: Elapsed = %d secs\n", time() - $sTime);
	exit;
}

$moz->generate_mosaic();
printf("DONE: Elapsed = %d secs\n", time() - $sTime);

