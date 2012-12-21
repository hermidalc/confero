package Confero::DB;

use strict;
use warnings;
use base 'DBIx::Class::Schema';
use Confero::Config qw(:database);
use Confero::LocalConfig qw(:database);

our $VERSION = '0.0.1';

__PACKAGE__->load_namespaces(
    #default_resultset_class => 'ResultSet',
);

# constructor
sub new {
    my $class = shift;
    my ($alt_user, $alt_pass) = @_;
    my $dsn = "DBI:$CTK_DB_DRIVER:" . 
              ($CTK_DB_DRIVER =~ /^mysql$/i  ? 'database' :
               $CTK_DB_DRIVER =~ /^pg$/i     ? 'dbname'   :
               $CTK_DB_DRIVER =~ /^oracle$/i ? 'sid'      : 
              __PACKAGE__->throw_exception("Unsupported DBD driver '$CTK_DB_DRIVER'")) . 
              "=$CTK_DB_NAME;host=$CTK_DB_HOST" . 
              ($CTK_DB_HOST !~ /^localhost$/i ? ";port=${CTK_DB_PORT}" : '');
    my $user = defined($alt_user) ? $alt_user : $CTK_DB_USER;
    my $pass = defined($alt_pass) ? $alt_pass : $CTK_DB_PASS;
    # DBIx::Class does it's own advanced transaction handling but only if you set AutoCommit = 1 (very important)
    my $dbi_attrs   = { PrintError => 0, RaiseError => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc', LongTruncOk => 0 };
    # as of MySQL 5.1.31 max_allowed_packet session value is read-only and by default set to 1G
    #my $extra_attrs = $CTK_DB_DRIVER =~ /^mysql$/i 
    #                ? { on_connect_do => [ "SET max_allowed_packet = $CTK_DB_MYSQL_MAX_ALLOWED_PACKET" ] }
    #                : undef;
    my $extra_attrs = undef;
    return __PACKAGE__->connect($dsn, $user, $pass, $dbi_attrs, $extra_attrs);
}

sub sqlt_deploy_hook {
    my ($self, $sqlt_schema) = @_;
    for my $table ($sqlt_schema->get_tables()) {
        $table->extra(
            mysql_table_type => 'InnoDB',
        );
    }
}


1;
