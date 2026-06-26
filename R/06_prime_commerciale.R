# =====================================================================
# 06_prime_commerciale.R  --  De la prime pure a la prime commerciale
# ---------------------------------------------------------------------
# Formule du cours :  PC = PP + tau*PC + alpha*PP
#   => PC = PP * (1 + alpha) / (1 - tau)
# avec tau   = chargement frais de gestion / commissions
#      alpha = chargement de securite
# On calcule aussi S/P et le RATIO COMBINE du portefeuille.
# =====================================================================

if (!exists("PROJ")) {
  .a <- commandArgs(FALSE); .f <- .a[grep("^--file=", .a)]
  .rdir <- if (length(.f))
    dirname(normalizePath(sub("^--file=", "", .f[1]), winslash = "/", mustWork = FALSE)) else "R"
  source(file.path(.rdir, "00_config.R"))
}
cat("\n========== 06 - PRIME COMMERCIALE ==========\n")

policies <- load_rds("policies_tarifees")
glm_obj  <- load_rds("modeles_glm")

# --- 1) Chargements : prime pure -> commerciale -> TTC ---------------
coef_charge <- (1 + CHARGE_SECU) / (1 - CHARGE_FRAIS)
policies[, PrimeCommerciale := PrimePure * coef_charge]
policies[, PrimeTTC := PrimeCommerciale * (1 + TAUX_TAXE)]
cat(sprintf("Coefficient de chargement PP->PC : %.3f (tau=%.0f%%, alpha=%.0f%%)\n",
            coef_charge, 100*CHARGE_FRAIS, 100*CHARGE_SECU))

# --- 2) Indicateurs techniques du portefeuille -----------------------
claims <- load_rds("claims")
charge_tot   <- sum(claims$ClaimAmount)
prime_pp_tot <- sum(policies$PrimePure       * policies$Exposure)
prime_pc_tot <- sum(policies$PrimeCommerciale * policies$Exposure)
frais        <- CHARGE_FRAIS * prime_pc_tot

sp_ratio       <- charge_tot / prime_pc_tot          # ratio sinistres/primes
ratio_combine  <- sp_ratio + CHARGE_FRAIS            # S/P + frais

kpi <- data.table(
  Indicateur = c("Primes pures acquises (EUR)",
                 "Primes commerciales acquises (EUR)",
                 "Charge sinistres (EUR)",
                 "Ratio S/P", "Ratio combine",
                 "Marge technique attendue"),
  Valeur = c(round(prime_pp_tot), round(prime_pc_tot), round(charge_tot),
             sprintf("%.1f%%", 100*sp_ratio),
             sprintf("%.1f%%", 100*ratio_combine),
             sprintf("%.1f%%", 100*(1 - ratio_combine))))
save_tab(kpi, "06_kpi_techniques")
print(kpi)
cat(ifelse(ratio_combine < 1,
  ">> Ratio combine < 100% : le portefeuille est techniquement rentable.\n",
  ">> Ratio combine > 100% : perte technique, tarif a revoir.\n"))

# --- 3) Exemples de tarifs par profil --------------------------------
profils <- data.table(
  Profil = c("Jeune conducteur, vehicule puissant, ville",
             "Conducteur experimente, vehicule moyen, rural",
             "Senior, petite cylindree, peripherie"),
  VehPowerBand   = factor(c("10+","6-7","<=5"),
                          levels = levels(policies$VehPowerBand)),
  VehAgeBand     = factor(c("1-5","6-12","6-12"),
                          levels = levels(policies$VehAgeBand)),
  DrivAgeBand    = factor(c("18-22","43-74","75+"),
                          levels = levels(policies$DrivAgeBand)),
  BonusMalusBand = factor(c("91+","50","51-60"),
                          levels = levels(policies$BonusMalusBand)),
  VehGas         = factor(c("Regular","Diesel","Regular"),
                          levels = levels(policies$VehGas)),
  Area           = factor(c("F","B","D"),
                          levels = levels(policies$Area)),
  DensityBand    = factor(c("Q4","Q1","Q3"),
                          levels = levels(policies$DensityBand)),
  Exposure = 1)

profils[, freq := predict(glm_obj$glm_freq, newdata = profils, type = "response")]
profils[, sev  := predict(glm_obj$glm_sev,  newdata = profils, type = "response")]
profils[, PrimePure := freq * ((1 - glm_obj$p_grave) * sev +
                                glm_obj$p_grave * glm_obj$Egrave)]
profils[, PrimeCommerciale := round(PrimePure * coef_charge, 1)]
profils[, PrimeTTC := round(PrimeCommerciale * (1 + TAUX_TAXE), 1)]
profils[, PrimePure := round(PrimePure, 1)]
tab_profils <- profils[, .(Profil, Freq = round(freq, 4),
                           PrimePure, PrimeCommerciale, PrimeTTC)]
save_tab(tab_profils, "06_exemples_profils")
cat("\n--- Exemples de tarifs ---\n"); print(tab_profils)

# --- 4) Graphique : decomposition de la prime ------------------------
deco <- data.table(
  Composante = factor(c("Prime pure","Frais (tau)","Securite (alpha)","Taxes"),
                levels = c("Prime pure","Frais (tau)","Securite (alpha)","Taxes")),
  Montant = c(
    mean(policies$PrimePure),
    mean(policies$PrimeCommerciale) - mean(policies$PrimePure) -
      CHARGE_SECU/(1-CHARGE_FRAIS)*mean(policies$PrimePure),
    CHARGE_SECU/(1-CHARGE_FRAIS)*mean(policies$PrimePure),
    mean(policies$PrimeTTC) - mean(policies$PrimeCommerciale)))
g_deco <- ggplot(deco, aes(x = "Prime moyenne", y = Montant, fill = Composante)) +
  geom_col() +
  scale_fill_manual(values = PALETTE) +
  labs(title = "Decomposition de la prime moyenne",
       subtitle = "De la prime pure a la prime TTC",
       x = NULL, y = "EUR", fill = NULL)
save_fig(g_deco, "06_decomposition_prime")

save_rds(policies, "policies_tarifees")
cat("[06] OK - prime commerciale et ratios calcules\n")
