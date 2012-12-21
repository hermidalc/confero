#!/bin/sh
scriptdir=`dirname $0`
export PERL5LIB=$scriptdir/../extlib/lib/perl5
$scriptdir/cfo_dump_db_ddl.pl > $scriptdir/cfo_db_ddl.sql
$scriptdir/../extlib/bin/sqlt-graph --db=MySQL --output=cfo_db_graph.png --color $scriptdir/cfo_db_ddl.sql
