# =====================================================================
# 07_provisionnement.R  --  Provisionnement (cours S4)
# ---------------------------------------------------------------------
# Le jeu freMTPL2 ne contient pas de dimension de DEROULEMENT des
# sinistres. On illustre donc l'evaluation des provisions pour sinistres
# sur un TRIANGLE DE LIQUIDATION standard (paiements cumules) :
#   - methode deterministe CHAIN-LADDER (implementee a la main)
#   - modele stochastique de MACK (erreur de prediction, via package)
# =====================================================================

if (!exists("PROJ")) {
  .a <- commandArgs(FALSE); .f <- .a[grep("^--file=", .a)]
  .rdir <- if (length(.f))
    dirname(normalizePath(sub("^--file=", "", .f[1]), winslash = "/", mustWork = FALSE)) else "R"
  source(file.path(.rdir, "00_config.R"))
}
cat("\n========== 07 - PROVISIONNEMENT ==========\n")

# --- Triangle de liquidation (paiements cumules) ---------------------
data(GenIns)                 # triangle classique (Taylor & Ashe)
tri <- GenIns / 1000         # en milliers d'euros
n <- ncol(tri)

# --- 1) Facteurs de developpement (age-to-age) -----------------------
#     f_j = somme_i C[i,j+1] / somme_i C[i,j]
f <- sapply(1:(n - 1), function(j) {
  sum(tri[1:(n - j), j + 1], na.rm = TRUE) / sum(tri[1:(n - j), j], na.rm = TRUE)
})
cat("Facteurs de developpement Chain-Ladder :\n")
print(round(f, 4))

# --- 2) Completion du triangle inferieur -----------------------------
full <- as.matrix(tri)
for (i in 2:n) {
  for (j in (n - i + 2):n) {
    if (is.na(full[i, j])) full[i, j] <- full[i, j - 1] * f[j - 1]
  }
}

# --- 3) Ultime, dernier paiement connu, provision (IBNR) -------------
ult    <- full[, n]
latest <- sapply(1:n, function(i) tri[i, n - i + 1])
reserve<- ult - latest

res_cl <- data.table(
  Annee_origine = 1:n,
  Paye_a_ce_jour = round(latest),
  Charge_ultime  = round(ult),
  Provision_CL   = round(reserve))
save_tab(res_cl, "07_chain_ladder")
print(res_cl)
cat(sprintf(">> Provision totale Chain-Ladder : %s milliers EUR\n",
            format(round(sum(reserve)), big.mark = " ")))

# --- 4) Modele de Mack : erreur de prediction ------------------------
mack <- MackChainLadder(tri, est.sigma = "Mack")
mack_by <- summary(mack)$ByOrigin
mack_tot<- summary(mack)$Totals
ibnr_tot<- mack_tot["IBNR", ]
se_tot  <- mack_tot["Mack S.E.", ]
cov_tot <- 100 * se_tot / ibnr_tot
cat(sprintf("Modele de Mack : IBNR total = %s | Mack S.E. = %s | CoV = %.1f%%\n",
            format(round(ibnr_tot), big.mark=" "),
            format(round(se_tot),   big.mark=" "), cov_tot))

mack_dt <- data.table(
  Annee_origine = 1:n,
  IBNR     = round(mack_by[, "IBNR"]),
  Mack_SE  = round(mack_by[, "Mack.S.E"]),
  CoV_pct  = round(100 * mack_by[, "Mack.S.E"] / pmax(mack_by[, "IBNR"], 1e-9), 1))
save_tab(mack_dt, "07_mack")

# --- 5) Graphique : provisions par annee d'origine -------------------
g_res <- ggplot(res_cl[Annee_origine > 1],
                aes(factor(Annee_origine), Provision_CL)) +
  geom_col(fill = PALETTE[1]) +
  labs(title = "Provisions pour sinistres par annee d'origine (Chain-Ladder)",
       subtitle = "Triangle de liquidation - paiements cumules",
       x = "Annee d'origine", y = "Provision (milliers EUR)")
save_fig(g_res, "07_provisions_chain_ladder")

# Graphique de developpement (paiements cumules par annee d'origine)
dev_long <- CJ(origine = 1:n, dev = 1:n)
dev_long[, cumul := full[cbind(origine, dev)]]
g_dev <- ggplot(dev_long, aes(dev, cumul, colour = factor(origine))) +
  geom_line() +
  labs(title = "Developpement des paiements cumules",
       x = "Annee de developpement", y = "Paiements cumules (milliers EUR)",
       colour = "Origine")
save_fig(g_dev, "07_developpement")

save_rds(list(reserve_cl = sum(reserve), ibnr_mack = ibnr_tot,
              se_mack = se_tot, cov = cov_tot), "params_provisions")

cat("[07] OK - provisions estimees (Chain-Ladder + Mack)\n")
