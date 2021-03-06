#' @title Adds \code{lowest_rank} to a phyloseq object
#'
#' @description Adds a \code{lowest_rank} column to a taxonomy table in a phyloseq object.
#'
#' @param ps A \code{phyloseq} object that contains a \code{\link[phyloseq]{tax_table}}
#'
#' @return This function returns the input \code{phyloseq} object with a \code{lowest_rank} column in the \code{tax_table()}.
#' If "Species" is present in the \code{tax_table()}, then this function returns <Genus_species>.
#' If "Species" is NA, this function returns the next highest taxonomic level available.
#' If more than 1 "Species" is present, this function returns <Genus_species1/species2+nspecies>.
#'
#' @examples
#' ps <- add_lowest_rank(ps)
add_lowest_rank <- function(ps){
  x=data.frame(tax_table(ps), stringsAsFactors=FALSE)
  t = dim(x)[2]
  x[,"lowest_rank"] <- x[t]
  if(colnames(x[t]) =="Species" && colnames(x[t-1]) =="Genus"){
    x[,"lowest_rank"] <- paste0(x[,"Genus"],"_", x[,"Species"])
  }
  taxNAs <- which(is.na(x[,t]))
  for(i in taxNAs){
    if(sum(!is.na(x[i,seq(1:t-1)])) == 0){
      x[i,"lowest_rank"] <-NA
    }else{
      x[i,"lowest_rank"] <- x[i , max(which(!is.na(x[i,seq(1:t-1)])))]
    }
  }

  if (sum(grepl("/", x[,"lowest_rank"])) > 0) {
    # for those with more than 1 "Species", only list first 2 and then denote how many more there are
    multi_names <- x[which(sapply(regmatches(x[,"lowest_rank"],
                                           gregexpr("/", x[,"lowest_rank"])), length) >1),"lowest_rank"]

    n_names <- sapply(regmatches(multi_names, gregexpr("/", multi_names)), length) +1

    multi_fixed <- paste0(sapply(strsplit(multi_names, "/"), `[`, 1), "/",
                          sapply(strsplit(multi_names, "/"), `[`, 2), "+", n_names-2)

    x[which(x$lowest_rank %in% multi_names), "lowest_rank"] <- multi_fixed
  }
  tax_table(ps) <- tax_table(as.matrix(x))
  return(ps)
}



#' @title Adds Microbial Dysbiosis Index to a phyloseq object
#'
#' @description Adds a \code{MDI} column to \code{\link[phyloseq]{sample_data}} in a \code{phyloseq} object.
#' The Microbial Dysbiosis Index first
#' proposed by \href{http://www.sciencedirect.com/science/article/pii/S1931312814000638}{Gevers \emph{et al.} (2014)}.
#'
#' @param ps A \code{phyloseq} object that contains \code{\link[phyloseq]{sample_data}}
#'
#' @return This function returns the input \code{phyloseq} object with a \code{MDI} column in the \code{sample_data()}.
#'
#' @examples
#' ps <- add_mdi(ps)

add_mdi<-function (ps){
  mdi_dec <- c("Dialister",
               "Faecalibacterium",
               "Ruminococcus",
               "Sutterella",
               "Rikenellaceae",
               "Parabacteroides",
               "Bacteroides",
               "Lachnospiraceae",
               "Coprococcus",
               "Erysipelotrichaceae",
               "Dorea",
               "Ruminococcaceae",
               "Oscillospira",
               "Bilophila"
                )

  mdi_down <- rownames(tax_table(ps)[which(tax_table(ps)[,"Genus"] %in% mdi_dec),])
  mdi_down_ps <- prune_taxa(mdi_down, ps)

  mdi_inc <- c("Escherichia",
               "Haemophilus",
               "Fusobacterium",
               "Veillonella"
                )

  mdi_up <- rownames(tax_table(ps)[which(tax_table(ps)[,"Genus"] %in% mdi_inc),])
  mdi_up_ps <- prune_taxa(mdi_up, ps)

  if(!is.null(ps@sam_data$MDI)){
    message("MDI already exists in sample_data() and will be overwritten.")
  }

  ps@sam_data$MDI <- log(sample_sums(mdi_up_ps)+1 / sample_sums(mdi_down_ps)+1)
  ps@sam_data$MDI[is.infinite(ps@sam_data$MDI)] <- NA

  if(sum(is.na(ps@sam_data$MDI)) > 0){
    message(paste0("There were ", sum(is.na(ps@sam_data$MDI)),
                   " samples (out of ", nsamples(ps) , " total) where MDI = NA."))
  }

  return(ps)
}


