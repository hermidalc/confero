package Confero::DataFile::RankedList;

use strict;
use warnings;
use base 'Confero::DataFile';
use Carp qw(confess);
use Confero::Config qw(:data);
use Confero::EntrezGene;
use Confero::LocalConfig qw(:data $CTK_DISPLAY_ID_PREFIX $CTK_DISPLAY_ID_SPACER);
use Confero::Utils qw(deconstruct_id);
use File::Basename qw(fileparse);
use Sort::Key qw(nsort nkeysort);
use Sort::Key::Natural qw(natsort);
use Utils qw(is_integer is_numeric);

our $VERSION = '0.0.1';

sub data_type_common_name {
    return 'Ranked List';
}

sub contrast_name {
    return shift->{contrast_name};
}

sub _load_data_from_file {
    my $self = shift;
    my (%file_ids, $read_first_non_header_line);
    # 3-arg form of open because file_path could be a scalar reference in-memory file
    open(my $ranked_list_fh, '<', $self->file_path) or confess('Could not open data file ' . $self->file_path . ": $!");
    while (<$ranked_list_fh>) {
        s/^\s+//;
        s/\s+$//;
        # header metadata line
        if (m/^#%/) {
            # at this point we can only check the metadata field names for validity
            # then just store the metadata line
            my ($field_name) = m/^#%\s*(\w+)(?:=.+)*$/;
            $field_name = lc($field_name);
            # fix field_name alternative spellings
            $field_name = $field_name eq 'contrast_name' ? 'contrast_names' : $field_name;
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
        # at the first non-header line check if column header exists and how many columns
        if (!$read_first_non_header_line) {
            $read_first_non_header_line++;
            my $at_column_header_line;
            my @column_header_fields = split /\t/;
            $self->{num_data_cols} = scalar(@column_header_fields) - 1;
            if ($self->num_data_cols >= 1) {
                $self->{num_data_groups} = 1;
                # if I have a column header then will skip data check below
                #m/^[\w ]+(\tM\tA\tP){1}$/i && $at_column_header_line++;
            }
            # bad file, abort parsing
            else {
                push @{$self->data_errors}, 'Data file not valid, invalid number of columns';
                return;
            }
            # finish checking header metadata lines and process metadata
            my %metadata_field_names;
            for my $metadata_line (@{$self->_raw_metadata}) {
                my ($field_name, $field_data_str) = $metadata_line =~ /^#%\s*(\w+)(?:=(.+))*$/;
                $field_name = lc($field_name);
                # fix field_name alternative spellings
                $field_name = $field_name eq 'contrast_name' ? 'contrast_names' : $field_name;
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
            # if organism name, dataset name, or dataset desc not passed to object constructor then use header metadata
            $self->{organism_name} = $self->metadata->{organism} if !defined $self->organism_name and 
                                                                     defined $self->metadata->{organism};
            $self->{dataset_name} = $self->metadata->{dataset_name} if !defined $self->dataset_name and 
                                                                        defined $self->metadata->{dataset_name};
            $self->{dataset_desc} = $self->metadata->{dataset_desc} if !defined $self->dataset_desc and 
                                                                        defined $self->metadata->{dataset_desc};
            $self->{contrast_name} = ${$self->metadata->{contrast_names}}[0] if !defined $self->contrast_name and
                                                                                 defined $self->metadata->{contrast_names};
            my $orig_file_basename = fileparse($self->orig_file_name, qr/\.[^.]*/);
            # extract from original file basename dataset_name, contrast_name
            (
                !defined $self->dataset_name  ? $self->{dataset_name}  : undef, 
                !defined $self->contrast_name ? $self->{contrast_name} : undef,
            ) = deconstruct_id($orig_file_basename);
            # if dataset_name starts with $CTK_DISPLAY_ID_PREFIX remove it and convert any 
            # $CTK_DISPLAY_ID_SPACER characters in dataset_name or contrast name into a space
            if (defined $self->dataset_name) {
                $self->{dataset_name} =~ s/^${CTK_DISPLAY_ID_PREFIX}${CTK_DISPLAY_ID_SPACER}//go;
                $self->{dataset_name} =~ s/$CTK_DISPLAY_ID_SPACER/ /go;
            }
            $self->{contrast_name} =~ s/$CTK_DISPLAY_ID_SPACER/ /go if defined $self->contrast_name;
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
            # at this point, before checking any data lines, we need to load valid ids into the _valid_ids hashref
            $self->_load_valid_ids();
            # skip data checking if at column header line
            next if $at_column_header_line;
        }
        # check data line
        # don't use /o for this regexp because $self->num_data_cols
        # will change across across object instantiations
        if (m/^.+?$/) {
            # nothing to needed to check yet
        }
        else {
            push @{$self->data_errors}, "Data not valid at line $.:\n$_";
        }
        # split line into two parts: ID and data string
        my ($id, $data_str) = split /\t/, $_, 2;
        # check ID is valid
        if (%{$self->_valid_ids}) {
            # many valid source IDs have no map to a Gene ID yet they are still valid
            # so that is why I use exists here since there might not be a hash value
            if (exists $self->_valid_ids->{$id}) {
                # check that all IDs are from the same organism (for Entrez Gene data only, not necessary for source data)
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
    close($ranked_list_fh);
    ## check multi-contrast dataset file metadata requirements
    #if ($self->num_data_groups > 1) {
    #    # check that contrast_names metadata line is defined for batch files
    #    if (!defined $self->metadata->{contrast_names}) {
    #        push @{$self->data_errors}, 'contrast_names metadata header is required for batch files';
    #    }
    #    # will use config default gene set size for all if no metadata
    #    ## check that gs_up_sizes metadata line is defined for batch files
    #    #if (!defined $self->metadata->{gs_up_sizes}) {
    #    #    push @{$self->data_errors}, 'gs_up_sizes metadata header is required for batch files';
    #    #}
    #    # check that gs_dn_sizes metadata line is defined for batch files
    #    #if (!defined $self->metadata->{gs_dn_sizes}) {
    #    #    push @{$self->data_errors}, 'gs_dn_sizes metadata header is required for batch files';
    #    #}
    #}
    ## check that gene set file has minimum number of entries
    #if (scalar(@{$self->source_data}) < $CTK_DATA_FILE_MIN_GENE_SET_SIZE) {
    #    push @{$self->data_errors}, "Data file doesn't have enough data rows, has " .
    #        scalar(@{$self->source_data}) . " and should have at least $CTK_DATA_FILE_MIN_GENE_SET_SIZE";
    #}
    ## check that gene set file not over maximum number of entries
    #if (scalar(@{$self->source_data}) > $CTK_DATA_FILE_MAX_GENE_SET_SIZE) {
    #    push @{$self->data_errors}, "Data file has too many rows, has " .
    #        scalar(@{$self->source_data}) . " and should no more than $CTK_DATA_FILE_MAX_GENE_SET_SIZE";
    #}
    # check for number of invalid IDs
    if (scalar(keys %{$self->_invalid_ids}) > $CTK_DATA_FILE_MAX_INVALID_IDS) {
        push @{$self->data_errors}, "Data file has " . scalar(keys %{$self->_invalid_ids}) . 
            " invalid IDs which exceeds the maximum ($CTK_DATA_FILE_MAX_INVALID_IDS)";
        for my $id (nkeysort { $self->_invalid_ids->{$_}->{line_num} } keys %{$self->_invalid_ids}) {
            push @{$self->data_errors}, "ID '$id' not valid at line " . $self->_invalid_ids->{$id}->{line_num};
            last if scalar(@{$self->data_errors}) > $CTK_DATA_FILE_MAX_ERRORS_TO_LOG;
        }
    }
    ## check that source contrast file has all the source IDs (if required by configuration)
    #if ($CTK_DATA_FILE_MUST_HAVE_ALL_IDS and defined $self->id_type and !$self->has_gene_ids) {
    #    my $num_source_ids_required = scalar(keys %{$self->_src2gene_id_bestmap});
    #    if (scalar(@{$self->source_data}) != $num_source_ids_required) {
    #        push @{$self->data_errors}, "Data file does not have enough data rows, should have " .
    #                                    "$num_source_ids_required for " . $self->id_type;
    #    }
    #}
    ## make sure P value specific metadata not defined if no P value data exists
    #if (!defined $self->P_idx and defined $self->metadata->{gs_p_val_thres}) {
    #    push @{$self->data_errors}, 'gs_p_val_thres cannot be defined if there is no P value data';
    #}
    ## make sure A value specific metadata not defined if no A value data exists
    #if (!defined $self->A_idx and defined $self->metadata->{gs_a_val_thres}) {
    #    push @{$self->data_errors}, 'gs_a_val_thres cannot be defined if there is no A value data';
    #}
    ## make sure M value specific metadata not defined if no M value data exists
    #if (!defined $self->M_idx and defined $self->metadata->{gs_m_val_thres}) {
    #    push @{$self->data_errors}, 'gs_m_val_thres cannot be defined if there is no M value data';
    #}
}

sub _process_data {
    my $self = shift;
    # process source data
    if (!$self->has_gene_ids) {
        my (@source_ids_with_no_map, @source_ids_with_no_map_diff_expressed, @source_ids_with_ambig_map,  @gene_data_rows_excluded, %mapped_gene_row_idx_to_keep);
        # first process source_data dataset rows to do ID checking and mapping
        for my $row_idx (0 .. $#{$self->source_data}) {
            my $source_id = $self->source_data->[$row_idx]->{source_id};
            # check if source ID is valid (again since we do allow for some invalid IDs during parsing)
            if (exists $self->_valid_ids->{$source_id}) {
                # check if source ID has a Gene ID map
                if (defined $self->_src2gene_id_bestmap->{$source_id}->{gene_id}) {
                    # unambiguous map to single or best Gene ID
                    $self->source_data->[$row_idx]->{gene_id} = $self->_src2gene_id_bestmap->{$source_id}->{gene_id};
                    my $gene_id = $self->source_data->[$row_idx]->{gene_id};
                    # keep track of which data rows to keep based on Gene ID
                    if (defined $mapped_gene_row_idx_to_keep{$gene_id}) {
                        $self->source_data->[$row_idx]->{skip}++;
                        push @gene_data_rows_excluded, $self->source_data->[$row_idx];
                    }
                    else {
                        $mapped_gene_row_idx_to_keep{$gene_id} = $row_idx;
                    }
                }
                # none or ambiguous Gene ID map
                else {
                    $self->source_data->[$row_idx]->{skip}++;
                    if (exists $self->_src2gene_id_bestmap->{$source_id}->{no_gene_map}) {
                        $self->source_data->[$row_idx]->{no_gene_map}++;
                        push @source_ids_with_no_map, $source_id;
                    }
                    elsif (exists $self->_src2gene_id_bestmap->{$source_id}->{ambig_gene_map}) {
                        $self->source_data->[$row_idx]->{ambig_gene_map}++;
                        push @source_ids_with_ambig_map, $source_id;
                    }
                }
            }
            # invalid source ID
            else {
                $self->source_data->[$row_idx]->{skip}++;
                $self->source_data->[$row_idx]->{has_invalid_id}++;
            }
        }
        # process skip flags to produce final processed_data structure
        for my $data_row (@{$self->source_data}) {
            next if $data_row->{skip};
            my @data_fields = split /\t/, $data_row->{data_str};
            push @{$self->processed_data}, [
                $data_row->{gene_id},
                @data_fields,
            ];
        }
        # set report summary values that aren't already set
        my $num_source_rows = scalar(@{$self->source_data});
        my $num_invalid_ids = scalar(keys %{$self->_invalid_ids});
        my $num_no_gene_map = @source_ids_with_no_map ? scalar(@source_ids_with_no_map) : 0;
        my $num_ambig_map = @source_ids_with_ambig_map ? scalar(@source_ids_with_ambig_map) : 0;
        my $num_excluded = @gene_data_rows_excluded ? scalar(@gene_data_rows_excluded) : 0;
        my $num_gene_rows = scalar(@{$self->processed_data});
        # generate summary report
        my $format = "format SRCREPORT =\n" .
            "Source gene set file: @*\n\"" . $self->orig_file_name . "\"\n" .
            "  @##########  source IDs/data rows\n$num_source_rows\n" .
            "- @##########  source IDs that are invalid\n$num_invalid_ids\n" .
            "- @##########  source IDs with no Entrez Gene ID mapping\n$num_no_gene_map\n" .
            "- @##########  source IDs excluded due to ambiguous mapping to Entrez Gene IDs\n$num_ambig_map\n" .
            #"- @##########  source IDs excluded due to existence of better representative source ID\n$num_better_id\n" .
            "- @##########  mapped Entrez Gene IDs excluded due to another identical Entrez Gene ID\n$num_excluded\n" .
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
        if (@source_ids_with_no_map) {
            $self->{report} .= "\nSource IDs with no Entrez Gene map:\n" . join("\n", @source_ids_with_no_map) . "\n";
        }
        if (@source_ids_with_ambig_map) {
            $self->{report} .= "\nSource IDs with ambiguous Entrez Gene map:\n" . join("\n", @source_ids_with_ambig_map) . "\n";
        }
    }
    # process already Gene ID-based data
    else {
        my $gene_history_hashref = Confero::EntrezGene->instance()->gene_history;
        # map Gene IDs
        my (@gene_data_rows_discontinued, @gene_data_rows_excluded, %mapped_gene_row_idx_to_keep);
        my $num_gene_ids_updated = 0;
        for my $row_idx (0 .. $#{$self->source_data}) {
            my $gene_id = $self->source_data->[$row_idx]->{gene_id};
            # check if Gene ID is valid (again since we do allow for some invalid IDs during parsing)
            if (exists $self->_valid_ids->{$gene_id}) {
                # check if Gene ID is historical and update it with current replacement if exists
                if (exists $gene_history_hashref->{$gene_id}) {
                    if (exists $gene_history_hashref->{$gene_id}->{current_gene_id}) {
                        # update historical Gene ID with current one
                        $self->source_data->[$row_idx]->{gene_id} = $gene_history_hashref->{$gene_id}->{current_gene_id};
                        $self->source_data->[$row_idx]->{updated_gene_id}++;
                        $num_gene_ids_updated++;
                    }
                    # discontinued Gene ID with no current replacement
                    else {
                        $self->source_data->[$row_idx]->{skip}++;
                        $self->source_data->[$row_idx]->{discontinued_gene_id}++;
                        push @gene_data_rows_discontinued, $gene_id;
                        next;
                    }
                }
                # keep track of which data rows to keep based on Gene ID
                if (defined $mapped_gene_row_idx_to_keep{$gene_id}) {
                    $self->source_data->[$row_idx]->{skip}++;
                    push @gene_data_rows_excluded, $self->source_data->[$row_idx];
                }
                else {
                    $mapped_gene_row_idx_to_keep{$gene_id} = $row_idx;
                }
            }
            # invalid Gene ID
            else {
                $self->source_data->[$row_idx]->{skip}++;
                $self->source_data->[$row_idx]->{has_invalid_id}++;
            }
        }
        # process skip flags to produce final processed_data structure
        for my $data_row (@{$self->source_data}) {
            next if $data_row->{skip};
            my @data_fields = split /\t/, $data_row->{data_str};
            push @{$self->processed_data}, [
                $data_row->{gene_id},
                @data_fields,
            ];
        }
        # set summary report values that aren't already set
        my $num_input_gene_data_rows = scalar(@{$self->source_data});
        my $num_invalid_ids = scalar(keys %{$self->_invalid_ids});
        my $num_discontinued = @gene_data_rows_discontinued ? scalar(@gene_data_rows_discontinued) : 0;
        my $num_excluded = @gene_data_rows_excluded ? scalar(@gene_data_rows_excluded) : 0;
        my $num_output_gene_data_rows = scalar(@{$self->processed_data});
        my $format = "format GENEREPORT = \n" .
            "Gene set file: @*\n\"" . $self->orig_file_name . "\"\n" .
            "  @##########  input Entrez Gene IDs/data rows\n$num_input_gene_data_rows\n" .
            "- @##########  input Entrez Gene IDs that are invalid\n$num_invalid_ids\n" .
            "- @##########  input Entrez Gene IDs/data rows excluded because they are discontinued with no replacement\n$num_discontinued\n" .
            "- @##########  input Entrez Gene IDs excluded due to another identical Entrez Gene ID\n$num_excluded\n" .
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
    #if ($num_output_gene_data_rows < $CTK_DATA_FILE_MIN_GENE_SET_SIZE) {
    #    push @{$self->data_errors}, "Processed data file doesn't have enough data rows, has $num_output_gene_data_rows"
    #        . " and should have at least $CTK_DATA_FILE_MIN_GENE_SET_SIZE";
    #}
}

sub write_processed_file {
    my $self = shift;
    my ($output_file_path, $output_as_gene_symbols) = @_;
    #confess('No output mapped file path passed as a parameter') unless defined $output_file_path;
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
    my $gene_info_hashref = Confero::EntrezGene->instance()->gene_info;
    my $output_fh;
    if (defined $output_file_path) {
        # write output mapped and/or collapsed gene contrast file
        # 3-arg form of open because $output_file_path could be a scalar reference in-memory file
        open($output_fh, '>', $output_file_path) or confess("Could not create $output_file_path: $!");
    }
    else {
        $output_fh = *STDOUT;
    }
    print $output_fh @new_raw_metadata  ? (join("\n", @new_raw_metadata),  "\n") : '', 
                     @{$self->comments} ? (join("\n", @{$self->comments}), "\n") : '';
    for my $data_row (@{$self->processed_data}) {
        print $output_fh 
            $output_as_gene_symbols 
                ? $gene_info_hashref->{$data_row->[0]}->{symbol} 
                : $data_row->[0], 
            "\t", join("\t", @{$data_row}[1..$#{$data_row}]), "\n";
    }
    close($output_fh);
}

1;
