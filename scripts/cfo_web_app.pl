#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use Confero::LocalConfig qw($CTK_WEB_SERVER_PORT);

die "Missing one or more parameters, first should be {start|stop} second should be {development|testing|production}\n" 
    unless @ARGV and scalar(@ARGV) == ($ARGV[0] eq 'start' ? 2 : 1);
my ($cmd_type, $env) = @ARGV;
{
    no strict 'refs';
    &$cmd_type;
}
exit;

sub start {
    my @cmd_args = (
        "$FindBin::Bin/../www/bin/app.pl",
        "--daemon",
        "--port=$CTK_WEB_SERVER_PORT",
        "--environment=$env"
    );
    system(@cmd_args) == 0 or die "Couldn't start web server, exit code: ", $? >> 8, "\n";
}

sub stop {
    #print "ps -eo pid,cmd | grep '$FindBin::Bin/../www/bin/app.pl' | grep -v grep | sed 's/^ *//' | cut -d' ' -f1\n";
    chomp(my $pid = `ps -eo pid,cmd | grep '$FindBin::Bin/../www/bin/app.pl' | grep -v grep | sed 's/^ *//' | cut -d' ' -f1`);
    if (defined $pid and $pid) { 
        system("kill $pid") == 0 or die "Couldn't not stop Confero web application server, exit code: ", $? >> 8, "\n";
    }
    else {
        die "Could not locate Confero web application server process, most likely server is not running\n";
    }
}
