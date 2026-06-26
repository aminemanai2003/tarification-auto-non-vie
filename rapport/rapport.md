---
title: "Construction d'un tarif d'assurance automobile (RC + dommages)"
subtitle: "De la donnee a la prime commerciale, avec provisionnement et reassurance"
author: "Projet personnel d'actuariat non-vie"
output: github_document
---



> **Donnees :** `freMTPL2freq` + `freMTPL2sev` (package R `CASdatasets`) -
> portefeuille de Responsabilite Civile automobile francaise,
> **677 991 polices** et **26 444 sinistres**.
> **Outils :** R (`data.table`, `glm`, `MASS`, `fitdistrplus`, `actuar`, `ChainLadder`).

---

## 1. Objectif et demarche

Ce projet reproduit la chaine complete du travail d'un actuaire non-vie en
cellule technique, telle que presentee dans le schema global de la
tarification :

**Donnees -> Frequence -> Cout -> Prime pure -> Prime commerciale ->
Provisionnement -> Reassurance.**

Chaque etape mobilise les methodes etudiees en cours : ajustement de lois
et tests d'adequation, modeles lineaires generalises (GLM), theorie des
valeurs extremes, Chain-Ladder et modele de Mack, traite Excess-of-Loss.

## 2. Preparation et exploration des donnees

La base contrats et la base sinistres sont rapprochees par `IDpol`, puis
fiabilisees (plafonnement de l'exposition a 1 an, traitement des valeurs
aberrantes). On discretise ensuite les variables continues (age, anciennete
du vehicule, bonus-malus, densite) pour la tarification.

**Indicateurs techniques du portefeuille :**

|Indicateur                 |Valeur     |
|:--------------------------|:----------|
|Exposition (annees-risque) |358 343    |
|Nombre de sinistres        |26 405     |
|Charge totale (EUR)        |59 909 216 |
|Frequence (sin/an)         |0.0737     |
|Cout moyen (EUR)           |2 268.9    |
|Prime pure empirique (EUR) |167.18     |

L'analyse univariee identifie les variables discriminantes en croisant
chaque facteur avec la frequence (rapport sinistres / annees-risque) :


