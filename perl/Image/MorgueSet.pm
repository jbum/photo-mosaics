package Image::MorgueSet;

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

  my $suffix = $minwidth <= 50? '_t' : '';
  my $photo = $self->{photos}->[$idx];
  return '' if !$photo;

  my $url = $photo->{url};
  $url =~ s/thumbnails/lowrez/ if $minwidth > 50;


  return $url;
}

sub build_dirs()
{
  my ($self,$lname) = @_;
  my @dirs = split /\//, $lname;
  my $ldir = '';
  foreach (split /\//, $lname)
  {
    last if /\.jpg/i;
    $ldir .= '/' if $ldir ne '';
    $ldir .= $_;
    if (!(-e $ldir))
    {
      print "Making $ldir ...\n";
      `mkdir $ldir`;
    }
  }
}

sub make_filepath()
{
  my ($self, $idx, $minwidth, $makedirs) = @_;

  my $suffix = $minwidth <= 50? '_t' : '';

  my $photo = $self->{photos}->[$idx];

  return '' if !$photo;

  my $url = $photo->{url};
  $url =~ s/thumbnails/lowrez/ if $minwidth > 50;

  my $localfile = $url;
  $localfile =~ s~http://\w+\.morguefile\.com/images/storage/~morgue/~i;
#  $self->BuildDirs($localfile);
  return $localfile;
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
    $self->build_dirs($fname);
    $self->download_image($idx, $minwidth);
  }
  return 0 if !(-e $fname);
  my $image = Image::Magick->new;
  my $err = $image->Read($fname);
  warn "$err\n" if $err;
  return $image;
}

sub get_image_dupeid()
{
  my ($self,$idx) = @_;
  return $idx;
}

sub get_image_desc()
{
  my ($self,$idx) = @_;
  my $photo = $self->{photos}->[$idx];
  my $url = $photo->{url};
  # $url =~ s~http://www\.morguefile\.com/images/storage/~~;
  return $url;
}

sub get_image_webpage()
{
  my ($self,$idx) = @_;
  my $photo = $self->{photos}->[$idx];
  my $url = $photo->{url};
  # $url =~ s~http://www\.morguefile\.com/images/storage/~~;
  return $url;
}

sub get_image_id()
{
  my ($self,$idx) = @_;
  my $photo = $self->{photos}->[$idx];
  my $url = $photo->{url};
  # $url =~ s~http://www\.morguefile\.com/images/storage/~~;
  return $url;
}

sub get_maximages()
{
  my ($self) = @_;
  return scalar(@{$self->{photos}});
}

1;
