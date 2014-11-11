package Image::Mosaic;
#
# Routines for building photo mosaics - Jim Bumgardner
#
# Works with an Image::Set module, used for delivering a sequence of images by index number.
#
# Currently Image::FlickrSet, Image::HFlickrSet and Image::SimpleSet are implemented
# some ideas for new ones: Pull frames from movies, use other image-services, etc...

use Image::Magick;
use Data::Dumper;
use Digest::MD5 qw(md5_hex);

require Exporter;
our @ISA = qw(Exporter);
@EXPORT = qw(sample_photos  make_heatmap  output_mosaic);
@EXPORT_OK = qw(setup_cells  select_tiles);

#use strict;
use warnings;

my %fields = (
  max_images => 800,
  resoX => 7,
  cellsize => 20,
  noborders => 0,
  verbose => 0,
  grabThumbs => 0,
  doflops => 0,
  rootname => 'mosaic',
  dupesOK => 0,
  cspace => 0,  # color space (in bits per component, 0 = normalized)
  hmode => 0,  # heatmap mode, with overlapping tiles
  hlimit => 0, # heatmap image limit 0 = unlimited
  hbase => '',
  mixin => 0,
  cmode => 'Darken',  # also 'Blend'
  speckle => 0,
  anno => 0,
  grayscale => 0,
  minDupeDist => 8,
  tileblur => 0.4,
  tilefilter => 'Sinc',  # currently unused
  targetblur => 0.4,
  dupeList => {},        # used to track duplicates
  hasForces => 0,
  targetfilter => 'Sinc', # currently unused
);

my $XN = (0.412453 + 0.357580 + 0.180423);
my $YN = (0.212671 + 0.715160 + 0.072169);
my $ZN = (0.019334 + 0.119193 + 0.950227);


sub new 
{
  my ($class,$options) = @_;
  my $self = {%fields};
  foreach my $key (keys %{$options})
  {
    printf "%s = %s\n", $key, $options->{$key} if $options->{verbose} > 1;
    $self->{$key} = $options->{$key};
  }
  $self->{cspace} = 8 if $self->{hmode} != 0 && $self->{cspace} == 0;
  $self->{resoX} = $self->{reso} if !$self->{resoX};
  $self->{resoY} = $self->{resoX} if !$self->{resoY};
  $self->{reso2} = $self->{resoX} * $self->{resoY};
  $self->{tileAspectRatio} = $self->{resoX} / $self->{resoY};
  $self->{minDupeDist2} = $self->{minDupeDist}**2;
  $self->{basename} = $self->{basepic};
	$self->{hbase} = $self->{basepic} if $self->{hmode} && $self->{hbase} eq '';
  $self->{basename} =~ s~^.*/~~g;
  $self->{basename} =~ s/\.(jpg|png|gif)//;

	if ($self->{speckle}) {
		$self->{tint} = 1;
		$self->{mixin} = 15 if $self->{mixin} == 0;
	}

  bless $self, $class;
  return $self;
}

sub CumDiff()
{
  my ($self,$img, $cell, $upperBound, $var) = @_;
  
  my $sum = 0;
  
  my ($pix1,$pix2) = ($cell->{pix}, $img->{pix}->[$var]);
  my $pi = 0;
  for (my $i = 0; $i < $self->{reso2} && $sum <= $upperBound; ++$i,$pi += 3)
  {
    $sum += ($pix1->[$pi]   - $pix2->[$pi])**2 +
            ($pix1->[$pi+1] - $pix2->[$pi+1])**2 +
            ($pix1->[$pi+2] - $pix2->[$pi+2])**2;
  }

  # exit;

  return $sum;
}

sub CumDiffFlop($$)
{
  my ($self,$img, $cell, $upperBound, $var) = @_;
  
  my $sum = 0;
  
  my ($pix1,$pix2) = ($cell->{pix}, $img->{pix}->[$var]);

  my $r = $self->{resoX};
  my $pi = 0;
  for (my $i = 0; $i < $self->{reso2} && $sum <= $upperBound; ++$i,$pi += 3)
  {

    my $x = $i % $r;
    my $y = int($i / $r);
    my $pi2 = ($y*$r + ($r-1)-$x) * 3;
    $sum += ($pix1->[$pi] - $pix2->[$pi2])**2 +
            ($pix1->[$pi+1] - $pix2->[$pi2+1])**2 +
            ($pix1->[$pi+2] - $pix2->[$pi2+2])**2;
  }
  return $sum;
}

# higher quality edge detection, but slower
sub Edginess()
{
  my ($self,$cell) = @_;

  my $pix = $cell->{pix};

  my $reso21 = $self->{reso2}-1;

  # compute deviation, and raise score for tied cells in center...
  my $cumdiff = 0;
  my $resoX = $self->{resoX};
  my $pi = 0;
  
  for (my $i = 0; $i <  $self->{reso2}; ++$i,$pi += 3)
  {
    my $x = $i % $resoX;
    my $y = int($i / $resoX);
    if ($y > 0)
    {
      my $j = ($i - $resoX)*3;
      $cumdiff += ($pix->[$j] - $pix->[$pi])**2 +
                  ($pix->[$j+1] - $pix->[$pi+1])**2 +
                  ($pix->[$j+2] - $pix->[$pi+2])**2;
    }
    if ($y < $self->{resoY}-1)
    {
      my $j = ($i + $resoX)*3;
      $cumdiff += ($pix->[$j] - $pix->[$pi])**2 +
                  ($pix->[$j+1] - $pix->[$pi+1])**2 +
                  ($pix->[$j+2] - $pix->[$pi+2])**2;
    }
    if ($x > 0)
    {
      my $j = ($i - 1)*3;
      $cumdiff += ($pix->[$j] - $pix->[$pi])**2 +
                  ($pix->[$j+1] - $pix->[$pi+1])**2 +
                  ($pix->[$j+2] - $pix->[$pi+2])**2;
    }
    if ($x < $resoX-1)
    {
      my $j = ($i + 1)*3;
      $cumdiff += ($pix->[$j] - $pix->[$pi])**2 +
                  ($pix->[$j+1] - $pix->[$pi+1])**2 +
                  ($pix->[$j+2] - $pix->[$pi+2])**2;
    }

# old method: too slow...

#    for (my $j = $i+1; $j < $self->{reso2}; ++$j)
#    {
#     my $d = ($pix->[$j]->[0] - $pix->[$i]->[0])**2 +
#             ($pix->[$j]->[1] - $pix->[$i]->[1])**2 +
#             ($pix->[$j]->[2] - $pix->[$i]->[2])**2;
#     $cumdiff += $d;
#    }
  }
  return $cumdiff;
}

sub RGBtoLAB($$$)
{

  my ($r,$g,$b) = @_;
  my $x0 = (0.412453*$r + 0.357580*$g + 0.180423*$b);
  my $y0 = (0.212671*$r + 0.715160*$g + 0.072169*$b);
  my $z0 = (0.019334*$r + 0.119193*$g + 0.950227*$b);
  my ($lstar,$astar,$bstar);

  if( $y0 < .008856 ) {
      $lstar = 9.033*$y0/$YN;
  }
  else {
      $lstar = 1.16*(($y0/$YN)**(1.0/3.0)) - 0.16;
  }
  $astar = 5.0*(fnf($x0/$XN) - fnf($y0/$YN));
  $bstar = 2.0*(fnf($y0/$YN) - fnf($z0/$ZN));
  $astar /= 1.9;
  $bstar /= 1.9;
  return ($lstar, $astar,$bstar);
}

