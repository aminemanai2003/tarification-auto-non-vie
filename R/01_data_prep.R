# =====================================================================
# 01_data_prep.R  --  Preparation et fiabilisation de la base
# ---------------------------------------------------------------------
# "La preparation des donnees represente 80% du temps" (cours Tarification).
# On rapproche la base CONTRATS (freMTPL2freq) et la base SINISTRES
# (freMTPL2sev), on fiabilise, et on cree des variables tarifaires.
# =====================================================================

# --- bootstrap : charge la config si pas deja fait --------------------
if (!exists("PROJ")) {
  .a <- commandArgs(FALSE); .f <- .a[grep("^--file=", .a)]
  .rdir <- if (length(.f))
    dirname(normalizePath(sub("^--file=", "", .f[1]), winslash = "/", mustWork = FALSE)) else "R"
  source(file.path(.rdir, "00_config.R"))
}

cat("\n========== 01 - PREPARATION DES DONNEES ==========\n")

# --- 1) Chargement des deux bases ------------------------------------
data(freMTPL2freq); data(freMTPL2sev)
freq <- as.data.table(freMTPL2freq)   # 1 ligne = 1 contrat (police)
sev  <- as.data.table(freMTPL2sev)    # 1 ligne = 1 sinistre

cat(sprintf("Base contrats : %d polices, %d variables\n", nrow(freq), ncol(freq)))
cat(sprintf("Base sinistres: %d sinistres\n", nrow(sev)))

# --- 2) Fiabilisation de la base contrats ----------------------------
# Anomalies connues du jeu freMTPL2 (cf. litterature Wuthrich) :
#   - Exposure parfois > 1  -> on plafonne a 1 an
#   - Exposure nulle/negative -> a retirer
#   - ClaimNb aberrant (tres rare) -> on plafonne a 4
n0 <- nrow(freq)
freq <- freq[Exposure > 0]
freq[Exposure > 1, Exposure := 1]
freq[ClaimNb > 4, ClaimNb := 4]
cat(sprintf("Nettoyage exposition : %d lignes retirees (Exposure<=0)\n", n0 - nrow(freq)))

# --- 3) Agregation des sinistres au niveau police --------------------
sev_agg <- sev[, .(ChargeTot = sum(ClaimAmount),
                   NbSinSev  = .N), by = IDpol]

# --- 4) Rapprochement contrats <-> sinistres -------------------------
freq <- merge(freq, sev_agg, by = "IDpol", all.x = TRUE)
freq[is.na(ChargeTot), ChargeTot := 0]
freq[is.na(NbSinSev),  NbSinSev  := 0]

# --- 5) Creation des variables tarifaires (discretisation) -----------
# Regroupement de modalites / discretisation des variables continues
# (cf. cours : "recodage des variables").
freq[, DrivAgeBand := cut(DrivAge,
        breaks = c(17, 22, 26, 42, 74, Inf),
        labels = c("18-22","23-26","27-42","43-74","75+"), right = TRUE)]
freq[, VehAgeBand := cut(VehAge,
        breaks = c(-1, 0, 5, 12, Inf),
        labels = c("0","1-5","6-12","13+"))]
freq[, VehPowerBand := cut(VehPower,
        breaks = c(0, 5, 7, 9, Inf),
        labels = c("<=5","6-7","8-9","10+"))]
freq[, BonusMalusBand := cut(BonusMalus,
        breaks = c(0, 50, 60, 90, Inf),
        labels = c("50","51-60","61-90","91+"))]
freq[, DensityBand := cut(Density,
        breaks = quantile(Density, c(0, .25, .5, .75, 1)),
        labels = c("Q1","Q2","Q3","Q4"), include.lowest = TRUE)]
freq[, VehGas := factor(VehGas)]
freq[, Area   := factor(Area)]
freq[, VehBrand := factor(VehBrand)]

# --- 6) Base sinistres enrichie (pour la modelisation du cout) -------
# On rattache a chaque sinistre les caracteristiques de sa police.
claims <- merge(sev, freq[, .(IDpol, DrivAgeBand, VehAgeBand, VehPowerBand,
                              BonusMalusBand, DensityBand, VehGas, Area,
                              VehBrand, Region)],
                by = "IDpol")
claims <- claims[ClaimAmount > 0]
claims[, Grave := ClaimAmount >= SEUIL_GRAVE]

cat(sprintf("Sinistres rattaches a une police : %d\n", nrow(claims)))
cat(sprintf("dont graves (>= %s EUR) : %d (%.2f%%)\n",
            format(SEUIL_GRAVE, big.mark=" "), sum(claims$Grave),
            100*mean(claims$Grave)))

# --- 7) Indicateurs portefeuille (rappel modele de l'assurance) ------
expo_tot  <- sum(freq$Exposure)
nb_sin    <- sum(freq$ClaimNb)
charge_tot<- sum(freq$ChargeTot)
kpi_portef <- data.table(
  Indicateur = c("Exposition (annees-risque)", "Nombre de sinistres",
                 "Charge totale (EUR)", "Frequence (sin/an)",
                 "Cout moyen (EUR)", "Prime pure empirique (EUR)"),
  Valeur = c(format(round(expo_tot), big.mark = " "),
             format(nb_sin, big.mark = " "),
             format(round(charge_tot), big.mark = " "),
             format(round(nb_sin/expo_tot, 4)),
             format(round(charge_tot/nb_sin, 1), big.mark = " "),
             format(round(charge_tot/expo_tot, 2))))
print(kpi_portef)

# --- 8) Sauvegardes --------------------------------------------------
save_rds(freq,       "policies")
save_rds(claims,     "claims")
save_tab(kpi_portef, "01_kpi_portefeuille")

cat("[01] OK - bases sauvegardees (policies.rds, claims.rds)\n")
