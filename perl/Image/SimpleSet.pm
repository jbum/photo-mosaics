package Image::SimpleSet;

use Image::Magick;
use LWP::Simple;

require Exporter;
our @ISA = qw(Exporter);
@EXPORT = qw(get_image);
@EXPORT_OK = qw();

use strict;
use warnings;

my %deffields = (
 imageRoot => './tiles'
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

  my $suffix = $minwidth <= 50? '_t' : '';

	if ($idx >= @{$self->{photos}})
	{
		# print "Out of photos at $idx\n";
		return '';
	}
  my $photo = $self->{photos}->[$idx];
  return "$self->{imageDir}/$photo->{id}$suffix.jpg";
}

sub get_image()
{
 my ($self, $idx, $minwidth) = @_;

  my $fname = $self->make_filepath($idx, $minwidth);
  return 0 if !$fname;

	if (!(-e $fname))
	{
		print "Can't find image: $fname (width=$minwidth)\n";
		return 0;
	}
	my $image = Image::Magick->new;
	my $err = $image->Read($fname);
	warn "$err\n" if $err;
	return $image;
}

