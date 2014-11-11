package Image::XMLSet;

use Image::Magick;
use LWP::Simple qw($ua get);

require Exporter;
our @ISA = qw(Exporter);
@EXPORT = qw(get_image);
@EXPORT_OK = qw();

use strict;
use warnings;

my %deffields = (
 cacheRoot => './snaps'
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
  
	$ua->timeout(20);

  return $self;
}

sub make_url()
{
  my ($self, $idx, $minwidth) = @_;

  my $photo = $self->{photos}->[$idx];
  return '' if !$photo;
  my $url = $minwidth <= 50? $photo->{small} : $photo->{big};
	return $url;
}

sub make_filepath()
{
  my ($self, $idx, $minwidth, $makedirs) = @_;

	my $url = $self->make_url($idx, $minwidth);
	return '' if !$url;
  my $fname = $url;
  $fname =~ s~^.*/~~g;
  return "$self->{cacheRoot}/$fname";
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

sub get_maximages()
{
 	my ($self) = @_;
	return scalar(@{$self->{photos}});
}