#' @title outputs a FASTA file from a phyloseq object
#'
#' @description This function outputs a FASTA-formatted text file from a \code{phyloseq} object
#'
#' @param ps A \code{phyloseq} object that contains \code{\link[phyloseq]{refseq}}.
#' If there the \code{refseq} slot is not filled, this function will try pull the
#' sequences from \code{\link[phyloseq]{get_taxa}}
#'
#' @param file (optional) A file name that ends in ".fasta" or ".fa".
#' If a file name is not supplied, the file will be named after the phyloseq object.
#'
#' @param rank (optional) A taxonomic rank from the \code{\link[phyloseq]{tax_table}} which will be used to name the sequences.
#' If no rank is supplied, samples will be named \code{ASV_#}
#'
#' @return This function saves a FASTA-formatted text file from the input \code{phyloseq} object.
#'
#' @examples
#' save_fasta(ps)
#' save_fasta(ps = ps, file = "sequences.fasta", rank = "Genus")

save_fasta <- function(ps = ps, file = NULL, rank = NULL){

  if(is.null(ps)){
    message("Phyloseq object not found.")
  }

  if(is.null(file)){
    file <- paste0(deparse(substitute(ps)), ".fasta")
  }

  if(is.null(rank) | !rank %in% rank_names(ps)){
    message("Rank not found. Naming sequences sequentially (i.e. ASV_#).")
    seq_names <- paste0("ASV_", 1:ntaxa(ps))
  } else {
    seq_names <- make.unique(unname(tax_table(ps)[,rank]), sep = "_")
  }

  if(!is.null(refseq(ps))){
    seqs <-as.vector(refseq(ps))
  } else{
    message("refseq() not found. Using taxa names for sequences.")
    if(sum(grepl("[^ACTG]", rownames(tax_table(ps)))) > 0){
      message("Taxa names do not appear to be DNA sequences. Proceed with caution.")
    }
    seqs <-get_taxa(ps)
  }

  for (i in 1:ntaxa(ps)){
    cat(paste(">", seq_names[i], sep=""), file=file, sep="\n", append=TRUE)
    cat(seqs[i], file=file, sep="\n", append=TRUE)
  }
  message(paste0(ntaxa(ps), " sequences written to <", file, ">."))
}




#' @title bar plot ordered across samples
#'
#' @description This function plots a bar plot from a \code{phyloseq} object.
#' The author of this fuction is GitHub user \href{https://github.com/pjames1}{pjames1} in \href{https://github.com/joey711/phyloseq/issues/442}{this thread}.
#'
#' @param ps A \code{phyloseq} object.
#'
#' @param x the varaiable in the \code{\link[phyloseq]{sample_data}} that you want on the x-axis.
#' Defaults to "Sample_ID".
#'
#' @param y the varaiable in the \code{\link[phyloseq]{sample_data}} that you want on the y-axis.
#' Defaults to "Abundance".
#'
#' @param fill the varaiable in the \code{\link[phyloseq]{sample_data}} that you want to color by.
#'
#' @param leg_size a number indicating the legend.key.size
#' The default value is 0.5.
#'
#' @param title (optional) the title of the plot.
#'
#' @return This function returns a bar plot that is ordered similarly across samples.
#'
#' @examples
#' plot_ordered_bar(ps)
#' plot_ordered_bar(ps, x = "Sample_ID", y = "Abundance", fill = Genus, title = "Sample Abundance")
plot_ordered_bar<-function (ps, x = "Sample_ID",
                            y = "Abundance",
                            fill = NULL,
                            leg_size = 0.5,
                            title = NULL) {
  bb <- psmelt(ps)

  samp_names <- aggregate(bb$Abundance, by=list(bb$Sample), FUN=sum)[,1]
  .e <- environment()
  bb[,fill]<- factor(bb[,fill], rev(sort(unique(bb[,fill])))) #fill to genus

  bb<- bb[order(bb[,fill]),] # genus to fill
  p = ggplot(bb, aes_string(x = x, y = y,
                            fill = fill),
             environment = .e, ordered = FALSE)

  p = p +geom_bar(stat = "identity",
                  position = "stack",
                  color = "black")

  p = p + theme(axis.text.x = element_text(angle = -90, hjust = 0))

  p = p + guides(fill = guide_legend(override.aes = list(colour = NULL), reverse=FALSE)) +
    theme(legend.key = element_rect(colour = "black"))

  p = p + theme(legend.key.size = unit(leg_size, "cm"))


  if (!is.null(title)) {
    p <- p + ggtitle(title)
  }
  return(p)
}




