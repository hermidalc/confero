#!/bin/bash

echo "Confero Perl Dependency Installer"
echo "Fetching cpanm"
cfo_script_dir=`dirname $0`
cd $cfo_script_dir/../
cpanm_bin=$cfo_script_dir/../tmp/cpanm
curl -skL http://cpanmin.us > $cpanm_bin
chmod u+x $cpanm_bin
echo "Downloading, building and installing Perl dependencies to local extlib..."
$cpanm_bin --local-lib-contained extlib --prompt $@ \
RDF/Clone-0.31.tar.gz \
DBI \
CAPTTOFU/DBD-mysql-4.021.tar.gz \
FREW/SQL-Translator-0.11011.tar.gz \
DateTime \
DROLSKY/DateTime-Format-MySQL-0.04.tar.gz \
DOY/Devel-GlobalDestruction-0.05.tar.gz \
GETTY/DBIx-Class-0.08204.tar.gz \
FREW/DBIx-Class-Helpers-2.007001.tar.gz \
FREW/DBIx-Class-DeploymentHandler-0.001005.tar.gz \
XSAWYERX/Dancer-1.3095.tar.gz \
DMUEY/File-Copy-Recursive-0.38.tar.gz \
Getopt::Long \
HTML::TreeBuilder \
JSON \
JSON::XS \
Math::Round \
Module::Pluggable::Object  \
DURIST/Proc-ProcessTable-0.44.tar.gz \
Parallel::Forker \
Parse::BooleanLogic \
Const::Fast \
Sort::Key \
Statistics::Basic \
Sys::Hostname::FQDN \
Text::CSV \
Text::CSV_XS \
Unix::Processors
