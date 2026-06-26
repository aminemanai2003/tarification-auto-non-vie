# =====================================================================
# 04_cout.R  --  Modelisation du cout des sinistres
# ---------------------------------------------------------------------
# Distinction ATTRITIONNELS / GRAVES (cours Tarification, slides 8-9) :
#   - attritionnels  -> lois continues classiques (Gamma, Lognormale)
#                       validees par le test de Kolmogorov-Smirnov
#   - graves         -> Theorie des Valeurs Extremes : loi de Pareto,
#                       estimateur de Hill, mean-excess plot, QQ-plot
# =====================================================================

if (!exists("PROJ")) {
  .a <- commandArgs(FALSE); .f <- .a[grep("^--file=", .a)]
  .rdir <- if (length(.f))
    dirname(normalizePath(sub("^--file=", "", .f[1]), winslash = "/", mustWork = FALSE)) else "R"
  source(file.path(.rdir, "00_config.R"))
}
cat("\n========== 04 - MODELISATION DU COUT ==========\n")

claims <- load_rds("claims")
attr_x  <- claims[Grave == FALSE, ClaimAmount]   # sinistres attritionnels
grave_x <- claims[Grave == TRUE,  ClaimAmount]   # sinistres graves
cat(sprintf("Attritionnels : %d sinistres (cout moyen %.0f EUR)\n",
            length(attr_x), mean(attr_x)))
cat(sprintf("Graves        : %d sinistres (cout moyen %.0f EUR)\n",
            length(grave_x), mean(grave_x)))

# =====================================================================
# PARTIE A - SINISTRES ATTRITIONNELS : Gamma vs Lognormale
# =====================================================================
m_attr <- mean(attr_x); v_attr <- var(attr_x)

# Gamma : estimation par methode des moments (robuste)
#   E(X) = shape/rate, V(X) = shape/rate^2  =>  shape = m^2/v, rate = m/v
gam_shape <- m_attr^2 / v_attr
gam_rate  <- m_attr / v_attr
ll_gamma  <- sum(dgamma(attr_x, gam_shape, gam_rate, log = TRUE))
aic_gamma <- -2 * ll_gamma + 2 * 2

# Lognormale : estimation par maximum de vraisemblance
ln_meanlog <- mean(log(attr_x))
ln_sdlog   <- sd(log(attr_x))
ll_lnorm   <- sum(dlnorm(attr_x, ln_meanlog, ln_sdlog, log = TRUE))
aic_lnorm  <- -2 * ll_lnorm + 2 * 2

# Tests de Kolmogorov-Smirnov (loi continue, cf. cours)
ks_gamma <- suppressWarnings(ks.test(attr_x, "pgamma",
              shape = gam_shape, rate = gam_rate))
ks_lnorm <- suppressWarnings(ks.test(attr_x, "plnorm",
              meanlog = ln_meanlog, sdlog = ln_sdlog))

comp_attr <- data.table(
  Loi   = c("Gamma", "Lognormale"),
  AIC   = round(c(aic_gamma, aic_lnorm)),
  KS_D  = round(c(ks_gamma$statistic, ks_lnorm$statistic), 4),
  KS_pvalue = signif(c(ks_gamma$p.value, ks_lnorm$p.value), 3))
save_tab(comp_attr, "04_attritionnels_comparaison")
print(comp_attr)

# Loi retenue (meilleur AIC)
best_attr <- if (aic_lnorm < aic_gamma) "Lognormale" else "Gamma"
cat(sprintf(">> Loi retenue pour les attritionnels : %s\n", best_attr))

# Graphiques d'ajustement (densites superposees + QQ-plot)
xcap <- as.numeric(quantile(attr_x, .98))
xx   <- seq(1, xcap, length.out = 300)
dens_dt <- rbind(
  data.table(x = xx, d = dgamma(xx, gam_shape, gam_rate), Loi = "Gamma"),
  data.table(x = xx, d = dlnorm(xx, ln_meanlog, ln_sdlog), Loi = "Lognormale"))
g_dens <- ggplot() +
  geom_histogram(data = data.table(x = attr_x[attr_x <= xcap]),
                 aes(x, after_stat(density)), bins = 60,
                 fill = "grey85", colour = "white") +
  geom_line(data = dens_dt, aes(x, d, colour = Loi), linewidth = 1) +
  scale_colour_manual(values = PALETTE[c(2, 1)]) +
  labs(title = "Attritionnels : ajustement Gamma vs Lognormale",
       subtitle = "Histogramme observe (98% des sinistres) + densites ajustees",
       x = "Cout du sinistre (EUR)", y = "Densite", colour = NULL)
save_fig(g_dens, "04_attritionnels_densite")

# QQ-plot de la loi retenue (sous-echantillon pour la lisibilite)
set.seed(1); idx <- sample.int(length(attr_x), min(3000, length(attr_x)))
pp  <- ppoints(length(idx))
emp <- sort(attr_x[idx])
theo <- if (best_attr == "Lognormale")
  qlnorm(pp, ln_meanlog, ln_sdlog) else qgamma(pp, gam_shape, gam_rate)
