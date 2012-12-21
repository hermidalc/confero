# File: generate_idmaps.R
# 
# Author: Sylvain Gubian, PMP SA
# Aim: Functions for generating a idMAPS file form LIMMA or SAMR

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.

#########################################################################################

generate.idmaps <- function(file.path,name,desc,id,dest,delta=0.001,ct.pthres.selected=NULL,all.selected=FALSE,all.pv.thres=NULL) {
	if (!file.exists(file.path)) {
		stop("R dat file does not exist!")
	}
	limma.checklist <- c("coefficients","p.value","t")
	samr.checklist <- c("genenames","x","y","geneid")
	obj.name <- load(file.path)
	obj <- get(x=obj.name)
	if (all(samr.checklist%in%names(obj))) {
		type="SAMR"
	} else if (all(limma.checklist%in%names(obj))) {
		type="LIMMA"
	} else {
		stop("The R object is not a LIMMA or samr compatible object.")
	}
	
	if ("LIMMA"==type) {
		res <- checkLIMMAObject(obj)
		if (!res) {
			stop("The R object is not a compatible LIMMA object")
		}
		res <- parse.limma(obj)
	} else if ("SAMR"==type) {
		res <- checkSAMRObject(obj)
		if (!res) {
			stop("The R object is not a compatible SAMR object")
		}
		res <- process.samr(obj, delta)
	}
	writeToFile(res,dest,name,desc,id, ct.pthres.selected, all.selected, all.pv.thres)
}

checkLIMMAObject <- function(obj) {
	if (class(obj) != "MArrayLM") {
		FALSE
	}
	TRUE
}

checkSAMRObject <- function(obj) {
	TRUE
}


process.samr <- function(obj, delta) {
	# Preprocess data for having two matrices for the two pair comparison
	if (length(unique(obj$y))>2 | length(unique(obj$y)) < 1) {
		warning("y in R object is not suitable for Two class unpaired.")
		return(NULL)
	}
	x <- obj$x[,which(obj$y==unique(obj$y)[1])]
	y <- obj$x[,which(obj$y==unique(obj$y)[2])]
	
	if(! identical(rownames(x),rownames(y)) ) { stop("x,y in compareTwoSamplesBySamr should have the same row names.")}
	result <- list()
	result$contrast.names <- c("Contrast_From_SAMR")
	samr.obj <-samr(obj,resp.type="Two class unpaired",nperms=ifelse(nrow(obj$x) > 1E5,100,100))
	delta.table <- samr.compute.delta.table(samr.obj)
	siggenes.table<-samr.compute.siggenes.table(samr.obj,delta, obj, delta.table,compute.localfdr=TRUE)
	tmp.table <- rbind(siggenes.table$"genes.up"[,c("Gene ID","Score(d)","q-value(%)")],
			siggenes.table$"genes.lo"[,c("Gene ID","Score(d)","q-value(%)")])
	if(is.null(tmp.table) || nrow(tmp.table) == 0) {
		warning("no any significant gene.") 
		return(NULL)
	}
	tmp.table <- cbind(tmp.table,rep(NA,nrow(tmp.table)))
	colnames(tmp.table)[4] <- "FC"
	x.restricted <- lapply(tmp.table[,1], function(X) x[which(obj$genenames==X),])
	y.restricted <- lapply(tmp.table[,1], function(X) y[which(obj$genenames==X),])
	x.restricted <- matrix(unlist(x.restricted),length(x.restricted),ncol(x))
	y.restricted <- matrix(unlist(y.restricted),length(y.restricted),ncol(y))
	
	tmp.table[,4] <- apply(x.restricted,1,mean,na.rm=T) - apply(y.restricted,1,mean,na.rm=T)
	
	metrics <- c("M", "P", "S")
	result$data <- matrix(NA, nrow(tmp.table), length(metrics))
	result$data[,1] <- as.numeric(tmp.table[,"FC"])
	result$data[,2] <- as.numeric(tmp.table[,"q-value(%)"])/100
	result$data[,3] <- as.numeric(tmp.table[,"Score(d)"])
	rownames(result$data) <-  tmp.table[,"Gene ID"]
	colnames(result$data) <- metrics
	return(result)
}