![Frequence par tranche d'age du conducteur](../output/figures/02_freq_DrivAgeBand.png)


![Frequence par niveau de bonus-malus](../output/figures/02_freq_BonusMalusBand.png)

La frequence decroit fortement avec l'experience du conducteur et augmente
massivement avec le malus : ce sont des facteurs tarifaires majeurs. Les
tests de liaison (Kruskal-Wallis) confirment la significativite des liens.

## 3. Modelisation de la frequence

On ajuste deux lois de comptage a la distribution du nombre de sinistres
par contrat, puis on les valide par le **test du Khi-deux**.

- Moyenne empirique $E(N) = 0.0389$,
  variance $V(N) = 0.042$.
- **Surdispersion** : $V(N)/E(N) = 1.079 > 1$.
  La loi de Poisson (qui impose $V(N)=E(N)$) est donc theoriquement mal
  adaptee ; la **Binomiale Negative** est preferable, conformement a la
  remarque du cours.

| NbSinistres| Observe| Theo_Poisson| Theo_BinomNeg|
|-----------:|-------:|------------:|-------------:|
|           0|  653047|       652094|        653047|
|           1|   23571|        25396|         23572|
|           2|    1298|          495|          1288|
|           3|      62|            6|            78|
|           4|      13|            0|             5|


|Loi                | D_khi2| ddl| seuil_5pct|    AIC|Decision                       |
|:------------------|------:|---:|----------:|------:|:------------------------------|
|Poisson            | 2162.0|   2|       5.99| 226315|Rejet de H0 (loi non adequate) |
|Binomiale Negative |   14.4|   2|       5.99| 225014|Rejet de H0 (loi non adequate) |



![Ajustement : observe vs Poisson vs Binomiale Negative](../output/figures/03_ajustement_frequence.png)

Les deux lois sont formellement rejetees par le Khi-deux, mais c'est un
artefact de la **tres grande taille d'echantillon** ($n \approx 678\,000$) :
le moindre ecart devient significatif. On s'appuie alors sur l'AIC et
l'ajustement graphique, qui montrent que la **Binomiale Negative domine
nettement** la loi de Poisson (statistique du Khi-deux divisee par ~150).

## 4. Modelisation du cout des sinistres

On distingue les sinistres **attritionnels** (frequents, peu couteux) des
sinistres **graves** (rares, tres couteux), avec un seuil a
**10 000 EUR**.

### 4.1 Attritionnels : lois Gamma et Lognormale

Validation par le **test de Kolmogorov-Smirnov** (loi continue) :

|Loi        |    AIC|   KS_D| KS_pvalue|
|:----------|------:|------:|---------:|
|Gamma      | 423669| 0.2310|         0|
|Lognormale | 427406| 0.2567|         0|



![Densites ajustees vs histogramme observe](../output/figures/04_attritionnels_densite.png)


![QQ-plot de la loi retenue](../output/figures/04_attritionnels_qqplot.png)

La loi **Gamma** est retenue (meilleur AIC). Comme pour la
frequence, le KS rejette formellement l'adequation parfaite (taille
d'echantillon), mais la loi capture bien la forme de la distribution.

### 4.2 Graves : theorie des valeurs extremes

Au-dela du seuil, le cout est modelise par une **loi de Pareto**. L'indice
de queue est estime par l'**estimateur de Hill** :
$\hat{\alpha} = 1.173$.


![Hill plot - estimation de l'indice de queue](../output/figures/04_hill_plot.png)


![Mean-excess plot - justification du comportement Pareto](../output/figures/04_mean_excess.png)


![QQ-plot Pareto des sinistres graves](../output/figures/04_qqplot_pareto.png)

Avec $\hat{\alpha} \approx 1.17$, la queue est tres
epaisse : l'esperance existe ($\alpha>1$) mais la variance est quasi
infinie. C'est typique de la RC automobile (sinistres corporels lourds) et
**justifie le recours a la reassurance** (section 8).

## 5. Prime pure par GLM

La prime pure est modelisee selon l'approche **frequence x cout moyen** :

- **GLM Poisson** (lien log, offset $\log(\text{Exposure})$) pour la frequence ;
- **GLM Gamma** (lien log) pour le cout moyen des attritionnels ;
- chargement forfaitaire pour les graves.

$$
\text{Prime Pure}(x) = \underbrace{\text{frequence}(x)}_{\text{GLM Poisson}}
\times \Big[(1-p_g)\,\underbrace{\text{cout attritionnel}(x)}_{\text{GLM Gamma}}
+ p_g\, E[\text{grave}]\Big]
$$

**Validation** (la prime pure moyenne doit egaler le burning cost) :

|Indicateur                          |Valeur |
|:-----------------------------------|:------|
|Prime pure moyenne (modele GLM)     |166.98 |
|Prime pure empirique (burning cost) |167.18 |
|Ecart relatif                       |-0.1%  |

L'ecart est inferieur a 0,2 % : le modele est **non biaise au global** tout
en etant **segmente** par profil de risque. Les relativites tarifaires
(effet multiplicatif de chaque modalite) sont coherentes :


![Relativites de frequence (age & bonus-malus)](../output/figures/05_relativites_frequence.png)


![Distribution de la prime pure par police](../output/figures/05_distribution_prime_pure.png)

## 6. De la prime pure a la prime commerciale

On applique la formule du cours
$PC = PP\,(1+\alpha)/(1-\tau)$ avec un chargement de frais
$\tau = 20\%$ et un chargement de securite
$\alpha = 5\%$, puis les taxes.

|Indicateur                         |Valeur   |
|:----------------------------------|:--------|
|Primes pures acquises (EUR)        |59836744 |
|Primes commerciales acquises (EUR) |78535727 |
|Charge sinistres (EUR)             |59909216 |
|Ratio S/P                          |76.3%    |
|Ratio combine                      |96.3%    |
|Marge technique attendue           |3.7%     |



![Decomposition de la prime moyenne](../output/figures/06_decomposition_prime.png)

Le **ratio combine** est inferieur a 100 % : le portefeuille est
techniquement rentable. Exemples de tarifs par profil :

|Profil                                        |   Freq| PrimePure| PrimeCommerciale| PrimeTTC|
|:---------------------------------------------|------:|---------:|----------------:|--------:|
|Jeune conducteur, vehicule puissant, ville    | 0.3207|     769.9|           1010.5|   1162.1|
|Conducteur experimente, vehicule moyen, rural | 0.0574|     125.8|            165.1|    189.9|
|Senior, petite cylindree, peripherie          | 0.0954|     219.8|            288.5|    331.8|

Un jeune conducteur sur vehicule puissant en ville paie plusieurs fois la
prime d'un conducteur experimente sur petit vehicule : la segmentation
**lutte contre l'antiselection**.

## 7. Provisionnement (Chain-Ladder + Mack)

Le jeu freMTPL2 ne contient pas de dimension de deroulement ; on illustre
donc le provisionnement sur un **triangle de liquidation** standard
(paiements cumules).

| Annee_origine| Paye_a_ce_jour| Charge_ultime| Provision_CL|
|-------------:|--------------:|-------------:|------------:|
|             1|           3901|          3901|            0|
|             2|           5339|          5434|           95|
|             3|           4909|          5379|          470|
|             4|           4588|          5298|          710|
|             5|           3873|          4858|          985|
|             6|           3692|          5111|         1419|
|             7|           3483|          5661|         2178|
|             8|           2864|          6785|         3920|
|             9|           1363|          5642|         4279|
|            10|            344|          4970|         4626|



![Developpement des paiements cumules](../output/figures/07_developpement.png)


![Provisions par annee d'origine](../output/figures/07_provisions_chain_ladder.png)

- **Provision Chain-Ladder totale** : 18 681 milliers EUR.
- **Modele de Mack** : erreur de prediction (Mack S.E.) avec un
  coefficient de variation de **13.1 %**, qui quantifie
  l'incertitude autour de la provision (dimension reglementaire / Solva 2).

## 8. Reassurance Excess-of-Loss et lien Solvabilite 2

On met en place un traite **XS** : priorite
50 000 EUR, portee
1 000 000 EUR.

|Indicateur                       |Valeur     |
|:--------------------------------|:----------|
|Priorite (retention)             |50 000     |
|Portee                           |1 000 000  |
|Charge brute (EUR)               |59 909 216 |
|Charge retenue (EUR)             |50 021 518 |
|Charge cedee au reassureur (EUR) |9 887 699  |
|Taux de cession                  |16.50%     |
|Nb sinistres touchant le traite  |88         |
|Sinistre max brut (EUR)          |4 075 401  |
|Sinistre max retenu (EUR)        |3 075 401  |



![Partage des plus gros sinistres entre cedante et reassureur](../output/figures/08_partage_xs.png)

Par simulation de la charge annuelle agregee (modele collectif), on mesure
l'impact sur le capital de solvabilite (VaR 99,5 %, horizon Solvabilite 2) :

|Mesure                                |     Brut| Net_de_reassurance|Reduction |
|:-------------------------------------|--------:|------------------:|:---------|
|Charge moyenne (EUR)                  | 59877076|           50007396|16.5%     |
|Ecart-type (EUR)                      |  4803827|            3173911|33.9%     |
|VaR 99,5% (EUR)                       | 74045892|           60616359|18.1%     |
|Capital SCR proxy (VaR99,5 - moyenne) | 14168816|           10608963|25.1%     |



![Charge agregee : brute vs nette de reassurance](../output/figures/08_distribution_agregee.png)

Le traite cede **16.5 %** de la charge mais
**reduit le capital de solvabilite (SCR proxy) de
25.1 %** : la reassurance transfere
prioritairement le risque de queue, ce qui ameliore la solvabilite.

## 9. Conclusion

Ce projet met en oeuvre, sur des donnees reelles, l'ensemble de la demarche
actuarielle non-vie :

| Etape | Methode | Resultat cle |
|---|---|---|
| Frequence | Poisson / Binomiale Negative + Khi-deux | surdispersion, BN retenue |
| Cout attritionnel | Gamma / Lognormale + KS | Gamma retenue |
| Cout grave | Pareto / Hill (EVT) | $\alpha = 1.17$ |
| Prime pure | GLM frequence x cout | ecart < 0,2 % vs burning cost |
| Prime commerciale | chargements + taxes | ratio combine ~96 % |
| Provisionnement | Chain-Ladder + Mack | CoV 13.1 % |
| Reassurance | traite XS | SCR -25 % |

**Limites et pistes** : modeles GAM/GBM pour capturer les non-linearites,
modele Tweedie pour une prime pure en une seule etape, provisionnement
stochastique (bootstrap ODP), credibilite pour les zones a faible exposition.
