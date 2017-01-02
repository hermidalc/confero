import sys, os, subprocess, json
#from galaxy import datatypes

def cfo_get_info(data_type, with_empty=False, annotation_names=''):
    cmd_opts = [ '--as-json', '--as-tuples' ]
    if with_empty: cmd_opts += [ '--with-empty' ]
    pipe = subprocess.Popen([ os.path.abspath(os.path.dirname(sys.argv[0])) + '/../tools/confero/bin/cfo_get_info.pl' ] + cmd_opts + [ data_type, annotation_names ], stdout=subprocess.PIPE)
    return json.loads(pipe.stdout.read())

def cfo_get_contrast_info_from_dataset(source, source_value):
    pipe = subprocess.Popen([ os.path.abspath(os.path.dirname(sys.argv[0])) + '/../tools/confero/galaxy/cfo_get_contrast_info_from_dataset.pl', '--as-tuples', '--get-idxs', '--dataset-' + ('file' if source == 'from_file' else 'id') + '=' + source_value ], stdout=subprocess.PIPE)
    return json.loads(pipe.stdout.read())

