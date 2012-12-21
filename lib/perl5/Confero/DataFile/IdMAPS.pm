package Confero::DataFile::IdMAPS;

use strict;
use warnings;
use base 'Confero::DataFile';
use Carp qw(confess);
use Confero::Config qw(:data);
use Confero::EntrezGene;
use Confero::LocalConfig qw(:data $CTK_DISPLAY_ID_PREFIX $CTK_DISPLAY_ID_SPACER);
use Const::Fast;
use File::Basename qw(fileparse);
use List::Util qw(sum);
use Sort::Key qw(nsort nkeysort);
use Sort::Key::Natural qw(natsort);
use Utils qw(is_integer is_numeric);
use Data::Dumper;

$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Terse = 1;
$Data::Dumper::Deepcopy = 1;

our $VERSION = '0.0.1';

const my $FLOAT_REGEXP => qr/[+-]?\ *(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/o;
const my @DATA_COL_HEADERS => qw(M A P S F Df);

sub data_type_common_name {
    return 'Contrast Dataset';
}

sub column_headers {
    return shift->{column_headers};
}

sub num_data_cols_per_group {
    return shift->{num_data_cols_per_group};
}

sub collapsing_method {
    return shift->{collapsing_method};
}

sub M_idx {
    return shift->{M_idx};
}

sub A_idx {
    return shift->{A_idx};
}

sub P_idx {
    return shift->{P_idx};
}

sub S_idx {
    return shift->{S_idx};
}

sub F_idx {
    return shift->{F_idx};
}

sub Df_idx {
    return shift->{Df_idx};
}

sub id_column_header {
    return shift->{id_column_header};
}

sub _load_data_from_file {
    my $self = shift;
    my (%file_ids, $read_first_non_header_line);
    # 3-arg form of open because file_path could be a scalar reference in-memory file
    open(my $idmaps_fh, '<', $self->file_path) or confess('Could not open data file ' . $self->file_path . ": $!");
    while (<$idmaps_fh>) {
        s/^\s+//;
        s/\s+$//;
        # header metadata line
        if (m/^#%/) {
            # at this point we can only check the metadata field names for validity
            # then just store the metadata line
            my ($field_name) = m/^#%\s*(\w+)(?:=.+)*$/;
            $field_name = lc($field_name);
            # fix field_name alternative spellings
            $field_name = $field_name eq 'data_set_name' ? 'dataset_name'   :
                          $field_name eq 'data_set_desc' ? 'dataset_desc'   : 
                          $field_name eq 'contrast_name' ? 'contrast_names' : $field_name;
            if (exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}) {
                push @{$self->_raw_metadata}, $_;
            }
            else {
                push @{$self->data_errors}, "Invalid metadata field name: $field_name";
            }
            next;
        }
        # comment line
        elsif (m/^#+/) {
            s/^#+\s*/## /;
            push @{$self->comments}, $_;
            next;
        }
        # blank line
        elsif (m/^\s*$/) {
            next;
        }
        # at the first non-header line do header processing
        if (!$read_first_non_header_line) {
            $read_first_non_header_line++;
            my @column_header_fields = split /\t/;
            $self->{num_data_cols} = scalar(@column_header_fields) - 1;
            $self->{id_column_header} = $column_header_fields[0];
            my @captured_column_header_parts = m/
                ^[^\t]*(
                \t(M|A|P|S|F|Df)
                (?:\t(?!\2)(M|A|P|S|F|Df))?
                (?:\t(?!\2|\3)(M|A|P|S|F|Df))?
                (?:\t(?!\2|\3|\4)(M|A|P|S|F|Df))?
                (?:\t(?!\2|\3|\4|\5)(M|A|P|S|F|Df))?
                (?:\t(?!\2|\3|\4|\5|\6)(M|A|P|S|F|Df))?
                (?:\t(?!(?:M|A|P|S|F|Df|\t)).+?)*
                ){1,}$
            /ix;
            # invalid column header, abort parsing
            if (!@captured_column_header_parts) {
                push @{$self->data_errors}, "Invalid data file column header:\n$_";
                return;
            }
            my $column_header_group_str = shift @captured_column_header_parts;
            $self->{num_data_groups} = () = m/$column_header_group_str/gi;
            $self->{num_data_cols_per_group} = int($self->num_data_cols/$self->num_data_groups);
            # second required column header check that header is valid and header groups are in same order
            if (!m/^[^\t]*(?:$column_header_group_str){$self->{num_data_groups}}$/i) {
                push @{$self->data_errors}, "Invalid data file column header or header groups not in same order:\n$_";
                return;
            }
            # remove leading/trailing whitespace from column header group str
            $column_header_group_str =~ s/^\s+//;
            $column_header_group_str =~ s/\s+$//;
            for my $column_header (split /\t/, $column_header_group_str) {
                $column_header = uc($column_header) if $column_header =~ /^(M|A|P|S|F|Df)$/i;
                $column_header =~ s/^DF$/Df/;
                push @{$self->{column_headers}}, $column_header;
            }
            # filter out undef entries in captured column header parts (if certain M-A-P-S-Df columns aren't there will have undef array entries)
            @captured_column_header_parts = grep defined, @captured_column_header_parts;
            # set M-A-P-S-F-Df column header indexes
            for my $i (0 .. $#captured_column_header_parts) {
                $self->{"\u$captured_column_header_parts[$i]_idx"} = $i + 1;
            }
            # finish checking header metadata lines and process metadata
            my %metadata_field_names;
            for my $metadata_line (@{$self->_raw_metadata}) {
                my ($field_name, $field_data_str) = $metadata_line =~ /^#%\s*(\w+)(?:=(.+))*$/;
                $field_name = lc($field_name);
                # fix field_name alternative spellings
                $field_name = $field_name eq 'data_set_name' ? 'dataset_name'   :
                              $field_name eq 'data_set_desc' ? 'dataset_desc'   : 
                              $field_name eq 'contrast_name' ? 'contrast_names' : $field_name;
                my $metadata_split_regexp = (
                    (exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_int}) or 
                    (exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_num}) or
                    (exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_uint}) or
                    (exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_unum})
                ) ? qr/,/ 
                  : qr/(?:"|'),(?:"|')/;
                # make boolean field values
                $field_data_str++ unless defined $field_data_str;
                # strip off first and last quotes if exists
                $field_data_str =~ s/^("|')|("|')$//g;
                my @field_data = split $metadata_split_regexp, $field_data_str, -1;
                # check that metadata doesn't appear twice
                if (defined $metadata_field_names{$field_name}) {
                    push @{$self->data_errors}, "Metadata line $field_name appears twice";
                }
                else {
                    $metadata_field_names{$field_name}++;
                }
                # check that multi metadata line has same number of fields as file data parts
                if (exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and 
                    exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_multi} and 
                    scalar(@field_data) != $self->num_data_groups) {
                    push @{$self->data_errors}, "Metadata line doesn't have enough fields (has " . 
                        scalar(@field_data) . " should have " . $self->num_data_groups . "):\n$field_data_str";
                }
                # check numeric metadata
                for (@field_data) {
                    if (exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and 
                        exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_int}) {
                        push @{$self->data_errors}, "Metadata value '$_' for metadata field " . 
                        $field_name . " isn't a positive integer" if $_ and !is_integer($_);
                    }
                    elsif (exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and 
                           exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_num}) {
                        push @{$self->data_errors}, "Metadata value '$_' for metadata field " . 
                        $field_name . " isn't a float" if $_ and !is_numeric($_);
                    }
                    elsif (exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and 
                           exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_uint}) {
                        push @{$self->data_errors}, "Metadata value '$_' for metadata field " . 
                        $field_name . " isn't a positive integer" if $_ and (!is_integer($_) or $_ < 0);
                    }
                    elsif (exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and 
                           exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_unum}) {
                        push @{$self->data_errors}, "Metadata value '$_' for metadata field " . 
                        $field_name . " isn't a positive float" if $_ and (!is_numeric($_) or $_ < 0);
                    }
                }
                # store metadata
                $self->metadata->{$field_name} = (
                    exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and 
                    exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_multi}
                ) ? \@field_data : $field_data[0];
            }
            # extract important metadata
            # if id_type is in header metadata this overrides any id_type passed to object constructor
            $self->{id_type} = $self->metadata->{id_type} if defined $self->metadata->{id_type};
            # if certain metadata passed to object constructor this overrides values set in file header metadata
            $self->{organism_name} = $self->metadata->{organism} if !defined $self->organism_name and 
                                                                     defined $self->metadata->{organism};
            $self->{dataset_name} = $self->metadata->{dataset_name} if !defined $self->dataset_name and 
                                                                        defined $self->metadata->{dataset_name};
            $self->{dataset_desc} = $self->metadata->{dataset_desc} if !defined $self->dataset_desc and 
                                                                        defined $self->metadata->{dataset_desc};
            $self->{collapsing_method} = $self->metadata->{collapsing_method} if !defined $self->collapsing_method and 
                                                                                  defined $self->metadata->{collapsing_method};
            my $orig_file_basename = fileparse($self->orig_file_name, qr/\.[^.]*/);
            # if dataset_name still not defined then use modified original file basename
            $self->{dataset_name} = $orig_file_basename if !defined $self->dataset_name;
            # for single-contrast datasets if contrast_names metadata header not defined then use original file basename
            if (!$self->num_data_groups > 1 and !defined $self->metadata->{contrast_names}) {
                push @{$self->metadata->{contrast_names}}, $orig_file_basename;
            }
            # if dataset_name starts with $CTK_DISPLAY_ID_PREFIX remove it and convert any 
            # $CTK_DISPLAY_ID_SPACER characters in dataset_name or contrast name into a space
            if (defined $self->dataset_name) {
                $self->{dataset_name} =~ s/^${CTK_DISPLAY_ID_PREFIX}${CTK_DISPLAY_ID_SPACER}//go;
                $self->{dataset_name} =~ s/$CTK_DISPLAY_ID_SPACER/ /go;
            }
            if (defined $self->metadata->{dataset_name}) {
                $self->metadata->{dataset_name} =~ s/^${CTK_DISPLAY_ID_PREFIX}${CTK_DISPLAY_ID_SPACER}//go;
                $self->metadata->{dataset_name} =~ s/$CTK_DISPLAY_ID_SPACER/ /go;
            }
            if (defined $self->metadata->{contrast_names}) {
                for (@{$self->metadata->{contrast_names}}) {
                    s/$CTK_DISPLAY_ID_SPACER/ /go;
                }
            }
            if (defined $self->organism_name) {
                $self->{organism_name} =~ s/_+/ /g;
                my @organism_words = split /\W+/, $self->{organism_name};
                if ($self->{organism_name} !~ /\w+\s+\w+/ or scalar(@organism_words) != 2) {
                    push @{$self->data_errors}, "Organism name '$self->{organism_name}' is invalid";
                }
                $organism_words[0] = ucfirst(lc($organism_words[0]));
                $organism_words[1] = lc($organism_words[1]);
                $self->{organism_name} = "$organism_words[0] $organism_words[1]";
            }
            #if ($self->check_metadata_is_complete) {
            #    
            #}
            # at this point, before checking any data lines, we need to load valid IDs into the _valid_ids hashref
            $self->_load_valid_ids();
            # skip data checking below since at column header line
            next;
        }
        # check data line
        my @data_fields = split /\t/;
        # remove ID
        shift @data_fields;
        while (@data_fields) {
            my @data_fields_group = (undef, splice(@data_fields, 0, $self->num_data_cols_per_group));
            for my $col (@DATA_COL_HEADERS) {
                my $col_idx_attr = "\u${col}_idx";
                push @{$self->data_errors}, "Data not valid at line $., $col value " . $data_fields_group[$self->$col_idx_attr] . " not a float:\n$_"
                    if defined $self->$col_idx_attr and $data_fields_group[$self->$col_idx_attr] !~ /$FLOAT_REGEXP/o;
            }
            #push @{$self->data_errors}, "Data not valid at line $., Df value " . $data_fields_group[$self->Df_idx] . " not an positive integer:\n$_"
            #    if defined $self->Df_idx and (!is_integer($data_fields_group[$self->Df_idx]) or $data_fields_group[$self->Df_idx] < 0);
            #push @{$self->data_errors}, "Data not valid at line $., S value " . $data_fields_group[$self->S_idx] . " not between -100 and 100:\n$_"
            #    if defined $self->S_idx and ($data_fields_group[$self->S_idx] < -100 or $data_fields_group[$self->S_idx] > 100);
            #push @{$self->data_errors}, "Data not valid at line $., A value " . $data_fields_group[$self->A_idx] . " less than 0:\n$_"
            #    if defined $self->A_idx and $data_fields_group[$self->A_idx] < 0;
            push @{$self->data_errors}, "Data not valid at line $., P value " . $data_fields_group[$self->P_idx] . " not between 0 and 1:\n$_"
                if defined $self->P_idx and ($data_fields_group[$self->P_idx] < 0 or $data_fields_group[$self->P_idx] > 1);
            push @{$self->data_errors}, "Data not valid at line $., F value " . $data_fields_group[$self->F_idx] . " not 0 or 1:\n$_"
                if defined $self->F_idx and ($data_fields_group[$self->F_idx] != 0 or $data_fields_group[$self->F_idx] != 1);
        }
        # split line into two parts: ID and data string
        my ($id, $data_str) = split /\t/, $_, 2;
        # check ID is valid
        if (%{$self->_valid_ids}) {
            # many valid source IDs have no map to a Gene ID yet they are still valid
            # so that is why I use exists here since there might not be a hash value
            if (exists $self->_valid_ids->{$id}) {
                # check that all IDs are from the same organism (for Gene ID source data, not necessary for other source data)
                if (defined $self->_valid_ids->{$id} and exists $self->_valid_ids->{$id}->{organism_tax_id}) {
                    if (defined $self->organism_tax_id) {
                        # turned off because files can have IDs from different organisms
                        #if ($self->organism_tax_id ne $self->_valid_ids->{$id}->{organism_tax_id}) {
                        #    push @{$self->data_errors}, "ID '$id' belongs to different organism at line $.:\n$_";
                        #}
                    }
                    else {
                        $self->{organism_tax_id} = $self->_valid_ids->{$id}->{organism_tax_id};
                    }
                }
            }
            # invalid ID
            else {
                $self->_invalid_ids->{$id}->{line_num} = $.;
                # not used anymore, replaced by logic below to allow for some invalid IDs (configurable)
                #push @{$self->data_errors}, "ID '$id' not valid at line $.:\n$_";
            }
        }
        elsif (!@{$self->data_errors}) {
            confess('_valid_ids property and data structure not initialized');
        }
        # check file for ID uniqueness
        if (defined $file_ids{$id}) {
            push @{$self->data_errors}, "ID '$id' exists more than once in data file";
        }
        else {
            $file_ids{$id}++;
        }
        # check for number of data errors and if too many abort parsing
        if (scalar(@{$self->data_errors}) > $CTK_DATA_FILE_MAX_ERRORS_TO_LOG) {
            push @{$self->data_errors}, 'Possibly more data errors but stopped parsing (maybe you picked the ' .
                                        'wrong ID mapping from drop-down menu selection? Please check your file)';
            return;
        }
        # dataset line is OK (since we got here) so add to source_data structure
        push @{$self->source_data}, {
            (!$self->has_gene_ids ? 'source_id' : 'gene_id') => $id,
            data_str => $data_str,
        };
    }
    close($idmaps_fh);
    # check multi-contrast dataset file metadata requirements
    if ($self->num_data_groups > 1) {
        # check that contrast_names metadata line is defined for batch files
        if (!defined $self->metadata->{contrast_names}) {
            push @{$self->data_errors}, 'contrast_names metadata header is required for batch files';
        }
        # will use config default gene set size for all if no metadata
        ## check that gs_up_sizes metadata line is defined for multi-contrast files
        #if (!defined $self->metadata->{gs_up_sizes}) {
        #    push @{$self->data_errors}, 'gs_up_sizes metadata header is required for batch files';
        #}
        # check that gs_dn_sizes metadata line is defined for multi-contrast files
        #if (!defined $self->metadata->{gs_dn_sizes}) {
        #    push @{$self->data_errors}, 'gs_dn_sizes metadata header is required for batch files';
        #}
    }
    # check that contrast file has minimum number of entries
    if (scalar(@{$self->source_data}) < $CTK_DATA_FILE_MIN_NUM_ENTRIES) {
        push @{$self->data_errors}, "Data file doesn't have enough data rows, has " .
            scalar(@{$self->source_data}) . " and should have at least $CTK_DATA_FILE_MIN_NUM_ENTRIES";
    }
    # check for number of invalid IDs
    if (scalar(keys %{$self->_invalid_ids}) > $CTK_DATA_FILE_MAX_INVALID_IDS) {
        push @{$self->data_errors}, "Data file has " . scalar(keys %{$self->_invalid_ids}) . 
            " invalid IDs which exceeds the maximum ($CTK_DATA_FILE_MAX_INVALID_IDS)";
        for my $id (nkeysort { $self->_invalid_ids->{$_}->{line_num} } keys %{$self->_invalid_ids}) {
            push @{$self->data_errors}, "ID '$id' not valid at line " . $self->_invalid_ids->{$id}->{line_num};
            last if scalar(@{$self->data_errors}) > $CTK_DATA_FILE_MAX_ERRORS_TO_LOG;
        }
    }
    # check that source contrast file has all the source IDs (if required by configuration)
    if ($CTK_DATA_FILE_MUST_HAVE_ALL_IDS and defined $self->id_type and !$self->has_gene_ids) {
        my $num_source_ids_required = scalar(keys %{$self->_src2gene_id_bestmap});
        if (scalar(@{$self->source_data}) != $num_source_ids_required) {
            push @{$self->data_errors}, "Data file does not have enough data rows, should have " .
                                        "$num_source_ids_required for " . $self->id_type;
        }
    }
    # make sure P value specific metadata not defined if no P value data exists
    if (!defined $self->P_idx and defined $self->metadata->{gs_p_val_thres}) {
        push @{$self->data_errors}, 'gs_p_val_thres cannot be defined if there is no P value data';
    }
    # make sure A value specific metadata not defined if no A value data exists
    if (!defined $self->A_idx and defined $self->metadata->{gs_a_val_thres}) {
        push @{$self->data_errors}, 'gs_a_val_thres cannot be defined if there is no A value data';
    }
    # make sure M value specific metadata not defined if no M value data exists
    if (!defined $self->M_idx and defined $self->metadata->{gs_m_val_thres}) {
        push @{$self->data_errors}, 'gs_m_val_thres cannot be defined if there is no M value data';
    }
}

