package Confero::Web;

use strict;
use warnings;
use CGI;
#use CGI::Carp qw(fatalsToBrowser);
use Confero::DB;
use Confero::Config qw(:web);
use Confero::LocalConfig qw(:general :web);
use Confero::Utils qw(construct_id deconstruct_id);
use List::Util qw(first);
use Sort::Key qw(nsort nkeysort);
use Sort::Key::Natural qw(natkeysort rnatkeysort);
use Sort::Key::Multi qw(s2keysort);
use Dancer ':syntax';
#use Dancer::Plugin::DirectoryView;

our $VERSION = '0.1';

#get '/' => sub {
#    template 'index';
#};

get '/' => sub {
    redirect '/view';
};

get '/view' => sub {
    my $cgi = CGI->new();
    my $params = params;
    my $cache_control = '';
    my $title         = 'Confero Contrast/Gene Set DB';
    my $onload        = '';
    my $onunload      = '';
    my $jscript = <<"    JSCRIPT";
    JSCRIPT
    my $body_html;
    eval {
        my $ctk_db = Confero::DB->new();
        $ctk_db->txn_do(sub {
            my $data_set_count = $ctk_db->resultset('ContrastDataSet')->count();
            my $gene_set_count = $ctk_db->resultset('GeneSet')->count();
            $body_html = <<"            HTML";
            <!-- <form method="post" action="/view"> -->
              <table class="richTableWide">
                <tr><th class="richTable">$title</th></tr>
            HTML
            $body_html .= '<tr><td style="text-align: right">Empty Database</td></tr>' if $data_set_count + $gene_set_count == 0;
            #$body_html .= $data_set_count + $gene_set_count > 0
            #    ? '<tr><td style="text-align: right">click here to extract contrast data from contrasts selected below&nbsp;&rarr;&nbsp;<input type="submit" value="EXTRACT"/></td></tr>'
            #    : '<tr><td style="text-align: right">Empty Database</td></tr>';
            if ($data_set_count > 0) {
                $body_html .= <<"                HTML";
                <tr><td>
                  <table class="richTableWide">
                    <tr>
                      <th class="richTable">Dataset ID</th>
                      <th class="richTable">Organism</th>
                      <!-- <th class="richTable">Dataset Name</th> -->
                      <!-- <th class="richTable">Extract All</th> -->
                      <th class="richTable">Contrast ID</th>
                      <!-- <th class="richTable">Contrast Name</th> -->
                      <!-- <th class="richTable">Extract</th> -->
                    </tr>
                HTML
                my @datasets = $ctk_db->resultset('ContrastDataSet')->search(undef, {
                    page     => $params->{page} || 1,
                    rows     => $params->{rows} || $CTK_WEB_EXTRACT_ROWS_PER_PAGE,
                    prefetch => [
                        'contrasts', 'organism',
                    ],
                    order_by => [
                        { -desc => 'me.id' },
                        { -asc => 'contrasts.id' },
                    ],
                })->all();
                for my $dataset (@datasets) {
                    my @contrasts = $dataset->contrasts;
                    for my $i (0 .. $#contrasts) {
                        my $num_contrasts = scalar(@contrasts);
                        $body_html .= '<tr>';
                        if ($i == 0) {
                            my $dataset_id_html = $cgi->escapeHTML(construct_id($dataset->name));
                            my $dataset_detail_href_html = $cgi->escapeHTML("/view/contrast_dataset/$dataset_id_html");
                            $body_html .= 
                                qq/<td class="btop" rowspan="$num_contrasts"><a href="$dataset_detail_href_html">/ . $dataset_id_html . '</a></td>' .
                                qq/<td class="btopcentered" rowspan="$num_contrasts">/ . $cgi->escapeHTML($dataset->organism->name || '') . ' [' . $cgi->escapeHTML($dataset->organism->tax_id || '') . ']</td>' .
                                #qq/<td class="btopcentered" rowspan="$num_contrasts">/ . $cgi->escapeHTML($dataset->name) . '</td>' .
                                #qq/<td class="btopcentered" rowspan="$num_contrasts"><input type="checkbox" name="datasets" value="/ . $dataset_id_html . '"/></td>';
                                '' ;
                                
                        }
                        my $contrast_id_html = $cgi->escapeHTML(construct_id($dataset->name, $contrasts[$i]->name));
                        my $contrast_detail_href_html = $cgi->escapeHTML("/view/contrast/$contrast_id_html");
                        $body_html .= $i == 0 
                                    ? qq/<td class="btop"><a href="$contrast_detail_href_html">/ . $contrast_id_html . '</a></td>' .
                                        #'<td class="btopcentered">' . $cgi->escapeHTML($contrasts[$i]->name) . '</td>' .
                                        #'<td class="btopcentered"><input type="checkbox" name="contrasts" value="' . $contrast_id_html . '"/></td></tr>'
                                        ''
                                    : qq/<td><a href="$contrast_detail_href_html">/ . $contrast_id_html . '</a></td>' .
                                        #'<td class="centered">' . $cgi->escapeHTML($contrasts[$i]->name) . '</td>' .
                                        #'<td class="centered"><input type="checkbox" name="contrasts" value="' . $contrast_id_html . '"/></td></tr>';
                                        '' ;
                    }
                }
                $body_html .= <<"                HTML";
                  </table>
                </td></tr>
                HTML
            }
            if ($gene_set_count > 0) {
                $body_html .= <<"                HTML";
                <tr><td>
                  <table class="richTableWide">
                    <tr>
                      <th class="richTable">Gene Set ID</th>
                      <th class="richTable">Size</th>
                      <th class="richTable">Organism</th>
                      <!-- <th class="richTable">Gene Set Name</th> -->
                      <!-- <th class="richTable">Extract</th> -->
                    </tr>
                HTML
                my @gene_sets = $ctk_db->resultset('GeneSet')->search(undef, {
                    page     => $params->{page} || 1,
                    rows     => $params->{rows} || $CTK_WEB_EXTRACT_ROWS_PER_PAGE,
                    prefetch => 'organism',
                    order_by => { -desc => 'me.id' },
                })->all();
                for my $gene_set (@gene_sets) {
                    my $gene_set_id_html = $cgi->escapeHTML(construct_id($gene_set->name, $gene_set->contrast_name, $gene_set->type));
                    my $gene_set_detail_href_html = $cgi->escapeHTML("/view/gene_set/$gene_set_id_html");
                    $body_html .= 
                        '<tr>' .
                        qq/<td><a href="$gene_set_detail_href_html">/ . $gene_set_id_html . '</a></td>' .
                          '<td class="centered">' . $cgi->escapeHTML($gene_set->gene_set_genes->count()) . '</td>' .
                          '<td class="centered">' . $cgi->escapeHTML($gene_set->organism->name || '') . ' [' . $cgi->escapeHTML($gene_set->organism->tax_id || '') . ']</td>' .
                          #'<td class="centered">' . $cgi->escapeHTML($gene_set->name) . '</td>' .
                          #'<td class="centered"><input type="checkbox" name="gene_sets" value="' . $gene_set_id_html . '"/></td></tr>';
                          '' ;
                }
                $body_html .= <<"                HTML";
                  </table>
                </td></tr>
                HTML
            }
            $body_html .= <<"            HTML";
              </table>
            HTML
            #$body_html .= <<"            HTML" if $data_set_count + $gene_set_count > 0;
            #    <tr><td style="text-align: right">click here to extract contrast data from contrasts selected below&nbsp;&rarr;&nbsp;<input type="submit" value="EXTRACT"/></td></tr>
            #  </table>
            #</form>
            #HTML
        });
    };
    if ($@) {
       my $message = "Confero database transaction failed";
       $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
       $body_html = "$message, please contact $CTK_ADMIN_EMAIL_ADDRESS: $@";
    }
    #$cgi->header(
    #    -type          => 'text/html',
    #    -charset       => 'utf-8',
    #    -encoding      => 'utf-8',
    #    -cache_control => $cache_control,
    #)
    headers 'Cache-control' => 'no-store';
    return 
        $cgi->start_html(
            -title     => $title,
            -encoding  => 'utf-8',
            -style     => { -src => '/css/main.css' },
            -script    => { -code => $jscript },
            #-script    => [ { -src => '/js/main.js' }, { -code => $jscript } ],
            -onLoad    => $onload,
            -onUnload  => $onunload
        ) . 
        $body_html .
        $cgi->end_html;
};

