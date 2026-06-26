# =====================================================================
# 02_eda.R  --  Analyse exploratoire / etudes univariees
# ---------------------------------------------------------------------
# Identification des variables discriminantes par croisement avec la
# variable a expliquer (frequence / cout), cf. cours Tarification.
# =====================================================================

if (!exists("PROJ")) {
  .a <- commandArgs(FALSE); .f <- .a[grep("^--file=", .a)]
  .rdir <- if (length(.f))
    dirname(normalizePath(sub("^--file=", "", .f[1]), winslash = "/", mustWork = FALSE)) else "R"
  source(file.path(.rdir, "00_config.R"))
}
cat("\n========== 02 - ANALYSE EXPLORATOIRE ==========\n")

policies <- load_rds("policies")
claims   <- load_rds("claims")

# Fonction : frequence empirique par modalite d'un facteur
freq_par_facteur <- function(dt, var) {
  dt[, .(Exposition = sum(Exposure),
         Sinistres  = sum(ClaimNb),
         Frequence  = sum(ClaimNb) / sum(Exposure)),
     by = var][order(get(var))]
}

# --- 1) Frequence par facteur (les plus parlants) --------------------
for (v in c("DrivAgeBand","BonusMalusBand","VehAgeBand","VehPowerBand",
            "VehGas","Area","DensityBand")) {
  tab <- freq_par_facteur(policies, v)
  save_tab(tab, paste0("02_freq_", v))
  g <- ggplot(tab, aes(x = get(v), y = Frequence)) +
    geom_col(fill = PALETTE[1]) +
    geom_hline(yintercept = sum(policies$ClaimNb)/sum(policies$Exposure),
               linetype = "dashed", colour = PALETTE[2]) +
    labs(title = paste("Frequence empirique par", v),
         subtitle = "Ligne rouge = frequence moyenne portefeuille",
         x = v, y = "Frequence (sinistres / annee-risque)")
  save_fig(g, paste0("02_freq_", v))
}

# --- 2) Cout moyen par facteur ---------------------------------------
cout_par_facteur <- function(dt, var) {
  dt[, .(NbSin = .N, CoutMoyen = mean(ClaimAmount),
         Mediane = median(ClaimAmount)), by = var][order(get(var))]
}
for (v in c("DrivAgeBand","VehAgeBand","VehGas","Area")) {
  tab <- cout_par_facteur(claims[Grave == FALSE], v)   # sur attritionnels
  save_tab(tab, paste0("02_cout_", v))
}

# --- 3) Distribution du cout des sinistres ---------------------------
g_cout <- ggplot(claims, aes(x = ClaimAmount)) +
  geom_histogram(bins = 60, fill = PALETTE[3], colour = "white") +
  scale_x_log10(labels = scales::comma) +
  geom_vline(xintercept = SEUIL_GRAVE, linetype = "dashed", colour = PALETTE[2]) +
  labs(title = "Distribution du cout des sinistres (echelle log)",
       subtitle = paste("Ligne rouge = seuil des graves =", SEUIL_GRAVE, "EUR"),
       x = "Cout du sinistre (EUR, log10)", y = "Effectif")
save_fig(g_cout, "02_distribution_cout")

# --- 4) Distribution du nombre de sinistres par contrat --------------
tab_nb <- policies[, .N, by = ClaimNb][order(ClaimNb)]
tab_nb[, Proportion := round(N / sum(N), 5)]
save_tab(tab_nb, "02_distribution_nbsin")
g_nb <- ggplot(tab_nb, aes(x = factor(ClaimNb), y = N)) +
  geom_col(fill = PALETTE[1]) +
  scale_y_log10(labels = scales::comma) +
  labs(title = "Distribution du nombre de sinistres par contrat",
       x = "Nombre de sinistres", y = "Nombre de contrats (log10)")
save_fig(g_nb, "02_distribution_nbsin")

# --- 5) Test de liaison (Kruskal-Wallis) cout ~ facteur --------------
# Conforme au cours : "tests de liaison (Kruskal-Wallis...)".
kw <- data.table(
  Facteur = c("DrivAgeBand","VehAgeBand","VehGas","Area"),
  pvalue  = sapply(c("DrivAgeBand","VehAgeBand","VehGas","Area"),
            function(v) kruskal.test(ClaimAmount ~ get(v),
                                     data = claims[Grave == FALSE])$p.value))
kw[, Lien_significatif := ifelse(pvalue < 0.05, "Oui", "Non")]
save_tab(kw, "02_kruskal_wallis")
print(kw)

cat("[02] OK - figures et tables exploratoires generees\n")
