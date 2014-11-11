package Image::FlickrSet;

use Image::Magick;
use LWP::Simple qw($ua get);

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
  
#  $self->{photokeys} = [sort keys %{$photos}];
  $ua->timeout(20);

  return $self;
}

sub make_url()
{
  my ($self, $idx, $minwidth) = @_;

  my $suffix = '';
  my $photo = $self->{photos}->[$idx];
  return '' if !$photo;

  return $self->MakeFlickrPath($photo, $suffix);
}

sub make_filepath()
{
  my ($self, $idx, $minwidth, $makedirs) = @_;

  my $suffix = '';

  my $photo = $self->{photos}->[$idx];

  return '' if !$photo;

  return $self->MakeLocalPath($photo, $suffix);
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

  if (!(-e $fname) && !$self->{noDownload})
  {
    $self->download_image($idx, $minwidth);
  }
  return 0 if !(-e $fname);
  my $image = Image::Magick->new;
  my $err = $image->Read($fname);
  warn "$err\n" if $err;
  return $image;
}

sub get_image_desc()
{
  my ($self,$idx) = @_;
  my $photo = $self->{photos}->[$idx];
  my $name = $photo->{name};
  $name =~ s~"~\&quot;~g;
  return sprintf '%s -- click to view', $name;
}

# get unique id for duplicate check (using owner now, to avoid near dupes)
sub get_image_dupeid()
{
  my ($self,$idx) = @_;
  my $photo = $self->{photos}->[$idx];
  return $photo->{id};
}

sub get_image_id()
{
  my ($self,$idx) = @_;
  my $photo = $self->{photos}->[$idx];
  return sprintf '%d', $photo->{id};
}

# http://www.flickr.com/photos/12037949754@N01/155761353/
sub get_image_webpage()
{
  my ($self,$idx) = @_;
  my $photo = $self->{photos}->[$idx];
  return 'http://omg.yahoo.com/awesome-celebrity-omg/celebs/' . $photo->{id};
#  my $nam = $photo->{name};
#  $nam =~ s/ /-/g;
#  $nam =~ s/[^\w\-]//g;
#  return sprintf 'http://music.yahoo.com/ar-%d---%s', $photo->{id}, $nam;
}

sub get_maximages()
{
  my ($self) = @_;
  return scalar(@{$self->{photos}});
}

sub MakeYahooPath($$)
{
	my ($self, $photo, $suffix) = @_;
	return sprintf "http://l.yimg.com/img.music.yahoo.com/image/v1/artist/%d%s", 
	            $photo->{id},$suffix;
}

sub MakeLocalPath($$)
{
	my ($self, $photo, $suffix) = @_;
	return $self->MakeDirName($photo->{id}) . "$photo->{id}.jpg";
}

sub MakeDirName($)
{
	my ($self, $id) = @_;
	return sprintf 'yahoo/%03d/%03d/', int($id/1000000)%1000, int($id/1000)%1000;
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