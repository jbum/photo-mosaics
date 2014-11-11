package Image::DVDSet;

use Image::Magick;
use LWP::Simple;

require Exporter;
our @ISA = qw(Exporter);
@EXPORT = qw(get_image);
@EXPORT_OK = qw();

use strict;
use warnings;

# UNUSED
my %deffields = (
 imageDirUNUSED => './hurlow_t',
 imageDirHUNUSED => './hurlow'
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
  
  return $self;
}

sub make_filepath()
{
  my ($self, $idx, $minwidth, $makedirs) = @_;

	if ($idx >= @{$self->{photos}})
	{
		# print "Out of photos at $idx\n";
		return '';
	}
  my $photo = $self->{photos}->[$idx];
  # return $minwidth > 100? "$self->{imageDirH}/$photo->{nam}.jpg" : "$self->{imageDir}/$photo->{nam}.jpg";
  return $photo->{nam};
}

sub get_image_force()
{
  my ($self, $idx) = @_;
  my $photo = $self->{photos}->[$idx];
  return $photo->{force}? 1 : 0;
}

sub get_image()
{
 my ($self, $idx, $minwidth) = @_;

  my $fname = $self->make_filepath($idx, $minwidth);
  return 0 if !$fname;

	if (!(-e $fname))
	{
		print "Can't find image: $fname\n";
		return 0;
	}
	my $image = Image::Magick->new;
	my $err = $image->Read($fname);
	$image->Set(colorspace=>'RGB');
	warn "$err\n" if $err;
	return $image;
}

sub get_maximages()
{
  my ($self) = @_;
  return scalar(@{$self->{photos}});
}

sub get_image_dupeid()
{
  my ($self,$idx) = @_;
  $idx = $self->{photos}->[$idx]->{dupecode} if defined $self->{photos}->[$idx]->{dupecode};
  return $idx;
}

sub get_image_id()
{
  my ($self,$idx) = @_;
  return $idx;
}

sub get_image_webpage()
{
  my ($self,$idx) = @_;
  return '';
}

sub get_image_desc()
{
  my ($self,$idx) = @_;
  my $photo = $self->{photos}->[$idx];
  return sprintf '%s', $photo->{nam};
}


