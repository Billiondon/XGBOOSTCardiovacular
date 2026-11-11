# Ce script déroule, étape par étape, la construction et l'évaluation d'un modèle de risque, comme on le ferait pour valider un score avant de l'utiliser en consultation :
#
#    1. simuler une cohorte de 800 participants ;
#    2. séparer un groupe d'entraînement et un groupe de test ;
#    3. régler le modèle par validation croisée ;
#    4. calculer un risque individuel pour chaque participant ;
#    5. évaluer le modèle sur des participants qu'il n'a jamais vus.
#
#  Les données sont fictives : les résultats n'ont aucune valeur clinique.


#  Préparation : packages et dossier de sortie
# xgboost : le modèle ; pROC : courbe ROC et AUC ; ggplot2 : graphiques.
pkgs <- c("xgboost", "pROC", "ggplot2")
to_install <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(to_install)) install.packages(to_install)
invisible(lapply(pkgs, library, character.only = TRUE))
dir.create("results", showWarnings = FALSE)


#Simulation de la cohorte (800 participants) 
# La graine (set.seed) fixe le hasard : tout le monde obtient exactement les
# mêmes participants, ce qui rend l'analyse reproductible.
set.seed(42)
n <- 800
clip <- function(x, lo, hi) pmin(pmax(x, lo), hi)   # borne les valeurs aberrantes

# Données démographiques et anthropométriques
age   <- round(clip(rnorm(n, 62, 11), 35, 90))
sex   <- sample(c("F", "M"), n, replace = TRUE)
male  <- as.integer(sex == "M")
bmi   <- round(clip(rnorm(n, 27.5 + 0.8 * male, 4.5), 17, 48), 1)

# Pression artérielle (augmente avec l'âge et l'IMC)
sbp   <- round(clip(rnorm(n, 115 + 0.45 * (age - 35) + 0.6 * (bmi - 27), 13), 90, 200))
dbp   <- round(clip(sbp * 0.55 + rnorm(n, 8, 6), 55, 115))

# Bilan lipidique et glycémique
ldl   <- round(clip(rnorm(n, 125 + 0.3 * (age - 60), 32), 50, 260))
hdl   <- round(clip(rnorm(n, 55 - 8 * male - 0.5 * (bmi - 27), 12), 22, 100))
tg    <- round(clip(rlnorm(n, log(125) + 0.012 * (bmi - 27), 0.45), 40, 600))
hba1c <- round(clip(rnorm(n, 5.7 + 0.01 * (bmi - 27) + 0.01 * (age - 60), 0.7), 4.4, 12), 1)
diabetes <- as.integer(hba1c >= 6.5 | runif(n) < 0.03)

# Tabagisme, antécédents, inflammation et fonction rénale
smoking_status <- sample(c("never", "former", "current"), n, replace = TRUE,
                         prob = c(0.45, 0.35, 0.20))
pack  <- ifelse(smoking_status == "never", 0,
                round(clip(rgamma(n, 2.2, scale = 9), 0.5, 100)))
fam   <- as.integer(runif(n) < 0.22)                    # antécédents familiaux CV
crp   <- round(clip(rlnorm(n, log(1.8) + 0.03 * (bmi - 27) +
                             0.4 * (smoking_status == "current"), 0.8), 0.1, 30), 1)
egfr  <- round(clip(rnorm(n, 98 - 0.75 * (age - 40), 14), 15, 130))

# Mesures de type "objet connecté" (montre, bracelet)
activity <- round(clip(rgamma(n, 2, scale = 70) - 0.8 * (age - 60), 0, 600))
rhr   <- round(clip(rnorm(n, 68 + 0.15 * (bmi - 27) - 0.002 * activity +
                            1.5 * (smoking_status == "current"), 8), 45, 105))
hrv   <- round(clip(rnorm(n, 38 - 0.35 * (age - 60) + 0.015 * activity, 11), 8, 90))
steps <- round(clip(rnorm(n, 6500 + 8 * activity - 40 * (age - 60), 2200), 800, 18000))
sleep <- round(clip(rnorm(n, 6.9, 0.9), 3.5, 10), 1)