sub fnf($)
{
  my ($t) = @_;
  return $t ** (1.0/3.0) if( $t > 0.008856 );
  return 7.787*$t + 16.0/116.0;
}


sub RGBtoHSV($$$)
{
  my ($r,$g,$b) = @_;
  # $r /= 255;
  # $g /= 255;
  # $b /= 255;
  my $max = $r > $g? $r : $g;
  $max = $max > $b? $max : $b;
  my $min = $r < $g? $r : $g;
  $min = $min < $b? $min : $b;
  my $v = $max;
  my $s = ($max != 0)? ($max-$min)/$max : 0;
  my $h;
  if ($s == 0) {
    $h = 0; # undefined, actually
  }
  else {
    my $d = $max - $min;
    if ($r == $max) {
      $h = ($g - $b)/$d;
    }
    elsif ($g == $max) {
      $h = 2 + ($b-$r)/$d;
    }
    elsif ($b == $max) {
      $h = 4 + ($r-$g)/$d;
    }
    $h *= 60;
    if ($h < 0) {
      $h += 360;
    }
  }
  return ($h/360,$s,$v);
}

sub getcroppedphoto($$$$)
{
  my ($self, $idx, $resoX, $var) = @_;
  my $image = $self->{imageset}->get_image($idx,$resoX);


  if (!$image) {
    warn "Problem getting image $photo->{idx}";
    return $image;
  }
  # crop to square
  my ($w, $h) = $image->Get('width', 'height');
  # if ($w < $h) {

  if ($var == 0)
  {
    if ($w/$h < $self->{tileAspectRatio}) {
      # horizontal strip
      my $nh = $w / $self->{tileAspectRatio};
      $image->Crop(width=>$w, height=>$nh, 'x'=>0, 'y'=>($h-$nh)/2);
    }
    elsif ($w/$h > $self->{tileAspectRatio}) {
      # vertical strip
      my $nw = $h * $self->{tileAspectRatio};
      $image->Crop(width=>$nw, height=>$h, 'y'=>0, 'x'=>($w-$nw)/2);
    }
  }
  elsif ($var == 1) { # left/top
    if ($w/$h < $self->{tileAspectRatio}) {
      # horizontal strip
      my $nh = $w / $self->{tileAspectRatio};
      $image->Crop(width=>$w, height=>$nh, 'x'=>0, 'y'=>0);
    }
    elsif ($w/$h > $self->{tileAspectRatio}) {
      # vertical strip
      my $nw = $h * $self->{tileAspectRatio};
      $image->Crop(width=>$nw, height=>$h, 'y'=>0, 'x'=>0);
    }
  }
  else { # right/bot
    if ($w/$h < $self->{tileAspectRatio}) {
      # horizontal strip
      my $nh = $w / $self->{tileAspectRatio};
      $image->Crop(width=>$w, height=>$nh, 'x'=>0, 'y'=>($h-$nh));
    }
    elsif ($w/$h > $self->{tileAspectRatio}) {
      # vertical strip
      my $nw = $h * $self->{tileAspectRatio};
      $image->Crop(width=>$nw, height=>$h, 'y'=>0, 'x'=>($w-$nw));
    }
  }
  return $image;
}

sub subsample_photo($)
{
  my ($self,$photo) = @_;
  if (!$photo->{pix})
  {
    $photo->{pix} = [];

    # bugfix - only clear if it doesn't already exist
    my $key = $self->{imageset}->get_image_dupeid($photo->{idx});
    $self->{dupeList}->{  $key } = [] if !exists($self->{dupeList}->{  $key });
    # printf "Setting dupeid for %s\n", $self->{imageset}->get_image_dupeid($photo->{idx});
    # $photo->{dupeCoords} = [];

    foreach my $v (0..2) {
      next if $v > 0 && !$self->{useVars};
      my $image = $self->getcroppedphoto($photo->{idx},$self->{resoX}, $v);

      my $err = $image->Resize(width=>$self->{resoX}, height=>$self->{resoY});

      my @pix = $image->GetPixels('x'=>0,'y'=>0,width=>$self->{resoX},height=>$self->{resoY},normalize=>1);
      $self->ConvertToColorSpace(\@pix,$self->{reso2}) if $self->{cspace} > 0;

      if ($self->{lab}) {
        my $pi = 0;
        for (my $i = 0; $i < $self->{reso2}; ++$i,$pi += 3)
        {
          my ($l,$a,$b) = RGBtoLAB($pix[$pi],$pix[$pi+1],$pix[$pi+2]);
          $pix[$pi] = $l;
          $pix[$pi+1] = $a;
          $pix[$pi+2] = $b;
        }
      }
      push @{$photo->{pix}}, \@pix;
      undef $image;
    }
  }
}

sub ConvertToColorSpace($$$)
{
	my ($self,$pix,$n) = @_;
	my $maxCompGamut = 2**$self->{cspace} - 1;
	my $maxComponents = $n*3;
  for (my $i = 0; $i < $maxComponents; ++$i)
	{
		$pix->[$i] = int($pix->[$i]*$maxCompGamut + .5);  # int(x+.5) is same as round(x)  - needed to reduce error on small gamutss
	}
}

sub make_heatmap($$)
{
  my ($self, $oname) = @_;
  
  $self->setup_cells() if !$self->{sortedcells};
  return if !$self->{sortedcells};

  my ($width, $height) = ($self->{resoX} * $self->{hcells}, $self->{resoY} * $self->{vcells});
  
  my $heatmap = Image::Magick->new;
  $heatmap->Set(size=>"${width}x${height}"); # worked okay at 10000x10000
  $heatmap->Read('xc:black');

  print "Heatmap size: $width x $height\n";

  # for each cell
  my $n = 0;  
  for my $cell (@{$self->{sortedcells}})
  {
    my $alpha = (1 - $n / (scalar(@{$self->{sortedcells}}) - 1));
    my $pix = $cell->{pix};
    my $pi = 0;
    for (my $py = 0; $py < $self->{resoY}; ++$py)
    {
      for (my $px = 0; $px < $self->{resoX}; ++$px)
      {
         my $r = $pix->[$pi]*255*$alpha + 255*(1-$alpha);
         my $g = $pix->[$pi+1]*255*$alpha + 255*(1-$alpha);
         my $b = $pix->[$pi+2]*255*$alpha + 255*(1-$alpha);

         # Draw pixel at right location
         my $lval = sprintf("pixel[%d,%d]",
                        $cell->{'x'}*$self->{resoX}+$px,$cell->{'y'}*$self->{resoY}+$py);
         my $rval = sprintf("#%02x%02x%02x", $r,$g,$b);
         # print "$str\n";  
         $heatmap->Set($lval => $rval);
         $pi += 3;
      }
    }
    $n++;
  }
  # save heatmap
  print "Writing $oname ...\n";
  $heatmap->Write($oname);
  undef $heatmap;
}

