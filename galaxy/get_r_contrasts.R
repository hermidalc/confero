# File: get_contrast_list.R
# 
# Author: Sylvain Gubian, PMP SA
# Aim: Functions for retrieving contrat from a limma object

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.

#########################################################################################

suppressPackageStartupMessages(library(limma))
options <- commandArgs((trailingOnly = TRUE));

obj.name <- load(options)
obj <- get(x=obj.name)
if ("genenames"%in%names(obj)) {
	# This means this is a SAM R object
	if (is.null(obj$contrast_name)) {
		cat(paste("[[\"samr_contrast\",\"samr_contrast\",0]]", sep=""))
	} else {
		cat(paste("[[\"",obj$contrast_name,"\",\"",obj$contrast_name,"\",0]]", sep=""))
	}
} else {
	# This is LIMMA object
	if ("contrasts"%in%names(obj)) {
		# This is pairwise comparison analysis
		names <- colnames(obj$contrasts)
	} else {
		# This is a linear model analysis
		names <- colnames(obj$coefficients)
	}
	ctk.str <- ""
	for(i in 1:length(names)) {
		if (i > 1) ctk.str <- paste(ctk.str,",",sep="")
		ctk.str <- paste(ctk.str,"[\"",names[i],"\",\"", names[i], "\",0]", sep="")
	}
	cat(paste("[[\"All\",\"All\",1],", ctk.str, "]", sep=""))
}