# Traitements en cours
statin  <- as.integer((ldl > 130 & runif(n) < 0.35) | (diabetes == 1 & runif(n) < 0.4))
antihyp <- as.integer(sbp > 135 & runif(n) < 0.55)

# Risque "vrai" d'athérosclérose : combinaison de facteurs de risque connus
# (âge, sexe masculin, pression, LDL, diabète, tabac...) plus une part d'aléa
# individuel, comme dans la réalité.
lin <- -9 + 0.075 * (age - 35) + 0.55 * male + 0.012 * (sbp - 120) +
  0.010 * (ldl - 120) - 0.018 * (hdl - 50) + 0.0012 * (tg - 120) +
  0.55 * diabetes + 0.35 * (smoking_status == "current") +
  0.18 * (smoking_status == "former") + 0.012 * pack + 0.35 * fam +
  0.18 * log(crp) - 0.005 * (egfr - 90) - 0.0015 * activity -
  0.015 * (hrv - 35) + 0.012 * (bmi - 27) - 0.25 * statin + 0.05 * antihyp +
  rnorm(n, 0, 0.6)
b <- uniroot(function(b) mean(plogis(lin + b)) - 0.35, c(-10, 10))$root  # prévalence visée ~35 %
atherosclerosis <- rbinom(n, 1, plogis(lin + b))        # 0 = absente, 1 = présente

# Assemblage du tableau : une ligne par participant
df <- data.frame(
  participant_id = sprintf("P%04d", 1:n), age_years = age, sex = sex, bmi = bmi,
  systolic_bp = sbp, diastolic_bp = dbp, ldl_mgdl = ldl, hdl_mgdl = hdl,
  triglycerides_mgdl = tg, hba1c_pct = hba1c, diabetes = diabetes,
  smoking_status = smoking_status, smoking_pack_years = pack,
  family_history_cvd = fam, crp_mgL = crp, egfr_ml_min = egfr,
  statin_use = statin, antihypertensive_use = antihyp,
  physical_activity_min_week = activity, resting_hr_bpm = rhr,
  hrv_rmssd_ms = hrv, steps_per_day = steps, sleep_hours = sleep,
  atherosclerosis = atherosclerosis)

# Valeurs manquantes réalistes (examen non fait, capteur non porté...)
df$crp_mgL[runif(n) < 0.08]            <- NA
df$hrv_rmssd_ms[runif(n) < 0.12]       <- NA
df$steps_per_day[runif(n) < 0.10]      <- NA
df$hdl_mgdl[runif(n) < 0.03]           <- NA
df$smoking_pack_years[runif(n) < 0.05] <- NA

write.csv(df, "atherosclerosis_participants.csv", row.names = FALSE)
cat("Données :", dim(df), "| cas :", sum(df$atherosclerosis), "\n")


# Préparation des variables et tableau de features --------------------

set.seed(42)
df$sex_male    <- as.integer(df$sex == "M")
df$smoking_ord <- match(df$smoking_status, c("never", "former", "current")) - 1L

# Les 22 variables explicatives (features) fournies au modèle
FEATURES <- c("age_years", "sex_male", "bmi", "systolic_bp", "diastolic_bp",
              "ldl_mgdl", "hdl_mgdl", "triglycerides_mgdl", "hba1c_pct", "diabetes",
              "smoking_ord", "smoking_pack_years", "family_history_cvd", "crp_mgL",
              "egfr_ml_min", "statin_use", "antihypertensive_use",
              "physical_activity_min_week", "resting_hr_bpm", "hrv_rmssd_ms",
              "steps_per_day", "sleep_hours")

# Tableau descriptif : proportion de valeurs manquantes, moyenne, écart-type
feature_table <- data.frame(
  feature     = FEATURES,
  pct_missing = round(100 * colMeans(is.na(df[, FEATURES])), 1),
  mean        = round(sapply(df[, FEATURES], mean, na.rm = TRUE), 2),
  sd          = round(sapply(df[, FEATURES], sd,   na.rm = TRUE), 2)
)
write.csv(feature_table, "results/feature_table.csv", row.names = FALSE)
print(feature_table)


