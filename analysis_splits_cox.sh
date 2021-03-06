mkdir Results > /dev/null 2> /dev/null
mkdir Programs > /dev/null 2> /dev/null
cd Programs
method=Cox
outdir=Prediction_$method
mkdir Results/$outdir > /dev/null 2> /dev/null
cat > DataAnalysis-$method.R << EOF
library(Hmisc)
library(R.utils)
library(survival)
library(data.table)

rawdata <- data.frame(fread("../Data/TCGA_8cancer_rmmis.csv",header=TRUE,sep=","),row.names=1)
x <- list(outcome=t(rawdata[1:2,]),xd=rawdata[-c(1:2),],fnames=rownames(rawdata)[-c(1,2)],snames=colnames(rawdata))

Clinical <- grep("Clinical_",x\$fnames)
Clinical <- setdiff(Clinical, which(x\$fnames=="Clinical_BRCA"))
CNV <- grep("CNV_",x\$fnames)
miRNA <- grep("miRNA_",x\$fnames)
Mutation <- grep("Mutation_",x\$fnames)
Module <- grep("Module_",x\$fnames)
Protein <- grep("Protein_",x\$fnames)
GeneExp <- grep("Gene_",x\$fnames)
data.types <- list(Clinical=Clinical,GeneExp=GeneExp,Module=Module,Protein=Protein,miRNA=miRNA,CNV=CNV,Mutation=Mutation)
data.types.names <- list("Clinical","Gene","Module","Protein","miRNA","CNV","Mutation")

features.rows <- list(Clinical,CNV,Mutation,miRNA,Protein)
features <- c("Clinical","CNV","Mutation","miRNA","Protein")
m <- length(features)

FEATURES <- list()
NAMES <- rep(NA, 2^m)
for (i in 0:(2^m-1)) {
	a <- unlist(strsplit(intToBin(i), split=""))
	a <- c(rep(0,m-length(a)), a)
	a <- rev(a)
	index <- c("")
	name <- c("")
	feature.tmp <- c()
	for (j in 1:m) {
		if (a[j] == "1") {
			index <- paste(index,j+1,sep="")
			name <- paste(name,features[j],sep=".")
			feature.tmp <- c(feature.tmp, features.rows[[j]])
		}
	}
	NAMES[i+1] <- paste(index,name,sep="")
	FEATURES <- c(FEATURES, list(feature.tmp))
}
NAMES[1] <- c(".")

insert.string <- function(name, index, feature) {
	a <- unlist(strsplit(name, split="\\\\."))
	if (length(a) == 0) a <- c("")
	out <- paste(c(paste(index,a[1],sep=""),feature,a[-1]), collapse=".")
	c(out)
}
combine <- function(x, object) c(object, x)

NAMES.95 <- as.vector(c(sapply(NAMES, insert.string, index=0, feature="GeneExp"), sapply(NAMES, insert.string, index=1, feature="Module"), NAMES[-1]))
FEATURES.95 <- c(lapply(FEATURES, combine, object=GeneExp), lapply(FEATURES, combine, object=Module), FEATURES[-1])
n.model <- length(NAMES.95)

split <- read.table("../Data/DataSplit.csv",sep=",",header=FALSE,row.names=1)
split <- split[match(x\$snames,rownames(split)),]
i <- 65
name<-NAMES.95[i]
features<-FEATURES.95[[i]]

for (s in 1:30) {
	for (type in c(1,2,3)) {
	        type.name <- ifelse(type == 1, "LUAD", ifelse(type == 2, "KIRC", "all"))
	        dir <- c("Results/$outdir")
	        out <- c()
	        out <- c(out, name)

		if (type == 1) filter.t <- (x\$xd["Clinical_LUAD",] == 1)
		if (type == 2) filter.t <- (x\$xd["Clinical_KIRC",] == 1)
		if (type == 3) filter.t <- rep(TRUE,ncol(x\$xd))
		rm.features <- c()
		for (k in Clinical) if (length(unique(as.numeric(x\$xd[k,filter.t]))) == 1) rm.features <- c(rm.features, k)
		features.t <- setdiff(features, rm.features)
		all.modules <- t(x\$xd[features.t, filter.t])
		all.outcome <- Surv(x\$outcome[filter.t,2],x\$outcome[filter.t,1])
		train.modules <- t(x\$xd[features.t, filter.t & split[,s] == 0])
		train.outcome <- Surv(x\$outcome[filter.t&split[,s]==0,2],x\$outcome[filter.t&split[,s]==0,1])
		test.modules <- t(x\$xd[features.t, filter.t & split[,s] == 1])
		test.outcome <- Surv(x\$outcome[filter.t&split[,s]==1,2],x\$outcome[filter.t&split[,s]==1,1])

		train.modules <- t(t(train.modules) - apply(train.modules,2,mean))
		train.modules.sd <- apply(train.modules,2,function(x)ifelse(sd(x)>0,sd(x),1))
		train.modules <- t(t(train.modules) / train.modules.sd)

		fit <- coxph(train.outcome~train.modules,ties="breslow")
		beta <- fit\$coef
		tuning <- c(NA,NA)

		out <- c(out, tuning)
		train.modules <- t(t(train.modules) * train.modules.sd)
		beta <- beta / train.modules.sd

		selected <- x\$fnames[features.t[which(beta != 0)]]
		selected.pos <- which(beta != 0)
		beta.nonzero <- beta[which(beta != 0)]
		out <- c(out, length(beta.nonzero))

		if (length(grep("GeneExp", name)) > 0) GeneExpsize <- length(grep("Gene_", selected)) else GeneExpsize <- c(NA)
		if (length(grep("Module", name)) > 0) Modulesize <- length(grep("Module_", selected)) else Modulesize <- c(NA)
		if (length(grep("Clinical", name)) > 0) Clinicalsize <- length(grep("Clinical_", selected)) else Clinicalsize <- c(NA)
		if (length(grep("CNV", name)) > 0) DNAsize <- length(grep("CNV_", selected)) else DNAsize <- c(NA)
		if (length(grep("Mutation", name)) > 0) Mutationsize <- length(grep("Mutation_", selected)) else Mutationsize <- c(NA)
		if (length(grep("miRNA", name)) > 0) miRNAsize <- length(grep("miRNA_", selected)) else miRNAsize <- c(NA)
		if (length(grep("Protein", name)) > 0) RPPAsize <- length(grep("Protein_", selected)) else RPPAsize <- c(NA)
		out <- c(out, GeneExpsize, Modulesize, Clinicalsize, DNAsize, Mutationsize, miRNAsize, RPPAsize)

		outmodel <- cbind(selected[order(beta.nonzero)], beta.nonzero[order(beta.nonzero)])
		write.table(outmodel, file=paste("../",dir, "/Model_split",s,"-",type.name,"-",name,".csv",sep=""), col.names=F, row.names=F, sep=",", quote=F)

		preds <- as.matrix(test.modules[,selected.pos]) %*% beta.nonzero
		if (length(unique(preds)) > 1) {
			preds <- (preds - mean(preds)) / sd(preds)
			vals.en <- cut(preds,c(-1000,median(preds),1000),c("low","high"))
			cindex <- signif(1-rcorr.cens(preds,test.outcome)[[1]],4)
			out <- c(out, dim(test.modules)[1], cindex)
		} else {
			out <- c(out, rep("NA",2))
		}

		sink(paste("../",dir,"/summary_split",s,"-",type.name,"-",name,".csv",sep=""),append=T)
		cat(out, sep=",")
		cat("\\n")
		sink()
		gc()
	}
}
EOF
