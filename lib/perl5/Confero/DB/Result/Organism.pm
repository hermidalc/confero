package Confero::DB::Result::Organism;

use strict;
use warnings;
use base 'DBIx::Class::Core';

our $VERSION = '0.8';

__PACKAGE__->table('organism');
__PACKAGE__->add_columns(
    'id' => {
        data_type         => 'integer',
        is_nullable       => 0,
        is_auto_increment => 1,
        extra             => { unsigned => 1 },
    },
    'tax_id' => {
        data_type         => 'varchar',
        size              => 100,
        is_nullable       => 0,
    },
    'name' => {
        data_type         => 'varchar',
        size              => 100,
        is_nullable       => 1,
    },
);
__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraints(
    organism_un_tax_id => [qw( tax_id )],
    organism_un_name   => [qw( name )],
);
__PACKAGE__->has_many('data_sets' => 'Confero::DB::Result::ContrastDataSet', 'organism_id');
__PACKAGE__->has_many('gene_sets' => 'Confero::DB::Result::GeneSet', 'organism_id');

1;
