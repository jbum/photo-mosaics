#!/usr/local/bin/perl 
#
# getPhotoList.pl - Jim Bumgardner
#

use Flickr::API;
use XML::Simple;
use Data::Dumper;
$Data::Dumper::Terse = 1;  # avoids $VAR1 = * ; in dumper output
$Data::Dumper::Indent = $verbose? 1 : 0;  # more concise output

# You will need to create this file...
# it supplies the authentication-related vars 
# $api_key and $sharedsecret
require 'apikey.ph';




$syntax = <<EOT;

  getPhotoList.pl [options] [<tags...>]
  getPhotoList.pl [options] -g group_id [<tag>]         
  getPhotoList.pl [options] -u username [<tags>]

Options:
  -u username
  -g group_id
  -all           Photos must match all tags (tag search only)
  -recent X      Only provide photos posted within the last X days (tag searches only)
  -limit X       Provide no more than X photos
  -license x,y   Provide photos with licenses x,y (1,2,4,5,7 is a good choice for mosaics)
  -extras "fields"
  -verbose
EOT

die $syntax if @ARGV == 0;

my $api = new Flickr::API({'key' => $api_key, secret => $sharedsecret});

$tags = '';
$ofname = '';
$method = 'flickr.photos.search';
$all = 0;
$extras = 'owner_name';
$recent = 0;
$limit = 4500;
$license = 0;
$dayoffset = 0;
$verbose = 0;
$forceOfname = 0;
$ofname = '';
$postTagFilter = 0;

while ($_ = shift)
{
  if (/^-g$/)
  {
    $group_id = shift;
    $method = 'flickr.groups.pools.getPhotos';
    print "Searching for photos in group $group_id\n";
    # determine output filename
    $ofname = $group_id if $ofname eq '';
  }
  elsif (/^-u$/)
  {
    $username = shift;
    $method = 'flickr.people.getPublicPhotos' if !$tags;
    $ofname = $username if $ofname eq '';
    $ofname =~ s/,\s*/_/g;
  }
  elsif (/^-all$/) {
    $all = 1;
  }
  elsif (/^-extras$/) {
    $extras = shift;
  }
  elsif (/^-limit$/) {
    $limit = shift;
  }
  elsif (/^-license$/) {
    $license = shift;
  }
  elsif (/^-v(erbose)?$/) {
    $verbose = 1;
  }
  elsif (/^-recent$/) {
    $recent = shift;
  }
  elsif (/^-dayoffset$/) {
    $dayoffset = shift;
  }
  elsif (/^-o$/) {
    $ofname = shift;
    $forceOfname = 1;
  }
  elsif (/^-desc$/) {
    $getDescriptions = 1; # currently unused
    # $extras .= ',' if ($extras ne '');
    # $extras .= 'last_update,machine_tags';
  }
  elsif (/^-/)
  {
    die $syntax;
  }
  else {
    $tags .= "," if $tags;
    $tags .= $_;
    print "Got tag $tags\n";
  }
}

if ($tags) {
  my $ftags = $tags;
  $ftags =~ s/,/_/g;
  if (!$forceOfname) {
	  $ofname .= '_' if $ofname;
  	$ofname .= $ftags;
	}
}

$ofname .= '.ph' if !$forceOfname;
 
$nbrPages = 0;
$photoIdx = 0;

open (OFILE, ">$ofname");

print OFILE "push \@photos, (\n";

$user_id = '';
$min_taken_date = '';
$max_taken_date = '';

$xmlp = new XML::Simple ();

if ($recent) 
{
  die "-recent option only valid for tag search\n" if $method ne 'flickr.photos.search';
  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
        gmtime(time - $recent*24*60*60);
  $min_taken_date = sprintf "%04d-%02d-%02d 00:00:00",1900+$year,$mon+1,$mday;
  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
        gmtime(time);
  $max_taken_date = sprintf "%04d-%02d-%02d 00:00:00",1900+$year,$mon+1,$mday;
}

