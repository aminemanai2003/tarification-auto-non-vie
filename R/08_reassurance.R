# =====================================================================
# 08_reassurance.R  --  Reassurance non proportionnelle + proxy de capital
# ---------------------------------------------------------------------
# Traite EXCESS-OF-LOSS (XS) : la cedante conserve les sinistres jusqu'a
# une PRIORITE, le reassureur prend la tranche au-dela (dans la limite
# de la PORTEE). On mesure :
#   - la cession (charge cedee / retenue, taux de cession)
#   - la reduction de volatilite et d'un proxy VaR 99,5% - moyenne
# =====================================================================

if (!exists("PROJ")) {
  .a <- commandArgs(FALSE); .f <- .a[grep("^--file=", .a)]
  .rdir <- if (length(.f))
    dirname(normalizePath(sub("^--file=", "", .f[1]), winslash = "/", mustWork = FALSE)) else "R"
  source(file.path(.rdir, "00_config.R"))
}
cat("\n========== 08 - REASSURANCE (XS) ==========\n")

claims <- load_rds("claims")
prio <- REA_PRIORITE; port <- REA_PORTEE

# --- 1) Decoupage sinistre par sinistre ------------------------------
claims[, Cede   := pmin(pmax(ClaimAmount - prio, 0), port)]
claims[, Retenu := ClaimAmount - Cede]

charge_brute  <- sum(claims$ClaimAmount)
charge_cedee  <- sum(claims$Cede)
charge_retenue<- sum(claims$Retenu)
nb_touches    <- sum(claims$Cede > 0)

kpi_rea <- data.table(
  Indicateur = c("Priorite (retention)", "Portee",
                 "Charge brute (EUR)", "Charge retenue (EUR)",
                 "Charge cedee au reassureur (EUR)", "Taux de cession",
                 "Nb sinistres touchant le traite",
                 "Sinistre max brut (EUR)", "Sinistre max retenu (EUR)"),
  Valeur = c(format(prio, big.mark=" ", scientific=FALSE),
             format(port, big.mark=" ", scientific=FALSE),
             format(round(charge_brute), big.mark=" "),
             format(round(charge_retenue), big.mark=" "),
             format(round(charge_cedee), big.mark=" "),
             sprintf("%.2f%%", 100*charge_cedee/charge_brute),
             nb_touches,
             format(round(max(claims$ClaimAmount)), big.mark=" "),
             format(round(max(claims$Retenu)), big.mark=" ")))
save_tab(kpi_rea, "08_kpi_reassurance")
print(kpi_rea)

# --- 2) Simulation de la charge annuelle agregee (brute vs nette) ----
# Modele collectif : N ~ Poisson(lambda), couts tires de l'empirique.
set.seed(2026)
S <- 2000
lambda_agg <- nrow(claims)              # nb annuel de sinistres du portefeuille
sev_all <- claims$ClaimAmount
agg_brut <- numeric(S); agg_net <- numeric(S)
for (s in 1:S) {
  ni <- rpois(1, lambda_agg)
  x  <- sev_all[sample.int(length(sev_all), ni, replace = TRUE)]
  ced <- pmin(pmax(x - prio, 0), port)
  agg_brut[s] <- sum(x)
  agg_net[s]  <- sum(x - ced)
}

var995 <- function(z) quantile(z, 0.995)
capital_proxy <- function(z) var995(z) - mean(z)  # VaR99.5 - moyenne

tab_solva <- data.table(
  Mesure = c("Charge moyenne (EUR)", "Ecart-type (EUR)",
             "VaR 99,5% (EUR)", "Proxy de capital (VaR99,5 - moyenne)"),
  Brut = c(round(mean(agg_brut)), round(sd(agg_brut)),
           round(var995(agg_brut)), round(capital_proxy(agg_brut))),
  Net_de_reassurance = c(round(mean(agg_net)), round(sd(agg_net)),
           round(var995(agg_net)), round(capital_proxy(agg_net))))
tab_solva[, Reduction := sprintf("%.1f%%", 100*(1 - Net_de_reassurance/Brut))]
save_tab(tab_solva, "08_solvabilite")
cat("\n--- Impact sur la charge annuelle agregee ---\n")
print(tab_solva)
cat(sprintf(">> Le traite XS reduit le proxy de capital de %.1f%%.\n",
            100*(1 - capital_proxy(agg_net)/capital_proxy(agg_brut))))

# --- 3) Graphique : effet du traite sur les gros sinistres -----------
gros <- claims[ClaimAmount >= prio][order(-ClaimAmount)][1:min(.N, 200)]
gros_long <- rbind(
  data.table(rang = 1:nrow(gros), montant = gros$Retenu, part = "Retenu (cedante)"),
  data.table(rang = 1:nrow(gros), montant = gros$Cede,   part = "Cede (reassureur)"))
g_xs <- ggplot(gros_long, aes(rang, montant, fill = part)) +
  geom_col() +
  scale_fill_manual(values = PALETTE[c(1,2)]) +
  labs(title = "Partage des plus gros sinistres (traite XS)",
       subtitle = paste0("Priorite = ", format(prio, big.mark=" "),
                         " EUR, portee = ", format(port, big.mark=" "), " EUR"),
       x = "Sinistres classes par taille decroissante",
       y = "Montant (EUR)", fill = NULL)
save_fig(g_xs, "08_partage_xs")

# --- 4) Graphique : distribution de la charge agregee ----------------
agg_dt <- rbind(
  data.table(charge = agg_brut, type = "Brut"),
  data.table(charge = agg_net,  type = "Net de reassurance"))
g_agg <- ggplot(agg_dt, aes(charge/1e6, fill = type)) +
  geom_density(alpha = .5) +
  scale_fill_manual(values = PALETTE[c(2,3)]) +
  labs(title = "Distribution de la charge annuelle agregee",
       subtitle = "La reassurance ecrete la queue de distribution",
       x = "Charge agregee (millions EUR)", y = "Densite", fill = NULL)
save_fig(g_agg, "08_distribution_agregee")

save_rds(list(taux_cession = charge_cedee/charge_brute,
              reduction_capital = 1 - capital_proxy(agg_net)/capital_proxy(agg_brut)),
         "params_reassurance")

cat("[08] OK - reassurance XS analysee avec un proxy de capital simplifie\n")
