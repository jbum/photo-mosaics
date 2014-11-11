#!/usr/bin/perl

#
# sub-sampling photo mosaic - Jim Bumgardner
#
# this script uses a subset of images from a larger set
# to make a mosaic against a target image
#
# work on reducing globals - store shared variables in an object...

use Image::Mosaic;
use Image::SimpleSet;


$syntax = <<EOT;
make_gmosaic.pl [options] <basepic> [<max_images>]

Options:
  -quick        Only use 1000 images or so...
  -dupesOK      Allow duplicate tiles
  -noborders    Reject images with solid-color borders or over 2:1 aspect ratio
  -noflops      Images may not be swapped horizontally
  -reso=\#      Subsamples per photo - default = 7
  -cellsize=\#  Size of tiles - default = 20
  -d imagedir   (Default=tiles)
EOT

my $imagedir = 'tiles';
my $resoX = 7;
my $resoY = 0;
my $cellsize = 20;
my $doflops = 1;
my $accurate = 0; # doesn't use index to shorten color search...SLOW...
my $verbose = 1;
my $dupesOK = 1;

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
	elsif (/^-cellsize/) {
		$cellsize = shift;
	}
	elsif (/^-(verbose|v)$/) {
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
	else {
		$basepic = $_;
	}
}


die "$syntax\n" if !$basepic;

@photos = ();
require 'rock.ph';
if (!$quick)
{
	require 'clouds.ph';
	require 'landscape.ph';
	require 'trees.ph';
	require 'ocean.ph';
	require 'sunset.ph';
	require 'light.ph';
	require 'snow.ph';
	require 'flower.ph';
}

$max_images = scalar(@photos)/4 if !$max_images;

my $imageset = Image::SimpleSet->new(\@photos, {imageDir => $imagedir, verbose=>1});
my $sTime = time();
my $moz = Image::Mosaic->new({resoX=>$resoX,
															resoY=>$resoY,
                              max_images=>$max_images,
                              imageset=>$imageset,
                              basepic=>$basepic,
                              noborders=>$noborders,
                              doflops=>$doflops,
                              cellsize=>$cellsize,
                              dupesOK=>$dupesOK,
                              accurate=>$accurate,
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