#' @title Adds alpha diversity metrics to a \code{phyloseq} object.
#'
#' @description This function adds several alpha diversity metrics to the
#' \code{\link[phyloseq]{sample_data}} of a \code{phyloseq} object.
#' This function largely a reimplementation of \code{\link[phyloseq]{estimate_richness}}.
#'
#' @param ps A \code{phyloseq} object that contains \code{\link[phyloseq]{sample_data}}.
#' If there is a tree in the \code{\link[phyloseq]{phy_tree}} slot, this function will
#' also add \href{http://www.sciencedirect.com/science/article/pii/0006320792912013}{Faith's Phylogenetic Diversity (1992)}
#' as implemented in \code{picante} with the \code{\link[picante]{pd}} function.
#'
#' @return This function returns the input \code{phyloseq} object with
#'  \code{Observed}, \code{Chao1}, \code{ACE}, \code{Shannon}, \code{Simpson},
#'  \code{InvSimpson}, \code{Fisher}, and \code{Faiths_PD} columns in the \code{sample_data()}.
#'
#' @examples
#' ps <- add_alpha_diversity(ps)

add_alpha_diversity<-function (ps){

  if(!is.null(ps@sam_data$Observed) |
     !is.null(ps@sam_data$Chao1) |
     !is.null(ps@sam_data$ACE) |
     !is.null(ps@sam_data$Shannon) |
     !is.null(ps@sam_data$Simpson) |
     !is.null(ps@sam_data$InvSimpson) |
     !is.null(ps@sam_data$Fisher)
  ){
    message("Richness already exists in sample_data() and will be overwritten.")

    alpha_div_df <- estimate_richness(ps)
    sample_data(ps)[,colnames(alpha_div_df)] <- NA
    sample_data(ps)[,colnames(alpha_div_df)] <- alpha_div_df

  } else {
    sample_data(ps) <- cbind(sample_data(ps), estimate_richness(ps))
  }

  #Calculate Faith's PD

  if(!is.null(phy_tree(ps))){
    message("Computing Faith's PD using phy_tree().")

    if(!is.null(ps@sam_data$Faiths_PD)){
      message("Faith's PD already exists in sample_data() and will be overwritten.")
    }

    if(ps@otu_table@taxa_are_rows == FALSE){
      mat <- otu_table(ps)@.Data
    }else{
      mat <- t(otu_table(ps)@.Data)
    }

    tree <- phy_tree(ps)
    suppressWarnings(
      ps@sam_data$Faiths_PD <- pd(mat, phy_tree(ps), include.root=FALSE)$PD
    )

    if(sum(is.na(ps@sam_data$Faiths_PD)) > 0){
      message(paste0("There were ", sum(is.na(ps@sam_data$Faiths_PD)),
                     " samples where Faiths_PD = NA."))
    }
  }

  return(ps)
}




#' @title Creates a data.frame of pairwise distances from a \code{phyloseq} object.
#'
#' @description This function outputs a data.frame of pairwise distances from
#' each pair of samples contained in a \code{phyloseq} object.
#'
#' @param ps A \code{phyloseq} object that contains \code{\link[phyloseq]{sample_data}}.

