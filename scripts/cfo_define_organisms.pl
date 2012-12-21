#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use sigtrap qw(handler sig_handler normal-signals error-signals ALRM);
use DBI;
use Confero::Config qw(:database);
use Confero::LocalConfig qw(:database);
use Getopt::Long qw(:config auto_help auto_version);
use Pod::Usage qw(pod2usage);
use Sys::Hostname::FQDN qw(fqdn);

sub sig_handler {
    die "\n\n$0 program exited gracefully [", scalar localtime, "]\n\n";
}
our $VERSION = '0.0.1';


# Unbuffer error and output streams (make sure STDOUT is last so that it remains the default filehandle)
select(STDERR); $| = 1;
select(STDOUT); $| = 1;


#my $confero_db = Confero::DB->new();
my $dsn = "DBI:$CTK_DB_DRIVER:" . 
    ($CTK_DB_DRIVER =~ /^mysql$/i  ? 'database' :
         $CTK_DB_DRIVER =~ /^pg$/i     ? 'dbname'   :
             $CTK_DB_DRIVER =~ /^oracle$/i ? 'sid'      : 
                 DBI->throw_exception("Unsupported DBD driver '$CTK_DB_DRIVER'")) . 
    "=$CTK_DB_NAME;host=$CTK_DB_HOST" . 
    ($CTK_DB_HOST !~ /^localhost$/i ? ";port=${CTK_DB_PORT}" : '');
my $user = $CTK_DB_USER;
my $pass = $CTK_DB_PASS;
my $dbi_attrs   = { PrintError => 0, RaiseError => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc', LongTruncOk => 0 };
my $extra_attrs = undef;
my $confero_db = DBI->connect($dsn, $user, $pass, $dbi_attrs, $extra_attrs);


# Add organism definitions
print "Adding Organism definitions...\n";

# sql inserts
my $sql =
  "INSERT INTO organism(tax_id, name) " .
  "VALUES (?, ?)";
my $sth = $confero_db->prepare($sql) or die "Couldn't prepare query";
$sth->execute('9606', 'Homo sapiens');
$sth->execute('10090', 'Mus musculus');
$sth->execute('10116', 'Rattus norvegicus');

print "\nDone.\n\n";
exit;
