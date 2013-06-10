#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use sigtrap qw(handler sig_handler normal-signals error-signals ALRM);
use Confero::LocalConfig qw(:database :web);
use Confero::DB;
use Getopt::Long qw(:config auto_help auto_version);
use Pod::Usage qw(pod2usage);
use Sys::Hostname qw(hostname);

sub sig_handler {
    die "\n\n$0 program exited gracefully [", scalar localtime, "]\n\n";
}
our $VERSION = '0.1';
# Unbuffer error and output streams (make sure STDOUT is last so that it remains the default filehandle)
select(STDERR); $| = 1;
select(STDOUT); $| = 1;

my $no_interactive = 0;
my $no_db = 0;
my $no_download = 0;
my $debug = 0;
my $verbose = 0;
GetOptions(
    'no-interactive' => \$no_interactive,
    'no-db'          => \$no_db,
    'no-download'    => \$no_download,
    'debug'          => \$debug,
    'verbose'        => \$verbose,
) || pod2usage(-verbose => 0);
print "#", '-' x 120, "#\n",
      "# Confero System Setup [" . scalar localtime() . "]\n\n",
      "Welcome to the Confero system setup program!\n\n";
# database setup
print "[Database]\n";
if (!$no_db) {
    my $hostname = hostname;
    my $DB_CREATE_STMTS =
    "CREATE DATABASE $CTK_DB_NAME DEFAULT CHARACTER SET = 'utf8'; \\
     GRANT ALL PRIVILEGES ON ${CTK_DB_NAME}.* TO ${CTK_DB_USER}\@'%' IDENTIFIED BY '${CTK_DB_PASS}'; \\
     GRANT ALL PRIVILEGES ON ${CTK_DB_NAME}.* TO ${CTK_DB_USER}\@'$hostname' IDENTIFIED BY '${CTK_DB_PASS}'; \\
     GRANT ALL PRIVILEGES ON ${CTK_DB_NAME}.* TO ${CTK_DB_USER}\@'localhost' IDENTIFIED BY '${CTK_DB_PASS}'; \\
     GRANT ALL PRIVILEGES ON ${CTK_DB_NAME}.* TO ${CTK_DB_USER}\@'127.0.0.1' IDENTIFIED BY '${CTK_DB_PASS}';";
    my $DB_DROP_STMTS =
    "DROP DATABASE $CTK_DB_NAME;";
    #DROP USER IF EXISTS ${CTK_DB_USER}\@'%'; \\
    #DROP USER IF EXISTS ${CTK_DB_USER}\@'$hostname'; \\
    #DROP USER IF EXISTS ${CTK_DB_USER}\@'localhost'; \\
    #DROP USER IF EXISTS ${CTK_DB_USER}\@'127.0.0.1';";
    print "Welcome, first need elevated credentials for creating database and granting privileges...\n";
    print "DB superuser username [$ENV{USER}]: ";
    chomp(my $db_user = <STDIN>);
    print "DB superuser password []: ";
    system 'stty -echo';
    chomp(my $db_pass = <STDIN>);
    system 'stty echo';
    # Check if database exists using passed elevated credentials 
    # (because if Confero user doesn't exist yet will get connection 
    # failure using configuration credentials)
    eval {
        Confero::DB->new($db_user, $db_pass)->storage->ensure_connected();
    };
    # Database doesn't exist
    if ($@) {
        if ($@ =~ /unknown database '$CTK_DB_NAME'/i) {
            print "\nLooks like database '$CTK_DB_NAME' doesn't exist, would you like to create it? [yes] ";
            chomp(my $answer = <STDIN>);
            $answer = 'yes' if $answer eq '';
            if ($answer =~ /^y(es|)$/i) {
                if ($CTK_DB_DRIVER =~ /^mysql$/i) {
                    $db_user = $db_user || $ENV{USER};
                    $db_pass = $db_pass || '';
                    my $db_create_cmd = "mysql --user=$db_user --password=$db_pass --host=$CTK_DB_HOST --show_warnings --execute=\\\n\"$DB_CREATE_STMTS\"";
                    $db_create_cmd .= ' --verbose' if $verbose or $debug;
                    (my $db_create_cmd_to_print = $db_create_cmd) =~ s/--password=$db_pass/--password=<...>/;
                    print "\n$db_create_cmd_to_print\n" if $verbose or $debug;
                    system($db_create_cmd) == 0 or die "\nCould not create Confero database! Exit code: ", $? >> 8, "\n\n";
                }
                else {
                    die "Database driver '$CTK_DB_DRIVER' not supported. Please check configuration file and change to a supported database driver and back-end.\n";
                }
            }
            else {
                print "\nNo changes made, exiting...\n\n";
                exit;
            }
        }
        else {
            die "\nProblem determining if database exists or if connection simply failed due to bad credentials or parameters\n$@\n";
        }
    }
    # Database already exists
    else {
        print "\nLooks like database '$CTK_DB_NAME' already exists, would you like to *drop* and re-create it? [no] ";
        chomp(my $answer = <STDIN>);
        if ($answer =~ /^y(es|)$/i) {
            if ($CTK_DB_DRIVER =~ /^mysql$/i) {
                $db_user = $db_user || $ENV{USER};
                $db_pass = $db_pass || '';
                my $db_drop_create_cmd = "mysql --user=$db_user --password=$db_pass --host=$CTK_DB_HOST --show_warnings --execute=\\\n\"$DB_DROP_STMTS \\\n $DB_CREATE_STMTS\"";
                $db_drop_create_cmd .= ' --verbose' if $verbose or $debug;
                (my $db_drop_create_cmd_to_print = $db_drop_create_cmd) =~ s/--password=$db_pass/--password=<...>/;
                print "Recreating database\n";
                print "\n$db_drop_create_cmd_to_print\n" if $verbose or $debug;
                system($db_drop_create_cmd) == 0 or die "\nCould not drop and re-create Confero database! Exit code: ", $? >> 8, "\n\n";
            }
            else {
                die "Database driver '$CTK_DB_DRIVER' not supported. Please check configuration.\n";
            }
        }
        else {
            print "\nNo changes made to database, exiting...\n\n";
            exit;
        }
    }
    # deploy schema
    my $ctk_db = Confero::DB->new();
    print "Deploying schema\n\n";
    my $mysql_sqlt_args = { show_warnings => 1, producer_args => { mysql_version =>  $ctk_db->storage->dbh->selectrow_array('SELECT VERSION()') } };
    my @deploy_stmts = $ctk_db->deployment_statements(undef, undef, undef, $mysql_sqlt_args);
    print "$deploy_stmts[0]", join(";\n", @deploy_stmts[1 .. $#deploy_stmts - 1]), ";\n--\n--\n$deploy_stmts[$#deploy_stmts];\n--\n--\n\n" if $verbose or $debug;
    # DBIx::Class schema deploy unfortunately doesn't return true/false on success/failure
    $ctk_db->deploy($mysql_sqlt_args); #or die "\nError, could not successfully deploy the Confero schema\n\n";
}
else {
    # Check if database exists using configured credentials 
    # (because if Confero user doesn't exist yet will get connection 
    # failure using configuration credentials)
    eval {
        Confero::DB->new()->storage->ensure_connected();
    };
    if ($@) {
        die "Database doesn't exist, cannot continue\n$@\n";
    }
    else {
        print "Skipping database setup, using existing database\n\n";
    }
}
# run admin management scripts
print "[Programs]\n",
      "Running management programs to download and generate required system files and initialize database\n\n";
my $cmd_opts = '';
$cmd_opts .= ' --no-interactive' if $no_interactive;
$cmd_opts .= $no_download 
           ? ' --no-entrez-download'
           : ' --download-netaffx --download-agilent --download-geo --download-illumina';
$cmd_opts .= ' --debug' if $debug;
$cmd_opts .= ' --verbose' if $verbose;
system("$FindBin::Bin/cfo_load_entrez_gene_mapping_reprocess.pl $cmd_opts") == 0 
    or die "\nCommand failed! Exit code: ", $? >> 8, "\n\n";
system("$FindBin::Bin/cfo_build_msigdb_c2_ar_gmt.pl") == 0 
    or warn "\nCommand failed! Exit code: ", $? >> 8, "\n\n";
system("$FindBin::Bin/cfo_fetch_process_genesigdb.pl") == 0 
    or warn "\nCommand failed! Exit code: ", $? >> 8, "\n\n";
system("$FindBin::Bin/cfo_create_gsdb_gene_set_galaxy_opts.pl") == 0 
    or warn "\nCommand failed! Exit code: ", $? >> 8, "\n\n";
system("$FindBin::Bin/cfo_define_organisms.pl") == 0 
    or warn "\nCommand failed! Exit code: ", $? >> 8, "\n\n";
print "[Web Server]\n";
# open Galaxy xml file and replace 'DANCER_URL' with the LocalConfig variable $CTK_WEB_SERVER_HOST
system("sed -i 's!CONFERO_WEB_SERVER_URL!$CTK_WEB_SERVER_HOST!g' $FindBin::Bin/../galaxy/view_manage_data.xml") == 0 
    or warn "\nFailed to find CONFERO_WEB_SERVER_URL in $FindBin::Bin/../galaxy/view_manage_data.xml! Exit code: ", $? >> 8, "\n\n";
system("$FindBin::Bin/cfo_app_server.pl start -h $CTK_WEB_SERVER_HOST -p $CTK_WEB_SERVER_PORT") == 0 
    or warn "\nCommand failed! Exit code: ", $? >> 8, "\n\n";
print "\nConfero system setup complete, platform is ready to use!\n\n";
exit;

__END__

=head1 NAME 

cfo_setup.pl - Confero System Setup

=head1 SYNOPSIS

 cfo_setup.pl [options]

 Options:
     --no-interactive          Run in non-interactive mode (default false)
     --no-db                   Skip database (re)creation step (default false)
     --debug                   Enable debug mode (default off)
     --verbose                 Be verbose (default off)
     --help                    Display usage and exit
     --version                 Display program version and exit

=cut
