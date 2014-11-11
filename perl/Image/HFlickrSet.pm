package Image::HFlickrSet;

use Image::Magick;
use LWP::Simple;

require Exporter;
our @ISA = qw(Exporter);
@EXPORT = qw(get_image);
@EXPORT_OK = qw();

use strict;
use warnings;

my %deffields = (
);

sub new
{
  my ($class,$photos, $options) = @_;
  my $self = {%deffields};
  $self->{photos} = $photos;
  foreach my $key (keys %{$options})
  {
  	$self->{$key} = $options->{$key};
  }
  bless $self, $class;
  
  $self->{photokeys} = [sort keys %{$photos}];
  
  return $self;
}

sub make_url()
{
  my ($self, $idx, $minwidth) = @_;

  my $suffix = $minwidth <= 50? '_t' : '';
  my $id = $self->{photokeys}->[$idx];
  my $photo = $self->{photos}->{$id};
  return '' if !$photo;

  return $self->MakeFlickrPath($photo, $suffix);
}

sub make_filepath()
{
  my ($self, $idx, $minwidth, $makedirs) = @_;

  my $suffix = $minwidth <= 100? '_t' : '';

  return '' if !(defined $self->{photokeys}->[$idx]);
  my $id = $self->{photokeys}->[$idx];
  my $photo = $self->{photos}->{$id};

  my $spathn = $self->MakeLocalPath($photo, $suffix);

  return $spathn;
}

sub download_image()
{
  my ($self, $idx, $minwidth) = @_;

  my $url = $self->make_url($idx, $minwidth);


  my $pimg;
	foreach (0..5)
	{
		$pimg = get $url;
		last if defined $pimg && $pimg ne '';
		print "Retry...\n" if $self->{verbose};
		sleep 1;
	}
  my $fname = $self->make_filepath($idx, $minwidth, 1);
  print "Adding $fname ...\n" if $self->{verbose};
  $self->BuildDirs($fname);
	open (OFILE, ">$fname") || die ("can't open $fname");
	binmode OFILE;
	print OFILE $pimg;
	close OFILE;
}

sub get_image()
{
 my ($self, $idx, $minwidth) = @_;

  my $fname = $self->make_filepath($idx, $minwidth);
  return 0 if !$fname;

	if (!(-e $fname))
	{
		$self->download_image($idx, $minwidth);
	}
	my $image = Image::Magick->new;
	my $err = $image->Read($fname);
	warn "$err\n" if $err;
	return $image;
}

sub get_maximages()
{
 	my ($self) = @_;
	return scalar(@{$self->{photokeys}});
}

sub MakeFlickrPath($$)
{
	my ($self, $photo, $suffix) = @_;
	return sprintf "http://farm%s.static.flickr.com/%d/%d_%s%s.jpg", 
	            $photo->{farm},
				$photo->{server},
				$photo->{id}, 
				$photo->{secret}, $suffix;
}

sub MakeLocalPath($$)
{
	my ($self, $photo, $suffix) = @_;
	return $self->MakeDirName($photo->{id}) . "$photo->{id}$suffix.jpg";
}

sub MakeDirName($)
{
	my ($self, $id) = @_;
	return sprintf 'flickrcache/%03d/%03d/', int($id/1000000)%1000, int($id/1000)%1000;
}

sub BuildDirs($)
{
  my ($self, $lname) = @_;
  my @dirs = split /\//, $lname;
  my $ldir = '';
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

1;