post '/view' => sub {
    my $params = params;
    my @errors;
    if (defined $params->{contrast_datasets} or defined $params->{contrasts} or defined $params->{gene_sets}) {
        my (@dataset_names, @contrast_names, @gene_set_names);
        # check for errors
        if (defined $params->{contrast_datasets}) {
            my @dataset_ids = split /\0/, $params->{contrast_datasets};
            for my $dataset_id (@dataset_ids) {
                my $dataset_name = deconstruct_id($dataset_id);
                if (defined $dataset_name) {
                    push @dataset_names, $dataset_name;
                }
                else {
                    push @errors, "Contrast dataset ID $dataset_id not valid";
                }
            }
        }
        if (defined $params->{contrasts}) {
            my @contrast_ids = split /\0/, $params->{contrasts};
            for my $contrast_id (@contrast_ids) {
                my ($dataset_name, $contrast_name) = deconstruct_id($contrast_id);
                if (defined $dataset_name and defined $contrast_name) {
                    push @dataset_names, $dataset_name;
                    push @contrast_names, $contrast_name;
                }
                else {
                    push @errors, "Contrast ID $contrast_id not valid";
                }
            }
        }
        if (defined $params->{gene_sets}) {
            my @gene_set_ids = split /\0/, $params->{gene_sets};
            for my $gene_set_id (@gene_set_ids) {
                my ($gene_set_name, $gene_set_contrast_name, $gene_set_type) = deconstruct_id($gene_set_id);
                if (defined $gene_set_name) {
                    push @gene_set_names, [$gene_set_name, $gene_set_contrast_name, $gene_set_type];
                }
                else {
                    push @errors, "Gene set ID $gene_set_id not valid";
                }
            }
        }
        if (!@errors) {
            my $extract_body;
            eval {
                my $ctk_db = Confero::DB->new();
                $ctk_db->txn_do(sub {
                    my ($contrasts_hashref, $gene_sets_hashref);
                    if (@dataset_names and !@contrast_names and !@gene_set_names) {
                        for my $dataset_name (@dataset_names) {
                            my $dataset = $ctk_db->resultset('ContrastDataSet')->find({
                                name => $dataset_name,
                            },{
                                prefetch => {
                                    'contrasts' => 'data_file',
                                },
                                order_by => 'contrasts.id',
                            });
                            my @contrasts = $dataset->contrasts;
                            for my $contrast (@contrasts) {
                                $contrasts_hashref->{$contrast->id} = $contrast;
                            }
                        }
                    }
                    elsif (@contrast_names and !@gene_set_names) {
                        for my $i (0 .. $#contrast_names) {
                            my $dataset = $ctk_db->resultset('ContrastDataSet')->find({
                                name => $dataset_names[$i],
                            });
                            my $contrast = $dataset->contrasts->find({
                                name => $contrast_names[$i],
                            },{
                                prefetch => ['data_set', 'data_file'],
                            });
                            $contrasts_hashref->{$contrast->id} = $contrast;
                        }
                    }
                    elsif (@gene_set_names) {
                        for my $gene_set_name_arrayref (@gene_set_names) {
                            my $gene_set = $ctk_db->resultset('GeneSet')->find({
                                name => $gene_set_name_arrayref->[0],
                                contrast_name => $gene_set_name_arrayref->[1],
                                type => $gene_set_name_arrayref->[2],
                            });
                            $gene_sets_hashref->{$gene_set->id} = $gene_set;
                        }
                    }
                    my $extract_data;
                    if (defined $contrasts_hashref) {
                        for my $contrast_id (nsort keys %{$contrasts_hashref}) {
                            open(DATFILE, '<', \$contrasts_hashref->{$contrast_id}->data_file->data) or die "Could not open contrast data file: $!";
                            my $header = <DATFILE>;
                            $header =~ s/\s+$//;
                            my @header_fields = split /\t/, $header;
                            my %column_header_idxs;
                            $column_header_idxs{$contrast_id}{uc($header_fields[$_])} = $_ for 1 .. $#header_fields;
                            while(<DATFILE>) {
                                s/\s+$//;
                                my @data_fields = split /\t/;
                                my $data_str = '';
                                for my $col_header_type (qw( M A P S )) {
                                    $data_str .= defined $column_header_idxs{$contrast_id}{uc($col_header_type)}
                                               ? "\t" . $data_fields[$column_header_idxs{$contrast_id}{uc($col_header_type)}]
                                               : "\tNA";
                                }
                                $extract_data->{$data_fields[0]}->{$contrast_id} = $data_str;
                            }
                            close(DATFILE);
                        }
                        $extract_body = 
                            qq/#%contrast_ids="/ . 
                            join(q/","/, map { construct_id($contrasts_hashref->{$_}->data_set->name, $contrasts_hashref->{$_}->name) } nsort keys %{$contrasts_hashref}) . "\n" .
                            "GeneID" . "\tM\tA\tP\tS" x scalar(keys %{$contrasts_hashref}) . "\n";
                        for my $gene_id (nsort keys %{$extract_data}) {
                            #my $gene_symbol = $ctk_db->resultset('Gene')->find($gene_id)->symbol;
                            $extract_body .= $gene_id;
                            for my $contrast_id (nsort keys %{$contrasts_hashref}) {
                                $extract_body .= defined $extract_data->{$gene_id}->{$contrast_id}
                                                   ? $extract_data->{$gene_id}->{$contrast_id}
                                                   : "\tNA\tNA\tNA\tNA";
                            }
                            $extract_body .= "\n";
                        }
                    }
                    elsif (defined $gene_sets_hashref) {
                        for my $gene_set_id (nsort keys %{$gene_sets_hashref}) {
                            open(DATFILE, '<', \$gene_sets_hashref->{$gene_set_id}->source_data_file->data) or die "Could not open gene set data file: $!";
                            close(DATFILE);
                            $extract_body = "This feature is not working yet...";
                        }
                    }
                });
            };
            if ($@) {
                my $message = "Confero database transaction failed";
                $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
                push @errors, "$message, please contact $CTK_ADMIN_EMAIL_ADDRESS: $@";
            }
            else {
                # write out data file
                #$cgi->header(
                #    -type                => 'text/plain',
                #    -charset             => 'utf-8',
                #    -encoding            => 'utf-8',
                #    -content_disposition => 'attachment; filename=extract_data.txt',
                #)
                headers  
                    'Content-type' => 'text/plain', 
                    'Encoding' => 'utf-8', 
                    'Content-disposition' => 'inline; filename=extract_data.txt';
                return $extract_body;
            }
        }
    }
    else {
        push @errors, 'No data selected for extraction';
    }
};

