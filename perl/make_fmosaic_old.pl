#!/usr/local/bin/perl -s

#
# sub-sampling photo mosaic - Jim Bumgardner
#
# this script uses a subset of images from a larger set
# to make a mosaic against a target image
#
# work on reducing globals - store shared variables in an object...

use Image::Mosaic;
use Image::HFlickrSet;

$syntax = <<EOT;
make_fmosaic.pl [options] <photolist> <basepic> [<max_images>]

Options:
  -quick        Only use 1000 images or so...
  -dupesOK      Allow duplicate tiles
  -mixin \#      Mix background in (percentage)
  -noborders    Reject images with solid-color borders or over 2:1 aspect ratio
  -noflops       Images may not be swapped horizontally
  -reso=\#      Subsamples per photo - default = 7
  -cellsize=\#   Size of tiles - default = 20
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
my $mixin = 0;
my $load = 0;	    # cause previously saved file to be used for rendering


while ($_ = shift)
{
	if (/^-reso$/i) {
		$resoX = $resoY = shift;
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
	elsif (/^-cellsize/) {
		$cellsize = shift;
	}
	elsif (/^-(verbose|v) /) {
		$verbose = shift;
	}
	elsif (/^-big/) {
		$cellsize = 100;
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

my $imageset = Image::HFlickrSet->new(\%photoList, {cacheRoot => 'C:/Documents and Settings/jbum/My Documents/websites/krazydad/flickr/snaps', verbose=>1});

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
                              mixin=>$mixin,
                              accurate=>$accurate,
                              load=>$load,
                              verbose=>$verbose
															});
if ($heatmap)
{
	$moz->make_heatmap("test.png");
	printf("DONE heatpmap: Elapsed = %d secs\n", time() - $sTime);
	exit;
}

$moz->generate_mosaic();

printf("DONE: Elapsed = %d secs\n", time() - $sTime);

