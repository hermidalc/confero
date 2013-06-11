#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use sigtrap qw(handler sig_handler normal-signals error-signals ALRM);
use Confero::DB;

sub sig_handler {
    die "\n\n$0 program exited gracefully [", scalar localtime, "]\n\n";
}

our $VERSION = '0.1';

# Unbuffer error and output streams (make sure STDOUT is last so that it remains the default filehandle)
select(STDERR); $| = 1;
select(STDOUT); $| = 1;

# dump schema DDL
my $ctk_db = Confero::DB->new();
my $mysql_server_version_str = $ctk_db->storage->dbh->selectrow_array('SELECT VERSION()');
my ($mysql_server_version) = split /-/, $mysql_server_version_str;
my $mysql_sqlt_args = { show_warnings => 1, producer_args => { mysql_version =>  $mysql_server_version } };
my @deploy_stmts = $ctk_db->deployment_statements(undef, undef, undef, $mysql_sqlt_args);
print "$deploy_stmts[0]", join(";\n", @deploy_stmts[1 .. $#deploy_stmts - 1]), ";\n--\n--\n$deploy_stmts[$#deploy_stmts];\n--\n--\n\n";
exit;
