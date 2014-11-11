#!/usr/local/bin/perl -s

use Data::Dumper;
$Data::Dumper::Terse = 1;  # avoids $VAR1 = * ; in dumper output
$Data::Dumper::Indent = $verbose? 1 : 0;  # more concise output

# mergeLists.pl list1 list2 [list3...]

@photos = ();


while ($fname = shift)
{
	require $fname;
}

%pKeys = ();

print "# Before: ",scalar(@photos),"\n";

@photos= grep { !$pKeys{$_->{id}}++;  } @photos;

print "# After: ",scalar(@photos),"\n";
# print Dumper($photos[0]);
# exit;

print "push \@photos, (\n";

my $n = 0;

foreach $photo (@photos)
{
    printf "%s%s", $n++? ",\n" : "",Dumper($photo);
}
print "\n);\n1;\n";
