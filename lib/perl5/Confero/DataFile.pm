package Confero::DataFile;

use strict;
use warnings;
use Carp qw(confess);
use Clone qw(clone);
use Confero::Config qw(:entrez :data :affy :agilent :geo :illumina);
use Confero::LocalConfig qw(:data);
use Confero::EntrezGene;
use File::Basename qw(fileparse);
use Module::Pluggable::Object require => 1;
use Sort::Key qw(nsort);
use Sort::Key::Natural qw(natsort);
use Storable qw(lock_retrieve);
use Data::Dumper;

$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Terse = 1;
$Data::Dumper::Deepcopy = 1;

our $VERSION = '0.1';

# do all this at class load to get plugins loaded into namespace; only need this instantiated once anyway
my $mp = Module::Pluggable::Object->new(
    require => 1,
    search_path => [ __PACKAGE__ ],
);
$mp->plugins();

sub new {
    my $invocant = shift;
    confess("Cannot instantiate abstract data file class directly, please use " . __PACKAGE__) if $invocant ne __PACKAGE__;
    # arguments
    my ($file_path, $data_type, $orig_file_name, $id_type, $collapsing_method, $check_metadata_is_complete, 
        $organism_name, $dataset_name, $dataset_desc, $src2gene_id_bestmap, $no_processing) = @_;
    confess('Input data file path a required parameter') unless defined $file_path;
    confess('Data file type a required parameter') unless defined $data_type;
    my $data_type_class = __PACKAGE__ . "::$data_type";
    my $self = {};
    for my $class ($mp->plugins) {
        if (lc($data_type_class) eq lc($class)) {
            bless $self, $class;
            last;
        }
    }
    if (lc(ref($self)) ne lc($data_type_class)) {
        confess("Unsupported data file type '$data_type', available data file types are: ", join(', ', map { m/::(\w+)$/ } $mp->plugins));
    }
    # initialization
    $self->{source_data} = [];
    $self->{_mapped_data} = [];
    $self->{processed_data} = [];
    $self->{data_errors} = [];
    $self->{_valid_ids} = {};
    $self->{_invalid_ids} = {};
    $self->{_raw_metadata} = [];
    $self->{metadata} = {};
    $self->{comments} = [];
    $self->{file_path} = $file_path;
    $self->{orig_file_name} = defined $orig_file_name ? $orig_file_name : fileparse($file_path);
    $self->{id_type} = $id_type if defined $id_type;
    $self->{organism_name}  = $organism_name if defined $organism_name;
    $self->{dataset_name} = $dataset_name if defined $dataset_name;
    $self->{dataset_desc} = $dataset_desc if defined $dataset_desc;
    $self->{collapsing_method} = $collapsing_method || $CTK_DATA_DEFAULT_COLLAPSING_METHOD;
    $self->{_src2gene_id_bestmap} = $src2gene_id_bestmap if defined $src2gene_id_bestmap;
    $self->{check_metadata_is_complete}++ if $check_metadata_is_complete;
    #$self->{_source_ids_with_better_id} = [];
    ($self->{data_type}) = ref($self) =~ /::(\w+)$/;
    $self->_load_data_from_file();
    if (!@{$self->data_errors}) {
        # set organism tax ID for non-Gene ID-based source data
        if (!defined $self->organism_tax_id) {
            # cannot use this one-liner because first valid ID might not have a mapping gene ID
            #my $valid_gene_id = $self->_valid_ids->{(keys %{$self->_valid_ids})[0]}->{gene_id};
            my $valid_gene_id;
            for my $source_id_hashref (values %{$self->_valid_ids}) {
                if (defined $source_id_hashref->{gene_id}) {
                    $valid_gene_id = $source_id_hashref->{gene_id};
                    last;
                }
            }
            confess('Could not obtain a valid gene ID from source IDs (this should not happen)') unless defined $valid_gene_id;
            my $gene_info_hashref = Confero::EntrezGene->instance()->gene_info;
            my $gene_history_hashref = Confero::EntrezGene->instance()->gene_history;
            $self->{organism_tax_id} = exists $gene_info_hashref->{$valid_gene_id} ? $gene_info_hashref->{$valid_gene_id}->{organism_tax_id}
                                     : exists $gene_history_hashref->{$valid_gene_id} ? $gene_history_hashref->{$valid_gene_id}->{organism_tax_id}
                                     : confess("Gene ID $valid_gene_id used for organism tax ID extraction does not exist in Entrez Gene (this should not happen)");
        }
        # set organism name if not set yet
        if (!defined $self->organism_name) {
            for my $organism_name (keys %CTK_ENTREZ_GENE_ORGANISM_DATA) {
                if ($CTK_ENTREZ_GENE_ORGANISM_DATA{$organism_name}{tax_id} eq $self->organism_tax_id) {
                    $self->{organism_name} = $organism_name;
                    last;
                }
            }
        }
        $self->_process_data() unless $no_processing;
    }
    return $self;
}