get '/view/:type/:id' => sub {
    my $cgi = CGI->new();
    my $params = params;
    my $cache_control  = '';
    my $title          = 'Confero Contrast/Gene Set DB Details';
    my $jscript        = '';
    my $onload         = '';
    my $onunload       = '';
    my $body_html      = '';
    if (defined $params->{id} and defined $params->{type} and $params->{type} =~ /^(contrast_dataset|contrast|contrast_gene_set|gene_set)$/i) {
        if ($params->{type} =~ /^(contrast_dataset|contrast|contrast_gene_set)$/i) {
            if (my ($dataset_name, $contrast_name, $gene_set_type) = deconstruct_id($params->{id})) {
                my $gene_set_genes_html = '';
                my ($dataset, @contrasts, $contrast, @gene_sets, $gene_set_gene_count);
                eval {
                    my $ctk_db = Confero::DB->new();
                    $ctk_db->txn_do(sub {
                        if ($params->{type} =~ /^contrast_dataset$/i) {
                            $dataset = $ctk_db->resultset('ContrastDataSet')->find({
                                name => $dataset_name,
                            },{
                                prefetch => [
                                    'organism', 
                                    { 'contrasts' => 'gene_sets' },
                                ],
                            });
                            # since prefetched contrasts with dataset won't necessarily be in desired order (we want in the order entered)
                            @contrasts = nkeysort { $_->id } $dataset->contrasts;
                            @gene_sets = map { $_->gene_sets } @contrasts;
                        }
                        elsif ($params->{type} =~ /^(contrast|contrast_gene_set)$/i) {
                            $dataset = $ctk_db->resultset('ContrastDataSet')->find({
                                name => $dataset_name,
                            });
                            $contrast = $dataset->contrasts->find({
                                name => $contrast_name,
                            },{
                                prefetch => { 'gene_sets' => { 'gene_set_genes' => 'gene' } },
                            });
                            @gene_sets = $contrast->gene_sets;
                            if (defined $gene_set_type) {
                                my $gene_set = first { $_->type =~ /\Q$gene_set_type\E/i } @gene_sets;
                                my @gene_set_genes = $gene_set->gene_set_genes;
                                $gene_set_gene_count = scalar(@gene_set_genes);
                                $gene_set_genes_html = join('', map { 
                                <<"                                HTML"
                                    <tr>
                                        <td class="richTable">@{[$cgi->escapeHTML($_->rank)]}</td>
                                        <td class="richTable"><a href="http://www.ncbi.nlm.nih.gov/gene/@{[$cgi->escapeHTML($_->gene->id)]}">@{[$cgi->escapeHTML($_->gene->id)]}</a></td>
                                        <td class="richTable"><a href="http://www.ncbi.nlm.nih.gov/gene?term=@{[$cgi->escapeHTML($_->gene->symbol)]}">@{[$cgi->escapeHTML($_->gene->symbol)]}</a></td>
                                        <td class="richTable">@{[$cgi->escapeHTML($_->gene->description)]}</td>
                                    </tr>
                                HTML
                                } nkeysort { $_->rank } @gene_set_genes);
                            }
                        }
                    });
                };
                if ($@) {
                    my $message = "Confero database transaction failed";
                    $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
                    $body_html = "$message, please contact $CTK_ADMIN_EMAIL_ADDRESS: $@";
                }
                else {
                    my $dataset_id = construct_id($dataset->name);
                    my $dataset_detail_href_html = $cgi->escapeHTML("/view/contrast_dataset/$dataset_id");
                    my $source_data_file_href_html = $cgi->escapeHTML("/data/contrast_dataset/$dataset_id");
                    my $data_processing_report_href_html = $cgi->escapeHTML("/data/contrast_dataset_report/$dataset_id");
                    if ($params->{type} =~ /^contrast_dataset$/i) {
                        $body_html = <<"                        HTML";
                        <table class="richTableWide" style="margin-top:5px;">
                            <tr><th class="richTable" colspan="3">Contrasts</th></tr>
                            <tr>
                                <th class="richTable" style="width:250px">ID</th>
                                <th class="richTable">Name</th>
                                <th class="richTable">Data File</th>
                            </tr>
                        HTML
                        my $gene_sets_html = '';
                        for my $contrast (@contrasts) {
                            my $contrast_id = construct_id($dataset->name, $contrast->name);
                            my $contrast_detail_href_html = $cgi->escapeHTML("/view/contrast/$contrast_id");
                            my $contrast_data_file_href_html = $cgi->escapeHTML("/data/contrast/$contrast_id");
                            $body_html .= qq(<tr><td><a href="$contrast_detail_href_html">) . $cgi->escapeHTML($contrast_id) . '</a></td>' .
                                                '<td class="richTableCentered">' . $cgi->escapeHTML($contrast->name) . '</td>' .
                                          qq(<td class="richTableCentered"><a href="$contrast_data_file_href_html" target="_blank">View</a></td></tr>);
                            for my $gene_set (rnatkeysort { $_->type } $contrast->gene_sets) {
                                my $gene_set_id = construct_id($dataset->name, $contrast->name, $gene_set->type);
                                my $gene_set_detail_href_html = $cgi->escapeHTML("/view/contrast_gene_set/$gene_set_id");
                                my $gene_set_data_file_href_html = $cgi->escapeHTML("/data/contrast_gene_set/$gene_set_id");
                                $gene_sets_html .= qq(<tr><td><a href="$gene_set_detail_href_html">) . $cgi->escapeHTML($gene_set_id) . '</a></td>' . 
                                                         '<td class="richTableCentered">' . $cgi->escapeHTML($gene_set->gene_set_genes->count()) . '</td>' . 
                                                       qq(<td class="richTableCentered"><a href="$gene_set_data_file_href_html" target="_blank">View</a></td></tr>);
                            }
                        }
                        $body_html .= '</table>';
                        $body_html .= <<"                        HTML" if @gene_sets;
                        <table class="richTable" style="margin-top:5px;">
                            <tr>
                                <th class="richTable" style="width:250px">Gene Set</th>
                                <th class="richTable">Size</th>
                                <th class="richTable">Data File</th>
                            </tr>
                            $gene_sets_html
                        </table>
                        HTML
                    }
                    elsif ($params->{type} =~ /^(contrast|contrast_gene_set)$/i) {
                        my $contrast_id = construct_id($dataset->name, $contrast->name);
                        my $contrast_detail_href_html    = $cgi->escapeHTML("/view/contrast/$contrast_id");
                        my $contrast_data_file_href_html = $cgi->escapeHTML("/data/contrast/$contrast_id");
                        $body_html = <<"                        HTML";
                        <table class="richTableWide" style="margin-top:5px;">
                            <tr><th class="richTable" colspan="3">Contrast</th></tr>
                            <tr>
                                <td class="richTableBold" style="width:200px">ID:</td>
                                <td><a href="$contrast_detail_href_html">@{[$cgi->escapeHTML($contrast_id)]}</a></td>
                            </tr>
                            <tr>
                                <td class="richTableBold">Name:</td>
                                <td>@{[$cgi->escapeHTML($contrast->name)]}</td>
                            </tr>
                            <tr>
                                <td class="richTableBold">Data File:</td>
                                <td><a href="$contrast_data_file_href_html" target="_blank">View</a></td>
                            </tr>
                        </table>
                        HTML
                        if (@gene_sets) {
                            if (!defined $gene_set_type) {
                                $body_html .= <<"                                HTML";
                                <table class="richTable" style="margin-top:5px;">
                                    <tr>
                                        <th class="richTable" style="width:250px">Gene Set</th>
                                        <th class="richTable">Size</th>
                                        <th class="richTable">Data File</th>
                                    </tr>
                                HTML
                                for my $gene_set (rnatkeysort { $_->type } @gene_sets) {
                                    my $gene_set_id = construct_id($dataset->name, $contrast->name, $gene_set->type);
                                    my $gene_set_detail_href_html = $cgi->escapeHTML("/view/contrast_gene_set/$gene_set_id");
                                    my $gene_set_data_file_href_html = $cgi->escapeHTML("/data/contrast_gene_set/$gene_set_id");
                                    $body_html .= qq(<tr><td><a href="$gene_set_detail_href_html">) . $cgi->escapeHTML($gene_set_id) . '</a></td>' .
                                                        '<td class="richTableCentered">' . $cgi->escapeHTML($gene_set->gene_set_genes->count()) . '</td>' . 
                                                      qq(<td class="richTableCentered"><a href="$gene_set_data_file_href_html" target="_blank">View</a></td></tr>);
                                }
                                $body_html .= '</table>';
                            }
                            else {
                                my $gene_set_detail_href_html = $cgi->escapeHTML("/view/contrast_gene_set/$params->{id}");
                                my $gene_set_data_file_href_html = $cgi->escapeHTML("/data/contrast_gene_set/$params->{id}");
                                $body_html .= <<"                                HTML";
                                <table class="richTableWide" style="margin-top:5px;">
                                    <tr><th class="richTable" colspan="2">Gene Set</th></tr>
                                    <tr>
                                        <td class="richTableBold" style="width:200px">Name:</td>
                                        <td><a href="$gene_set_detail_href_html">@{[$cgi->escapeHTML($params->{id})]}</a></td>
                                    </tr>
                                    <tr>
                                        <td class="richTableBold">Size:</td>
                                        <td>@{[$cgi->escapeHTML($gene_set_gene_count)]}</td>
                                    </tr>
                                    <tr>
                                        <td class="richTableBold">Data File:</td>
                                        <td><a href="$gene_set_data_file_href_html" target="_blank">View</a></td>
                                    </tr>
                                </table>
                                <table class="richTableWide" style="margin-top:5px;">
                                    <tr>
                                        <th class="richTable" style="width:100px">Rank in Gene Set</th>
                                        <th class="richTable" style="width:100px">Entrez Gene ID</th>
                                        <th class="richTable" style="width:100px">Symbol</th>
                                        <th class="richTable">Description</th>
                                    </tr>
                                    $gene_set_genes_html
                                </table>
                                HTML
                            }
                        }
                    }
                    # annotations
                    my $annot_html = '';
                    for my $annotation (s2keysort { $_->name, $_->value } $dataset->annotations) {
                        $annot_html .= <<"                        HTML";
                        <tr>
                          <td class="richTableBold">Annotation [@{[$cgi->escapeHTML($annotation->name)]}]:</td>
                          <td>@{[$cgi->escapeHTML($annotation->value)]}</td>
                        </tr>
                        HTML
                    }
                    $body_html = <<"                    HTML";
                    <table class="richTableWide">
                    <tr><th class="richTable">Confero Contrast/Gene Set DB Details</th></tr>
                      <tr><td>
                        <table class="richTableWide">
                          <tr><th class="richTable" colspan="2">Contrast Dataset</th></tr>
                          <tr>
                            <td class="richTableBold" style="width:200px">ID:</td>
                            <td>
                                <form method="post" action="/delete">
                                    <a href="$dataset_detail_href_html">@{[$cgi->escapeHTML($dataset_id)]}</a>
                                    <input type="submit" value="DELETE"/>
                                    <input type="hidden" name="contrast_dataset" value="@{[$cgi->escapeHTML($dataset_id)]}"/>
                                </form>
                            </td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Name:</td>
                            <td>@{[$cgi->escapeHTML($dataset->name)]}</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Description:</td>
                            <td>@{[$cgi->escapeHTML($dataset->description) || '&nbsp;']}</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Organism:</td>
                            <td>@{[$cgi->escapeHTML($dataset->organism->name || '')]} [@{[$cgi->escapeHTML($dataset->organism->tax_id || '')]}]</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Source Data ID Type:</td>
                            <td>@{[$cgi->escapeHTML($dataset->source_data_file_id_type)]}</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Source Data File Name:</td>
                            <td>@{[$cgi->escapeHTML($dataset->source_data_file_name)]}</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Creation Time:</td>
                            <td>@{[$cgi->escapeHTML($dataset->creation_time)]}</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Source Data File:</td>
                            <td><a href="$source_data_file_href_html" target="_blank">View</a></td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Data Processing Report:</td>
                            <td><a href="$data_processing_report_href_html" target="_blank">View</a></td>
                          </tr>
                          $annot_html
                        </table>
                        $body_html
                      </td></tr>
                    </table>
                    HTML
                }
            }
            else {
                $body_html = "Error: $params->{id} is not valid";
            }
        }
        elsif ($params->{type} =~ /^gene_set$/i) {
            if (my ($gene_set_name, $gene_set_contrast_name, $gene_set_type) = deconstruct_id($params->{id})) {
                #$gene_set_name = "$gene_set_name $gene_set_contrast_name" if defined $gene_set_contrast_name;
                #$gene_set_name = "$gene_set_name $gene_set_type" if defined $gene_set_type;
                my $gene_set_genes_html = '';
                my ($gene_set, $gene_set_gene_count, $genes_have_ranks);
                eval {
                    my $ctk_db = Confero::DB->new();
                    $ctk_db->txn_do(sub {
                        $gene_set = $ctk_db->resultset('GeneSet')->find({
                            name => $gene_set_name,
                            contrast_name => $gene_set_contrast_name,
                            type => $gene_set_type,
                        },{
                            prefetch => [
                                'organism', 
                                { 'gene_set_genes' => 'gene' },
                            ],
                        });
                        my @gene_set_genes = $gene_set->gene_set_genes;
                        $gene_set_gene_count = scalar(@gene_set_genes);
                        $genes_have_ranks = first { $_->rank } @gene_set_genes;
                        $gene_set_genes_html = join('', $genes_have_ranks 
                            ?
                            map {
                            <<"                            HTML"
                                <tr>
                                    <td class="richTable">@{[$cgi->escapeHTML($_->rank)]}</td>
                                    <td class="richTable"><a href="http://www.ncbi.nlm.nih.gov/gene/@{[$cgi->escapeHTML($_->gene->id)]}">@{[$cgi->escapeHTML($_->gene->id)]}</a></td>
                                    <td class="richTable"><a href="http://www.ncbi.nlm.nih.gov/gene?term=@{[$cgi->escapeHTML($_->gene->symbol)]}">@{[$cgi->escapeHTML($_->gene->symbol)]}</a></td>
                                    <td class="richTable">@{[$cgi->escapeHTML($_->gene->description)]}</td>
                                </tr>
                            HTML
                            } nkeysort { $_->rank } @gene_set_genes
                            :
                            map {
                            <<"                            HTML"
                                <tr>
                                    <td class="richTable"><a href="http://www.ncbi.nlm.nih.gov/gene/@{[$cgi->escapeHTML($_->gene->id)]}">@{[$cgi->escapeHTML($_->gene->id)]}</a></td>
                                    <td class="richTable"><a href="http://www.ncbi.nlm.nih.gov/gene?term=@{[$cgi->escapeHTML($_->gene->symbol)]}">@{[$cgi->escapeHTML($_->gene->symbol)]}</a></td>
                                    <td class="richTable">@{[$cgi->escapeHTML($_->gene->description)]}</td>
                                </tr>
                            HTML
                            } natkeysort { $_->gene->symbol } @gene_set_genes
                        );
                    });
                };
                if ($@) {
                    my $message = "Confero database transaction failed";
                    $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
                    $body_html = "$message, please contact $CTK_ADMIN_EMAIL_ADDRESS: $@";
                }
                else {
                    my $gene_set_id = construct_id($gene_set->name, $gene_set->contrast_name, $gene_set->type);
                    my $gene_set_detail_href_html = $cgi->escapeHTML("/view/gene_set/$gene_set_id");
                    my $source_data_file_href_html = $cgi->escapeHTML("/data/source_gene_set/$gene_set_id");
                    my $gene_set_data_file_href_html = $cgi->escapeHTML("/data/gene_set/$gene_set_id");
                    my $data_processing_report_href_html = $cgi->escapeHTML("/data/gene_set_report/$gene_set_id");
                    $body_html = <<"                    HTML";
                    <table class="richTableWide">
                    <tr><th class="richTable">Confero Details</th></tr>
                      <tr><td>
                        <table class="richTableWide">
                          <tr><th class="richTable" colspan="2">Gene Set</th></tr>
                          <tr>
                            <td class="richTableBold" style="width:200px">ID:</td>
                            <td>
                                <form method="post" action="/delete">
                                    <a href="$gene_set_detail_href_html">@{[$cgi->escapeHTML($gene_set_id)]}</a>
                                    <input type="submit" value="DELETE"/>
                                    <input type="hidden" name="gene_set" value="@{[$cgi->escapeHTML($gene_set_id)]}"/>
                                </form>
                            </td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Name:</td>
                            <td>@{[$cgi->escapeHTML($gene_set->name)]}</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Contrast Name:</td>
                            <td>@{[$cgi->escapeHTML($gene_set->contrast_name) || '&nbsp;']}</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Type:</td>
                            <td>@{[$cgi->escapeHTML($gene_set->type) || '&nbsp;']}</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Size:</td>
                            <td>@{[$cgi->escapeHTML($gene_set_gene_count) || '&nbsp;']}</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Description:</td>
                            <td>@{[$cgi->escapeHTML($gene_set->description) || '&nbsp;']}</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Organism:</td>
                            <td>@{[$cgi->escapeHTML($gene_set->organism->name || '')]} [@{[$cgi->escapeHTML($gene_set->organism->tax_id || '')]}]</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Source Data ID Type:</td>
                            <td>@{[$cgi->escapeHTML($gene_set->source_data_file_id_type)]}</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Source Data File Name:</td>
                            <td>@{[$cgi->escapeHTML($gene_set->source_data_file_name)]}</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Creation Time:</td>
                            <td>@{[$cgi->escapeHTML($gene_set->creation_time)]}</td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Source Data File:</td>
                            <td><a href="$source_data_file_href_html" target="_blank">View</a></td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Gene Set Data File:</td>
                            <td><a href="$gene_set_data_file_href_html" target="_blank">View</a></td>
                          </tr>
                          <tr>
                            <td class="richTableBold">Data Processing Report:</td>
                            <td><a href="$data_processing_report_href_html" target="_blank">View</a></td>
                          </tr>
                        </table>
                        <table class="richTableWide" style="margin-top:5px;">
                            <tr>
                    HTML
                    $body_html .= qq(<th class="richTable" style="width:100px">Rank in Gene Set</th>) if $genes_have_ranks;
                    $body_html .= <<"                    HTML";
                                <th class="richTable" style="width:100px">Entrez Gene ID</th>
                                <th class="richTable" style="width:100px">Symbol</th>
                                <th class="richTable">Description</th>
                            </tr>
                            $gene_set_genes_html
                        </table>
                      </td></tr>
                    </table>
                    HTML
                }
            }
            else {
                $body_html = "Error: $params->{id} is not valid";
            }
        }
    }
    else {
        $body_html = 'Error: Missing id and/or type query parameters or type parameter not valid';
    }
    #$cgi->header(
    #    -type          => 'text/html',
    #    -charset       => 'utf-8',
    #    -encoding      => 'utf-8',
    #    -cache_control => $cache_control
    #)
    headers 'Cache-control' => 'no-store';
    return
        $cgi->start_html(
            -title     => $title,
            -encoding  => 'utf-8',
            -style     => { -src => '/css/main.css' },
            #-script    => [ { -src => '/js/main.js' }, { -code => $jscript } ],
            -onLoad    => $onload,
            -onUnload  => $onunload
        ) .
        $body_html .
        $cgi->end_html;
};

