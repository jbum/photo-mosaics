#!/usr/bin/perl -s

# getSnapsDir.pl - Jim Bumgardner
#
# grab tagged photos and put small thumbnails into a named folder.
#
# use -med option for medium-sized photos

use LWP::Simple qw($ua get);
$| = 1;

$ua->timeout(10);

$photolist = shift;
$dirname = shift;

die "getsnapsdir.pl [-big] <photolist_file> [dirname]\n" if !$photolist;

$dirname = $photolist;
$dirname =~ s/(_nb)?\.ph// if $dirname =~ /\.ph$/;
$photolist .= '.ph' if !($photolist =~ /\./);

require "$photolist";

$nbrAdded = 0;

$suffix = $big? '' : '_t';
my $counted = 0;

@photos = sort { $a->{id} <=> $b->{id} } @photos;
@photos = reverse @photos if $rev || $r;

$n = 0;
foreach my $photo (@photos)
{
	$purlt = MakeFlickrPath($photo, $suffix);
	$fnam  = MakeLocalPath($photo, $suffix);

	$hasSmall = 0;
	++$counted;

	print "Checking $fnam...\n" if $verbose;
  ++$n;

	# printf "Checking $fnam...\n";
	if (!(-e $fnam)) 
	{
    printf "%.1f%% Getting $fnam...  \r", $n*100.0/scalar(@photos);
		foreach (0..5)
		{
			$pimg = get $purlt;
			last if $pimg;
			print "Retry...\n";
			sleep 1;
		}
		die "Couldn't get image $purlt\n" if !$pimg;
		BuildDirs($fnam);
		open (OFILE, ">$fnam") || die ("can't open $fnam\n");
		binmode OFILE;
		print OFILE $pimg;
		close OFILE;
		print "$nbrAdded...\n" if ++$nbrAdded % 500 == 0;
	}
}

print "\n\n$nbrAdded added, $counted counted\n"; 

sub MakeFlickrPath($$)
{
	my ($photo, $suffix) = @_;
	return sprintf "http://farm%s.static.flickr.com/%d/%s_%s%s.jpg", 
	            $photo->{farm},
				$photo->{server},
				$photo->{id}, 
				$photo->{secret}, $suffix;
}

sub MakeLocalPath($$)
{
	my ($photo, $suffix) = @_;
	return MakeDirName($photo->{id}) . "$photo->{id}$suffix.jpg";
}

sub MakeDirName($)
{
	my ($id) = @_;
	return sprintf 'flickrcache/%03d/%03d/', int($id/1000000)%1000, int($id/1000)%1000;
}

sub BuildDirs($)
{
  my ($lname) = @_;
  my @dirs = split /\//, $lname;
  $ldir = '';
  @dirs = splice(@dirs, 0, scalar(@dirs)-1);
  foreach (@dirs)
  {
    last if /\.jpg/i;
    $ldir .= '/' if $ldir ne '';
    $ldir .= $_;
    if (!(-e $ldir))
    {
      # print "Making $ldir ...\n";
      `mkdir $ldir`;
    }
  }
}
