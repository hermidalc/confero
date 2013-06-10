#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use sigtrap qw(handler sig_handler normal-signals error-signals ALRM);
use Confero::DB;
use Confero::Utils qw(deconstruct_id is_valid_id);
use Getopt::Long qw(:config auto_help auto_version);
use Pod::Usage qw(pod2usage);
use Storable qw(lock_nstore);

sub sig_handler {
    die "\n\n$0 program exited gracefully [", scalar localtime, "]\n\n";
}
our $VERSION = '0.1';
# Unbuffer error and output streams (make sure STDOUT is last so that it remains the default filehandle)
select(STDERR); $| = 1;
select(STDOUT); $| = 1;

my $force = 0;
my $man = 0;
GetOptions(
    'force' => \$force,
    'man' => \$man,
) || pod2usage(-verbose => 0);
pod2usage(-exitstatus => 0, -verbose => 2) if $man;
pod2usage(-message => 'Missing CTK Dataset ID') unless @ARGV and scalar(@ARGV) == 1;
pod2usage(-message => "Invalid CTK dataset ID $ARGV[0]") unless is_valid_id($ARGV[0]);
print "#", '-' x 120, "#\n",
      "# Confero Dataset Deleter [" . scalar localtime() . "]\n\n";
my $result_message;
eval {
    my $ctk_db = Confero::DB->new();
    $ctk_db->txn_do(sub {
        my $dataset_name = deconstruct_id($ARGV[0]);
        if (my $dataset = $ctk_db->resultset('ContrastDataSet')->find({
                name => $dataset_name,
        })) {
            if (!$force) {
                print "Are you *sure* you would like to completely delete dataset '$ARGV[0]', including all of its contrasts, gene sets, and data? [no] ";
                chomp(my $answer = <STDIN>);
                $answer = 'no' if $answer =~ /^\s*$/;
                if ($answer =~ /^y(es|)$/i) {
                    $dataset->delete();
                    $result_message = "Successfully removed CTK dataset '$ARGV[0]'";
                }
                else {
                    $result_message = "No changes made to database, exiting...";
                }
            }
            else {
                $dataset->delete();
                $result_message = "Successfully removed CTK dataset '$ARGV[0]'";
            }
        }
        else {
            $result_message = "ERROR: CTK dataset '$ARGV[0]' does not exist in repository, no changes made to database";
        }
    });
};
if ($@) {
    my $message = "Confero database transaction failed";
    $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
    die "$message: $@\n";
}
else {
    print "$result_message\n\n";
}

exit;

__END__

=head1 NAME 

cfo_delete_dataset.pl - Confero Dataset Deleter

=head1 SYNOPSIS

 cfo_delete_dataset.pl [options] [Confero Dataset ID]

 Options:
     --force      Force delete without prompt
     --help       Display usage message and exit
     --man        Display full program documentation
     --version    Display program version and exit

=cut
