#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use sigtrap qw(handler sig_handler normal-signals error-signals ALRM);
use Confero::Cmd;
use Confero::LocalConfig qw(:general);
use Confero::DB;
use Confero::Utils qw(construct_id);
use File::Basename qw(fileparse);
use File::Copy qw(move);
use File::Spec;
use Getopt::Long qw(:config auto_help auto_version);
use List::Util qw(min);
use Parallel::Forker;
use Pod::Usage qw(pod2usage);
use Unix::Processors;

sub sig_handler {
    die "\n\n$0 program exited gracefully [", scalar localtime, "]\n\n";
}
our $VERSION = '0.1';
# Unbuffer error and output streams (make sure STDOUT is last so that it remains the default filehandle)
select(STDERR); $| = 1;
select(STDOUT); $| = 1;

# end program if already running
if (`ps -eo cmd | grep -v grep | grep -c "perl $0"` > 1) {
    print "$0 already running! Exiting...\n\n";
    exit;
}

my $data_type;
my $num_parallel_procs = 0;
my $no_threshold_checks = 0;
my $overwrite_existing = 0;
GetOptions(
    'data-type=s'         => \$data_type,
    'parallel:i'          => \$num_parallel_procs,
    'no-threshold-checks' => \$no_threshold_checks,
    'overwrite-existing'  => \$overwrite_existing,
) || pod2usage(-verbose => 0);
pod2usage(-message => 'Missing required --data-type=<type> option') unless defined $data_type;
pod2usage(-message => 'Missing data file directory or file path') unless @ARGV and scalar(@ARGV) == 1;
pod2usage(-message => "'$ARGV[0]' is not a valid directory or file path") unless -d $ARGV[0] or -f $ARGV[0];
pod2usage(-message => 'Data type must be one of: IdMAPS, IdList') unless $data_type =~ /^Id(MAPS|List)$/;
print "#", '-' x 120, "#\n",
      "# Confero Batch Data File Loader [" . scalar localtime() . "]\n\n";
my @data_file_paths;
# directory of data files
if (-d $ARGV[0]) {
    my $data_file_dir_path = $ARGV[0];
    $data_file_dir_path =~ s/\/+$//;
    $data_file_dir_path = File::Spec->rel2abs($data_file_dir_path);
    opendir(my $data_dh, $data_file_dir_path) or die "Could not open directory $data_file_dir_path: $!\n\n";
    @data_file_paths = map { "$data_file_dir_path/$_" } grep { !m/^\./ && !m/\.(log|err)$/ && -f "$data_file_dir_path/$_" } readdir($data_dh);
    closedir($data_dh);
}
# single data file
else {
    my $data_file_path = $ARGV[0];
    push @data_file_paths, File::Spec->rel2abs($data_file_path);
}
if (@data_file_paths) {
    eval {
        my $ctk_db = Confero::DB->new();
        $ctk_db->txn_do(sub {
            print $num_parallel_procs > 1 ? "[Process]\n" : "[Process & Database Load]\n", scalar(@data_file_paths), ' ', $data_type eq 'IdMAPS' ? 'contrast datasets' : 'gene sets', "...\n";
            # remove any previously existing temporary reprocessing files
            unlink(<$CTK_TEMP_DIR/*.log>, <$CTK_TEMP_DIR/*.pls>); #or warn "Could not clean up pre-existing $CTK_TEMP_DIR/*.pls and *.log files: $!\n";
            # parallel
            if ($num_parallel_procs > 1) {
                my $fork_manager = Parallel::Forker->new(use_sig_child => 1, max_proc => min($num_parallel_procs, Unix::Processors->new()->max_physical));
                $SIG{CHLD} = sub { Parallel::Forker::sig_child($fork_manager) };
                $SIG{TERM} = sub { $fork_manager->kill_tree_all('TERM') if $fork_manager and $fork_manager->in_parent; die "Exiting child process\n" };
                for my $data_file_path (sort @data_file_paths) {
                    $fork_manager->schedule(run_on_start => sub {
                        my ($data_file_basename, $data_file_dir_path, $data_file_ext) = fileparse($data_file_path, qr/\.[^.]*/);
                        my $log_file_name = "$data_file_basename.log";
                        my $log_file_path = "$data_file_dir_path/$log_file_name";
                        my $err_file_name = "$data_file_basename.err";
                        my $err_file_path = "$data_file_dir_path/$err_file_name";
                        eval {
                            print "Processing and loading $data_file_basename$data_file_ext [PID $$]\n";
                            Confero::Cmd->process_submit_data_file(
                                $data_file_path, $data_type, $log_file_path, (undef) x 13, $no_threshold_checks, $overwrite_existing,
                            );
                            print "Success $data_file_basename$data_file_ext [PID $$], see $log_file_name for report\n";
                        };
                        if ($@) {
                            if (-e $log_file_path) {
                                move($log_file_path, $err_file_path) or warn "WARNING: could not rename $log_file_name --> $err_file_name\n";
                            }
                            print "ERROR: $data_file_basename$data_file_ext not loaded into repository, please see $err_file_name for details\n";
                        }
                    })->ready();
                }
                # wait for all child processes to finish
                $fork_manager->wait_all();
            }
            else {
                for my $data_file_path (sort @data_file_paths) {
                    my ($data_file_basename, $data_file_dir_path, $data_file_ext) = fileparse($data_file_path, qr/\.[^.]*/);
                    my $log_file_name = "$data_file_basename.log";
                    my $log_file_path = "$data_file_dir_path/$log_file_name";
                    my $err_file_name = "$data_file_basename.err";
                    my $err_file_path = "$data_file_dir_path/$err_file_name";
                    eval {
                        print "Processing and loading $data_file_basename$data_file_ext: ";
                        Confero::Cmd->process_submit_data_file(
                            $data_file_path, $data_type, $log_file_path, (undef) x 13, $no_threshold_checks, $overwrite_existing,
                        );
                    };
                    if ($@) {
                        if (-e $log_file_path) {
                            move($log_file_path, $err_file_path) or warn "WARNING: could not rename $log_file_name --> $err_file_name\n";
                        }
                        print "ERROR: data file not loaded into repository, please see $err_file_name for details\n";
                    }
                    else {
                        print "success, see $log_file_name for report\n";
                    }
                }
            }
        });
    };
    if ($@) {
        my $message = "ERROR: Confero database transaction failed";
        $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
        die "\n\n$message: $@\n";
    }
}
else {
    die "ERROR: directory has no files, so no files to process\n\n";
}
print "\nConfero Batch Data File Loader complete [", scalar localtime, "]\n\n";
exit;

__END__

=head1 NAME 

cfo_load_data_files.pl - Confero Batch Data File Loader

=head1 SYNOPSIS

 cfo_load_data_files.pl [options] [data file directory or file path]

 Options:
    --data-type=<type>        Data file type, currently IdMAPS or IdList (required)
    --no-threshold-checks     Skip gene set threshold checks
    --overwrite-existing      Overwrite any existing dataset of the same name (and all related gene sets)
    --help                    Display usage and exit
    --version                 Display program version and exit

=cut
