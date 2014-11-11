#!/usr/local/bin/perl -s

#
# USE THIS ONE when making custom mosaics from collections on DVD-ROMs and external drives.
#

#
# sub-sampling photo mosaic - Jim Bumgardner
#
# this script uses a subset of images from a larger set
# to make a mosaic against a target image
#
# work on reducing globals - store shared variables in an object...

use Image::Mosaic;
use Image::DVDSet;

$| = 1;

$syntax = <<EOT;
make_jmosaic.pl [options] <cachedir> <basepic> [<max_images>]

Options:
  -quick           Only use 1000 images or so...
  -dupesOK         Allow duplicate tiles
  -mixin \#        Mix background in (percentage)
  -noborders       Reject images with solid-color borders or over 2:1 aspect ratio
  -noflops         Images may not be swapped horizontally
  -reso=\#         Subsamples per photo - default = 7
  -cellsize=\#     Size of tiles - default = 20
  -forcedir <dir>  Directory for forced images
  -grayscale       Force result to grayscale
  -anno            Add annotations
  -dd #            Min Dupe Distance
EOT


my $resoX = 7;
my $resoY = 0;
my $cellsize = 20;
my $doflops = 0;
my $verbose = 1;
my $accurate = 0; # doesn't use index to shorten color search...SLOW...
my $dupesOK = 1;
my $mixin = 0;
my $speckle = 0;
my $cmode = 'Blend';

my $load = 0;
my $hmode = 0;  # heatmap style, with overlapping cells
my $hlimit = 0; # limit for photos in HMAP
my $hbase = '';
my $cspace = 0;
my $anno = 0;
my $filename = '';
my $forcedir = '';
my $grayscale = 0;
my $dd = 8; # min dupe dist
my $strip = 0;

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
	elsif (/^-strip$/i) {
		$strip = 1;
	}
	elsif (/^-speckle$/i) {
		$speckle = 1;
	}
	elsif (/^-anno$/i) {
		$anno = 1;
	}
	elsif (/^-cmode$/i) {
		$cmode = shift;
	}
	elsif (/^-cellsize/) {
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
	elsif (/^-filename/i) {
		$filename = shift;
	}
	elsif (/^-(verbose|v) /) {
		$verbose = shift;
	}
	elsif (/^-forcedir$/) {
		$forcedir = shift;
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
	elsif (/^-dd$/) {
		$dd = shift;
	}
	elsif (/^-load/i) {
		$load = 1;
	}
	elsif (/^-gr[ea]y(scale)?$/i) {
		$grayscale = 1;
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
	elsif ($cachedir) {
		$basepic = $_;
	}
	else {
		$cachedir = $_;
	}
}

die "$syntax\n" if !$basepic;

@photos = ();

print "Loading images\n";
foreach (<$cachedir/*>)
{
	next if !(/(png|jpg|gif)$/);
	my $prec = {nam=>"$_"};
	# $prec->{dupecode} = int($1) if /\/xx_(\d\d)_/i;
	print "Dupecode $prec->{dupecode}\n", if defined $prec->{dupecode};
	push @photos, $prec;
}
print "Loading images done\n";

die "No photos found\n" if @photos == 0;
# require 'hurlowpix.ph';

#
# these are all command line options
#
#$max_images = scalar(@photos) if !$dupesOK;
#print "Max Images = $max_images\n";


my $sTime = time();

if ($forcedir ne '') {
  my $n = 0;
	foreach (<$forcedir/*>)
	{
		next if !(/(png|jpg|gif)$/);
		push @photos, {nam=>"$_", force=>1};
		++$n;
	}
  printf "Adding $n forces\n";
}

$max_images = scalar(@photos)/4 if !$max_images;
print "Max Images = $max_images\n";

my $imageset = Image::DVDSet->new(\@photos, {verbose=>1});


my $moz = Image::Mosaic->new({resoX=>$resoX,
															resoY=>$resoY,
                              max_images=>$max_images,
                              imageset=>$imageset,
                              basepic=>$basepic,
                              noborders=>$noborders,
                              doflops=>$doflops,
                              cellsize=>$cellsize,
                              cspace=>$cspace,
                              hmode=>$hmode,
                              hlimit=>$hlimit,
                              hbase=>$hbase,
                              load=>$load,
                              dupesOK=>$dupesOK,
                              minDupeDist=>$dd,
                              mixin=>$mixin,
							  strip=>$strip,
                              grayscale=>$grayscale,
                              cmode=>$cmode,
                              anno=>$anno,
                              filename=>$filename,
                              speckle=>$speckle,
                              accurate=>$accurate,
                              verbose=>$verbose,
                              hasForces=>$forcedir ne '',
															});

if ($heatmap)
{
	$moz->make_heatmap("test.png");
	printf("DONE heatpmap: Elapsed = %d secs\n", time() - $sTime);
	exit;
}
$moz->generate_mosaic();
printf("DONE: Elapsed = %d secs\n", time() - $sTime);

