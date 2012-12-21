#!/bin/sh
scriptdir=`dirname $0`
export PERL5LIB=$scriptdir/../extlib/lib/perl5
$scriptdir/cfo_dump_db_ddl.pl > $scriptdir/cfo_db_ddl.sql
$scriptdir/../extlib/bin/sqlt-diagram --db=MySQL --title="Confero DB Schema" --output=cfo_db_schema.png -c 3 --color $scriptdir/cfo_db_ddl.sql
