#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use sigtrap qw(handler sig_handler normal-signals error-signals ALRM);
use Cwd qw(abs_path);
use Getopt::Long qw(:config auto_help auto_version);
use Pod::Usage qw(pod2usage);

sub sig_handler {
    die "\n\n$0 program exited gracefully [", scalar localtime, "]\n\n";
}

our $VERSION = '0.1';

# Unbuffer error and output streams (make sure STDOUT is last so that it remains the default filehandle)
select(STDERR); $| = 1;
select(STDOUT); $| = 1;

# config
my $CPANM_URL = 'http://xrl.us/cpanm';
my $CFO_BASE_DIR = abs_path("$FindBin::Bin/..");
my $DEP_TREE_FILE = "$CFO_BASE_DIR/conf/cfo_perl_dep_tree_all.conf";

my $verbose = 0;
my $no_cpanm_download = 0;
my $dep_file_path = $DEP_TREE_FILE;
GetOptions(
    'verbose+' => \$verbose,
    'no-cpanm-download' => \$no_cpanm_download,
    'dep-file=s' => \$dep_file_path,
) || pod2usage(-verbose => 0);
pod2usage(-message => "$dep_file_path is not a valid file path") unless -f $dep_file_path;
$dep_file_path = abs_path($dep_file_path);
print "#", '-' x 120, "#\n",
      "# Confero Perl Dependency Installer [" . scalar localtime() . "]\n\n";
print "Loading dependency tree\n";
print "$dep_file_path\n" if $verbose;
open(my $deps_fh, '<', $dep_file_path) 
    or die "ERROR: could not open $dep_file_path: $!\n";
my @deps = grep { !m/^#/ } map { s/\s+//g; $_; } <$deps_fh>;
close($deps_fh);
my $deps_str = join(' ', @deps);
if (!$no_cpanm_download) {
    print "Fetching cpanm\n";
    mkdir("$CFO_BASE_DIR/tmp", 0750) or die "ERROR: could not create $CFO_BASE_DIR/tmp directory: $!\n" 
        unless -e "$CFO_BASE_DIR/tmp";
    chdir "$CFO_BASE_DIR/tmp" or die "ERROR: could not chdir to $CFO_BASE_DIR/tmp: $!\n";
    my $cpanm_fetch_cmd = 'curl -SkLO' . ($verbose < 2 ? 's' : '') . " $CPANM_URL";
    print "$cpanm_fetch_cmd\n" if $verbose;
    system(split(' ', $cpanm_fetch_cmd)) == 0 or die "ERROR: could not fetch cpanm: ", $? >> 8, "\n";
    chmod 0700, 'cpanm';
}
chdir $CFO_BASE_DIR or die "ERROR: could not chdir to $CFO_BASE_DIR: $!\n";
print "Downloading, building and installing self-contained dependency tree into local extlib:\n";
my $cpanm_install_cmd = 
    "$CFO_BASE_DIR/tmp/cpanm --local-lib-contained extlib --prompt" . 
    ($verbose == 2 ? ' --verbose' : $verbose == 0 ? ' --quiet' : '') . 
    " $deps_str";
print "$cpanm_install_cmd\n" if $verbose;
system(split(' ', $cpanm_install_cmd)) == 0 
    or print "\nERROR: cpanm had an problem installing dependencies, check console output. Exit code: ", $? >> 8, "\n";
print "\nConfero Perl Dependency Installer complete [", scalar localtime, "]\n\n";
exit;

__END__

=head1 NAME 

cfo_install_deps.pl - Confero Perl Dependency Installer

=head1 SYNOPSIS

 cfo_install_deps.pl [options]

 Options:
     --verbose                  Be more verbose (default off)
     --no-cpanm-download        Skip download of cpanm and use existing program (default false)         
     --help                     Display usage and exit
     --version                  Display program version and exit

=cut
