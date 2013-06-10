#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use sigtrap qw(handler sig_handler normal-signals error-signals ALRM);
use Confero::LocalConfig qw(:web);
use File::Basename qw(fileparse);
use Getopt::Long qw(:config auto_help auto_version);
use Pod::Usage qw(pod2usage);
use Term::ANSIColor;

sub sig_handler {
    die "$0 program exited gracefully [", scalar localtime, "]\n";
}
our $VERSION = '0.1';
# unbuffer error and output streams (make sure STDOUT is last so that it remains the default filehandle)
select(STDERR); $| = 1;
select(STDOUT); $| = 1;

# config
my $pid_file = "$FindBin::Bin/../www/" . fileparse($0, qr/\.[^.]*/) . '.pid';
my $app_file = "$FindBin::Bin/../www/bin/app.pl";
my $error_log_file = "$FindBin::Bin/../www/logs/starman_error.log";

# set PERL5LIB for system calls
$ENV{PERL5LIB} = "$FindBin::Bin/../lib/perl5:$FindBin::Bin/../extlib/lib/perl5";

# defaults
my $num_workers = 5;
my $app_env = 'deployment';
my $host = $CTK_WEB_SERVER_HOST;
my $port = $CTK_WEB_SERVER_PORT;
my $debug = 0;
GetOptions(
    'env|e=s'     => \$app_env,
    'workers|w=i' => \$num_workers,
    'host|h=s'    => \$host,
    'port|p=i'    => \$port,
    'debug|d'     => \$debug,
) || pod2usage(-verbose => 0);
$ARGV[0] =~ s/\s+//g;
pod2usage(-message => 'Missing or invalid {start|stop} required parameter', -verbose => 0)
    unless @ARGV and $ARGV[0] =~ /^(start|stop|status)$/i;
my $cmd_type = shift @ARGV;
{
    no strict 'refs';
    &$cmd_type;
}
exit;

sub start {
    my $start_cmd_str = <<"    PLACKUPCMD";
    $FindBin::Bin/../extlib/bin/plackup \\
    --daemonize \\
    --env $app_env \\
    --server Starman \\
    --listen $host:$port \\
    --workers $num_workers \\
    --pid $pid_file \\
    --app $app_file \\
    --error-log $error_log_file
    PLACKUPCMD
    print "$start_cmd_str\n" if $debug;
    print 'Starting Confero Application Server...';
    if (system(split(' ', $start_cmd_str)) == 0) {
        print +(' ' x 20), '[ ', colored('OK', 'green'), " ]\n";
    }
    else {
        print +(' ' x 20), '[ ', colored('FAILED', 'red'), " ]\n";
        die "Could not start Confero application server, exit code: ", $? >> 8, "\n";
    }
}

sub stop {
    my $get_pid_cmd_str = "cat $pid_file";
    print "$get_pid_cmd_str\n" if $debug;
    print 'Stopping Confero Application Server...';
    chomp(my $pid = `$get_pid_cmd_str`);
    if (defined $pid and $pid) {
        # SIGQUIT and Starman will automatically reap child workers
        my $stop_cmd_str = "kill -QUIT $pid";
        print "$stop_cmd_str\n" if $debug;
        if (system(split(' ', $stop_cmd_str)) == 0) {
            print +(' ' x 20), '[ ', colored('OK', 'green'), " ]\n";
        }
        else {
            print +(' ' x 20), '[ ', colored('FAILED', 'red'), " ]\n";
            die "Could not stop Confero application server, exit code: ", $? >> 8, "\n";
        }
    }
    else {
        print +(' ' x 20), '[ ', colored('FAILED', 'red'), " ]\n";
        die "Could not locate Confero application server process, most likely server is not running\n";
    }
}

sub status {
    my $status_cmd_str = "pgrep -F $pid_file > /dev/null 2>&1";
    if (system(split(' ', $status_cmd_str)) == 0) {
        print "Confero application server is running\n";
    }
    else {
        print "Confero application server is stopped\n";
    }
}

sub restart {
    &stop;
    sleep 5;
    &start;
}

__END__

=head1 NAME 

cfo_app_server.pl - Confero Application Server

=head1 SYNOPSIS

 cfo_app_server.pl {start|stop|status} [options]

 Options:
    --env|-e <development|deployment|test>  Application environmnent (default 'deployment', i.e. production)
    --workers|-w <n>                        Size of Starman server worker pool (default 5)
    --host|-h <hostname>                    Host address to bind to (default Confero configuration)
    --port|-p <port>                        Port to bind to (default Confero configuration)
    --help                                  Display usage message and exit
    --version                               Display program version and exit

=cut
