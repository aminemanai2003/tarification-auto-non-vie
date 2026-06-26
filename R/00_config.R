# =====================================================================
# 00_config.R  --  Configuration globale du projet
# Projet : Construction d'un tarif d'assurance automobile (RC + dommages)
# Projet personnel d'actuariat non-vie
# ---------------------------------------------------------------------
# Ce script est source() par tous les autres. Il :
#   - charge les packages,
#   - determine la racine du projet,
#   - cree l'arborescence de sortie,
#   - definit les parametres metier (seuils, chargements...),
#   - fournit quelques fonctions utilitaires.
# =====================================================================

suppressWarnings(suppressMessages({
  library(CASdatasets)   # donnees freMTPL2 (RC auto France)
  library(data.table)    # manipulation rapide
  library(dplyr)         # verbes de manipulation
  library(ggplot2)       # graphiques
  library(MASS)          # glm.nb, fitdistr
  library(fitdistrplus)  # ajustement de lois + tests
  library(actuar)        # lois actuarielles (Pareto...)
  library(ChainLadder)   # provisionnement (Mack)
}))

# --- Racine du projet (robuste : deduite du fichier appelant) --------
.get_proj_root <- function() {
  args <- commandArgs(FALSE)
  file_arg <- args[grep("^--file=", args)]
  if (length(file_arg) > 0) {
    rdir <- dirname(normalizePath(sub("^--file=", "", file_arg[1]),
                                  winslash = "/", mustWork = FALSE))
    return(dirname(rdir))            # parent du dossier R/
  }
  # fallback (mode interactif) : on suppose un lancement depuis la racine
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}
# .PROJ_OVERRIDE permet de forcer la racine (utile lors du knit du rapport)
PROJ <- if (exists(".PROJ_OVERRIDE")) get(".PROJ_OVERRIDE") else .get_proj_root()

DIR_FIG     <- file.path(PROJ, "output", "figures")
DIR_TAB     <- file.path(PROJ, "output", "tables")
DIR_DERIVED <- file.path(PROJ, "output", "derived")
for (d in c(DIR_FIG, DIR_TAB, DIR_DERIVED)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

# --- Parametres metier ------------------------------------------------
SEUIL_GRAVE   <- 10000   # seuil des sinistres "graves" (en euros)
CHARGE_FRAIS  <- 0.20    # tau : chargement frais de gestion / commissions
CHARGE_SECU   <- 0.05    # alpha : chargement de securite
TAUX_TAXE     <- 0.15    # taxe sur les conventions d'assurance (indicatif)

# Traite de reassurance non proportionnelle (Excess of Loss)
REA_PRIORITE  <- 50000   # priorite / retention de la cedante
REA_PORTEE    <- 1e6     # portee (limite au-dela de la priorite)

set.seed(2026)           # reproductibilite

# --- Fonctions utilitaires -------------------------------------------

# Sauvegarde standardisee d'un ggplot
save_fig <- function(plot, name, w = 8, h = 5) {
  path <- file.path(DIR_FIG, paste0(name, ".png"))
  ggsave(path, plot = plot, width = w, height = h, dpi = 110, bg = "white")
  invisible(path)
}

# Sauvegarde standardisee d'une table
save_tab <- function(df, name) {
  path <- file.path(DIR_TAB, paste0(name, ".csv"))
  fwrite(as.data.table(df), path)
  invisible(path)
}

# Lecture / ecriture d'objets intermediaires
save_rds <- function(obj, name) saveRDS(obj, file.path(DIR_DERIVED, paste0(name, ".rds")))
load_rds <- function(name)      readRDS(file.path(DIR_DERIVED, paste0(name, ".rds")))

# Test d'adequation du Khi-deux "fait main" (conforme au cours :
# regroupement des classes < 5, ddl = nb classes - 1 - nb parametres estimes)
khi2_adequation <- function(obs_counts, prob_theo, n_params) {
  N <- sum(obs_counts)
  expected <- prob_theo * N
  # regroupement des classes d'effectif theorique < 5 (par la fin)
  o <- obs_counts; e <- expected
  while (length(e) > 2 && e[length(e)] < 5) {
    e[length(e) - 1] <- e[length(e) - 1] + e[length(e)]
    o[length(o) - 1] <- o[length(o) - 1] + o[length(o)]
    e <- e[-length(e)]; o <- o[-length(o)]
  }
  D  <- sum((o - e)^2 / e)
  ddl <- length(e) - 1 - n_params
  pval <- pchisq(D, df = ddl, lower.tail = FALSE)
  list(D = D, ddl = ddl, pvalue = pval,
       seuil_5pct = qchisq(0.95, ddl),
       decision = ifelse(D > qchisq(0.95, ddl),
                         "Rejet de H0 (loi non adequate)",
                         "Non rejet de H0 (loi adequate)"))
}

# Theme graphique homogene
theme_set(theme_minimal(base_size = 12))
PALETTE <- c("#1F3864", "#C00000", "#70AD47", "#ED7D31", "#7F7F7F")

cat("[00_config] Projet :", PROJ, "\n")
cat("[00_config] Packages charges, parametres definis.\n")