post '/delete' => sub {
    my $params = params;
    my @errors;
    if (defined $params->{contrast_dataset}) {
        eval {
            my $ctk_db = Confero::DB->new();
            $ctk_db->txn_do(sub {
                my $dataset_name = deconstruct_id($params->{contrast_dataset});
                if (my $dataset = $ctk_db->resultset('ContrastDataSet')->find({
                        name => $dataset_name,
                })) {
                    $dataset->delete();
                }
                else {
                    push @errors, "Contrast dataset '$params->{dataset}' does not exist in database";
                }
            });
        };
        if ($@) {
            my $message = "Confero database transaction failed";
            $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
            push @errors, "$message, please contact $CTK_ADMIN_EMAIL_ADDRESS: $@";
        }
        else {
            redirect '/view';
            return;
        }
    }
    elsif (defined $params->{gene_set}) {
        eval {
            my $ctk_db = Confero::DB->new();
            $ctk_db->txn_do(sub {
                my ($gene_set_name, $gene_set_contrast_name, $gene_set_type) = deconstruct_id($params->{gene_set});
                if (my $gene_set = $ctk_db->resultset('GeneSet')->find({
                        name => $gene_set_name,
                        contrast_name => $gene_set_contrast_name,
                        type => $gene_set_type,
                })) {
                    $gene_set->delete();
                }
                else {
                    push @errors, "Gene set '$params->{gene_set}' does not exist in database";
                }
            });
        };
        if ($@) {
            my $message = "Confero database transaction failed";
            $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
            push @errors, "$message, please contact $CTK_ADMIN_EMAIL_ADDRESS: $@";
        }
        else {
            redirect '/view';
            return;
        }
    }
    else {
        push @errors, 'No dataset or gene set selected for removal';
    }
};