sub sample_photos($)
{
  my ($self) = @_;
  my @images = ();

  die "No imageset provided\n" if !$self->{imageset};

  my $maxImages = $self->{imageset}->get_maximages();
  print "Sampling $maxImages source images...\n" if $self->{verbose};
  my $idx = 0;
  my $maxReso = $self->{resoX} >= $self->{resoY}? $self->{resoX} : $self->{resoY};
  while ($idx < $maxImages)
  {
      my $image = $self->{imageset}->get_image($idx, $maxReso);
      if ($image)
      {
        # get dimensions
        my ($w, $h) = $image->Get('width', 'height');

        # kill bad choices... (overly uniform images)
        my $badImage = 0;

        if ($self->{noborders}) {
          my ($w1, $h1) = ($w-1,$h-1);
          my ($w2, $h2) = ($w/2,$h/2);
          my ($r1,$g1,$b1) = $image->GetPixels(x=>$w2,y=>0,width=>1,height=>1,normalize=>1);
          my ($r2,$g2,$b2) = $image->GetPixels(x=>$w2,y=>$h1,width=>1,height=>1,normalize=>1);
          my ($r3,$g3,$b3) = $image->GetPixels(x=>0,y=>$h2,width=>1,height=>1,normalize=>1);
          my ($r4,$g4,$b4) = $image->GetPixels(x=>$w1,y=>$h2,width=>1,height=>1,normalize=>1);
          my $d1 =  ($r2 - $r1)**2 +
                    ($g2 - $g1)**2 +
                    ($b2 - $b1)**2;
          my $d2 =  ($r4 - $r3)**2 +
                    ($g4 - $g3)**2 +
                    ($b4 - $b3)**2;
          if ($d1 <= .007 || $d2 <= .007 || $w/$h >= 2 || $h/$w >= 2) {
            $badImage = 1;
            print "." if $self->{verbose};
          }
        }

        if (!$badImage)
        {
          # no need to crop during this step - just getting overall lum
          #if ($w/$h < $self->{tileAspectRatio}) {
          # my $nh = $w / $self->{tileAspectRatio};
          # $image->Crop(width=>$w, height=>$nh, 'x'=>0, 'y'=>($h-$nh)/2);
          #}
          #elsif ($w/$h > $self->{tileAspectRatio}) {
          # my $nw = $h * $self->{tileAspectRatio};
          # $image->Crop(width=>$nw, height=>$h, 'y'=>0, 'x'=>($w-$nw)/2);
          #}
          $image->Resize(width=>1,height=>1);
          my ($r,$g,$b) = $image->GetPixels(x=>0,y=>0,width=>1,height=>1,normalize=>1);
          my $l = 0.3086*$r + 0.6094*$g + 0.0820*$b; # Haeberli

          my $photo = {idx=>$idx, l=>$l};
					if ($self->{hasForces}) {
						$photo->{force} = $self->{imageset}->get_image_force($idx)
					}
          # print " photo rgb = $r $g $b l=$l\n";

          push @images, $photo;
        }
        undef $image;
      }
      ++$idx;
      print "$idx...\n" if $idx % 500 == 0 && $self->{verbose};
  }
  my $num_images = scalar(@images);
  print "Got $num_images images\n";
  $self->{images} = \@images;
}

sub setup_cells()
{
  my $self = shift;

  my @cells = ();

  # my @aart = split //, 'BBBEEEMMMWWQQQNNNHH@@@KKKRRAAA###ddgggqqq88bbbXXXppPPPGGGFFFDDSSSwwwUU444%%%kk999666OOmmm00022xxx$$$ZZaaayyyhhhLLfffeee&&VVV333ss555oooCCTTTuuuYYzzzvvvJJnnnccclllIIrrrtttjj[[[]]]??>>><<<11}}}{{{77==="""((iii)))///\\+++***;;|||!!!^^:::,,,\'\'~~~---__...```   ';
    my @aart = split //, 'BEEEEEEEEEMWWQQQQQQQQQQQNHHHHH@@@@@KKKRRRAA#dddgg88bbbbXXpppPFFFDSSww4444%k9966m222xx$ZhhLLLf&&&V3s55555555ooTuuzvvJJJJJJJJJnclIrrrttjjjjjjj[]]??>><1}}}}}}}}{{{{{="""i/\\\\\\\\\\++++*;;||||!!!!^^^^^^^^^^^^^^^^:::,,,,,,\'\'~~~~~-----____________.......`````````````';
  my $baseimg = Image::Magick->new;
  my $err = $baseimg->Read($self->{basepic});
  $baseimg->Set(colorspace=>'RGB');
  warn "$err" if "$err";

  my ($w, $h) = $baseimg->Get('width', 'height');
  my $aspect = $h/$w;
  $self->{targetAspectRatio} = $aspect;
  $self->{max_images} = scalar(@{$self->{images}})/4 if !$self->{max_images};
  $self->{max_images} = scalar(@{$self->{images}}) if $self->{images} && $self->{max_images} > scalar(@{$self->{images}}) && !$self->{dupesOK};
  my $hcells = sqrt($self->{max_images} / $aspect);

  # for a square output image, there are more vertical cells if aspect ratio is > 1
  my $vcells = ($hcells * $aspect) * $self->{tileAspectRatio};

  $self->{hcells} = int($hcells + .5);
  $self->{vcells} = int($vcells + .5);
  if ($self->{hcells} * $self->{vcells} > $self->{max_images})
  {
    # round down to fit...
    $self->{hcells} = int($hcells);
    $self->{vcells} = int($vcells);
  }

  # if $reso is too large for target image, reduce it...
  if ($self->{resoX}*$self->{hcells} > $w)
  {
    $self->{resoX} = int($w / $self->{hcells});
    $self->{resoX} = 1 if ($self->{resoX} < 1);
    $self->{resoY} = int($self->{resoX}/$self->{tileAspectRatio});
    $self->{reso2} = $self->{resoX}*$self->{resoY};
    print "Forcing Reso to $self->{resoX}x$self->{resoY} due to lack of resolution in target image\n";
  }
  elsif ($self->{resoY}*$self->{vcells} > $h)
  {
    $self->{resoY} = int($h / $self->{vcells});
    $self->{resoY} = 1 if ($self->{resoY} < 1);
    $self->{resoX} = int($self->{resoY} * $self->{tileAspectRatio});
    $self->{reso2} = $self->{resoX}*$self->{resoY};
    print "Forcing Reso to $self->{resoX}x$self->{resoY} due to lack of resolution in target image\n";
  }

  print "Original Image Width: $w x $h\n" if $self->{verbose};
  print "Allocating cell data ($self->{hcells} x $self->{vcells}) x reso=$self->{resoX}x$self->{resoY} (AR=$self->{tileAspectRatio})...\n" if $self->{verbose};
  
  my $baseimg2 = Image::Magick->new;
  $err = $baseimg2->Read($self->{basepic});
  $baseimg2->Set(colorspace=>'RGB');
  warn "$err" if "$err";

  $baseimg->Resize(width=>$self->{hcells}, height=>$self->{vcells});
  $baseimg2->Resize(width=>$self->{hcells}*$self->{resoX}, height=>$self->{vcells}*$self->{resoY});

	if (!$self->{hmode})
	{
		# NORMAL MODE
		#
		my $i = 0;
		for (my $y = 0; $y < $self->{vcells}; ++$y)
		{
			for (my $x = 0; $x < $self->{hcells}; ++$x)
			{
				my ($r,$g,$b) = $baseimg->GetPixels(x=>$x,y=>$y,width=>1,height=>1,normalize=>1);
				my $l = 0.3086*$r + 0.6094*$g + 0.0820*$b; # Haeberli
				
				print $aart[255 - int($l * 255)] x 2;
				
				
				my ($h, $s, $v) = RGBtoHSV($r,$g,$b);
	
				# print " cell rgb = $r $g $b l=$l  hsv = $h $s $v\n";
	
				my ($x0,$y0) = ($x*$self->{resoX}, $y*$self->{resoY});
	
				# normal case, one cell per grid cell
				my @pix = $baseimg2->GetPixels(x=>$x0,y=>$y0,width=>$self->{resoX},height=>$self->{resoY},normalize=>1);
				$self->ConvertToColorSpace(\@pix,$self->{reso2}) if $self->{cspace} > 0;
	
				if ($self->{lab}) {
					my $pi = 0;
					for (my $i = 0; $i < $self->{reso2}; ++$i,$pi += 3)
					{
						my ($l,$a,$b) = RGBtoLAB($pix[$pi],$pix[$pi+1],$pix[$pi+2]);
						$pix[$pi] = $l;
						$pix[$pi+1] = $a;
						$pix[$pi+2] = $b;
					}
				}
				my $cell = {i=>$i, 'x'=>$x, 'y'=>$y, l=>$l, 's'=>$s, pix=>\@pix};
				if ($self->{tint}) {
					if ($self->{speckle}) {
						my $a = rand()*2*3.14159;
						my $r = .5 + sin($a)*.5;
						my $g = .5 + sin($a+2)*.5;
						my $b = .5 + sin($a+4)*.5;
						$cell->{tint} = sprintf '#%02x%02x%02x', int($r*255), int($g*255), int($b*255);
					}
					else {
						$cell->{tint} = sprintf '#%02x%02x%02x', int($r*255), int($g*255), int($b*255);
					}
				}
				push @cells, $cell;
				$i++;
			}
			print "\n";
		}
	}
	else {
		# HMODE - overlapping cells...
    #
    my %ucells = ();
    
#    $self->{ucells} = {}; # unique cells by signature

		my $i = 0;
		for (my $y = 0; $y <= ($self->{vcells}-1)*$self->{resoY}; ++$y)
		{
			for (my $x = 0; $x <= ($self->{hcells}-1)*$self->{resoX}; ++$x)
			{
				my ($r,$g,$b) = $baseimg->GetPixels('x'=>int($x/$self->{resoX}),'y'=>int($y/$self->{resoY}),width=>1,height=>1,normalize=>1);
				my $l = 0.3086*$r + 0.6094*$g + 0.0820*$b; # Haeberli
				
				print $aart[255 - int($l * 255)] x 2 if $y % $self->{resoY} == 0 && $x % $self->{resoX} == 0;
				
				
				my ($h, $s, $v) = RGBtoHSV($r,$g,$b);
	
				# print " cell rgb = $r $g $b l=$l  hsv = $h $s $v\n";
	
				# normal case, one cell per grid cell
				my @pix = $baseimg2->GetPixels('x'=>$x,'y'=>$y,width=>$self->{resoX},height=>$self->{resoY},normalize=>1);
				$self->ConvertToColorSpace(\@pix,$self->{reso2}) if $self->{cspace} > 0;
	
				my $cell = {i=>$i, 'x'=>$x, 'y'=>$y, 'l'=>$l, var=>0};
				push @cells, $cell;

				if ($self->{tint}) {
					if ($self->{speckle}) {
						my $a = rand()*2*3.14159;
						my $r = .5 + sin($a)*.5;
						my $g = .5 + sin($a+2)*.5;
						my $b = .5 + sin($a+4)*.5;
						$cell->{tint} = sprintf '#%02x%02x%02x', int($r*255), int($g*255), int($b*255);
					}
					else {
						$cell->{tint} = sprintf '#%02x%02x%02x', int($r*255), int($g*255), int($b*255);
					}
				}


				my $cellsig = md5_hex(join(',',@pix));
				# printf "%s\n", $cellsig;
				$cell->{pix} = \@pix;
				$ucells{$cellsig} = { ucnt=>0, cells=>[], 'l'=>$l, 'pix'=>\@pix } if not defined $ucells{$cellsig};
				push @{$ucells{$cellsig}->{cells}}, $cell;
				$i++;
			}
			printf "\n" if $y % $self->{resoY} == 0;
		}
	  printf "%d unique cells out of %d (cspace=%d)\n", scalar(keys %ucells), scalar(@cells), $self->{cspace};
	  $self->{ucells} = [];
	  foreach my $ckey (keys %ucells) {
	  	push @{$self->{ucells}}, $ucells{$ckey};
	  }
	  %ucells = ();
	}

  undef $baseimg;
  undef $baseimg2;

  $self->{cells} = \@cells;

	if ( !$self->{hmode} )
	{
		print "Sorting cells...\n" if $self->{verbose};
		foreach my $cell (@cells)
		{
			$cell->{e} = $self->Edginess($cell);
		}
	
	
		$self->{sortedcells} = [reverse sort { $a->{e} <=> $b->{e}; } @{$self->{cells}}];
		if ($self->{verbose} > 1)
		{
			my $n = 0;
			foreach my $cell (@{$self->{sortedcells}})
			{
				printf("%d: e:%d\n", $n, $cell->{e});
				$n++;
			}
		}
	}
}