#' @param distances A vector of distances metrics you want included.
#' Defaults to c("wuf", "uuf", "bray", "jsd", "jaccard").
#' If the distance matrix is alrady present in the global enviroment,
#' it will not calculate it again unless \code{force_distance_calculations} = TRUE.
#' It will also check to make sure the sample_names(ps) are found in the exsiting
#' distance matrix.
#'
#' @param force_distance_calculations (Logical)
#' Would you like the function to overwrite any distance matrices in the global enviroment?
#' Defaults to FALSE
#'
#' @param intragroup_only (Logical)
#' If you would like to restrict comparisions to within a group,
#' you can set this as TRUE (defaults to "Subject_ID") or you
#' can specify which column in \code{\link[phyloseq]{sample_variables}}.
#'
#' @param variables A vector of \code{\link[phyloseq]{sample_variables}}
#' that you would like compared in the output data.frame.
#' For each factor, it will make a column for each sample, as well as a
#' comparision column. For numerics, the comparison will be the absolute
#' value of the difference of the numeric. For factors, the comparison
#' will be if the two samples are the same or not.
#'
#'
#' @return This function returns a data.frame with every pair of samples and their
#' distance by several distance metrics. It can also output variables, as well as
#' comparisions between those variables for easy subsetting.
#'
#' @examples
#'
#' df <- make_distance_df(ps = ps)
#' df <- make_distance_df(ps = ps,
#'                        distances = c("jsd", "jaccard"),
#'                        intragroup_only = "Subject_ID",
#'                        variables = c("Country", "Age_Months"))

