#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use Confero::Config qw(:data :affy :agilent :geo :illumina $CTK_GALAXY_ANNOT_NV_SEPARATOR);
use Confero::DB;
use Confero::Utils qw(construct_id);
use Const::Fast;
use Getopt::Long qw(:config auto_help auto_version);
use JSON qw(encode_json);
use Pod::Usage qw(pod2usage);
use Sort::Key::Multi qw(s2keysort);
use Sort::Key::Natural qw(natsort);
use Utils qw(distinct);

our $VERSION = '0.1';

sub distinct_annotations {
    my %seen = ();
    grep { not $seen{$_->name . $_->value}++ } @_;
}

const my $ANNOT_NV_DISPLAY_SEPARATOR => ': ';

my $as_json = 0;
my $as_tuples = 0;
my $with_empty = 0;
my $pretty_print = 0;
GetOptions(
    'as-json'      => \$as_json,
    'as-tuples'    => \$as_tuples,
    'with-empty'   => \$with_empty,
    'pretty-print' => \$pretty_print,
) || pod2usage(-verbose => 0);
my @data;
my $data_type = @ARGV ? shift @ARGV : '';
my $ctk_db = Confero::DB->new();
# Galaxy needs some value even for empty field so using ?
push @data, [ '', '?', JSON::true ] if $as_tuples and $with_empty;
if ($data_type =~ /^(array|id)_types$/) {
    for my $array_symbol (
        (sort keys %CTK_AFFY_ARRAY_DATA), 
        (sort keys %CTK_AGILENT_ARRAY_DATA), 
        (sort keys %CTK_GEO_ARRAY_DATA), 
        (sort keys %CTK_ILLUMINA_ARRAY_DATA)
    ) {
        push @data, $as_tuples ? [ $array_symbol, $array_symbol, JSON::false ] : $array_symbol;
    }
    if ($data_type eq 'id_types') {
        push @data, $as_tuples 
            ? ([ 'GeneSymbol', 'GeneSymbol', JSON::false ], [ 'EntrezGene', 'EntrezGene', JSON::false ]) 
            : ('GeneSymbol', 'EntrezGene');
    }
}
elsif ($data_type eq 'contrast_dataset_ids') {
    my @contrast_datasets = $ctk_db->resultset('ContrastDataSet')->search(undef, {
        order_by => { -desc => 'me.id' },
    })->all();
    for my $contrast_dataset (@contrast_datasets) {
        my $contrast_dataset_id = construct_id($contrast_dataset->name);
        push @data, $as_tuples ? [ $contrast_dataset_id, $contrast_dataset_id, JSON::false ] : $contrast_dataset_id;
    }
}
elsif ($data_type eq 'contrast_ids') {
    my @contrast_datasets = $ctk_db->resultset('ContrastDataSet')->search(undef, {
        prefetch => 'contrasts',
        order_by => [
            { -desc => 'me.id' },
            { -asc => 'contrasts.id' },
        ],
    })->all();
    for my $contrast_dataset (@contrast_datasets) {
        for my $contrast ($contrast_dataset->contrasts) {
            my $contrast_id = construct_id($contrast_dataset->name, $contrast->name);
            push @data, $as_tuples ? [ $contrast_id, $contrast_id, JSON::false ] : $contrast_id;
        }
    }
}
elsif ($data_type eq 'contrast_gene_set_ids') {
    my @contrast_datasets = $ctk_db->resultset('ContrastDataSet')->search(undef, {
        prefetch => { 'contrasts' => 'gene_sets' },
        order_by => [
            { -desc => 'me.id' },
            { -asc => 'contrasts.id' },
        ],
    })->all();
    for my $contrast_dataset (@contrast_datasets) {
        for my $contrast ($contrast_dataset->contrasts) {
            for my $contrast_gene_set ($contrast->gene_sets) {
                my $contrast_gene_set_id = construct_id($contrast_dataset->name, $contrast->name, $contrast_gene_set->type);
                push @data, $as_tuples ? [ $contrast_gene_set_id, $contrast_gene_set_id, JSON::false ] : $contrast_gene_set_id;
            }
        }
    }
}
elsif ($data_type eq 'gene_set_ids') {
    my @gene_sets = $ctk_db->resultset('GeneSet')->search(undef, {
        order_by => { -desc => 'me.id' },
    })->all();
    for my $gene_set (@gene_sets) {
        my $gene_set_id = construct_id($gene_set->name, $gene_set->contrast_name, $gene_set->type);
        push @data, $as_tuples ? [ $gene_set_id, $gene_set_id, JSON::false ] : $gene_set_id;
    }
}
elsif ($data_type eq 'annotations') {
    #for my $field_name (sort keys %CTK_DATA_FILE_METADATA_FIELDS) {
    #    next unless exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_annot};
    #    push @data, $as_tuples ? [ $field_name, $field_name, JSON::false ] : $field_name;
    #}
    my @cd_annotations = $ctk_db->resultset('ContrastDataSetAnnotation')->search(undef, {
        columns => [qw( name value )],
    })->all();
    my @gs_annotations = $ctk_db->resultset('GeneSetAnnotation')->search(undef, {
        columns => [qw( name value )],
    })->all();
    push @data, 
        map { [ $_->name . $ANNOT_NV_DISPLAY_SEPARATOR . $_->value, $_->name . $CTK_GALAXY_ANNOT_NV_SEPARATOR . $_->value, JSON::false ] } 
        s2keysort { $_->name, $_->value } 
        distinct_annotations(@cd_annotations, @gs_annotations);
}
elsif ($data_type eq 'organisms') {
    my @organism_names = map { $_->name } $ctk_db->resultset('Organism')->search(undef, {
        columns => [qw( name )],
    })->all();
    push @data, map { $as_tuples ? [ $_, $_, JSON::false ] : $_ } @organism_names;
}
elsif ($data_type eq 'contrast_names') {
    my @contrast_dataset_contrast_names = map { $_->name } $ctk_db->resultset('Contrast')->search({
        name => { '!=' => undef },
    }, {
        columns => [qw( name )],
        distinct => 1,
    })->all();
    my @gene_set_contrast_names = map { $_->contrast_name } $ctk_db->resultset('GeneSet')->search({
        contrast_name => { '!=' => undef },
    }, {
        columns => [qw( contrast_name )],
        distinct => 1,
    })->all();
    # have to make this array first because natsort acts weird
    my @distinct_names = distinct(@contrast_dataset_contrast_names, @gene_set_contrast_names);
    push @data, map { $as_tuples ? [ $_, $_, JSON::false ] : $_ } natsort @distinct_names;
}
elsif ($data_type eq 'gene_set_types') {
    # have to make this array first because natsort acts weird
    my @types = @CTK_DATA_CONTRAST_GENE_SET_TYPE_SUFFIXES;
    push @data, map { $as_tuples ? [ $_, $_, JSON::false ] : $_ } natsort @types;
}
# not used right now
elsif ($data_type eq 'annotation_values') {
    my @annotation_names = split /,/, shift @ARGV;
    my @cd_annotation_values = $ctk_db->resultset('ContrastDataSetAnnotation')->search({
        name => {
            -in => \@annotation_names,
        },
    },{
        columns => [qw( value )],
        order_by => 'value',
    })->all();
    my @gs_annotation_values = $ctk_db->resultset('GeneSetAnnotation')->search({
        name => {
            -in => \@annotation_names,
        },
    },{
        columns => [qw( value )],
        order_by => 'value',
    })->all();
    push @data, map { $as_tuples ? [ $_, $_, JSON::false ] : $_ } distinct(map { $_->value } (@cd_annotation_values, @gs_annotation_values));
}
else {
    pod2usage(
        "Argument must one of: array_types, id_types, contrast_dataset_ids, contrast_ids, contrast_names, contrast_gene_set_ids, gene_set_ids, annotations, organisms, gene_set_types"
    );
}
print $as_json
    ? encode_json(\@data)
    : join("\n", $as_tuples ? map { "$_->[0]\t$_->[1]\t$_->[2]" } @data : @data), "\n";    
exit;

__END__

=head1 NAME 

cfo_get_info.pl - Confero Platform Information

=head1 SYNOPSIS

 cfo_get_info.pl [options] [argument] [annotation names]
 
 Argument:
    array_types
    id_types
    contrast_dataset_ids
    contrast_ids
    contrast_names
    contrast_gene_set_ids
    gene_set_ids
    annotations
    organisms
    gene_set_types
 
 Options:
    --as-json                   Return JSON (default false)
    --as-tuples                 Return tuples (default false)
    --with-empty                Start with an empty tuple (default false)
    --help                      Display usage message and exit
    --version                   Display program version and exit

=cut
