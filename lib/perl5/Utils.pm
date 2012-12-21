package Utils;

use strict;
use warnings;
use Carp qw(confess);
use File::Path ();
use MIME::Base64 qw(encode_base64 decode_base64);
use POSIX ();
use Storable qw(freeze thaw);
require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    clean_whitespace
    clean_freetext
    escape_XML
    escape_shell_metachars
    remove_shell_metachars
    ignoring_case
    is_integer
    is_numeric
    numerically
    dir_size
    ascii_serialize
    ascii_unserialize
    curr_sub_name
    clean_dir
    intersect_arrays
    distinct
);
our $VERSION = '0.8';

sub clean_whitespace {
    my $value = shift;
    $value =~ s/^\s+//o;
    $value =~ s/\s+$//o;
    $value =~ s/\s+/ /go;
    return $value;
}

sub clean_freetext {
    my $value = shift;
    $value =~ s/^\s+//o;
    $value =~ s/\s+$//o;
    return $value;
}

sub escape_XML {
    my $value = shift;
    $value =~ s/&/&amp;/go;
    $value =~ s/</&lt;/go;
    $value =~ s/>/&gt;/go;
    $value =~ s/"/&quot;/go;
    $value =~ s/'/&#39;/go;
    return $value;
}

sub escape_shell_metachars {
    my ($str) = @_;
    $str =~ s/([&;`'\"|*?~<>^()\[\]{}\$])/\\$1/g;
    return $str;
}

sub remove_shell_metachars {
    my ($str) = @_;
    $str =~ s/[&;`'\"|*?~<>^()\[\]{}\$]//go;
    return $str;
}

sub ignoring_case ($$) {
    my ($a, $b) = @_;
    lc($a) cmp lc($b);
}

sub is_integer {
    my $value = shift;
    return $value =~ m/^-?\d+$/o ? 1 : 0;
}

sub is_numeric {
    my $str = shift;
    $str =~ s/^\s+//o;
    $str =~ s/\s+$//o;
    $! = 0;
    my ($num, $n_unparsed) = POSIX::strtod($str);
    return (($str eq '') || ($n_unparsed != 0) || $!) ? 0 : 1;
}

sub numerically ($$) {
    my ($a, $b) = @_;
    $a <=> $b;
}

sub dir_size {
    my $dirpath = shift;
    my $dir_size = 0;
    opendir DIR, $dirpath or die "Unable to open $dirpath: $!";
    my @filenames = readdir DIR;
    closedir DIR;
    for my $filename (@filenames) {
        next if -d "$dirpath/$filename";
        $dir_size += -s "$dirpath/$filename";
    }
    return $dir_size;
}

sub ascii_serialize {
    my $data_ref = shift;
    return encode_base64(nfreeze(${$data_ref}));
}

sub ascii_unserialize {
    my $serialized_data_ref = shift;
    return thaw(decode_base64(${$serialized_data_ref}));
}

sub curr_sub_name {
    my $full_sub_name = (caller(1))[3];
    return pop(@{[split(/::/, $full_sub_name)]});
}

sub clean_dir {
    my ($dir, $max_age) = @_;
    opendir(DIR, $dir) or die "Could not open directory for cleaning: $!";
    while (my $filename = readdir(DIR)) {
        next if $filename =~ /^\./o;
        File::Path::rmtree("$dir/$filename") if (stat("$dir/$filename"))[8] >= $max_age;
    }
    closedir(DIR);
}

sub intersect_arrays {
    my @arrayrefs = @_;
    confess(curr_sub_name() . '() not passed any array references') if scalar(@arrayrefs) == 0;
    foreach (@arrayrefs) {
        confess(curr_sub_name() . '() not passed a list or array of array references') unless ref eq 'ARRAY';
    }
    # if passed only one array then just return it
    return wantarray ? @{$arrayrefs[0]} : $arrayrefs[0] if scalar(@arrayrefs) == 1;
    #my @union = ();
    my @intersection = ();
    my @difference = ();
    my %count = ();
    $count{$_}++ for map { @{$_} } @arrayrefs;
    foreach my $element (keys %count) {
        #push @union, $element;
        push @{ $count{$element} > 1 ? \@intersection : \@difference }, $element;
    }
    return wantarray ? @intersection : \@intersection;
}

sub distinct {
    my %seen = ();
    grep { not $seen{$_}++ } @_;
}

1;