qq_attr <- data.table(theorique = theo, empirique = emp)
g_qq_attr <- ggplot(qq_attr, aes(theorique, empirique)) +
  geom_point(size = .6, colour = PALETTE[1]) +
  geom_abline(slope = 1, intercept = 0, colour = PALETTE[2]) +
  coord_cartesian(xlim = c(0, xcap), ylim = c(0, xcap)) +
  labs(title = paste("QQ-plot", best_attr, "(attritionnels)"),
       x = "Quantiles theoriques", y = "Quantiles empiriques")
save_fig(g_qq_attr, "04_attritionnels_qqplot")

# =====================================================================
# PARTIE B - SINISTRES GRAVES : Theorie des Valeurs Extremes
# =====================================================================
u <- SEUIL_GRAVE

# (1) Estimateur de Hill = EMV de l'indice de queue de Pareto au seuil u
#     Pour X > u, (X/u) suit une Pareto ; alpha = n / sum(log(X/u))
logratio  <- log(grave_x / u)
alpha_hill <- length(grave_x) / sum(logratio)
cat(sprintf("Indice de queue de Pareto (Hill) : alpha = %.3f\n", alpha_hill))
cat(ifelse(alpha_hill > 2,
  "  -> alpha > 2 : esperance et variance finies.\n",
  "  -> alpha <= 2 : variance infinie (queue tres epaisse).\n"))

# (2) Hill plot : alpha en fonction du nombre k de valeurs extremes
allbig <- sort(claims$ClaimAmount, decreasing = TRUE)
kseq <- 20:min(600, length(allbig) - 1)
hill_k <- sapply(kseq, function(k) {
  top <- allbig[1:(k + 1)]
  k / sum(log(top[1:k] / top[k + 1]))
})
hill_dt <- data.table(k = kseq, alpha = hill_k)
g_hill <- ggplot(hill_dt, aes(k, alpha)) +
  geom_line(colour = PALETTE[1]) +
  geom_hline(yintercept = alpha_hill, linetype = "dashed", colour = PALETTE[2]) +
  labs(title = "Hill plot - estimation de l'indice de queue",
       subtitle = "Zone de stabilite = choix de l'indice alpha",
       x = "k (nombre de valeurs extremes)", y = expression(hat(alpha)))
save_fig(g_hill, "04_hill_plot")

# (3) Mean-excess plot : e(u) lineaire croissant => queue de type Pareto
useq <- quantile(claims$ClaimAmount, seq(.80, .995, by = .005))
me <- sapply(useq, function(s) {
  ex <- claims$ClaimAmount[claims$ClaimAmount > s] - s
  if (length(ex) > 5) mean(ex) else NA_real_
})
me_dt <- data.table(seuil = as.numeric(useq), exces_moyen = me)
g_me <- ggplot(me_dt, aes(seuil, exces_moyen)) +
  geom_line(colour = PALETTE[1]) + geom_point(size = .8) +
  geom_vline(xintercept = u, linetype = "dashed", colour = PALETTE[2]) +
  labs(title = "Mean-excess plot",
       subtitle = "Tendance lineaire croissante = comportement Pareto",
       x = "Seuil u (EUR)", y = "Exces moyen e(u)")
save_fig(g_me, "04_mean_excess")

# (4) QQ-plot Pareto : log(X/u) doit suivre une exponentielle Exp(alpha)
qy <- sort(logratio)
qx <- qexp(ppoints(length(qy)), rate = alpha_hill)
qq_dt <- data.table(theorique = qx, empirique = qy)
g_qq <- ggplot(qq_dt, aes(theorique, empirique)) +
  geom_point(size = .7, colour = PALETTE[1]) +
  geom_abline(slope = 1, intercept = 0, colour = PALETTE[2]) +
  labs(title = "QQ-plot Pareto (graves)",
       subtitle = "Alignement sur la diagonale = bon ajustement",
       x = "Quantiles theoriques Exp(alpha)", y = "log(X/u) ordonnes")
save_fig(g_qq, "04_qqplot_pareto")

# (5) Cout moyen des graves sous Pareto : E(X | X>u) = u * alpha/(alpha-1)
cout_moyen_grave <- if (alpha_hill > 1) u * alpha_hill / (alpha_hill - 1) else NA
cat(sprintf("Cout moyen theorique d'un grave (Pareto) : %.0f EUR\n",
            cout_moyen_grave))

# =====================================================================
# Synthese severite
# =====================================================================
synth_cout <- list(
  best_attr = best_attr,
  gamma  = list(shape = gam_shape, rate = gam_rate),
  lnorm  = list(meanlog = ln_meanlog, sdlog = ln_sdlog),
  cout_moyen_attr = mean(attr_x),
  alpha_pareto = alpha_hill,
  u = u,
  cout_moyen_grave = cout_moyen_grave,
  prop_graves = mean(claims$Grave),
  freq_grave_par_sinistre = mean(claims$Grave))
save_rds(synth_cout, "params_cout")

cat("[04] OK - cout modelise (attritionnels + graves EVT)\n")