parse.limma <- function(obj) {
	# Check if we have a linear model or a pair-wise comparison
	result <- list()
	nb.rows <- length(rownames(obj$coefficients))
	
	
	if ("contrasts"%in%names(obj)) {
		# We have pair-wise comparison
		metrics <- c("M", "P", "S")
		result$contrast.names <- colnames(obj$contrasts)
		nb.contrasts <- length(result$contrast.names)
		cols <- rep(metrics,nb.contrasts)
		# M: Fold change
		# A: means
		# P: adjusted p-value
		# S: moderated-t
		result$data <- matrix(NA, nb.rows, length(cols))
		rownames(result$data) <- rownames(obj$coefficients)
		for(i in 1:(nb.contrasts)) {
			result$data[,((i-1)*length(metrics) + 1)] <- obj$coefficients[,i]
			result$data[,((i-1)*length(metrics) + 2)] <- p.adjust(obj$p.value[,i],method="fdr")
			result$data[,((i-1)*length(metrics) + 3)] <- obj$t[,i]
			
#			result$data[,((i-1)*length(metrics) + 1)] <- obj$coefficients[,i]
#			result$data[,((i-1)*length(metrics) + 2)] <- obj$Amean
#			result$data[,((i-1)*length(metrics) + 3)] <- p.adjust(obj$p.value[,i],method="fdr")
#			result$data[,((i-1)*length(metrics) + 4)] <- obj$t[,i]
#			result$data[,((i-1)*length(metrics) + 5)] <- obj$df.prior
			#result$data[,((i-1)*length(metrics) + 6)] <- obj$coefficients[,i] / obj$t[,i]
			#result$data[,((i-1)*length(metrics) + 7)] <- (obj$Amean - obj$coefficients[,i]) / 2
			#result$data[,((i-1)*length(metrics) + 8)] <- (obj$Amean + obj$coefficients[,i]) / 2
			#result$data[,((i-1)*length(metrics) + 9)] <- round(runif(nb.rows,min=0.4,max=1))
		}
		colnames(result$data) <- cols
		return(result)
	} else {
		# We have linear models analysis
		metrics <- c("M", "A", "P", "S","Df")
		#metrics <- c("M", "A", "P", "S", "DF", "DM", "CC", "TT", "AS")
		#metrics <- c("M", "A", "P", "S", "DF")
		result$contrast.names <- colnames(obj$coefficients)
		nb.contrasts <- length(result$contrast.names)
		cols <- rep(metrics,nb.contrasts)
		result$data <- matrix(NA, nb.rows, length(cols))
		rownames(result$data) <- rownames(obj$coefficients)
		for(i in 1:(nb.contrasts)) {
			result$data[,((i-1)*length(metrics) + 1)] <- obj$coefficients[,i]
			result$data[,((i-1)*length(metrics) + 2)] <- obj$Amean
			result$data[,((i-1)*length(metrics) + 3)] <- p.adjust(obj$p.value[,i],method="fdr")
			result$data[,((i-1)*length(metrics) + 4)] <- obj$t[,i]
			result$data[,((i-1)*length(metrics) + 5)] <- obj$df.residual
			#result$data[,((i-1)*length(metrics) + 6)] <- obj$coefficients[,i] / obj$t[,i]
			#result$data[,((i-1)*length(metrics) + 7)] <- (obj$Amean - obj$coefficients[,i]) / 2
			#result$data[,((i-1)*length(metrics) + 8)] <- (obj$Amean + obj$coefficients[,i]) / 2
			#result$data[,((i-1)*length(metrics) + 9)] <- round(runif(nb.rows,min=0.4,max=1))
		}
		colnames(result$data) <- cols
		return(result)
	}
}

writeToFile <- function(res,dest,name,desc,id,ct.pthres.selected=NULL,all.selected,all.pv.thres) {
	f <- file(dest,"w")
	if (!isOpen(f,"w")) {
		stop(paste("Unable to write IDMAPS file to: ", dest))
	}
	# Write header
	writeLines(text=paste("#%dataset_name=\"", name, "\"",sep=""), con=f)
	writeLines(text=paste("#%dataset_desc=\"", desc, "\"",sep=""), con=f)
	writeLines(text=paste("#%id_type=\"", id, "\"",sep=""), con=f)
	
	# Write constrast list
	ctk.str <- ""
	for(i in 1:length(res$contrast.names)) {
		if (i > 1) ctk.str <- paste(ctk.str,",",sep="")
		ctk.str <- paste(ctk.str,"\"",res$contrast.names[i],"\"", sep="")
	}
	col.names <- ""
	for(i in 1:length(colnames(res$data))) {
		if (i == 1) col.names <- paste(col.names,"ID",sep="")
		col.names <- paste(col.names,"\t", colnames(res$data)[i], sep="")
	}
	writeLines(text=paste("#%contrast_names=",ctk.str,sep=""), con=f)
	
	if (!is.null(ct.pthres.selected)) {
		ct.intersect <- intersect(res$contrast.names, names(ct.pthres.selected))
		gs.pval.thres <- ""
		for(i in 1:length(res$contrast.names)) {
			if (!res$contrast.names[i]%in%ct.intersect) {
				if (!all.selected) {
					if (i < length(res$contrast.names)) {
						gs.pval.thres <- paste(gs.pval.thres,",",sep="")
					}
				} else {
					if (i < length(res$contrast.names)) {
						gs.pval.thres <- paste(gs.pval.thres,all.pv.thres, ",", sep="")
					} else {
						gs.pval.thres <- paste(gs.pval.thres,all.pv.thres, sep="")
					}
				}
			} else {
				if (i < length(res$contrast.names)) {
					gs.pval.thres <- paste(gs.pval.thres,ct.pthres.selected[res$contrast.names[i]], ",", sep="")
				} else {
					gs.pval.thres <- paste(gs.pval.thres,ct.pthres.selected[res$contrast.names[i]], sep="")
				}
			}
		}
	}
	writeLines(text=paste("#%gs_p_val_thres=", gs.pval.thres, sep=""), con=f)
	writeLines(text=col.names, con=f)
	close(f)
	
	# Write data
	if (!is.null(res$data)) {
		write.table(append=TRUE, quote=FALSE, x=res$data, file=dest, sep="\t",col.names=FALSE)
	}	
}

