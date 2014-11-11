#!/usr/local/bin/perl

#
# sub-sampling photo mosaic - Jim Bumgardner
#
# this script uses a subset of images from a larger set
# to make a mosaic against a target image
#
# work on reducing globals - store shared variables in an object...

use Image::Mosaic;
use Image::DVDSet;

$syntax = <<EOT;
make_jmosaic.pl [options] <includefile> <basepic> [<max_images>]

Options:
  -quick        Only use 1000 images or so...
  -dupesOK      Allow duplicate tiles
  -mixin \#      Mix background in (percentage)
  -noborders    Reject images with solid-color borders or over 2:1 aspect ratio
  -noflops       Images may not be swapped horizontally
  -reso=\#      Subsamples per photo - default = 7
  -cellsize=\#   Size of tiles - default = 20
  -d imagedir   (Default=tiles)
EOT


my $imagedir = 'sundancet'; # UNUSED
my $resoX = 7;
my $resoY = 0;
my $cellsize = 20;
my $doflops = 1;
my $verbose = 1;
my $accurate = 0; # doesn't use index to shorten color search...SLOW...
my $dupesOK = 1;
my $mixin = 0;
my $max_images = 800;
my $minDupeDist = 8;
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
	elsif (/^-mindupedist$/i) {
		$minDupeDist = shift;
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
	elsif ($basepic) {
		$max_images = $_;
	}
	elsif ($incfile) {
		$basepic = $_;
		
	}
	else {
		$incfile = $_;
	}
}

die "$syntax\n" if !$basepic;

@photos = ();
require $incfile;

#
# these are all command line options
#

$max_images = scalar(@photos)/4 if !$max_images;

my $sTime = time();

my $imageset = Image::DVDSet->new(\@photos, {imageDir => $imagedir, verbose=>1});
my $moz = Image::Mosaic->new({resoX=>$resoX,
															resoY=>$resoY,
                              max_images=>$max_images,
                              imageset=>$imageset,
                              basepic=>$basepic,
                              noborders=>$noborders,
                              doflops=>$doflops,
                              rootname=>'dvd',
                              cellsize=>$cellsize,
							  minDupeDist=>$minDupeDist,
							  dupesOK=>$dupesOK,
                              mixin=>$mixin,
                              accurate=>$accurate,
                              load=>$load,
                              verbose=>$verbose,
															});

if ($heatmap)
{
	$moz->make_heatmap("test.png");
	printf("DONE heatpmap: Elapsed = %d secs\n", time() - $sTime);
	exit;
}
$moz->generate_mosaic();
printf("DONE: Elapsed = %d secs\n", time() - $sTime);