# Séparation entraînement (75 %) / test (25 %) 
# Le jeu de test est mis de côté : il ne sert qu'à évaluer le modèle final,comme une cohorte de validation. La séparation est stratifiée : la même proportion de cas se retrouve dans les deux groupes.
y <- df$atherosclerosis
idx_test <- unlist(lapply(split(seq_len(nrow(df)), y),
                          function(i) sample(i, size = round(length(i) * 0.25))))
is_test <- seq_len(nrow(df)) %in% idx_test

X <- as.matrix(df[, FEATURES])
dtrain <- xgb.DMatrix(X[!is_test, ], label = y[!is_test])
y_test <- y[is_test]
print(table(is_test))      # attendu : 600 entraînement, 200 test


# Réglage du modèle par validation croisée (5 plis) 
# Combien d'arbres de décision empiler ? Trop peu : le modèle apprend mal.
# Trop : il mémorise le bruit (surapprentissage). La validation croisée découpe l'entraînement en 5 parties, entraîne sur 4 et vérifie sur la 5e, à tour de rôle, et on s'arrête quand la performance cesse de s'améliorer.
params <- list(objective = "binary:logistic", eval_metric = "logloss",
               eta = 0.05, max_depth = 3, min_child_weight = 3,
               subsample = 0.8, colsample_bytree = 0.8)

cv <- xgb.cv(params = params, data = dtrain, nrounds = 1000, nfold = 5,
             stratified = TRUE, early_stopping_rounds = 30, verbose = 0)
cv_log   <- as.data.frame(cv$evaluation_log)
test_col <- grep("^test_.*_mean$", names(cv_log), value = TRUE)[1]
best_nrounds <- which.min(cv_log[[test_col]])
cat("Nombre d'arbres retenu :", best_nrounds, "\n")   


# Pour chaque participant, le modèle renvoie une probabilité entre 0 et 1 :
# son risque estimé d'athérosclérose.
model  <- xgb.train(params = params, data = dtrain, nrounds = best_nrounds, verbose = 0)
p_all  <- predict(model, xgb.DMatrix(X))
p_test <- p_all[is_test]

predictions <- data.frame(participant_id = df$participant_id,
                          set = ifelse(is_test, "test", "train"),
                          observed = y,
                          predicted_risk = round(p_all, 4))
write.csv(predictions, "results/predictions_per_participant.csv", row.names = FALSE)



# Évaluation sur le jeu de test 
# AUC : probabilité que le modèle attribue un risque plus élevé à un sujet
# atteint qu'à un sujet indemne (0,5 = hasard, 1 = parfait).
roc_obj <- roc(y_test, p_test, quiet = TRUE, direction = "<")
print(auc(roc_obj)); print(ci.auc(roc_obj))

# Seuil de Youden : seuil de risque qui équilibre au mieux sensibilité et
# spécificité. Au-dessus du seuil, on classe le participant "à risque".
thr <- as.numeric(coords(roc_obj, "best", best.method = "youden",
                         ret = "threshold", transpose = FALSE)$threshold[1])
pred_class <- as.integer(p_test >= thr)
tp <- sum(pred_class == 1 & y_test == 1)   
tn <- sum(pred_class == 0 & y_test == 0) 
fp <- sum(pred_class == 1 & y_test == 0)   
fn <- sum(pred_class == 0 & y_test == 1)   

print(c(seuil = thr,
        sensibilite = tp / (tp + fn),      # part des malades repérés
        specificite = tn / (tn + fp),      # part des sujets sains écartés
        VPP = tp / (tp + fp),              # fiabilité d'un test positif
        VPN = tn / (tn + fn),              # fiabilité d'un test négatif
        exactitude = (tp + tn) / length(y_test)))

# Score de Brier : écart entre risque annoncé et réalité (plus bas = mieux).
# La référence correspond à un modèle sans information (même risque pour tous).
cat("Brier :", mean((p_test - y_test)^2),
    "| référence :", mean(y_test) * (1 - mean(y_test)), "\n")

# Mesure du surapprentissage : AUC sur les participants d'entraînement.
cat("AUC entraînement :", as.numeric(auc(roc(y[!is_test], p_all[!is_test],
                                             quiet = TRUE, direction = "<"))), "\n")


#Courbe ROC.
p_roc <- ggroc(roc_obj) + theme_minimal()
ggsave("results/roc_curve.png", p_roc, width = 6, height = 5, dpi = 200)