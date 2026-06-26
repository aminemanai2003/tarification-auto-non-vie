# =====================================================================
# 03_frequence.R  --  Modelisation de la frequence des sinistres
# ---------------------------------------------------------------------
# Ajustement de lois de comptage (cours "Modelisation Freq & Cout") :
#   - loi de Poisson P(lambda)
#   - loi Binomiale Negative BN(r,p)
# Estimation par methode des moments / max de vraisemblance,
# validation par le TEST D'ADEQUATION DU KHI-DEUX.
# =====================================================================

if (!exists("PROJ")) {
  .a <- commandArgs(FALSE); .f <- .a[grep("^--file=", .a)]
  .rdir <- if (length(.f))
    dirname(normalizePath(sub("^--file=", "", .f[1]), winslash = "/", mustWork = FALSE)) else "R"
  source(file.path(.rdir, "00_config.R"))
}
cat("\n========== 03 - MODELISATION DE LA FREQUENCE ==========\n")

policies <- load_rds("policies")
N <- policies$ClaimNb
n <- length(N)

# --- 1) Statistiques essentielles (cf. cours) ------------------------
m_emp   <- mean(N)                 # moyenne empirique = E(N) estime
v_emp   <- var(N)                  # variance empirique modifiee (sans biais)
ratio   <- v_emp / m_emp           # indice de surdispersion
cat(sprintf("E(N) estime = %.5f | V(N) estime = %.5f | V/E = %.3f\n",
            m_emp, v_emp, ratio))
cat(ifelse(ratio > 1,
  ">> Surdispersion (V(N) > E(N)) : la loi de Poisson est mal adaptee,\n   la Binomiale Negative est preferable (cf. remarque du cours).\n",
  ">> Pas de surdispersion.\n"))

# Tableau des frequences empiriques
kmax <- max(N)
obs  <- as.integer(table(factor(N, levels = 0:kmax)))

# --- 2) Ajustement loi de Poisson : lambda_hat = moyenne ------------
lambda_hat <- m_emp
p_pois <- dpois(0:kmax, lambda_hat)
p_pois[kmax + 1] <- 1 - sum(p_pois[1:kmax])   # derniere classe = reste

# --- 3) Ajustement Binomiale Negative -------------------------------
# (a) Methode des moments (formules du cours) :
#     r_hat = n_bar^2 / (sigma^2 - n_bar) ; p_hat = n_bar / sigma^2
r_mm <- m_emp^2 / (v_emp - m_emp)
p_mm <- m_emp / v_emp
# (b) Maximum de vraisemblance (via MASS::glm.nb sur modele constant)
mle  <- glm.nb(N ~ 1)
r_mle <- mle$theta
mu_mle <- exp(coef(mle)[[1]])
p_mle <- r_mle / (r_mle + mu_mle)   # conversion vers parametrisation (r,p)
cat(sprintf("Poisson : lambda = %.5f\n", lambda_hat))
cat(sprintf("BN moments : r = %.4f, p = %.4f\n", r_mm, p_mm))
cat(sprintf("BN max.vraisemblance : r = %.4f, p = %.4f\n", r_mle, p_mle))

# Probabilites theoriques BN (dnbinom : size=r, prob=p == param du cours)
p_nb <- dnbinom(0:kmax, size = r_mle, prob = p_mle)
p_nb[kmax + 1] <- 1 - sum(p_nb[1:kmax])

# --- 4) Tableau de comparaison observe vs theorique ------------------
comp <- data.table(
  NbSinistres = 0:kmax,
  Observe     = obs,
  Theo_Poisson = round(p_pois * n),
  Theo_BinomNeg = round(p_nb * n))
save_tab(comp, "03_comparaison_lois")
print(comp)

# --- 5) Tests d'adequation du Khi-deux -------------------------------
test_pois <- khi2_adequation(obs, p_pois, n_params = 1)
test_nb   <- khi2_adequation(obs, p_nb,   n_params = 2)

resume <- data.table(
  Loi      = c("Poisson", "Binomiale Negative"),
  D_khi2   = round(c(test_pois$D, test_nb$D), 1),
  ddl      = c(test_pois$ddl, test_nb$ddl),
  seuil_5pct = round(c(test_pois$seuil_5pct, test_nb$seuil_5pct), 2),
  AIC      = round(c(
              -2*sum(dpois(N, lambda_hat, log=TRUE)) + 2,
               AIC(mle))),
  Decision = c(test_pois$decision, test_nb$decision))
save_tab(resume, "03_tests_adequation")
print(resume)
cat("Note : avec n =", n, "contrats, la puissance du test est telle que\n",
    "tout ecart minime conduit au rejet ; on s'appuie donc aussi sur l'AIC\n",
    "et l'ajustement graphique. La BN domine nettement la Poisson.\n")

# --- 6) Graphique observe vs ajuste ----------------------------------
gdat <- rbind(
  data.table(k = 0:kmax, prob = obs/n,   type = "Observe"),
  data.table(k = 0:kmax, prob = p_pois,  type = "Poisson"),
  data.table(k = 0:kmax, prob = p_nb,    type = "Binomiale Negative"))
g <- ggplot(gdat, aes(factor(k), prob, fill = type)) +
  geom_col(position = "dodge") +
  scale_y_sqrt() +
  scale_fill_manual(values = PALETTE[c(5,2,1)]) +
  labs(title = "Ajustement de la frequence : observe vs theorique",
       subtitle = "Echelle racine pour visualiser les petites classes",
       x = "Nombre de sinistres par contrat", y = "Probabilite", fill = NULL)
save_fig(g, "03_ajustement_frequence")

# --- 7) Sauvegarde des parametres pour la suite ----------------------
save_rds(list(lambda = lambda_hat, r = r_mle, p = p_mle,
              E_N = m_emp, V_N = v_emp), "params_frequence")

cat("[03] OK - frequence modelisee (Poisson & Binomiale Negative)\n")