# Build index into luminence values in pre-sorted images
#

sub BuildLumIndex($)
{
  my $self = shift;

  $self->{images} = [sort {$a->{l} <=> $b->{l}} @{$self->{images}}];

  my @iIndex = ();
  my $lIdx = -1;
  my $n = 0;
  my $j = 0;
  my $num = scalar(@{$self->{images}});

  print "Sorting $num images for luminance\n" if $self->{verbose} > 1;

  for my $img (@{$self->{images}})
  {
     if (int($img->{l}*255) != $lIdx)
     {
       $lIdx = int($img->{l}*255);
       while ($n <= $lIdx)
       {
        # print "iIndex[ $n ] = $j\n";
        $iIndex[$n++] = $j;
       }
     }
     $j++;
  }
  while ($n <= 255) {
    $iIndex[$n++] = $j;
  }
  printf "Lumindex has $n entries\n" if $self->{verbose} > 1;
  $self->{iIndex} = \@iIndex;
}

sub BuildLumIndex_hmode($)
{
  my $self = shift;

  print "Building Lum Index...\n";

  $self->{ucells} = [sort {$a->{l} <=> $b->{l}} @{$self->{ucells}}];

  my @iIndex = ();
  my $lIdx = -1;
  my $n = 0;
  my $j = 0;
  my $num = scalar(@{$self->{ucells}});

  for my $ucell (@{$self->{ucells}})
  {
     if (int($ucell->{l}*255) != $lIdx)
     {
       $lIdx = int($ucell->{l}*255);
       while ($n <= $lIdx)
       {
        # print "iIndex[ $n ] = $j\n";
        $iIndex[$n++] = $j;
       }
     }
     $j++;
  }
  while ($n <= 255) {
    $iIndex[$n++] = $j;
  }
  printf "Done... Lumindex has $n entries\n" if $self->{verbose} > 1;
  $self->{iIndex} = \@iIndex;
}

sub ComputeSig($$)
{
	my ($self,$pix) = @_;

  # random sig test
  # return int( rand() * 255 );

	my @sums = (0,0,0,0); # sum/cnt for each quadrant...
	my @cnts = (0,0,0,0);

	my $pi = 0;
	my $cy = $self->{resoY}/2;
	my $cx = $self->{resoX}/2;
  for (my $y = 0; $y < $self->{resoY}; ++$y) {
  	for (my $x = 0; $x < $self->{resoX}; ++$x) {
			# my $l = ($pix->[$pi] + $pix->[$pi+1] + $pix->[$pi+2])/3;
      my $l = 0.3086*$pix->[$pi] + 0.6094*$pix->[$pi+1] + 0.0820*$pix->[$pi+2]; # Haeberli
			$l = $l / 2**$self->{cspace};
      my $i = ($x >= $cx? 1 : 0) + ($y >= $cy? 2 : 0); # quadrant idx
			$sums[$i] += $l;
			$cnts[$i]++;

			$pi += 3;
  	}
  }

	return (int($sums[0]*4/$cnts[0]) << 6) |
				 (int($sums[1]*4/$cnts[1]) << 4) |
				 (int($sums[2]*4/$cnts[2]) << 2) |
				 (int($sums[3]*4/$cnts[3]) << 0);

}

