# Tarification d'un portefeuille d'assurance automobile (RC + dommages)

> **De la donnee a la prime commerciale** — un projet actuariel non-vie complet,
> en R, sur donnees reelles (RC auto France, ~678 000 polices).
>
> *Non-life pricing project: full actuarial pipeline from raw data to commercial
> premium, with reserving and reinsurance — built in R on the French MTPL dataset.*

![R](https://img.shields.io/badge/R-4.5-276DC3?logo=r&logoColor=white)
![Domaine](https://img.shields.io/badge/Actuariat-Non%20Vie-1F3864)
![Donnees](https://img.shields.io/badge/Donnees-freMTPL2-70AD47)

---

## Contexte

Projet personnel d'**actuariat non-vie**. Il reproduit la
demarche complete d'un actuaire en cellule technique tarification, en
mobilisant les methodes classiques de la branche :

**Donnees → Frequence → Cout → Prime pure → Prime commerciale → Provisionnement → Reassurance**

## Donnees

- `freMTPL2freq` : **677 991 polices** RC automobile (exposition, age,
  vehicule, bonus-malus, zone…).
- `freMTPL2sev` : **26 444 sinistres** (montants).
- Source : package R [`CASdatasets`](http://cas.uqam.ca/).

## Competences demontrees

| Domaine | Methodes mises en oeuvre |
|---|---|
| **Modelisation frequence** | Loi de Poisson, Binomiale Negative, estimation moments / max de vraisemblance, **test du Khi-deux**, detection de surdispersion |
| **Modelisation cout** | Lois Gamma & Lognormale, **test de Kolmogorov-Smirnov**, separation attritionnels / graves |
| **Valeurs extremes (EVT)** | Loi de Pareto, **estimateur de Hill**, mean-excess plot, QQ-plot |
| **Tarification** | **GLM** Poisson (frequence) & Gamma (cout), segmentation, relativites, prime pure |
| **Pilotage technique** | Chargements, prime commerciale, **S/P et ratio combine** |
| **Provisionnement** | Triangle de liquidation, **Chain-Ladder**, modele de **Mack** |
| **Reassurance & Solva 2** | Traite **Excess-of-Loss**, simulation de la charge agregee, **VaR 99,5% / SCR** |

## Resultats cles

| Etape | Resultat |
|---|---|
| Frequence | Surdispersion `V/E = 1,08` → Binomiale Negative retenue (AIC 225 014 vs 226 315) |
| Cout grave | Indice de queue de Pareto (Hill) `α ≈ 1,17` (queue tres epaisse) |
| Prime pure GLM | Ecart < **0,2 %** vs burning cost (modele non biaise & segmente) |
| Prime commerciale | **Ratio combine ≈ 96 %** (portefeuille rentable) |
| Provisionnement | Provision Chain-Ladder, CoV de Mack ≈ **13 %** |
| Reassurance XS | Cession 16,5 % de la charge, **SCR reduit de ~25 %** |

![Relativites de frequence](output/figures/05_relativites_frequence.png)
![Charge agregee brute vs nette de reassurance](output/figures/08_distribution_agregee.png)

📄 **Rapport complet et commente : [`rapport/rapport.md`](rapport/rapport.md)**

## Structure du projet

```
projet_tarification_auto/
├── R/
│   ├── 00_config.R            # packages, chemins, parametres, utilitaires
│   ├── 01_data_prep.R         # rapprochement & fiabilisation des bases
│   ├── 02_eda.R               # analyse exploratoire / etudes univariees
│   ├── 03_frequence.R         # Poisson / Binomiale Negative + Khi-deux
│   ├── 04_cout.R              # Gamma / Lognormale + KS, Pareto / Hill (EVT)
│   ├── 05_prime_pure_glm.R    # GLM frequence x cout = prime pure
│   ├── 06_prime_commerciale.R # chargements, S/P, ratio combine
│   ├── 07_provisionnement.R   # Chain-Ladder + Mack
│   ├── 08_reassurance.R       # traite XS + lien Solvabilite 2
│   └── run_all.R              # execute tout le pipeline
├── rapport/
│   ├── rapport.Rmd            # rapport source (R Markdown)
│   └── rapport.md             # rapport genere (lisible sur GitHub)
└── output/
    ├── figures/               # graphiques (.png)
    └── tables/                # tableaux (.csv)
```

## Reproduire l'analyse

Pre-requis : **R ≥ 4.3** et les packages
`CASdatasets`, `data.table`, `dplyr`, `ggplot2`, `MASS`, `fitdistrplus`,
`actuar`, `ChainLadder`.

```r
# installation de CASdatasets (depuis le depot dedie)
install.packages("CASdatasets", repos = "http://cas.uqam.ca/pub/", type = "source")
install.packages(c("data.table","dplyr","ggplot2","MASS",
                   "fitdistrplus","actuar","ChainLadder"))
```

```bash
# 1) lancer tout le pipeline (genere figures + tables)
Rscript R/run_all.R

# 2) regenerer le rapport
Rscript -e "knitr::knit('rapport/rapport.Rmd','rapport/rapport.md')"
```

## Limites et pistes d'amelioration

- Modeles **GAM / GBM** pour capturer les non-linearites des facteurs continus.
- Modele **Tweedie** pour estimer la prime pure en une seule etape.
- Provisionnement **stochastique** (bootstrap ODP) au-dela de Mack.
- Theorie de la **credibilite** pour les segments a faible exposition.

## Auteur

Projet personnel de portfolio en actuariat non-vie.
