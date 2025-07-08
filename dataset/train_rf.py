#!/usr/bin/env python3
import os
import sys
import pandas as pd
import numpy as np
from sklearn import __version__ as SKL_VER
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split, GridSearchCV, cross_val_score
from sklearn.metrics import classification_report
import joblib
import coremltools as ct

# 0. Check scikit-learn version
print("scikit-learn", SKL_VER)
if tuple(map(int, SKL_VER.split('.')[:2])) > (1, 5):
    sys.exit("Please install scikit-learn≤1.5.1: pip install 'scikit-learn<=1.5.1'")

# 1. Paths
BASE_DIR = os.path.dirname(__file__)
csv_path = os.path.join(BASE_DIR, "all_windows.csv")
model_pkl = os.path.join(BASE_DIR, "rf_model.pkl")
coreml_path = os.path.join(BASE_DIR, "PresenceRF.mlmodel")

# 2. Load data
df = pd.read_csv(csv_path)
# windows features are all columns except 'label'
feature_cols = [c for c in df.columns if c != "label"]
X = df[feature_cols].values
# binary label: DESK→0, else→1
y = (df["label"] != "DESK").astype(int).values

# 3. Train/test split
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.3, stratify=y, random_state=42
)

# 4. Grid-search RandomForest
param_grid = {
    "n_estimators": [50, 100, 200],
    "max_depth": [5, 10, 20],
    "min_samples_leaf": [1, 2, 5]
}
rf = RandomForestClassifier(random_state=42, n_jobs=1)
grid = GridSearchCV(rf, param_grid, cv=5, scoring="f1", n_jobs=1, verbose=1)
print("Running GridSearchCV…")
grid.fit(X_train, y_train)
best = grid.best_estimator_
print("Best params:", grid.best_params_)

# 5. Cross-val score on full training set
scores = cross_val_score(best, X_train, y_train, cv=5, scoring="f1")
print("CV F1 scores:", scores, "→ mean:", scores.mean())

# 6. Evaluate on held-out test set
y_pred = best.predict(X_test)
from sklearn.metrics import classification_report

print("\nTest classification report:")
print(classification_report(
    y_test,
    y_pred,
    labels=[0, 1],               # explicitly include both classes
    target_names=["LEFT","WITH"]
))


# 7. Persist the sklearn model
joblib.dump(best, model_pkl)
print(f"\nSaved RandomForest to {model_pkl}")

# 8. Convert to Core ML
print("Converting to Core ML…")
coreml_model = ct.converters.sklearn.convert(
    best,
    feature_cols,    # input feature names
    "isWithUser"     # output name
)
coreml_model.author = "Issayush"
coreml_model.short_description = (
    "RF model: LEFT=0 (desk), WITH=1 (in hand/pocket)"
)
coreml_model.save(coreml_path)
print(f" Core ML model saved to {coreml_path}")