sub _process_data {
    my $self = shift;
    # process source data
    if (!$self->has_gene_ids) {
        my (@source_ids_with_no_map, @source_ids_with_no_map_diff_expressed, @source_ids_with_ambig_map);
        # first process source_data dataset rows to do ID checking and mapping
        for my $dataset_row (@{$self->source_data}) {
            # check if source ID is valid (again since we do allow for some invalid IDs during parsing)
            if (exists $self->_valid_ids->{$dataset_row->{source_id}}) {
                my @dataset_row_data = split /\t/, $dataset_row->{data_str};
                # check if source ID has a Gene ID map
                if (defined $self->_src2gene_id_bestmap->{$dataset_row->{source_id}}->{gene_id}) {
                    # unambiguous map to single or best Gene ID
                    $dataset_row->{gene_id} = $self->_src2gene_id_bestmap->{$dataset_row->{source_id}}->{gene_id};
                    if ($self->collapsing_method eq 'contrast_data') {
                        # add data to per contrast structured _mapped_data
                        my $contrast_idx = 0;
                        while (@dataset_row_data) {
                            push @{$self->_mapped_data->[$contrast_idx]}, {
                                data => [
                                    $dataset_row->{gene_id},
                                    splice(@dataset_row_data, 0, $self->num_data_cols_per_group),
                                ],
                            };
                            $contrast_idx++;
                        }
                    }
                    elsif ($self->collapsing_method eq 'dataset_data') {
                        # add data to dataset structured _mapped_data
                        push @{$self->_mapped_data}, {
                            data => [
                                $dataset_row->{gene_id}, 
                                @dataset_row_data,
                            ],
                        };
                    }
                    else {
                        confess("'", $self->collapsing_method , "' not a valid collapsing method");
                    }
                }
                # none or ambiguous Gene ID map
                else {
                    $dataset_row->{skip}++;
                    if (exists $self->_src2gene_id_bestmap->{$dataset_row->{source_id}}->{no_gene_map}) {
                        $dataset_row->{no_gene_map}++;
                        push @source_ids_with_no_map, $dataset_row->{source_id};
                    }
                    elsif (exists $self->_src2gene_id_bestmap->{$dataset_row->{source_id}}->{ambig_gene_map}) {
                        $dataset_row->{ambig_gene_map}++;
                        push @source_ids_with_ambig_map, $dataset_row->{source_id};
                    }
                    # check if unmapped dataset row is differentially expressed
                    if (defined $self->P_idx) {
                        if ($self->_compute_dataset_row_mean_for_col($self->P_idx, \@dataset_row_data) <= $CTK_DATA_DEFAULT_DIFF_EXPRESS_P_VAL) {
                            $dataset_row->{diff_expressed}++;
                            push @source_ids_with_no_map_diff_expressed, $dataset_row->{source_id};
                        }
                    }
                    elsif (defined $self->M_idx) {
                        if ($self->_compute_dataset_row_mean_for_col($self->M_idx, \@dataset_row_data) >= $CTK_DATA_DEFAULT_DIFF_EXPRESS_M_VAL) {
                            $dataset_row->{diff_expressed}++;
                            push @source_ids_with_no_map_diff_expressed, $dataset_row->{source_id};
                        }
                    }
                }
            }
            # invalid source ID
            else {
                $dataset_row->{skip}++;
                $dataset_row->{has_invalid_id}++;
            }
        }
        # collapsed _mapped_data and prepare processed_data data structure
        $self->_process_and_collapse_mapped_data();
        # set report summary values that aren't already set
        my $num_source_rows = scalar(@{$self->source_data});
        my $num_invalid_ids = scalar(keys %{$self->_invalid_ids});
        my $num_no_gene_map = @source_ids_with_no_map ? scalar(@source_ids_with_no_map) : 0;
        my $num_no_gene_map_diff_expressed = @source_ids_with_no_map_diff_expressed ? scalar(@source_ids_with_no_map_diff_expressed) : 0;
        my $num_ambig_map = @source_ids_with_ambig_map ? scalar(@source_ids_with_ambig_map) : 0;
        my $num_gene_rows = scalar(@{$self->processed_data->[0]});
        my $num_excluded = $self->collapsing_method eq 'contrast_data' ? scalar(@{$self->_mapped_data->[0]}) - $num_gene_rows
                         : $self->collapsing_method eq 'dataset_data' ? scalar(@{$self->_mapped_data}) - $num_gene_rows
                         : 'ERROR';
        # generate summary report
        my $format = "format SRCREPORT =\n" .
            "Source contrast file: @*\n\"" . $self->orig_file_name . "\"\n" .
            "  @##########  source IDs/data rows\n$num_source_rows\n" .
            "- @##########  source IDs that are invalid\n$num_invalid_ids\n" .
            "- @##########  source IDs with no Entrez Gene ID mapping\n$num_no_gene_map\n" .
            "- @##########  source IDs excluded due to ambiguous mapping to Entrez Gene IDs\n$num_ambig_map\n" .
            #"- @##########  source IDs excluded due to existence of better representative source ID\n$num_better_id\n" .
            "- @##########  mapped Entrez Gene IDs excluded due to another identical Entrez Gene ID with a " . $self->_report_excluded_text . " value\n$num_excluded\n" .
            "-------------\n" .
            "  @##########  mapped Entrez Gene IDs/data rows\n$num_gene_rows\n.\n";
        {
          #no warnings 'redefine';
          no warnings;
          eval $format;
        }
        open(SRCREPORT, '>', \$self->{report}) or confess("Could not create summary report: $!");
        write SRCREPORT;
        close(SRCREPORT);
        # report which source IDs are invalid, no map, ambiguous
        if ($num_invalid_ids) {
            $self->{report} .= "\nSource IDs which are invalid:\n" . join("\n", keys %{$self->_invalid_ids}) . "\n";
        }
        #if (@source_ids_with_no_map) {
        #    $self->{report} .= "\nSource IDs with no Entrez Gene map:\n" . join("\n", @source_ids_with_no_map) . "\n";
        #}
        if ($num_no_gene_map_diff_expressed) {
            $self->{report} .= "\n$num_no_gene_map_diff_expressed differentially expressed source IDs with no Entrez Gene map:\n" . join("\n", @source_ids_with_no_map_diff_expressed) . "\n";
        }
        #if (@source_ids_with_ambig_map) {
        #    $self->{report} .= "\nSource IDs with ambiguous Entrez Gene map:\n" . join("\n", @source_ids_with_ambig_map) . "\n";
        #}
    }
    # process already Gene ID-based data
    else {
        my $gene_history_hashref = Confero::EntrezGene->instance()->gene_history;
        # map Gene IDs
        my @gene_data_rows_discontinued;
        my $num_gene_ids_updated = 0;
        for my $dataset_row (@{$self->source_data}) {
            # check if Gene ID is valid (again since we do allow for some invalid IDs during parsing)
            if (exists $self->_valid_ids->{$dataset_row->{gene_id}}) {
                # check if Gene ID is historical and update it with current replacement if exists
                if (exists $gene_history_hashref->{$dataset_row->{gene_id}}) {
                    if (exists $gene_history_hashref->{$dataset_row->{gene_id}}->{current_gene_id}) {
                        # update historical Gene ID with current one
                        $dataset_row->{gene_id} = $gene_history_hashref->{$dataset_row->{gene_id}}->{current_gene_id};
                        $dataset_row->{updated_gene_id}++;
                        $num_gene_ids_updated++;
                    }
                    # discontinued Gene ID with no current replacement
                    else {
                        $dataset_row->{skip}++;
                        $dataset_row->{discontinued_gene_id}++;
                        push @gene_data_rows_discontinued, $dataset_row->{gene_id};
                        next;
                    }
                }
                my @dataset_row_data = split /\t/, $dataset_row->{data_str};
                if ($self->collapsing_method eq 'contrast_data') {
                    # add data to per contrast _mapped_data structure
                    my $contrast_idx = 0;
                    while (@dataset_row_data) {
                        push @{$self->_mapped_data->[$contrast_idx]}, {
                            data => [
                                $dataset_row->{gene_id},
                                splice(@dataset_row_data, 0, $self->num_data_cols_per_group),
                            ],
                        };
                        $contrast_idx++;
                    }
                }
                elsif ($self->collapsing_method eq 'dataset_data') {
                    # add data to dataset structured _mapped_data
                    push @{$self->_mapped_data}, {
                        data => [
                            $dataset_row->{gene_id}, 
                            @dataset_row_data,
                        ],
                    };
                }
                else {
                    confess("'", $self->collapsing_method , "' not a valid collapsing method");
                }
            }
            # invalid Gene ID
            else {
                $dataset_row->{skip}++;
                $dataset_row->{has_invalid_id}++;
            }
        }
        # collapsed _mapped_data and prepare processed_data data structure
        $self->_process_and_collapse_mapped_data();
        # set summary report values that aren't already set
        my $num_input_gene_data_rows = scalar(@{$self->source_data});
        my $num_invalid_ids = scalar(keys %{$self->_invalid_ids});
        my $num_discontinued = @gene_data_rows_discontinued ? scalar(@gene_data_rows_discontinued) : 0;
        my $num_output_gene_data_rows = scalar(@{$self->processed_data->[0]});
        my $num_excluded = $self->collapsing_method eq 'contrast_data' ? scalar(@{$self->_mapped_data->[0]}) - $num_output_gene_data_rows
                         : $self->collapsing_method eq 'dataset_data' ? scalar(@{$self->_mapped_data}) - $num_output_gene_data_rows
                         : 'ERROR';
        # generate summary report
        my $format = "format GENEREPORT = \n" .
            "Gene contrast file: @*\n\"" . $self->orig_file_name . "\"\n" .
            "  @##########  input Entrez Gene IDs/data rows\n$num_input_gene_data_rows\n" .
            "- @##########  input Entrez Gene IDs that are invalid\n$num_invalid_ids\n" .
            "- @##########  input Entrez Gene IDs/data rows excluded because they are discontinued with no replacement\n$num_discontinued\n" .
            "- @##########  input Entrez Gene IDs excluded due to another identical Entrez Gene ID with a " . $self->_report_excluded_text . " value\n$num_excluded\n" .
            "-------------\n" .
            "  @##########  output Entrez Gene IDs/data rows (of which @* were discontinued and updated)\n$num_output_gene_data_rows,$num_gene_ids_updated\n.\n";
        {
          #no warnings 'redefine';
          no warnings;
          eval $format;
        }
        open(GENEREPORT, '>', \$self->{report}) or confess("Could not create summary report: $!");
        write GENEREPORT;
        close(GENEREPORT);
    }
    # check again that contrast data has minimum number of entries
    #if ($num_out_gene_data_rows < $CTK_DATA_FILE_MIN_NUM_ENTRIES) {
    #    push @{$self->data_errors}, "Processed data file doesn't have enough data rows, has $num_out_gene_data_rows"
    #        . " and should have at least $CTK_DATA_FILE_MIN_NUM_ENTRIES";
    #}
}