sub AddSigCell($$$)
{
	my ($iIndex, $sig, $ucell) = @_;
	# printf " sig=%d\n", $sig;
	$iIndex->[$sig] = [] if not defined $iIndex->[$sig];
	push @{$iIndex->[$sig]}, $ucell;
}

sub SigDist($$)
{
	my ($sig1, $sig2) = @_;
  return 0 if $sig1 == $sig2;
	my $d0 = (($sig1 >> 6) & 0x03) - (($sig2 >> 6) & 0x03);
	my $d1 = (($sig1 >> 4) & 0x03) - (($sig2 >> 4) & 0x03);
	my $d2 = (($sig1 >> 2) & 0x03) - (($sig2 >> 2) & 0x03);
	my $d3 = (($sig1 >> 0) & 0x03) - (($sig2 >> 0) & 0x03);
	return sqrt( $d0*$d0 + $d1*$d1 + $d2*$d2 + $d3*$d3 );
}

sub BuildLumIndex_hmode2($)
{
  my $self = shift;
  print "Building Lum Index...\n";

  my @iIndex = ();
  
  my $simDistance = 1.1;
  
  for my $ucell (@{$self->{ucells}})
  {
    # determine sig of cell
  	$ucell->{lsig} = $self->ComputeSig($ucell->{pix});
    my $cnt = 0;
  	foreach my $sig (0..255) {
  		my $dist = SigDist($ucell->{lsig}, $sig);
  	  AddSigCell( \@iIndex, $sig, $ucell) if $dist <= $simDistance;
  	  $cnt++ if $dist < $simDistance;
  	}
  }
  $self->{iIndex} = \@iIndex;
  printf "Done Lum Index\n";
}


sub GetMinDupeDist2($$$$)
{
  my $mind = 100000000;
  my ($self,$img, $x, $y) = @_;
#  my $dupeCoords = $img->{dupeCoords};
  my $dupeCoords = $self->{dupeList}->{$self->{imageset}->get_image_dupeid($img->{idx})};
  
  foreach my $dd (@{$dupeCoords})
  {
    my $dx = ($dd->{'x'} - $x)**2;
    my $dy = ($dd->{'y'} - $y)**2;
    $mind = $dx if $dx == 0;
    $mind = $dy if $dy == 0;
    $mind = $dx+$dy if ($dx+$dy) < $mind;
  }
  return $mind;
}

sub select_tiles()
{
  my ($self) = @_;

  $self->sample_photos() if !$self->{images};
  return if !$self->{images};
  $self->setup_cells() if !$self->{sortedcells};
  return if !$self->{sortedcells};

  # sort images by luminance and build histogram index
  # to speed up matching
  my $numImages = scalar( @{$self->{images}} );
  my $lastImageIdx = $numImages-1;
  print "Selecting from $numImages images...\n" if $self->{verbose};

  $self->BuildLumIndex();
  
  my $i = 0;
  my @fimages = ();
  
  my $stime = time();
  for my $cell (@{$self->{sortedcells}})
  {
    print "tile $i  cell $cell->{'x'} x $cell->{'y'} $cell->{l}  ", if $self->{verbose} > 1;
    #   Find the closest match in @images
    my $cIdx;
    my $minDiff = 100000000;
    my $flop;
    my $var;
    # my $lErr = $numImages > 10000? 1 : ($numImages > 5000? 5 : 10);  # 10 is an improvement over 1...
    # scale search broadness based on complexity of image within cell
    # we don't need to look as far afield if cell is homogenous
    my $lErr += 20+$cell->{e}*256/$self->{reso2};
    my $gotOne = 0;
    
    while (!$gotOne)
    {
      # use iIndex to find a group of photos which have the approximate
      # overall desired luminance
      my $ii = int($cell->{l}*255);
      my $mini = $self->{iIndex}->[$ii - $lErr < 0? 0 : $ii - $lErr];
      my $maxi = $self->{iIndex}->[$ii + $lErr > 255? 255 : $ii + $lErr];
      if ($maxi - $mini < 256) 
      {
        $mini -= 128;
        $maxi += 128;
      }
      $mini = 0 if $mini < 0 || $self->{accurate};
      $maxi = $lastImageIdx if $maxi > $lastImageIdx || $self->{accurate} || $ii + $lErr >= 255;

      print "  $mini - $maxi\n" if $self->{verbose} > 1;
      # loop thru those cells and find the best fit
      for (my $j = $mini; $j <= $maxi; ++$j)
      {
        my $image = $self->{images}->[$j];
      
        next if $image->{xx};
        next if $self->GetMinDupeDist2($image, $cell->{'x'}, $cell->{'y'}) < $self->{minDupeDist2};

        $self->subsample_photo($image); # subsample photo if we haven't looked at it yet

        foreach my $v (0..2)
        {
          next if $v > 0 && !$self->{useVars};
          my $diff = $self->CumDiff($image, $cell, $minDiff,$v);
          # printf(" cumdiff = %d\n", $diff);
          if ($diff < $minDiff) {
            $minDiff = $diff;
            $cIdx = $j;
            $flop = 0;
            $var = $v;
            $gotOne = 1;
          }

          if ($self->{doflops}) 
          {
            $diff = $self->CumDiffFlop($image, $cell, $minDiff,$v);
            if ($diff < $minDiff) {
              $minDiff = $diff;
              $cIdx = $j;
              $flop = 1;
              $var = $v;
              $gotOne = 1;
            }
          }
        }
      }
      # if no match was find, widen the range and search again
      $lErr += 5;
    }
    # my $cPhoto = clone($self->{images}->[$cIdx]);
    my $cPhoto = $self->{images}->[$cIdx];
    $cPhoto->{i} = $cell->{i};  # cell number for image

#   printf "Cell l=%.3f  Tile l=%.3f (%s)\n", $cell->{l}, $cPhoto->{l}, 
#       $self->{imageset}->make_filepath($cPhoto->{idx}, 100);

    $cell->{iIdx} = scalar(@fimages);     # image number for cell
    $cell->{img} = $cPhoto;
    $cell->{flop} = $flop;
    $cell->{var} = $var;
	  $cell->{diff} = $minDiff;
    # $cPhoto->{flop} = $flop;
    push @fimages,$cPhoto;

    #   handle dupes
    $cPhoto->{xx} = 1 if !$self->{dupesOK};
		$cPhoto->{placed} = 1;
		
    # my $dupeCoords = $self->{images}->[$cIdx]->{dupeCoords};
    my $dupeCoords = $self->{dupeList}->{ $self->{imageset}->get_image_dupeid($self->{images}->[$cIdx]->{idx}) };
    # push @{$self->{images}->[$cIdx]->{dupeCoords}}, {x=>$cell->{'x'}, 'y'=>$cell->{'y'}};
    push @{$dupeCoords}, {x=>$cell->{'x'}, 'y'=>$cell->{'y'}};


    print "$i...\n" if ++$i % 100 == 0 && $self->{verbose};
  }
  printf "Done: elapsed = %.1f minutes\n", (time() - $stime)/60.0 if $self->{verbose};

	if ($self->{hasForces})
	{
		printf "Placing unplaced force images from collection of %d (%d cells)\n", scalar(@{$self->{images}}), scalar($self->{sortedcells});

		# place unplaced force images in a queue
		my @iq = grep { (not defined $_->{placed}) && $_->{force}} @{$self->{images}};
		printf "%d images are known forces\n", scalar(grep { $_->{force} } @{$self->{images}});
		printf "%d images still need to be placed\n", scalar(@iq);
		
		# proceed thru the queue
		while (@iq > 0) {

		# 	find closest cell that meets one of the following criteria (unforced tile or current match closer than present contents
				my $image = shift @iq;

		    my $minDiff = 100000000;
				my $cIdx = -1;
		
				my $nbrPlacedForces = 0;
			  for my $cell (@{$self->{sortedcells}})
				{
					my $diff = $self->CumDiffFlop($image, $cell, $minDiff,0);
					if ($diff < $minDiff and (!$cell->{img}->{force} or $diff < $cell->{diff})) {
						$minDiff = $diff;
						$cIdx = $cell->{i};
					}
					$nbrPlacedForces++ if $cell->{img}->{force};
				}
#				printf "%d placed forces, first diff = %f\n", $nbrPlacedForces, $self->CumDiffFlop($image, $self->{sortedcells}->[0], 100000000,0);
#				$debugx = 1 if $nbrPlacedForces == 37;
				
				if ($cIdx == -1) {
					warn "No Cell match!  minDiff = $minDiff\n";
				}
				else {
					my $cell = $self->{cells}->[$cIdx];
					#       if a force photo is already there, push it to end of queue
					if ($cell->{img}->{force}) {
						push @iq, $cell->{img};
						print "Repush\n";
					}
					else {
#						print "Place\n";
					}
					#       place new photo there
					$cell->{img} = $image;
					$image->{i} = $cell->{i};
					$cell->{diff} = $minDiff;
				}			
		}
	}

	# recollect fimages here
	@fimages = ();
	foreach my $cell (@{$self->{cells}})
	{
		$cell->{iIdx} = scalar(@fimages);
		push @fimages, $cell->{img};
	}

  $self->{finalimages} = \@fimages;

  undef $self->{images};
  undef $self->{iIndex};
  undef $self->{sortedcells};
}

