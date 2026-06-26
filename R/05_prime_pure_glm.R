# =====================================================================
# 05_prime_pure_glm.R  --  Prime pure par Modeles Lineaires Generalises
# ---------------------------------------------------------------------
# Approche "frequence x cout moyen" segmentee (cours Tarification) :
#   - GLM Poisson (offset = log Exposure) pour la FREQUENCE
#   - GLM Gamma (lien log) pour le COUT MOYEN des attritionnels
#   - chargement forfaitaire pour les GRAVES (cf. module 04)
#   Prime Pure(x) = frequence(x) x cout moyen(x)
# =====================================================================

if (!exists("PROJ")) {
  .a <- commandArgs(FALSE); .f <- .a[grep("^--file=", .a)]
  .rdir <- if (length(.f))
    dirname(normalizePath(sub("^--file=", "", .f[1]), winslash = "/", mustWork = FALSE)) else "R"
  source(file.path(.rdir, "00_config.R"))
}
cat("\n========== 05 - PRIME PURE (GLM) ==========\n")

policies <- load_rds("policies")
claims   <- load_rds("claims")

# Variables tarifaires retenues
facteurs <- c("VehPowerBand","VehAgeBand","DrivAgeBand",
              "BonusMalusBand","VehGas","Area","DensityBand")

# =====================================================================
# (1) GLM FREQUENCE - Poisson avec offset log(Exposure)
# =====================================================================
form_freq <- as.formula(paste("ClaimNb ~",
                paste(facteurs, collapse = " + "), "+ offset(log(Exposure))"))
glm_freq <- glm(form_freq, family = poisson(link = "log"), data = policies)
cat("GLM frequence (Poisson) ajuste.\n")
cat(sprintf("  Deviance expliquee : %.1f%%\n",
            100 * (1 - glm_freq$deviance / glm_freq$null.deviance)))

# =====================================================================
# (2) GLM COUT MOYEN - Gamma (lien log) sur les attritionnels
# =====================================================================
form_sev <- as.formula(paste("ClaimAmount ~", paste(facteurs, collapse = " + ")))
glm_sev <- glm(form_sev, family = Gamma(link = "log"),
               data = claims[Grave == FALSE])
cat("GLM cout moyen (Gamma) ajuste sur les attritionnels.\n")

# =====================================================================
# (3) Chargement des graves (forfaitaire, par sinistre)
# =====================================================================
p_grave   <- mean(claims$Grave)                       # part des graves parmi les sinistres
Egrave_emp<- mean(claims[Grave == TRUE, ClaimAmount]) # cout moyen empirique d'un grave
cat(sprintf("Part des graves : %.2f%% | cout moyen grave : %.0f EUR\n",
            100 * p_grave, Egrave_emp))

# =====================================================================
# (4) Calcul de la prime pure par police (annuelle, Exposure = 1)
# =====================================================================
nd <- copy(policies); nd[, Exposure := 1]
freq_pred <- predict(glm_freq, newdata = nd, type = "response")  # frequence annuelle
sev_attr  <- predict(glm_sev,  newdata = nd, type = "response")  # cout moyen attritionnel

# Prime Pure = frequence x cout moyen (melange attritionnel + grave)
pp_attr   <- freq_pred * (1 - p_grave) * sev_attr
pp_grave  <- freq_pred * p_grave * Egrave_emp
policies[, PP_attritionnel := pp_attr]
policies[, PP_grave        := pp_grave]
policies[, PrimePure       := pp_attr + pp_grave]

# =====================================================================
# (5) Validation : prime pure moyenne vs charge observee (burning cost)
# =====================================================================
pp_moyenne   <- weighted.mean(policies$PrimePure, policies$Exposure)
burning_cost <- sum(claims$ClaimAmount) / sum(policies$Exposure)
valid <- data.table(
  Indicateur = c("Prime pure moyenne (modele GLM)",
                 "Prime pure empirique (burning cost)",
                 "Ecart relatif"),
  Valeur = c(round(pp_moyenne, 2), round(burning_cost, 2),
             sprintf("%.1f%%", 100*(pp_moyenne/burning_cost - 1))))
save_tab(valid, "05_validation_prime_pure")
print(valid)

# =====================================================================
# (6) Relativites tarifaires (effet multiplicatif des modalites)
# =====================================================================
relat <- function(model, label) {
  co <- summary(model)$coefficients
  data.table(Modele = label, Variable = rownames(co),
             Relativite = round(exp(co[, "Estimate"]), 3),
             pvalue = signif(co[, 4], 2))[Variable != "(Intercept)"]
}
rel_freq <- relat(glm_freq, "Frequence")
rel_sev  <- relat(glm_sev,  "Cout moyen")
save_tab(rbind(rel_freq, rel_sev), "05_relativites")
cat("\n--- Relativites frequence (extrait) ---\n"); print(head(rel_freq, 12))

# Graphique : relativites de frequence pour l'age et le bonus-malus
rel_plot <- rel_freq[grepl("DrivAgeBand|BonusMalusBand", Variable)]
g_rel <- ggplot(rel_plot, aes(reorder(Variable, Relativite), Relativite)) +
  geom_col(fill = PALETTE[1]) +
  geom_hline(yintercept = 1, linetype = "dashed", colour = PALETTE[2]) +
  coord_flip() +
  labs(title = "Relativites de frequence (age conducteur & bonus-malus)",
       subtitle = "Effet multiplicatif vs modalite de reference",
       x = NULL, y = "Relativite (exp du coefficient)")
save_fig(g_rel, "05_relativites_frequence")

# Graphique : distribution de la prime pure
g_pp <- ggplot(policies, aes(PrimePure)) +
  geom_histogram(bins = 60, fill = PALETTE[3], colour = "white") +
  scale_x_continuous(limits = c(0, quantile(policies$PrimePure, .99))) +
  geom_vline(xintercept = pp_moyenne, linetype = "dashed", colour = PALETTE[2]) +
  labs(title = "Distribution de la prime pure par police",
       subtitle = paste("Prime pure moyenne =", round(pp_moyenne, 1), "EUR"),
       x = "Prime pure annuelle (EUR)", y = "Nombre de polices")
save_fig(g_pp, "05_distribution_prime_pure")

# =====================================================================
# (7) Sauvegardes
# =====================================================================
save_rds(policies, "policies_tarifees")
save_rds(list(glm_freq = glm_freq, glm_sev = glm_sev,
              p_grave = p_grave, Egrave = Egrave_emp,
              pp_moyenne = pp_moyenne, burning_cost = burning_cost),
         "modeles_glm")

cat("[05] OK - prime pure calculee par police\n")