if ($dayoffset) 
{
	my $r = $recent? abs($recent) : 1;

  die "-dayoffset option only valid for tag search\n" if $method ne 'flickr.photos.search';
  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
        gmtime(time - ($dayoffset+$r)*24*60*60);
  $min_taken_date = sprintf "%04d-%02d-%02d 00:00:00",1900+$year,$mon+1,$mday;

  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
        gmtime(time - ($dayoffset)*24*60*60);
  $max_taken_date = sprintf "%04d-%02d-%02d 00:00:00",1900+$year,$mon+1,$mday;
  $extras = "date_taken,date_upload";
  print "Time Range: $min_taken_date - $max_taken_date\n";
}


if ($username)
{
  # look up user id if a username was provided
  #
  my $response = $api->execute_method('flickr.people.findByUsername', {
                    username => $username} );
  die "Problem determining user_id: $response->{error_message}\n" if !$response->{success};

  print Dumper($response) if $verbose;  # explore results of call using -verbose

  my $xm = $xmlp->XMLin($response->{_content}); 
  $user_id = $xm->{user}->{id};

  if ($tags) {
    $extras .= ',' if ($extras ne '');
    $extras .= 'tags';
    $postTagFilter = 1;
  }

  print "Userid: $user_id\n";
}

print "License = $license\n" if $license;
print "Extras= $extras\n" if $extras;
print "Tags= $tags\n" if $tags;

do
{
  my $params = {  per_page => 500,
                  page => $nbrPages+1};

  $params->{tags} = $tags if $tags and not $text and not $postTagFilter;
  $params->{text} = $tags if $text;
  $params->{user_id} = $user_id if $user_id;
  $params->{group_id} = $group_id if $group_id;
  $params->{min_taken_date} = $min_taken_date if $min_taken_date;
  $params->{max_taken_date} = $max_taken_date if $max_taken_date;
  $params->{license} = $license if $license;
  $params->{extras} = $extras if $extras;
  $params->{tag_mode} = 'all' if $all and not $postTagFilter;
  $params->{auth_token} = $auth_token_JBUM;

  # print Dumper($params);

  print "\n\n$method: " . Dumper($params) . "\n\n" if $verbose;
  # exit;
   
  my $response = $api->execute_method($method, $params );
  die "Problem: $response->{error_message}\n" if !$response->{success};

  # printf "Nbr Children = %d\n", scalar(@{$response->{tree}->{children}->[1]->{children}});

  # print Dumper($response) if $verbose;  # explore results of call using -verbose
  # exit;
  
  # printf "decoded content? %s\n", defined $response->{_decoded_content}? "true" : "false";


  my $xml = $response->decoded_content;
  
  print "XML: $xml\n" if $verbose;

  # $xml =~ s/ownername="[^"]+"//g;
  # $xml =~ s/title="[^"]+"//g;

  my $xm = $xmlp->XMLin($xml,forcearray=>['photo']);

  $photos = $xm->{photos};
  print "Page $photos->{page} of $photos->{pages}\n";

  # loop thru photos
  $photoList = $xm->{photos}->{photo};

PHOTO:
  foreach $id (keys %{$photoList})
  {
    my $photo = $photoList->{$id};

    if ($postTagFilter)
    {
      next if not defined $photo->{tags};
      my $gotHit = 0;
      foreach my $tg (split /,/,$tags)
      {
        if ($photo->{tags} =~ m~\b$tg\b~i)
        {
          $gotHit = 1;
        }
        else {
          next PHOTO if $all;
        }
      }
      next PHOTO if !$gotHit;
    }

    $photo->{id} = $id;

    print OFILE ($photoIdx++? ",\n" : "") . Dumper($photo);
  }
  ++$nbrPages;
} while ($photos->{page} < $photos->{pages} && (!$limit || $photoIdx < $limit));

print OFILE "\n);\n1;\n";
close OFILE;

print "$photoIdx photos written to $ofname\n";