sub select_tiles_hmode()
{
  my ($self) = @_;

  $self->sample_photos() if !$self->{images};
  return if !$self->{images};
  $self->setup_cells() if not defined $self->{ucells};
  return if not defined $self->{ucells};

  # sort images by luminance and build histogram index
  # to speed up matching
  my $numImages = scalar( @{$self->{images}} );
  my $lastImageIdx = $numImages-1;
  print "Selecting from $numImages images...\n" if $self->{verbose};

  $self->BuildLumIndex_hmode2();  # !!! MAKE LUM INDEX FOR CELLS...
  
  my $i = 0;
  my @fimages = ();
  
  my $stime = time();
  my $nbrImagesMatched = 0;
  my $maximages = scalar(@{$self->{images}});
  $maximages = $self->{hlimit} if $self->{hlimit} > 0 && $self->{hlimit} < $maximages;

	my $lastUCellIdx = scalar(@{$self->{ucells}})-1;
  my $nbrPlaced = 0;
  my $hPass = 0;

  my @unplacedImages = @{$self->{images}};
  my $nbrUnplaced = scalar(@unplacedImages);

  while ($nbrUnplaced > 0 && $nbrImagesMatched < $maximages)
  {
  	$hPass++;
    print "HPass $hPass, nbrUnplaced = $nbrUnplaced\n";

    # exit if $hPass == 3;

    $nbrUnplaced = 0;
		for my $i (0..$#unplacedImages)
		{
		  my $image = $unplacedImages[$i];
		  next if $image->{placed};

			$self->subsample_photo($image); # subsample photo if we haven't looked at it yet
	
			$image->{lsig} = $self->ComputeSig($image->{pix}->[0]) if not defined $image->{lsig};
	
			# next if not defined $self->{iIndex}->[$image->{lsig}];
			
			if ($image->{cellIdx}) {
				# check if overlap a previously placed image...
				my $cell1 = $self->{cells}->[$image->{cellIdx}];
				my $overlaps = 0;
				foreach my $j (0..$i-1) {
				  my $image2 = $unplacedImages[$j];
          next if not defined $image2->{cellIdx};
					my $cell2 = $self->{cells}->[$image2->{cellIdx}];
					# 10% overlap check
					# printf "Comparing cells %s\n and %s\n", Dumper($cell1), Dumper($cell2);
					if ($self->CellsOverlap($cell1, $cell2)) {
						$overlaps = 1;
						# printf "Cell [%d,%d] overlaps with [%d,%d]\n", $cell1->{'x'}, $cell1->{'y'}, $cell2->{'x'}, $cell2->{'y'};
						last;
					}
				}
				
				# if we don't overlap with previous images, 
				#     add image to fimages, 
				#     removing overlapping cells
				#     and skip to next image
				if (!$overlaps) {
					print "Placed image $i\n";
					push @fimages, $image;
					$image->{placed} = 1;
					++$nbrImagesMatched;
					last if $nbrImagesMatched >= $maximages;
					# remove all overlapping cells from ucelllist
					my $cell1 = $self->{cells}->[$image->{cellIdx}];
					for my $cell2 (@{$self->{cells}})
					{
						if ($self->CellsOverlap($cell1,$cell2)) 
						{
							$cell2->{used} = 1;
						}
					}
					next;
				}
				else {
					print "Image $i overlaps, replacing\n";
				}
			}
			$nbrUnplaced++;
			
			my $ucellList = $self->{iIndex}->[$image->{lsig}];
	
			# find closest cell and assign it...
			# consider using optimization tricks to sort cells by lum
			# !!! break after max-images...
			my $minDiff = 100000000;
			my $gotOne = 0;
	
			foreach my $ucrec (@{$self->{cells}})
			{
				next if $ucrec->{used};
				my $diff = $self->CumDiff($image, $ucrec, $minDiff, 0);
				if ($diff < $minDiff) {
					$minDiff = $diff;
					$cIdx = $ucrec->{i};
					$minUCell = $ucrec;
					$flop = 0;
					$var = 0;
					$gotOne = 1;
				}
			}
			if ($gotOne) {
				$image->{cellIdx} = $cIdx;
				$image->{cDist} = $minDiff;
			}
		}
		# sort images so that better matches are first
		@unplacedImages = sort {$a->{cDist} <=> $b->{cDist}} @unplacedImages;
  }

  # sort images so that better matches render last
	@fimages = sort {$b->{cDist} <=> $a->{cDist}} @fimages;
  
  # only use last X images...
  # splice @fimages, 0, -($self->{max_images});
  
  printf "Done: elapsed = %.1f minutes, %d images placed\n", (time() - $stime)/60.0, $nbrImagesMatched if $self->{verbose};
  $self->{finalimages} = \@fimages;

  undef $self->{images};
  undef $self->{iIndex};
}

sub CellsOverlap()
{
	my ($self,$cell1,$cell2) = @_;
	my ($x1,$y1) = ($cell1->{'x'} , $cell1->{'y'} );
	my ($x2,$y2) = ($cell2->{'x'} , $cell2->{'y'} );
	my $w = $self->{resoX};
	my $h = $self->{resoY};
	return 0 if ($x1 >= $x2+$w);
	return 0 if ($x1+$w <= $x2);
	return 0 if ($y1 >= $y2+$h);
	return 0 if ($y1+$h <= $y2);
	return 1;
}

sub load_data()
{
  my ($self) = @_;

  print "Loading Data...\n";
# my ($basepic,$hcells,$vcells,$tileAspectRatio);
# my @cells;
# my @finalimages;
  require "$self->{rootname}_$self->{basename}_mozdata.ph";
  $self->{basepic} = $basepic;
  $self->{hcells} = $hcells;
  $self->{vcells} = $vcells;
  $self->{tileAspectRatio} = $tileAspectRatio;
  $self->{targetAspectRatio} = $targetAspectRatio;
  $self->{cells} = \@cells;
  $self->{finalimages} = \@finalimages;
}

sub save_data()
{
  my ($self) = @_;
  my $savename = "$self->{rootname}_$self->{basename}_mozdata.ph";
  
  open (OFILE, ">$savename") || die ("Can't save data file $savename\n");
  print OFILE <<EOT;
\$basepic = '$self->{basepic}';
\$hcells = $self->{hcells};
\$vcells = $self->{vcells};
\$tileAspectRatio = $self->{tileAspectRatio};
\$targetAspectRatio = $self->{targetAspectRatio};
EOT

  print OFILE "\@cells = (\n";
  my $n = 0;
  foreach my $cell (@{$self->{cells}}) {
    printf OFILE '%s{x=>%d,y=>%d,iIdx=>%d,var=>%d,flop=>%d,tint=>\'%s\'}',
                $n? ",\n" : "",
                $cell->{'x'}, $cell->{'y'}, 
                $cell->{iIdx}, 
                $cell->{var},
                $cell->{flop}? 1 : 0,
                $cell->{tint}? $cell->{tint} : '';
    $n++;
  }
  print OFILE "\n);\n";

  print OFILE "\@finalimages = (\n";
  $n = 0;
  foreach my $img (@{$self->{finalimages}}) {
    printf OFILE '%s{idx=>%d,desc=>"%s"}',($n? ",\n" : ""), $img->{idx}, $self->{imageset}->get_image_desc($img->{idx});
    $n++;
  }
  print OFILE "\n);\n1;\n";
  
  close OFILE;
}

sub generate_mosaic()
{
  my ($self, $iopts) = @_;

  if (!$self->{finalimages})
  {
    if ($self->{load}) {
      $self->load_data();
    }
    else {
    	if ($self->{hmode})
    	{
	      $self->select_tiles_hmode();
    	}
    	else {
	      $self->select_tiles();
	    }
      return if !$self->{finalimages};
      $self->save_data() if !$self->{hmode};
    }
  }

  # if cellsize is not defined, compute a cellsize which will make us reach minWidth and maxWidth
  if (!$self->{cellsize}) 
  {
    if (!$self->{minWidth} || !$self->{minHeight})
    {
      die ("No output dimensions defined\n");
    }
    print "No explicit cellsize defined\n";
    my $outputAspectRatio = $self->{minHeight} / $self->{minWidth};
    if ($self->{targetAspectRatio} < $outputAspectRatio) {
      # output is taller than target-image, scale to minHeight
      $self->{cellsize} = int($self->{minHeight}/($self->{vcells} / $self->{tileAspectRatio}));
    }
    else {
      # output is wider or equal to target-image, scale to minWidth
      $self->{cellsize} = int($self->{minWidth}/$self->{hcells});
    }
    $self->{cellsize}++ if $self->{hcells}*$self->{cellsize} < $self->{minWidth};
    $self->{cellsize}++ if $self->{vcells}*int($self->{cellsize}*$self->{tileAspectRatio}+.5) < $self->{minWidth};
  }

  my %opts = (filename => "$self->{rootname}_$self->{basename}_$self->{hcells}_x_$self->{vcells}_c$self->{cellsize}.jpg", 
              pngname => "$self->{rootname}_$self->{basename}_$self->{hcells}_x_$self->{vcells}_c$self->{cellsize}.png", 
              quality=>90, 
              width=>$self->{cellsize} * $self->{hcells},
              height=>($self->{cellsize}/$self->{tileAspectRatio}) * $self->{vcells}
              );

  $opts{filename} = $self->{filename} if ($self->{filename} && $self->{filename} ne '');

  for my $k (keys %{$iopts})
  {
    $opts{$k} = $iopts->{$k};
  }
  
  print "Output filename: $opts{filename}\n";
  
  my $cellsizeX = int($opts{width} / $self->{hcells} + .5);
  my $cellsizeY = int($opts{height} / $self->{vcells} + .5);

  my ($width, $height) = ($cellsizeX*$self->{hcells}, 
                          $cellsizeY*$self->{vcells});

  print "Image Dimensions will be $width x $height (tiles = $cellsizeX x $cellsizeY)\n" if $self->{verbose};

  my $maxCellsize = $cellsizeX > $cellsizeY? $cellsizeX : $cellsizeY;

  my $htmlName = $opts{filename};
  $htmlName =~ s/\.jpg/\.html/;
  open (HFILE, ">$htmlName") or die ("Can't open html file $htmlName\n");
  printf HFILE "<img src=\"%s\" usemap=\"#mozmap\" border=0>\n", $opts{filename};
  print  HFILE "<map name=\"mozmap\">\n";
  my $mosaic;

  if ($self->{strip}) # !!! note, strip currently only works for normal (hmode==0)
  {
    foreach my $cy (0..$self->{vcells}-1)
    {
      $mosaic = Image::Magick->new;
      $mosaic->Set(size=>"${width}x${cellsizeY}"); # worked okay at 10000x10000
      my $err = $mosaic->Read('xc:black');
      warn "$err" if "$err";

      my $i = 0;
      foreach my $cell (@{$self->{cells}})
      {
        next if $cell->{'y'} != $cy;

        my $imgdat = $self->{finalimages}->[$cell->{iIdx}];
        my ($x, $y) = ($cell->{'x'}, $cell->{'y'});
        
        printf HFILE "<AREA SHAPE=rect COORDS=\"%d,%d,%d,%d\" href=\"%s\" TITLE=\"%s\">\n",
          $x*$cellsizeX,$y*$cellsizeY,($x+1)*$cellsizeX,($y+1)*$cellsizeY,
          $self->{imageset}->get_image_webpage($imgdat->{idx}),
          $self->{imageset}->get_image_desc($imgdat->{idx});

        my $img = $self->getcroppedphoto($imgdat->{idx}, $maxCellsize, $cell->{var});
        $img->Set(colorspace=>'RGB');
        $img->Resize(width=>$cellsizeX, height=>$cellsizeY);
        $img->Flop() if ($cell->{flop});
		if ($self->{grayscale}) {
		  $img->Quantize(colorspace=>'gray');
		}

        $err = $mosaic->Composite(image=>$img, 'x'=>$x*$cellsizeX, 'y'=>($y-$cy)*$cellsizeY);  # y will be zero
        warn "$err" if "$err";

        undef $img;

        # tile-by-tile tint mode - less memory intensive than regular mixin, but only accurate to the tile.
        if ($self->{mixin} > 0 && $self->{tint})
        {
          my $tintpic = Image::Magick->new;
          $tintpic->Set(size=>"${cellsizeX}x${cellsizeY}");
          $tintpic->Read('xc:' . $cell->{tint});
          $err = $mosaic->Composite(image=>$tintpic, compose=>$self->{cmode}, # 'Dissolve' 
                                    opacity=>Image::Magick->QuantumRange*$self->{mixin}/100, 'x'=>$x*$cellsizeX, 'y'=>($y-$cy)*$cellsizeY);
          undef $tintpic;
        }
      }
      # save strip here...
      my $pngname = 'strips/' . $opts{pngname};
      my $sname = sprintf "%03d", $cy;
      $pngname =~ s/\.png/_S_$sname.png/;
      print "Saving PNG $pngname...\n" if $self->{verbose};
      $mosaic->Write($pngname);
      undef $mosaic;
    }
    my $ocname = 'strips/make_' . $opts{pngname};
    $basename = $opts{pngname};
    $basename =~ s/\.png//;
    $ocname =~ s/\.png/.bat/;
    print "Writing construction script $ocname\n";
    open (OCFILE, ">$ocname");
    print OCFILE "montage -geometry ${width}x${cellsizeY}+0+0 -tile 1x$self->{vcells} ${basename}_S*.png -quality 90 ../${basename}.jpg\n";
    print OCFILE "montage -geometry ${width}x${cellsizeY}+0+0 -tile 1x$self->{vcells} ${basename}_S*.png ../${basename}.png\n";
    close OCFILE;
  
  }
  else
  {
	  if (!$self->{hmode})
	  {
			# NORMAL
			#
			$mosaic = Image::Magick->new;
			if ($self->{grayscale}) {
				$mosaic->Set(size=>"${width}x${height}",colorspace=>'gray');
			}
			else {
				$mosaic->Set(size=>"${width}x${height}");
			}
			my $err = $mosaic->Read('xc:black');
			warn "$err" if "$err";
	
			my $i = 0;
			foreach my $cell (@{$self->{cells}})
			{
				my $imgdat = $self->{finalimages}->[$cell->{iIdx}];
				my ($x, $y) = ($cell->{'x'}, $cell->{'y'});
	
				printf HFILE "<AREA SHAPE=rect COORDS=\"%d,%d,%d,%d\" href=\"%s\" TITLE=\"%s\">\n",
					$x*$cellsizeX,$y*$cellsizeY,($x+1)*$cellsizeX,($y+1)*$cellsizeY,
					$self->{imageset}->get_image_webpage($imgdat->{idx}),
					$self->{imageset}->get_image_desc($imgdat->{idx});
	
				my $img = $self->getcroppedphoto($imgdat->{idx}, $maxCellsize, $cell->{var});
				$img->Set(colorspace=>'RGB');
				$img->Resize(width=>$cellsizeX, height=>$cellsizeY);
				$img->Flop() if ($cell->{flop});
				if ($self->{grayscale}) {
 				  $img->Quantize(colorspace=>'gray');
				}
	
			    $err = $mosaic->Composite(image=>$img, 'x'=>$x*$cellsizeX, 'y'=>$y*$cellsizeY);
				
				warn "$err" if "$err";
	
				undef $img;
	
				# tile-by-tile tint mode - less memory intensive than regular mixin, but only accurate to the tile.
				# !!! only works for hmode==0
				if ($self->{mixin} > 0 && $self->{tint})
				{
					my $tintpic = Image::Magick->new;
					$tintpic->Set(size=>"${cellsizeX}x${cellsizeY}");
					$tintpic->Read('xc:' . $cell->{tint});
					$err = $mosaic->Composite(image=>$tintpic, compose=>$self->{cmode}, # Blend, Darken, 'Dissolve' 
																		opacity=>Image::Magick->QuantumRange*$self->{mixin}/100, 
																		'x'=>$x*$cellsizeX, 'y'=>$y*$cellsizeY);
					undef $tintpic;
				}
	
        		if ($self->{anno})
				{
				  my $pointsize = int($cellsizeX * .33);
				  my $anno = sprintf '%c%d', 65+$x,$y+1;
					$mosaic->Annotate(font=>'Arial.ttf', 
																text=>$anno, 
																align=>'Left',
																'x'=>int($x*$cellsizeX+4), 
																'y'=>int($y*$cellsizeY+$pointsize+2), 
																stroke=>'none',
																fill=>'#FFFFFF',
																antialias=>1,
																pointsize=>$pointsize);
					$mosaic->Annotate(font=>'Arial.ttf', 
																text=>$anno, 
																align=>'Left',
																'x'=>int($x*$cellsizeX+4+2), 
																'y'=>int($y*$cellsizeY+$pointsize+2+2), 
																stroke=>'none',
																fill=>'#000000',
																antialias=>1,
																pointsize=>$pointsize);
				}
				print "$i...\n" if (++$i % 500 == 0);
			}
	  }
	  else {
	  	# HMODE
	  	#
			$mosaic = Image::Magick->new;
			
			if ($self->{hbase} =~ /xc:/) {
				# solid color background
				$mosaic->Set(size=>"${width}x${height}");
				$err = $mosaic->Read($self->{hbase});
			}
			else {
				$err = $mosaic->Read($self->{hbase});
				$mosaic->Resize(width=>$width, height=>$height);
			}
			if ($self->{grayscale}) {
				$mosaic->Set(colorspace=>'gray');
			}

			warn "$err" if "$err";
	
			my $i = 0;
			
			# IMAGES POINT TO CELLS...
			foreach my $imgdat (@{$self->{finalimages}})
			{
				my $cell = $self->{cells}->[$imgdat->{cellIdx}];

				my ($x, $y) = ($cell->{'x'}, $cell->{'y'});
	
				# !!! HTML params invalid here...
				printf HFILE "<AREA SHAPE=rect COORDS=\"%d,%d,%d,%d\" href=\"%s\" TITLE=\"%s\">\n",
					$x*$cellsizeX,$y*$cellsizeY,($x+1)*$cellsizeX,($y+1)*$cellsizeY,
					$self->{imageset}->get_image_webpage($imgdat->{idx}),
					$self->{imageset}->get_image_desc($imgdat->{idx});
	
				my $img = $self->getcroppedphoto($imgdat->{idx}, $maxCellsize, $cell->{var});
				$img->Set(colorspace=>'RGB');
				$img->Resize(width=>$cellsizeX, height=>$cellsizeY);
				$img->Flop() if ($cell->{flop});
				if ($self->{grayscale}) {
 				  $img->Quantize(colorspace=>'gray');
				}
	
				$err = $mosaic->Composite(image=>$img, 'x'=>$x*$cellsizeX/$self->{resoX}, 'y'=>$y*$cellsizeY/$self->{resoY});
				
				if ($self->{mixin} > 0 && $self->{tint})
				{
					my $tintpic = Image::Magick->new;
					$tintpic->Set(size=>"${cellsizeX}x${cellsizeY}");
					$tintpic->Read('xc:' . $cell->{tint});
					$err = $mosaic->Composite(image=>$tintpic, compose=>$self->{cmode}, # 'Dissolve' 
																		opacity=>Image::Magick->QuantumRange*$self->{mixin}/100, 
																		'x'=>$x*$cellsizeX/$self->{resoX}, 'y'=>$y*$cellsizeY/$self->{resoY});
					undef $tintpic;
				}


				warn "$err" if "$err";
	
				undef $img;
	
				print "$i...\n" if (++$i % 500 == 0);
			}
	  }

    print HFILE "</map>\n";
    close HFILE;

		if ($self->{mixin} > 0 && !$self->{tint}) 
		{
	
			my $bgpic = Image::Magick->new;
			my $err = $bgpic->Read($self->{basepic});
			$bgpic->Resize(width=>$width, height=>$height);
	
			printf "Mixing in: $self->{mixin}...(%f)\n", Image::Magick->QuantumRange*$self->{mixin}/100;
	
			print "$err\n" if $err;
			$err = $mosaic->Composite(image=>$bgpic, compose=>$self->{cmode}, # was 'Dissolve' 
																opacity=>Image::Magick->QuantumRange*$self->{mixin}/100, 'x'=>0, 'y'=>0);
			undef $bgpic;
		}

		if ($self->{png}) {
			print "Saving PNG $opts{pngname}...\n" if $self->{verbose};
			$mosaic->Write($opts{pngname});
		}
	
		print "Saving JPEG $opts{filename}...\n" if $self->{verbose};
		# printf "Opts = %s\n", Dumper(\%opts);
		$mosaic->Set(quality=>$opts{quality});
		$mosaic->Write($opts{filename});
		$self->{filename} = $opts{filename};
		$self->{pngname} = $opts{pngname};
		undef $mosaic;
  }
}

1;
