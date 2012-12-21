import os, sys, subprocess, json

def get_contrast_list(file_selected):
	# Call the process for R
	f = open('log.txt', 'w')
	f.write('file_selected: ' + file_selected + '\n')
	runme = 'R --vanilla --slave --args ' + file_selected + ' < ' + os.path.abspath(os.path.dirname(sys.argv[0])) + '/../tools/confero_platform/galaxy/get_r_contrasts.R' 
	f.write('Runme: ' + runme + '\n')
	process = subprocess.Popen(runme, shell=True, stdout=subprocess.PIPE)
	stdout_value = process.communicate()[0]
	f.close()
	return(json.loads(stdout_value))
