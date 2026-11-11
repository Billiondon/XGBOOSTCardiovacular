#  Prédire la présence d'athérosclérose avec XGBoost
Ce projet construit, à partir de 800 participants fictifs, un modèle de ML (XGBoost) qui estime la probabilité d'être atteint d'athérosclérose. 

## Pourquoi ce projet ?
En consultation médicale, on cherche souvent à estimer le risque d'un patient à partir d'informations simples.
Avant d'appliquer ces méthodes à de vraies cohortes, il est précieux de s'entraîner sur des données simulées.

## La démarche suivie
- Creation d'une cohorte simulée
- Mise en place d'un groupe d'entrainement et d'un groupe de test
- Définition du meilleur modele offrant un compromis en performance et risque d'overfitting
- Entraînement du modèle final sur les données d'apprentissage, puis calcul pour chaque participant d'une probabilité individuelle d'athérosclérose comprise entre 0 et 1
- Evaluatuion des performances

## Les données
800 participants, une ligne par participant, 22 variables explicatives et une variable à prédire.

| Famille | Variables |
|---|---|
| Démographie | âge, sexe |
| Anthropométrie et hémodynamique | IMC, pression artérielle systolique et diastolique |
| Bilan lipidique | LDL-cholestérol, HDL-cholestérol, triglycérides |
| Métabolisme glucidique | HbA1c, diabète |
| Mode de vie et antécédents | statut tabagique, paquets-années, antécédents familiaux cardiovasculaires |
| Inflammation et fonction rénale | CRP ultrasensible, DFG estimé |
| Traitements | statine, antihypertenseur |
| Mesures de type « objet connecté » | activité physique, fréquence cardiaque de repos, variabilité sinusale (RMSSD), nombre de pas, durée de sommeil |

**Variable à prédire :** `atherosclerosis` (0 = absente, 1 = présente), par exemple une plaque athéromateuse carotidienne à l'échographie.

Quelques valeurs manquantes ont été introduites volontairement (CRP, VFC, pas, HDL, paquets-années), comme dans les données de vie réelle. XGBoost les gère directement.



## Résultats sur le jeu de test (n = 200)

| Indicateur | Valeur | Ce que cela signifie |
|---|---|---|
| **AUC**  | **0,69** (IC 95 % bootstrap : 0,60 à 0,77) | Si l'on prend au hasard un sujet atteint et un sujet indemne, le modèle se trompe 3 fois sur 10. |
| **Sensibilité** | 0,44 | Le modèle repère 44 % des sujets atteints ; 56 % passent inaperçus (faux négatifs). |
| **Spécificité** | 0,91 | 91 % des sujets indemnes sont correctement écartés. |
| **Valeur prédictive positive** | 0,73 | Quand le modèle prédit l'athérosclérose, il a raison 73 % du temps. |
| **Valeur prédictive négative** | 0,74 | Quand le modèle écarte l'athérosclérose, il a raison 74 % du temps. |
| **Exactitude** | 0,74 | Un modèle répondant « indemne » à tout le monde aurait 64 % d'exactitude (1 − prévalence) : le gain est réel mais limité. |
| **Score de Brier** | 0,208 | Le modèle ne donne pas des probabilités absurdes, mais reste un marge à combler. |
| **Seuil retenu** | 0,595 | Le modèle est prudent avant d'affirmer qu'un patient est atteint. |

![Courbe ROC du jeu de test](results/roc_curve.png)


## Conclusion
- Discrimination limitée.** Avec une AUC de 0,69, le modèle trie les participants mieux que le hasard, mais pas assez pour guider une décision individuelle.
- Surapprentissage. L'AUC atteint **0,94 sur les participants d'entraînement** contre 0,69 sur le test. Le modèle a en partie mémorisé les particularités de l'échantillon au lieu d'apprendre des règles généralisables. C'est pourquoi seules les lignes `test` du fichier de prédictions constituent une évaluation honnête.
- Faible effectif Avec 200 participants en test, l'incertitude est large (IC 95 % de 0,60 à 0,77).
- Une légère surestimation du risque. Le risque moyen prédit (0,38) dépasse un peu la fréquence observée (0,36). La calibration n'a toutefois pas été analysée en détail.

## Limites
- Les données sont simulées : les associations retrouvées reflètent la formule de simulation, pas la biologie.
- Un seul découpage entraînement / test, sur un échantillon de taille modeste.
- Aucune validation externe sur une cohorte indépendante.
- Une prédiction n'est pas une causalité : un bon score de risque ne prouve pas qu'un facteur cause la maladie.


## Comment refaire la simulation
1. Ouvrir `analysis.R` dans RStudio.
2. Aller à Session > Set Working Directory > To Source File Location.
3. Cliquer sur Source

Le script régénère les données, entraîne le modèle et écrit les résultats dans le dossier `results/`.

## Contenu du dépôt

| Fichier | Rôle |
|---|---|
| `analysis.R` | Code complet, commenté, de la simulation à l'évaluation |
| `results/predictions_per_participant.csv` | Risque prédit pour chaque participant, avec la colonne `set` (train ou test) |
| `results/roc_curve.png` | Courbe ROC du jeu de test |
| `results/feature_table.csv` | Tableau des variables (valeurs manquantes, moyenne, écart-type), créé à l'exécution du script |