make_distance_df <- function(ps = ps,
                             distances = c("wuf", "uuf", "bray", "jsd", "jaccard"),
                             force_distance_calculations = FALSE,
                             intragroup_only = FALSE,
                             variables = NULL){

  if ( is.null(ps) | class(ps)[1] != "phyloseq"){
    message("phyloseq object not found or is not an object of class 'phyloseq'")
  }

  if(nsamples(ps) > 500){
    message(paste0("This function calulates the distance between all pairs of samples.
                   You've supplied a phyloseq object with ", nsamples(ps), " samples, meaning
                   the data.frame output will contain ", ((nsamples(ps)^2)/2) - nsamples(ps), " rows.
                   This could take a while." ))
  }


  if (force_distance_calculations == TRUE){
    rm(wuf_mat, uuf_mat, bray_mat, jsd_mat, jaccard_mat)
  }


  if ( "wuf" %in% distances){
    if( exists("wuf_mat") ){
      message("Weighted Unifrac Distance matrix found.")
      if ( !identical(colnames(wuf_mat), sample_names(ps)) ){
        message("Weighted Unifrac Distance matrix does not contain the
                same sample names as this phyloseq object.
                Recalculating the matrix.")
        wuf_mat <- as.matrix(phyloseq::distance(ps, method = "wunifrac"))
        assign("wuf_mat", wuf_mat, envir = .GlobalEnv)
      }
    } else {
      message("Weighted Unifrac Distance matrix not found. Calculating it now.")
      wuf_mat <- as.matrix(phyloseq::distance(ps, method = "wunifrac"))
      assign("wuf_mat", wuf_mat, envir = .GlobalEnv)
    }
  }


  if ( "uuf" %in% distances){
    if( exists("uuf_mat") ){
      message("Unweighted Unifrac Distance matrix found.")
      if ( !identical(colnames(uuf_mat), sample_names(ps)) ){
        message("Unweighted Unifrac Distance matrix does not contain the
                same sample names as this phyloseq object.
                Recalculating the matrix.")
        uuf_mat <- as.matrix(phyloseq::distance(ps, method = "uunifrac"))
        assign("uuf_mat", uuf_mat, envir = .GlobalEnv)
      }
    } else {
      message("Unweighted Unifrac Distance matrix not found. Calculating it now.")
      uuf_mat <- as.matrix(phyloseq::distance(ps, method = "uunifrac"))
      assign("uuf_mat", uuf_mat, envir = .GlobalEnv)
    }
  }


  if ( "bray" %in% distances){
    if( exists("bray_mat") ){
      message("Bray–Curtis dissimilarity matrix found.")
      if ( !identical(colnames(bray_mat), sample_names(ps)) ){
        message("Bray–Curtis dissimilarity matrix does not contain the
                same sample names as this phyloseq object.
                Recalculating the matrix.")
        bray_mat <- as.matrix(phyloseq::distance(ps, method = "bray"))
        assign("bray_mat", bray_mat, envir = .GlobalEnv)
      }
    } else {
      message("Bray–Curtis dissimilarity matrix not found. Calculating it now.")
      bray_mat <- as.matrix(phyloseq::distance(ps, method = "bray"))
      assign("bray_mat", bray_mat, envir = .GlobalEnv)
    }
  }


  if ( "jsd" %in% distances){
    if( exists("jsd_mat") ){
      message("Jensen-Shannon divergence matrix found.")
      if ( !identical(colnames(jsd_mat), sample_names(ps)) ){
        message("Jensen-Shannon divergence matrix does not contain the
                same sample names as this phyloseq object.
                Recalculating the matrix.")
        jsd_mat <- as.matrix(phyloseq::distance(ps, method = "jsd"))
        assign("jsd_mat", jsd_mat, envir = .GlobalEnv)
      }
    } else {
      message("Jensen-Shannon divergence matrix not found. Calculating it now.")
      jsd_mat <- as.matrix(phyloseq::distance(ps, method = "jsd"))
      assign("jsd_mat", jsd_mat, envir = .GlobalEnv)
    }
  }

  if ( "jaccard" %in% distances){
    if( exists("jaccard_mat") ){
      message("Jaccard index matrix found.")
      if ( !identical(colnames(jaccard_mat), sample_names(ps)) ){
        message("Jaccard index matrix does not contain the
                same sample names as this phyloseq object.
                Recalculating the matrix.")
        jaccard_mat <- as.matrix(phyloseq::distance(ps, method = "jaccard"))
        assign("jaccard_mat", jsd_mat, envir = .GlobalEnv)
      }
    } else {
      message("Jaccard index matrix not found. Calculating it now.")
      jaccard_mat <- as.matrix(phyloseq::distance(ps, method = "jaccard", binary = TRUE))
      assign("jaccard_mat", jsd_mat, envir = .GlobalEnv)
    }
  }


  # sample data look-up table
  sd <- data.frame(sample_data(ps))

  # set-up a pairwise comparision between every sample
  df <- data.frame(t(combn(as.character(sample_names(ps)),2)))
  colnames(df) <- c("sample1", "sample2")

  # filter comparisons if only doing intragroup comparisons
  if (intragroup_only != FALSE){
    if (intragroup_only == TRUE) {intragroup_only <- "Subject_ID"}

    if( intragroup_only %in% sample_variables(ps) ){
      message(paste0("Restricting comparsions to intragroup comparisons.
                     Grouping variable: ", intragroup_only))
      df$s1_SubID <- as.character(sd[match(df$sample1, rownames(sd)),intragroup_only])
      df$s2_SubID <- as.character(sd[match(df$sample2, rownames(sd)),intragroup_only])
      # trim to get only intra-subject samples:
      df <- df[which(df$s1_SubID == df$s2_SubID),]
      colnames(df)[3] <-"Subject_ID"
      df[4] <- NULL
    } else {
      message(paste0("Factor ", intragroup_only, " not found in sample_variables(ps)."))
    }
  }


  if (is.null(variables)){
    message("You can specify sample_variables(ps) that you'd like to compare using 'variables = c('x', 'y', 'z')'.")
  } else {

    for( var in variables){

      if (class(get_variable(ps, var)) == "numeric") {
        s1_var <- paste0("s1_", var)
        s2_var <- paste0("s2_", var)
        Abs_Dist_var <- paste0("Abs_Dist_", var)
        df[,s1_var] <- sd[match(df$sample1, rownames(sd)),var]
        df[,s2_var] <- sd[match(df$sample2, rownames(sd)),var]
        df[,Abs_Dist_var] <- as.numeric(abs(df[,s1_var] - df[,s2_var]))

      } else {
        s1_var <- paste0("s1_", var)
        s2_var <- paste0("s2_", var)
        same_var <- paste0("same_", var)
        df[,s1_var] <- sd[match(df$sample1, rownames(sd)),var]
        df[,s2_var] <- sd[match(df$sample2, rownames(sd)),var]
        df[,same_var] <- ifelse(df[,s1_var] == df[,s2_var],"yes", "no")
      }
    }
  }


  # Add distances
  for(dist in distances){
    dist_var <- paste0(dist, "_mat")
    df2 <- data.frame(cbind(match(df$sample1, rownames(get(dist_var))), match(df$sample2, colnames(get(dist_var)))))
    for( i in 1:dim(df)[1]){
      df[i , dist] <- get(dist_var)[df2[i,1], df2[i,2]]
    }
  }

  return(df)

}