get '/data/:type/:id' => sub {
    my $cgi = CGI->new();
    my $params = params;
    my ($body, $filename);
    if (defined $params->{id} and defined $params->{type} and $params->{type} =~ /^(contrast_dataset(_report|)|contrast|contrast_gene_set|source_gene_set|gene_set(_report|))$/i) {
        if ($params->{type} =~ /^(contrast_dataset(_report|)|contrast|contrast_gene_set)$/i) {
            if (my ($dataset_name, $contrast_name, $gene_set_type) = deconstruct_id($params->{id})) {
                eval {
                    my $ctk_db = Confero::DB->new();
                    $ctk_db->txn_do(sub {
                        my $dataset = $ctk_db->resultset('ContrastDataSet')->find({
                            name => $dataset_name,
                        });
                        if ($params->{type} =~ /^contrast_dataset$/i) {
                            $body = $dataset->source_data_file->data;
                        }
                        elsif ($params->{type} =~ /^contrast_dataset_report$/i) {
                            $body = $dataset->data_processing_report;
                        }
                        elsif ($params->{type} =~ /^(contrast|contrast_gene_set)$/i) {
                            if ($params->{type} =~ /^contrast$/i) {
                                my $contrast = $dataset->contrasts->find({
                                    name => $contrast_name,
                                },{
                                    prefetch => 'data_file',
                                });
                                $body = $contrast->data_file->data;
                            }
                            else {
                                my $contrast = $dataset->contrasts->find({
                                    name => $contrast_name,
                                },{
                                    prefetch => {
                                        'gene_sets' => { 'gene_set_genes' => 'gene' },
                                    },
                                });
                                my $gene_set = first { $_->type =~ /\Q$gene_set_type\E/i } $contrast->gene_sets;
                                # don't do it this way anymore as this makes another database call
                                #my $gene_set = $contrast->gene_sets->find({
                                #    type => uc($gene_set_type),
                                #});
                                $body = join("\n", map { 
                                    join("\t", $_->gene->id, $_->gene->symbol, $_->gene->description)
                                } nkeysort { $_->rank } $gene_set->gene_set_genes);
                                #} natkeysort { $_->gene->symbol } $gene_set->gene_set_genes);
                            }
                        }
                    });
                    #my $ext = $cgi->user_agent =~ /MSIE/i ? 'txt' : 'tab';
                    #$filename = "$params->{id}.$ext";
                    $filename = "$params->{id}.txt";
                };
                if ($@) {
                    my $message = "Confero database transaction failed";
                    $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
                    $body = "$message, please contact $CTK_ADMIN_EMAIL_ADDRESS: $@";
                }
            }
            else {
                $body = "Error: $params->{id} is not valid";
            }
        }
        elsif ($params->{type} =~ /^(source_gene_set|gene_set(_report|))$/i) {
            if (my ($gene_set_name, $gene_set_contrast_name, $gene_set_type) = deconstruct_id($params->{id})) {
                eval {
                    my $ctk_db = Confero::DB->new();
                    $ctk_db->txn_do(sub {
                        if ($params->{type} =~ /^source_gene_set$/i) {
                            my $gene_set = $ctk_db->resultset('GeneSet')->find({
                                name => $gene_set_name,
                                contrast_name => $gene_set_contrast_name,
                                type => $gene_set_type,
                            },{
                                prefetch => 'source_data_file',
                            });
                            $body = $gene_set->source_data_file->data;
                        }
                        elsif ($params->{type} =~ /^gene_set_report$/i) {
                            my $gene_set = $ctk_db->resultset('GeneSet')->find({
                                name => $gene_set_name,
                                contrast_name => $gene_set_contrast_name,
                                type => $gene_set_type,
                            });
                            $body = $gene_set->data_processing_report;
                        }
                        else {
                            my $gene_set = $ctk_db->resultset('GeneSet')->find({
                                name => $gene_set_name,
                                contrast_name => $gene_set_contrast_name,
                                type => $gene_set_type,
                            },{
                                prefetch => {
                                    gene_set_genes => 'gene',
                                },
                            });
                            $body = join("\n", map {
                                join("\t", $_->gene->id, $_->gene->symbol, $_->gene->description) 
                            } natkeysort { $_->gene->symbol } $gene_set->gene_set_genes);
                        }
                    });
                    #my $ext = $cgi->user_agent =~ /MSIE/i ? 'txt' : 'tab';
                    #$filename = "$params->{id}.$ext";
                    $filename = "$params->{id}.txt";
                };
                if ($@) {
                    my $message = "Confero database transaction failed";
                    $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
                    $body = "$message, please contact $CTK_ADMIN_EMAIL_ADDRESS: $@";
                }
            }
            else {
                $body = "Error: $params->{id} is not valid";
            }
        }
    }
    else {
        $body = 'Error: Missing id and/or type parameter or type parameter not valid';
    }
    # display data file
    #$cgi->header(
    #    -type                => 'text/plain',
    #    -charset             => 'utf-8',
    #    -encoding            => 'utf-8',
    #    -content_disposition => "inline; filename=$filename",
    #)
    headers 
        'Content-type' => 'text/plain', 
        'Encoding' => 'utf-8', 
        'Content-disposition' => "inline; filename=$filename";
    return $body;
};

true;