sub file_path {
    return shift->{file_path};
}

sub orig_file_name {
    return shift->{orig_file_name};
}

sub data_type {
    return shift->{data_type};
}

sub id_type {
    return shift->{id_type};
}

sub dataset_name {
    return shift->{dataset_name};
}

sub dataset_desc {
    return shift->{dataset_desc};
}

sub check_metadata_is_complete {
    return shift->{check_metadata_is_complete};
}

sub organism_name {
    return shift->{organism_name};
}

sub organism_tax_id {
    return shift->{organism_tax_id};
}

sub data_errors {
    return shift->{data_errors};
}

sub source_data {
    return shift->{source_data};
}

sub _mapped_data {
    return shift->{_mapped_data};
}

sub processed_data {
    return shift->{processed_data};
}

sub _valid_ids {
    return shift->{_valid_ids};
}

sub _invalid_ids {
    return shift->{_invalid_ids};
}

sub num_data_cols {
    return shift->{num_data_cols};
}

sub num_data_groups {
    return shift->{num_data_groups};
}

sub _raw_metadata {
    return shift->{_raw_metadata};
}

sub metadata {
    return shift->{metadata};
}

sub comments {
    return shift->{comments};
}

sub report {
    return shift->{report};
}

sub _src2gene_id_bestmap {
    return shift->{_src2gene_id_bestmap};
}

sub has_gene_ids {
    my $self = shift;
    if (!defined $self->{has_gene_ids}) {
        $self->{has_gene_ids} = defined $self->{id_type}
                              ? $self->{id_type} =~ /entrezgene/i
                                  ? 1 
                                  : 0
                              : undef;
    }
    return $self->{has_gene_ids};
}

sub has_gene_symbols {
    my $self = shift;
    if (!defined $self->{has_gene_symbols}) {
        $self->{has_gene_symbols} = defined $self->{id_type} 
                                  ? $self->{id_type} =~ /genesymbol/i
                                      ? 1 
                                      : 0
                                  : undef;
    }
    return $self->{has_gene_symbols};
}

sub _load_valid_ids {
    my $self = shift;
    if (defined $self->id_type) {
        # extend if statement for new ID types as required
        if (exists $CTK_AFFY_ARRAY_DATA{$self->id_type} or 
            exists $CTK_AGILENT_ARRAY_DATA{$self->id_type} or 
            exists $CTK_GEO_ARRAY_DATA{$self->id_type} or 
            exists $CTK_ILLUMINA_ARRAY_DATA{$self->id_type} or 
            $self->has_gene_ids or 
            $self->has_gene_symbols) {
            # source IDs
            if (!$self->has_gene_ids) {
                my $map_file_basename;
                if (!$self->has_gene_symbols) {
                    ($map_file_basename = $self->id_type) =~ s/\s/_/g;
                }
                # gene symbols
                elsif (defined $self->organism_name) {
                    (my $organism_file_basename = $self->organism_name) =~ s/\s+/_/g;
                    $map_file_basename = "${organism_file_basename}${CTK_DATA_ID_MAPPING_GENE_SYMBOL_SUFFIX}";
                }
                else {
                    push @{$self->data_errors}, "id_type '" . $self->id_type . "' requires missing #\%organism metadata";
                }
                if (defined $map_file_basename) {
                    if (!defined $self->_src2gene_id_bestmap) {
                        $self->{_src2gene_id_bestmap} = lock_retrieve("$CTK_DATA_ID_MAPPING_FILE_DIR/${map_file_basename}.bestmap.pls")
                            or confess("Could not retrieve and unserialize $CTK_DATA_ID_MAPPING_FILE_DIR/${map_file_basename}.bestmap.pls: $!");
                    }
                    # all valid IDs for source data can be found in _src2gene_id_bestmap keys
                    $self->{_valid_ids} = $self->_src2gene_id_bestmap;
                }
            }
            # entrez gene IDs
            else {
                my $gene_info_hashref = Confero::EntrezGene->instance()->gene_info;
                my $gene_history_hashref = Confero::EntrezGene->instance()->gene_history;
                my %valid_ids = (%{$gene_info_hashref}, %{$gene_history_hashref});
                $self->{_valid_ids} = \%valid_ids;
            }
        }
        else {
            push @{$self->data_errors}, "id_type '" . $self->id_type . "' is either not valid or supported";
        }
    }
    else {
        push @{$self->data_errors}, 'No id_type metadata header defined in file or selected, id_type is required';
    }
}

sub write_debug_file {
    my ($self, $debug_file_path) = @_;
    my @data_file_obj_attrs_to_remove = qw(
        _valid_ids
        _src2gene_id_bestmap
    );
    my $copy = clone($self);
    delete @{$copy}{@data_file_obj_attrs_to_remove};
    open(my $output_fh, '>', $debug_file_path) or confess("Could not open output debug file $debug_file_path: $!");
    print $output_fh Dumper($copy);
    close($output_fh);
}

1;
