#' @title Sparse estimation of distance correlations among microbiomes
#'
#' @description Obtain the sparse correlation matrix for distance correlations
#' between taxa.
#'
#' @details The \href{https://doi.org/10.1214/009053607000000505}{distance correlation},
#' which is a measure of dependence between two random variables, can be used to
#' quantify any dependence, whether linear, monotonic, non-monotonic or
#' nonlinear relationships.
#'
#' @param data a list of the input data. Each element of the list can be a
#' \code{phyloseq}, \code{SummarizedExperiment}, or
#' \code{TreeSummarizedExperiment} object, which consists of
#' a feature table (microbial count table), a sample metadata, a
#' taxonomy table (optional), and a phylogenetic tree (optional). The row names
#' of the metadata must match the sample names of the feature table, and the
#' row names of the taxonomy table must match the taxon (feature) names of the
#' feature table. See \code{?phyloseq::phyloseq},
#' \code{?SummarizedExperiment::SummarizedExperiment}, or
#' \code{?TreeSummarizedExperiment::TreeSummarizedExperiment} for more details.
#' It is highly recommended that the input data
#' are in low taxonomic levels, such as OTU or species level, as the estimation
#' of sampling fractions requires a large number of taxa.
#' For multiple ecosystems, simply stack the data. For example, for two
#' ecosystems, such as gut and tongue, specify the list of input data as
#' \code{data = list(gut = tse1, tongue = tse2)}.
#' @param assay_name character. Name of the count table in the data object
#' (only applicable if data object is a \code{(Tree)SummarizedExperiment}).
#' Default is "counts".
#' See \code{?SummarizedExperiment::assay} for more details.
#' @param tax_level character. The taxonomic level of interest. The input data
#' can be agglomerated at different taxonomic levels based on your research
#' interest. Default is NULL, i.e., do not perform agglomeration, and the
#' SECOM anlysis will be performed at the lowest taxonomic level of the
#' input \code{data}.
#' @param pseudo numeric. Add pseudo-counts to the data.
#' Default is 0 (no pseudo-counts).
#' @param prv_cut a numerical fraction between 0 and 1. Taxa with prevalences
#' less than \code{prv_cut} will be excluded in the analysis. For instance,
#' suppose there are 100 samples, if a taxon has nonzero counts presented in
#' less than 10 samples, it will not be further analyzed. Default is 0.50.
#' @param lib_cut a numerical threshold for filtering samples based on library
#' sizes. Samples with library sizes less than \code{lib_cut} will be
#' excluded in the analysis. Default is 1000.
#' @param corr_cut numeric. To prevent false positives due to taxa with
#' small variances, taxa with Pearson correlation coefficients greater than
#' \code{corr_cut} with the estimated sample-specific bias will be flagged.
#' The pairwise correlation coefficient between flagged taxa will be set to 0s.
#' Default is 0.5.
#' @param wins_quant a numeric vector of probabilities with values between
#' 0 and 1. Replace extreme values in the abundance data with less
#' extreme values. Default is \code{c(0.05, 0.95)}. For details,
#' see \code{?DescTools::Winsorize}.
#' @param R numeric. The number of replicates in calculating the p-value for
#' distance correlation. For details, see \code{?energy::dcor.test}.
#' Default is 1000.
#' @param thresh_hard Numeric. Set a hard threshold for the correlation matrix.
#' Pairwise distance correlation less than or equal to \code{thresh_hard}
#' will be set to 0. Default is 0 (No ad-hoc hard thresholding).
#' @param max_p numeric. Obtain the sparse correlation matrix by
#' p-value filtering. Pairwise correlation coefficient with p-value greater than
#' \code{max_p} will be set to 0. Default is 0.005.
#' @param n_cl numeric. The number of nodes to be forked. For details, see
#' \code{?parallel::makeCluster}. Default is 1 (no parallel computing).
#'
#' @return a \code{list} with components:
#'         \itemize{
#'         \item{ \code{s_diff_hat}, a numeric vector of estimated
#'         sample-specific biases.}
#'         \item{ \code{y_hat}, a matrix of bias-corrected abundances}
#'         \item{ \code{mat_cooccur}, a matrix of taxon-taxon co-occurrence
#'         pattern. The number in each cell represents the number of complete
#'         (nonzero) samples for the corresponding pair of taxa.}
#'         \item{ \code{dcorr}, the sample distance correlation matrix
#'         computed using the bias-corrected abundances \code{y_hat}.}
#'         \item{ \code{dcorr_p}, the p-value matrix corresponding to the sample
#'         distance correlation matrix \code{dcorr}.}
#'         \item{ \code{dcorr_fl}, the sparse correlation matrix obtained by
#'         p-value filtering based on the cutoff specified in \code{max_p}.}
#'         }
#'
#' @seealso \code{\link{secom_linear}}
#'
#' @examples
#' library(ANCOMBC)
#' data(dietswap, package = "microbiome")
#' tse = mia::makeTreeSummarizedExperimentFromPhyloseq(dietswap)
#'
#' # subset to baseline
#' tse = tse[, tse$timepoint == 1]
#'
#' set.seed(123)
#' res_dist = secom_dist(data = list(tse), assay_name = "counts",
#'                       tax_level = "Phylum", pseudo = 0,
#'                       prv_cut = 0.5, lib_cut = 1000, corr_cut = 0.5,
#'                       wins_quant = c(0.05, 0.95), R = 1000,
#'                       thresh_hard = 0.3, max_p = 0.005, n_cl = 2)
#'
#' dcorr_fl = res_dist$dcorr_fl
#'
#' @author Huang Lin
#'
#' @importFrom mia makeTreeSummarizedExperimentFromPhyloseq taxonomyRanks agglomerateByRank
#' @importFrom SingleCellExperiment altExp
#' @importFrom SummarizedExperiment assay colData rowData
#' @importFrom TreeSummarizedExperiment TreeSummarizedExperiment
#' @importFrom S4Vectors DataFrame SimpleList
#' @importFrom energy dcor dcor.test
#' @importFrom parallel makeCluster stopCluster
#' @importFrom foreach foreach %dopar% registerDoSEQ
#' @importFrom doParallel registerDoParallel
#' @importFrom doRNG %dorng%
#' @importFrom dplyr filter bind_rows left_join right_join
#' @importFrom tidyr pivot_longer
#' @importFrom tibble rownames_to_column
#' @importFrom Hmisc rcorr
#' @importFrom DescTools Winsorize
#' @importFrom magrittr %>%
#' @importFrom rlang .data
#' @importFrom Rdpack reprompt
#'
#' @export
secom_dist = function(data, assay_name = "counts", tax_level = NULL,
                      pseudo = 0, prv_cut = 0.5, lib_cut = 1000,
                      corr_cut = 0.5, wins_quant = c(0.05, 0.95), R = 1000,
                      thresh_hard = 0, max_p = 0.005, n_cl = 1) {
    # ===========Sampling fraction and absolute abundance estimation============
    if (length(data) == 1) {
        tse_obj = tse_construct(data = data[[1]], assay_name = assay_name[1],
                                tax_level = tax_level[1], phyloseq = NULL)
        abn_list = abn_est(tse = tse_obj$tse, tax_level = tse_obj$tax_level,
                           assay_name = tse_obj$assay_name, pseudo = pseudo,
                           prv_cut = prv_cut, lib_cut = lib_cut)
        s_diff_hat = abn_list$s_diff_hat
        y_hat = abn_list$y_hat
    } else {
        if (is.null(names(data))) names(data) = paste0("data", seq_along(data))

        # Check common samples
        samp_names = lapply(data, function(x) colnames(x))
        samp_common = Reduce(intersect, samp_names)
        samp_txt = sprintf(paste0("The number of samples in common ",
                                  "across datasets: ",
                                  length(samp_common)))
        message(samp_txt)
        if (length(samp_common) < 10) {
            stop_txt = paste0("The number of common samples is too small. ",
                              "Multi-dataset computation is not recommended.")
            stop(stop_txt)
        }

        # Rename taxa
        tse_list = lapply(seq_along(data), function(i) {
            tse_obj = tse_construct(data = data[[i]], assay_name = assay_name[i],
                                    tax_level = tax_level[i], phyloseq = NULL)
            return(tse_obj)
        })

        for (i in seq_along(tse_list)) {
            rownames(SingleCellExperiment::altExp(tse_list[[i]]$tse,
                                                  tse_list[[i]]$tax_level)) =
                paste(names(data)[[i]],
                      rownames(SingleCellExperiment::altExp(tse_list[[i]]$tse,
                                                            tse_list[[i]]$tax_level)),
                      sep = " - ")
        }

        abn_list = lapply(seq_along(tse_list), function(i) {
            abn_est(tse = tse_list[[i]]$tse,
                    tax_level = tse_list[[i]]$tax_level,
                    assay_name = assay_name[i], pseudo = pseudo,
                    prv_cut = prv_cut, lib_cut = lib_cut)
        })
        s_diff_hat = lapply(abn_list, function(x) x$s_diff_hat)
        y_hat = dplyr::bind_rows(lapply(abn_list, function(x)
            as.data.frame(x$y_hat)))
        y_hat = as.matrix(y_hat)
    }

    # ================Sparse estimation on distance correlations================
    if (n_cl > 1) {
      cl = parallel::makeCluster(n_cl)
      doParallel::registerDoParallel(cl)
    } else {
      foreach::registerDoSEQ()
    }

    res_corr = sparse_dist(mat = t(y_hat), wins_quant, R, thresh_hard, max_p)

    if (n_cl > 1) {
      parallel::stopCluster(cl)
    }

    # To prevent FP from taxa with extremely small variances
    if (length(data) == 1) {
        corr_s = cor(cbind(s_diff_hat, t(y_hat)),
                     use = "pairwise.complete.obs")[1, -1]
        fp_ind1 = replicate(nrow(y_hat), corr_s > corr_cut)
        fp_ind2 = t(replicate(nrow(y_hat), corr_s > corr_cut))
        fp_ind = (fp_ind1 * fp_ind2 == 1)
        diag(fp_ind) = FALSE
        res_corr$dcorr[fp_ind] = 0
        res_corr$dcorr_fl[fp_ind] = 0
        res_corr$dcorr_p[fp_ind] = 1
    } else {
        for (i in seq_along(data)) {
            df_s = data.frame(s = s_diff_hat[[i]]) %>%
                tibble::rownames_to_column("sample_id")
            df_y = as.data.frame(t(y_hat)) %>%
                tibble::rownames_to_column("sample_id")
            df_merge = df_s %>%
                dplyr::right_join(df_y, by = "sample_id") %>%
                dplyr::select(-.data$sample_id)
            corr_s = cor(df_merge, use = "pairwise.complete.obs")[1, -1]
            fp_ind1 = replicate(nrow(y_hat), corr_s > corr_cut)
            fp_ind2 = t(replicate(nrow(y_hat), corr_s > corr_cut))
            fp_ind = (fp_ind1 * fp_ind2 == 1)
            diag(fp_ind) = FALSE
            res_corr$dcorr[fp_ind] = 0
            res_corr$dcorr_fl[fp_ind] = 0
            res_corr$dcorr_p[fp_ind] = 1
        }
    }

    # ==================================Outputs=================================
    res = c(list(s_diff_hat = s_diff_hat, y_hat = y_hat), res_corr)
    return(res)
}