sub _process_and_collapse_mapped_data {
    my $self = shift;
    # process _mapped data to do collapsing
    if ($self->collapsing_method eq 'contrast_data') {
        # collapse contrast data with same Gene ID by doing contrast data comparison and flag which contrast data rows to skip
        for my $contrast_idx (0 .. $#{$self->_mapped_data}) {
            my %mapped_gene_row_idx_to_keep;
            for my $row_idx (0 .. $#{$self->_mapped_data->[$contrast_idx]}) {
                # evaluate contrast data row to current best contrast data row with same Gene ID
                $self->_process_contrast_data_row_cmp($contrast_idx, $row_idx, \%mapped_gene_row_idx_to_keep);
            }
        }
        # to maintain pretty much the same data order in processed file as in source file need to get row idxs for gene IDs
        my $processed_row_idx = 0;
        my %processed_row_idx_for_gene_id;
        for my $data_row (@{$self->_mapped_data->[0]}) {
            my $gene_id = $data_row->{data}->[0];
            if (!exists $processed_row_idx_for_gene_id{$gene_id}) {
                $processed_row_idx_for_gene_id{$gene_id} = $processed_row_idx++;
            }
        }
        # process _mapped_data skip flags to produce final processed_data structure
        for my $contrast_idx (0 .. $#{$self->_mapped_data}) {
            my %contrast_gene_ids;
            for my $data_row (@{$self->_mapped_data->[$contrast_idx]}) {
                if (!exists $data_row->{skip}) {
                    my $gene_id = $data_row->{data}->[0];
                    if (!exists $contrast_gene_ids{$gene_id}) {
                        $self->processed_data->[$contrast_idx]->[$processed_row_idx_for_gene_id{$gene_id}] = $data_row->{data};
                        $contrast_gene_ids{$gene_id}++;
                    }
                    # shouldn't get here unless something is messed up with algorithm
                    else {
                        confess("Collapsing algorithm error, $gene_id data found more than once in same contrast (this should not happen)");
                    }
                }
            }
        }
    }
    elsif ($self->collapsing_method eq 'dataset_data') {
        # collapse dataset data with same Gene ID by doing full dataset data row comparison and flag which dataset rows to skip
        my %mapped_gene_row_idx_to_keep;
        for my $row_idx (0 .. $#{$self->_mapped_data}) {
            # evaluate dataset row to current best dataset row with same Gene ID
            $self->_process_dataset_data_row_cmp($row_idx, \%mapped_gene_row_idx_to_keep);
        }
        # process _mapped_data skip flags to produce final processed_data structure
        for my $data_row (@{$self->_mapped_data}) {
            if (!exists $data_row->{skip}) {
                my $gene_id = $data_row->{data}->[0];
                my @dataset_row_data = @{$data_row->{data}}[1 .. $#{$data_row->{data}}];
                my $contrast_idx = 0;
                while (@dataset_row_data) {
                    push @{$self->processed_data->[$contrast_idx]}, [
                        $gene_id,
                        splice(@dataset_row_data, 0, $self->num_data_cols_per_group),
                    ];
                    $contrast_idx++;
                }
            }
        }
    }
    else {
        confess("'", $self->collapsing_method , "' not a valid collapsing method");
    }
}

sub _process_contrast_data_row_cmp {
    my $self = shift;
    my ($contrast_idx, $row_idx, $mapped_gene_row_idx_to_keep_hashref) = @_;
    my $gene_id = $self->_mapped_data->[$contrast_idx]->[$row_idx]->{data}->[0];
    # keep track of which data rows to keep based on Gene ID and contrast data values
    if (defined $mapped_gene_row_idx_to_keep_hashref->{$gene_id}) {
        my $data_row = $self->_mapped_data->[$contrast_idx]->[$row_idx];
        my $best_data_row = $self->_mapped_data->[$contrast_idx]->[$mapped_gene_row_idx_to_keep_hashref->{$gene_id}];
        if (defined $self->P_idx) {
            if ($data_row->{data}->[$self->P_idx] < $best_data_row->{data}->[$self->P_idx]) {
                $best_data_row->{skip}++;
                $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
            }
            elsif ($data_row->{data}->[$self->P_idx] == $best_data_row->{data}->[$self->P_idx]) {
                if (defined $self->M_idx) {
                    if ($data_row->{data}->[$self->M_idx] > $best_data_row->{data}->[$self->M_idx]) {
                        $best_data_row->{skip}++;
                        $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
                    }
                    elsif ($data_row->{data}->[$self->M_idx] == $best_data_row->{data}->[$self->M_idx]) {
                        if (defined $self->A_idx) {
                            if ($data_row->{data}->[$self->A_idx] > $best_data_row->{data}->[$self->A_idx]) {
                                $best_data_row->{skip}++;
                                $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
                            }
                            else {
                                $data_row->{skip}++;
                            }
                        }
                        # shouldn't get here unless something messed up data file
                        else {
                            confess('Contrast row data comparison error, cannot find a valid data column to use for data comparison (this should not happen)');
                        }
                    }
                    else {
                        $data_row->{skip}++;
                    }
                }
                elsif (defined $self->A_idx) {
                    if ($data_row->{data}->[$self->A_idx] > $best_data_row->{data}->[$self->A_idx]) {
                        $best_data_row->{skip}++;
                        $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
                    }
                    else {
                        $data_row->{skip}++;
                    }
                }
                # shouldn't get here unless something messed up data file
                else {
                    confess('Contrast row data comparison error, cannot find a valid data column to use for data comparison (this should not happen)');
                }
            }
            else {
                $data_row->{skip}++;
            }
        }
        elsif (defined $self->M_idx) {
            if ($data_row->{data}->[$self->M_idx] > $best_data_row->{data}->[$self->M_idx]) {
                $best_data_row->{skip}++;
                $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
            }
            elsif ($data_row->{data}->[$self->M_idx] == $best_data_row->{data}->[$self->M_idx]) {
                if (defined $self->A_idx) {
                    if ($data_row->{data}->[$self->A_idx] > $best_data_row->{data}->[$self->A_idx]) {
                        $best_data_row->{skip}++;
                        $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
                    }
                    else {
                        $data_row->{skip}++;
                    }
                }
                # shouldn't get here unless something messed up data file
                else {
                    confess('Contrast row data comparison error, cannot find a valid data column to use for data comparison (this should not happen)');
                }
            }
            else {
                $data_row->{skip}++;
            }
        }
        elsif (defined $self->A_idx) {
            if ($data_row->{data}->[$self->A_idx] > $best_data_row->{data}->[$self->A_idx]) {
                $best_data_row->{skip}++;
                $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
            }
            else {
                $data_row->{skip}++;
            }
        }
        # shouldn't get here unless something messed up data file
        else {
            confess('Contrast row data comparison error, cannot find a valid data column to use for data comparison (this should not happen)');
        }
    }
    else {
        $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
    }
}

sub _process_dataset_data_row_cmp {
    my $self = shift;
    my ($row_idx, $mapped_gene_row_idx_to_keep_hashref) = @_;
    my $gene_id = $self->_mapped_data->[$row_idx]->{data}->[0];
    # keep track of which data rows to keep based on Gene ID and mean data row values
    if (defined $mapped_gene_row_idx_to_keep_hashref->{$gene_id}) {
        my $data_row = $self->_mapped_data->[$row_idx];
        my $best_data_row = $self->_mapped_data->[$mapped_gene_row_idx_to_keep_hashref->{$gene_id}];
        my @data_row_data = @{$data_row->{data}}[1 .. $#{$data_row->{data}}];
        my @best_data_row_data = @{$best_data_row->{data}}[1 .. $#{$best_data_row->{data}}];
        if (defined $self->P_idx) {
            $data_row->{mean_p_val} = $self->_compute_dataset_row_mean_for_col($self->P_idx, \@data_row_data) unless defined $data_row->{mean_p_val};
            $best_data_row->{mean_p_val} = $self->_compute_dataset_row_mean_for_col($self->P_idx, \@best_data_row_data) unless defined $best_data_row->{mean_p_val};
            if ($data_row->{mean_p_val} < $best_data_row->{mean_p_val}) {
                $best_data_row->{skip}++;
                $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
            }
            elsif ($data_row->{mean_p_val} == $best_data_row->{mean_p_val}) {
                if (defined $self->M_idx) {
                    $data_row->{mean_m_val} = $self->_compute_dataset_row_mean_for_col($self->M_idx, \@data_row_data) unless defined $data_row->{mean_m_val};
                    $best_data_row->{mean_m_val} = $self->_compute_dataset_row_mean_for_col($self->M_idx, \@best_data_row_data) unless defined $best_data_row->{mean_m_val};
                    if ($data_row->{mean_m_val} > $best_data_row->{mean_m_val}) {
                        $best_data_row->{skip}++;
                        $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
                    }
                    elsif ($data_row->{mean_m_val} == $best_data_row->{mean_m_val}) {
                        if (defined $self->A_idx) {
                            $data_row->{mean_a_val} = $self->_compute_dataset_row_mean_for_col($self->A_idx, \@data_row_data) unless defined $data_row->{mean_a_val};
                            $best_data_row->{mean_a_val} = $self->_compute_dataset_row_mean_for_col($self->A_idx, \@best_data_row_data) unless defined $best_data_row->{mean_a_val};
                            if ($data_row->{mean_a_val} > $best_data_row->{mean_a_val}) {
                                $best_data_row->{skip}++;
                                $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
                            }
                            else {
                                $data_row->{skip}++;
                            }
                        }
                        # shouldn't get here unless something messed up data file
                        else {
                            confess('Dataset row data comparison error, cannot find a valid data column to use for data comparison (this should not happen)');
                        }
                    }
                    else {
                        $data_row->{skip}++;
                    }
                }
                elsif (defined $self->A_idx) {
                    $data_row->{mean_a_val} = $self->_compute_dataset_row_mean_for_col($self->A_idx, \@data_row_data) unless defined $data_row->{mean_a_val};
                    $best_data_row->{mean_a_val} = $self->_compute_dataset_row_mean_for_col($self->A_idx, \@best_data_row_data) unless defined $best_data_row->{mean_a_val};
                    if ($data_row->{mean_a_val} > $best_data_row->{mean_a_val}) {
                        $best_data_row->{skip}++;
                        $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
                    }
                    else {
                        $data_row->{skip}++;
                    }
                }
                # shouldn't get here unless something messed up data file
                else {
                    confess('Dataset row data comparison error, cannot find a valid data column to use for data comparison (this should not happen)');
                }
            }
            else {
                $data_row->{skip}++;
            }
        }
        elsif (defined $self->M_idx) {
            $data_row->{mean_m_val} = $self->_compute_dataset_row_mean_for_col($self->M_idx, \@data_row_data) unless defined $data_row->{mean_m_val};
            $best_data_row->{mean_m_val} = $self->_compute_dataset_row_mean_for_col($self->M_idx, \@best_data_row_data) unless defined $best_data_row->{mean_m_val};
            if ($data_row->{mean_m_val} > $best_data_row->{mean_m_val}) {
                $best_data_row->{skip}++;
                $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
            }
            elsif ($data_row->{mean_m_val} == $best_data_row->{mean_m_val}) {
                if (defined $self->A_idx) {
                    $data_row->{mean_a_val} = $self->_compute_dataset_row_mean_for_col($self->A_idx, \@data_row_data) unless defined $data_row->{mean_a_val};
                    $best_data_row->{mean_a_val} = $self->_compute_dataset_row_mean_for_col($self->A_idx, \@best_data_row_data) unless defined $best_data_row->{mean_a_val};
                    if ($data_row->{mean_a_val} > $best_data_row->{mean_a_val}) {
                        $best_data_row->{skip}++;
                        $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
                    }
                    else {
                        $data_row->{skip}++;
                    }
                }
                # shouldn't get here unless something messed up data file
                else {
                    confess('Dataset row data comparison error, cannot find a valid data column to use for data comparison (this should not happen)');
                }
            }
            else {
                $data_row->{skip}++;
            }
        }
        elsif (defined $self->A_idx) {
            $data_row->{mean_a_val} = $self->_compute_dataset_row_mean_for_col($self->A_idx, \@data_row_data) unless defined $data_row->{mean_a_val};
            $best_data_row->{mean_a_val} = $self->_compute_dataset_row_mean_for_col($self->A_idx, \@best_data_row_data) unless defined $best_data_row->{mean_a_val};
            if ($data_row->{mean_a_val} > $best_data_row->{mean_a_val}) {
                $best_data_row->{skip}++;
                $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
            }
            else {
                $data_row->{skip}++;
            }
        }
        # shouldn't get here unless something messed up data file
        else {
            confess('Dataset row data comparison error, cannot find a valid data column to use for data comparison (this should not happen)');
        }
    }
    else {
        $mapped_gene_row_idx_to_keep_hashref->{$gene_id} = $row_idx;
    }
}

sub _compute_dataset_row_mean_for_col {
    my $self = shift;
    my ($col_idx, $dataset_row_data_arrayref) = @_;
    my @row_col_vals;
    while (@{$dataset_row_data_arrayref}) {
        my @row_data_group = (undef, splice(@{$dataset_row_data_arrayref}, 0, $self->num_data_cols_per_group));
        push @row_col_vals, $row_data_group[$col_idx];
    }
    return scalar(@row_col_vals) > 1 
        ? sum(@row_col_vals) / scalar(@row_col_vals) 
        : shift @row_col_vals;
}

sub _report_excluded_text {
    my $self = shift;
    return defined $self->P_idx ? 'lower P' : defined $self->M_idx ? 'higher M' : 'better';
}

sub write_processed_file {
    my $self = shift;
    my ($output_file_path, $output_as_gene_symbols) = @_;
    #confess('No output mapped file path passed as a parameter') unless defined $output_file_path;
    #my $file_header = defined $self->report ? $self->report : '';
    #$file_header =~ s/^/## /gm;
    # create column header based on number of data columns excluding ID column
    my $col_header_line = 'GeneID' . ("\t" . join("\t", @{$self->column_headers})) x $self->num_data_groups . "\n";
    # add dataset_name and dataset_desc if not in metadata header
    unshift @{$self->_raw_metadata}, qq/#%dataset_name="$self->{dataset_name}"/ 
        if !defined $self->metadata->{dataset_name} and defined $self->{dataset_name};
    unshift @{$self->_raw_metadata}, qq/#%dataset_desc="$self->{dataset_desc}"/
        if !defined $self->metadata->{dataset_desc} and defined $self->{dataset_desc};
    # since output file will always be of ID type EntrezGene make sure
    # to remove any source id_type metadata and put the correct one
    my $id_type_metadata_exists;
    my @new_raw_metadata = @{$self->_raw_metadata};
    for my $metadata_str (@new_raw_metadata) {
        if ($metadata_str =~ /^#%\s*id_type=/i) {
            $metadata_str = '#%id_type=' . ($output_as_gene_symbols ? 'GeneSymbol' : 'EntrezGene');
            $id_type_metadata_exists++;
        }
    }
    if (!$id_type_metadata_exists) {
        push @new_raw_metadata, '#%id_type=' . ($output_as_gene_symbols ? 'GeneSymbol' : 'EntrezGene');
    }
    my $output_fh;
    if (defined $output_file_path) {
        # write output mapped and/or collapsed gene contrast file
        # 3-arg form of open because $output_file_path could be a scalar reference in-memory file
        open($output_fh, '>', $output_file_path) or confess("Could not create $output_file_path: $!");
    }
    else {
        $output_fh = *STDOUT;
    }
    #print $output_fh $file_header if $self->isa(__PACKAGE__ . '::IdMAPS') or $self->isa(__PACKAGE__ . '::IdList');
    print $output_fh @new_raw_metadata  ? (join("\n", @new_raw_metadata),  "\n") : '', 
                     @{$self->comments} ? (join("\n", @{$self->comments}), "\n") : '', 
                     $col_header_line;
    my $gene_info_hashref = Confero::EntrezGene->instance()->gene_info;
    # we can loop over processed_data structure inside out (since each contrast has same num entries) and then print
    for my $row_idx (0 .. $#{$self->processed_data->[0]}) {
        my $gene_id_printed;
        for my $contrast_idx (0 .. $#{$self->processed_data}) {
            if (!$gene_id_printed) {
                # print Entrez Gene ID (or official gene symbol) once
                print $output_fh $output_as_gene_symbols 
                    ? $gene_info_hashref->{${$self->processed_data->[$contrast_idx]->[$row_idx]}[0]}->{symbol}
                    : ${$self->processed_data->[$contrast_idx]->[$row_idx]}[0];
                $gene_id_printed++;
            }
            # print contrast data 
            print $output_fh "\t", join("\t", @{$self->processed_data->[$contrast_idx]->[$row_idx]}[1 .. $self->num_data_cols_per_group]);
        }
        print $output_fh "\n";
    }
    close($output_fh);
}

sub write_subset_file {
    my $self = shift;
    my ($output_file_path, $contrast_idxs_hashref) = @_;
    my $output_fh;
    if (defined $output_file_path) {
        # write output mapped and/or collapsed gene contrast file
        # 3-arg form of open because $output_file_path could be a scalar reference in-memory file
        open($output_fh, '>', $output_file_path) or confess("Could not create $output_file_path: $!");
    }
    else {
        $output_fh = *STDOUT;
    }
    # print number of column headers for subset
    my $col_header_line = $self->id_column_header . ("\t" . join("\t", @{$self->column_headers})) x scalar(keys %{$contrast_idxs_hashref}) . "\n";
    # rewrite multi metadata headers for subset
    my @new_raw_metadata = @{$self->_raw_metadata};
    for my $metadata_str (@new_raw_metadata) {
        # parser already checked and fixed any metadata during object loading so no need to check again here
        my ($field_name) = $metadata_str =~ /^#%\s*(\w+)(?:=.+)*$/;
        # rewrite only multi metadata headers
        if (ref($self->metadata->{$field_name}) eq 'ARRAY') {
            my $field_is_numeric = ($CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_int} or 
                                    $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_num} or
                                    $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_uint} or
                                    $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_unum})
                                 ? 1
                                 : 0;
            $metadata_str = "#%$field_name=" . ($field_is_numeric ? '' : '"') . join($field_is_numeric ? ',' : '","', 
                map {
                    $self->metadata->{$field_name}->[$_] 
                }
                grep {
                    $contrast_idxs_hashref->{$_}
                } 0 .. $#{$self->metadata->{$field_name}}
            ) . ($field_is_numeric ? '' : '"');
        }
    }
    print $output_fh @new_raw_metadata  ? (join("\n", @new_raw_metadata),  "\n") : '', 
                     @{$self->comments} ? (join("\n", @{$self->comments}), "\n") : '', 
                     $col_header_line;
    for my $dataset_row (@{$self->source_data}) {
        print $output_fh $dataset_row->{ $self->has_gene_ids ? 'gene_id' : 'source_id' };
        my @dataset_row_data = split /\t/, $dataset_row->{data_str};
        my $contrast_idx = 0;
        while (@dataset_row_data) {
            my @data_fields = splice(@dataset_row_data, 0, $self->num_data_cols_per_group);
            if ($contrast_idxs_hashref->{$contrast_idx}) {
                print $output_fh "\t", join("\t", @data_fields);
            }
            $contrast_idx++;
        }
        print $output_fh "\n";
    }
    close($output_fh);
}

1;
