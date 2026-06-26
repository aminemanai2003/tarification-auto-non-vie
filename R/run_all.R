# =====================================================================
# run_all.R  --  Execution complete du pipeline de tarification
# ---------------------------------------------------------------------
# Lance dans l'ordre les 8 etapes du projet et genere toutes les
# figures et tables dans output/.
#   Usage :  Rscript R/run_all.R
# =====================================================================

t0 <- Sys.time()
rdir <- dirname(normalizePath(sub("^--file=", "",
          commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]),
          winslash = "/", mustWork = FALSE))

source(file.path(rdir, "00_config.R"))

etapes <- c("01_data_prep.R", "02_eda.R", "03_frequence.R", "04_cout.R",
            "05_prime_pure_glm.R", "06_prime_commerciale.R",
            "07_provisionnement.R", "08_reassurance.R")

for (e in etapes) {
  cat("\n>>>>>>>>>> ", e, " <<<<<<<<<<\n")
  source(file.path(rdir, e))
}

cat(sprintf("\n=== PIPELINE TERMINE en %.1f min ===\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
cat("Figures :", DIR_FIG, "\nTables  :", DIR_TAB, "\n")
