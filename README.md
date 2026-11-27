# Prédire la présence d'athérosclérose avec XGBoost

Se basant sur les données de 800 patients fictifs, ce projet construit un modèle de prédiction XGBoost de la probabilité d'être atteint d'athérosclérose, puis réalise une comparaison à une régression logistique avec plafond de performance.

## Pourquoi ce projet ?
En consultation médicale, on cherche souvent à définir la stratégie thérapeutique selon plusieurs considérations, dont son risque cardiovasculaire dans le temps. Aujourd'hui, on estime ce risque par une approche statistique, à partir des résultats d'essais cliniques de grande envergure. Par ML, on peut estimer le risque individuel d'un patient en combinant un grand nombre de variables cliniques, biologiques et comportementales. Avant d'appliquer ces méthodes à de vraies bases de données, il est précieux de s'entraîner sur des données simulées.

## La démarche suivie

1. Création d'une cohorte simulée.
2. Séparation en un groupe d'entraînement (75 %) et un groupe de test (25 %).
3. Choix du nombre d'arbres par validation croisée à 5 plis, pour limiter le surapprentissage (les autres hyperparamètres sont fixés à l'avance).
4. Entraînement du modèle final sur le groupe d'entraînement, puis calcul pour chaque participant d'une probabilité individuelle d'athérosclérose comprise entre 0 et 1.
5. Évaluation sur le groupe de test, utilisé une seule fois.
6. Comparaison à des références : un plafond de performance (calculable car le mécanisme de simulation est connu) et une régression logistique.

## Les données

800 participants, une ligne par participant, 22 variables explicatives et une variable à prédire.

| Famille | Variables |
|---|---|
| Démographie | âge, sexe |
| Corpulence et hémodynamique | IMC, pression artérielle systolique et diastolique |
| Bilan lipidique (EAL) | LDL-cholestérol, HDL-cholestérol, triglycérides |
| Métabolisme glucidique | HbA1c, diabète |
| Mode de vie et antécédents | statut tabagique, paquets-années, antécédents familiaux cardiovasculaires |
| Inflammation et fonction rénale | CRP ultrasensible, DFG estimé |
| Traitements | statine, antihypertenseur |
| Mesures de type « objet connecté » | activité physique, fréquence cardiaque de repos, variabilité sinusale (RMSSD), nombre de pas, durée de sommeil |

Variable à prédire : `atherosclerosis` (0 = absente, 1 = présente). La prévalence est de 36 % (288 cas sur 800).

Quelques valeurs manquantes ont été introduites volontairement (CRP, VFC, pas, HDL, paquets-années), comme dans les données de vie réelle. XGBoost les gère directement ; pour la régression logistique, elles sont remplacées par la médiane du groupe d'entraînement.


### XGBoost

Le nombre d'arbres retenu par validation croisée est de 68.

| Indicateur | Valeur | Ce que cela signifie |
|---|---|---|
| AUC | 0,70 (IC 95 % DeLong : 0,62 à 0,78) | Pour un sujet atteint et un sujet indemne tirés au hasard, le modèle classe correctement la paire 7 fois sur 10. |
| AUC (entraînement) | 0,92 | Le modèle a en partie « appris par cœur » les particularités de l’échantillon d’entraînement plutôt que des règles générales. |
| Score de Brier | 0,206 | Référence d'un modèle sans information : 0,230. Gain relatif : 10,5 %. |
| Pente de calibration | 0,74 |Les risques prédits sont trop extrêmes (modèle trop confiant). |
| Intercept de calibration | −0,12 | le modèle pousse ses estimations trop près de 0 % ou de 100 %. |

**Classification au seuil de 0,329.** Le seuil maximise l'indice de Youden sur les prédictions « hors pli » du groupe d'entraînement (chaque participant est prédit par un modèle qui ne l'a pas vu), puis il est appliqué tel quel au test.

| Sensibilité | Spécificité | VPP | VPN | Exactitude |
|---|---|---|---|---|
| 0,76 | 0,56 | 0,49 | 0,81 | 0,63 |

L'exactitude est proche de celle d'un modèle répondant « indemne » à tout le monde (0,64) : le critère de Youden équilibre sensibilité et spécificité, il ne maximise pas l'exactitude. 

### Comparaison avec des références

| Modèle | AUC (IC 95 %) | Brier | Pente de calibration |
|---|---|---|---|
| Plafond : vrai risque (aléa individuel inclus) | 0,77 (0,70 à 0,84) | 0,182 | 0,89 |
| Plafond : signal mesurable (sans l'aléa) | 0,75 (0,68 à 0,83) | — | — |
| Régression logistique | 0,75 (0,67 à 0,82) | 0,193 | 0,74 |
| XGBoost | 0,70 (0,62 à 0,78) | 0,206 | 0,74 |

- **Plafond « vrai risque »** : AUC obtenue en connaissant la probabilité exacte utilisée pour simuler chaque participant. Aucun modèle ne peut faire mieux.
- **Plafond « signal mesurable »** : AUC obtenue en connaissant le mécanisme de simulation mais pas l'aléa individuel, qu'aucune variable ne mesure. C'est le meilleur résultat réaliste.
- Les plafonds sont calculés sur les mêmes 200 participants de test : ils sont eux aussi imprécis.
- Test de DeLong, XGBoost contre régression logistique : écart d'AUC de 0,05 (IC 95 % : −0,098 à −0,001), p = 0,044. L'écart est à la limite de la significativité.

![Courbes ROC](results/roc_curve.png)

![Courbe de calibration](results/calibration_curve.png)

## Conclusion

- XGBoost se surapprend: Avec seulement 600 dossiers pour apprendre, un outil trop complexe finit par retenir des détails inutiles .
- Comparaison limitée: Les données sont simulées à partir d'un modèle logistique, ce que la régression logistique reproduit . Sur des données réelles, on peut penser que XGBoost aura une meilleure performance.
- Calibration imparfaite: les deux modèles donnent des probabilités de risque extrêmes.
- Métriques au seuil instables: La sensibilité vaut 0,76 ou 0,51 selon le seuil 

**Limites.** Un seul découpage entraînement/test ; 200 participants de test ; seul le nombre d'arbres est réglé ; données fictives, sans valeur clinique. Piste suivante : validation croisée répétée sur les 800 participants.

## Comment refaire la simulation ?

1. Ouvrir `analysis.R` dans RStudio.
2. Aller à *Session > Set Working Directory > To Source File Location*.
3. Cliquer sur *Source*.

Le script régénère les données (`atherosclerosis_participants.csv`), entraîne les modèles et écrit les résultats dans le dossier `results/`.

## Contenu du dépôt

| Fichier | Rôle |
|---|---|
| `analysis.R` | Code complet, commenté, de la simulation à l'évaluation |
| `results/predictions_per_participant.csv` | Risque prédit pour chaque participant, avec la colonne `set` (train ou test) |
| `results/roc_curve.png` | Courbes ROC de XGBoost et de la régression logistique sur le jeu de test |
| `results/calibration_curve.png` | Courbe de calibration sur le jeu de test |
| `results/model_comparison.csv` | AUC, Brier et calibration des plafonds, de la régression logistique et de XGBoost |
| `results/feature_table.csv` | Tableau des variables (valeurs manquantes, moyenne, écart-type), créé à l'exécution du script |
| `results/session_info.txt` | Versions de R et des packages utilisés |
