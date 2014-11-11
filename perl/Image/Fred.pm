package Image::Fred;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(func1, func2);
@EXPORT_OK = qw(func3);

my %fields = (
  x => 1,
  y => 2
);

sub new 
{
  my ($that,$arg1) = @_;
  my $class = ref($that) || $that;
  my $self = {%fields};
  $self->{x} = $arg1 if defined $arg1;
  bless $self, $class;
  return $self;
}

sub func1()
{
  my ($self, $a1, $a2) = @_;
  print("Func 1: a1 = $a1 x = $self->{x}\n")
}

sub func2($$)
{
  my ($self, $a1, $a2) = @_;
  print("Func 2: a1 = $a1 y = $self->{y}\n")
}

sub func3()
{
  my ($self, $a1, $a2) = @_;
  print("Func 3: a1 = $a1 x = $self->{x}\n")
}
1;
