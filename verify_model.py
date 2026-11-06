"""
Verifies the deployed churn model against the held-out test set, using the
EXACT preprocessing and train/test split from Tabular_classification.ipynb,
and the ACTUAL decision threshold used in production (app/model_utils.py).

Run from the project root:
    venv/bin/python verify_model.py
"""
import joblib
import pandas as pd
from pathlib import Path
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    classification_report,
    accuracy_score,
    precision_score,
    recall_score,
    f1_score,
    confusion_matrix,
)

DATA_PATH = Path("model") / "WA_Fn-UseC_-Telco-Customer-Churn.csv"
MODEL_PATH = Path("model") / "churn_model.joblib"
THRESHOLD = 0.4  # must match CHURN_THRESHOLD in app/model_utils.py

# --- Reproduce the exact preprocessing from the training notebook ---
df = pd.read_csv(DATA_PATH)
df["TotalCharges"] = pd.to_numeric(df["TotalCharges"], errors="coerce")
df["TotalCharges"] = df["TotalCharges"].fillna(0)
df = df.drop("customerID", axis=1)
df["Churn"] = df["Churn"].map({"Yes": 1, "No": 0})
df = pd.get_dummies(df, drop_first=True)

X = df.drop("Churn", axis=1)
y = df["Churn"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

# --- Load the actual deployed model artifact ---
model = joblib.load(MODEL_PATH)

# Sanity check: deployed model's expected columns must match our X_test columns
missing = set(model.feature_names_in_) - set(X_test.columns)
extra = set(X_test.columns) - set(model.feature_names_in_)
if missing or extra:
    print("WARNING: feature mismatch between deployed model and reconstructed test set!")
    print("Missing from X_test:", missing)
    print("Extra in X_test:", extra)
X_test = X_test.reindex(columns=model.feature_names_in_, fill_value=0)

# --- Evaluate at the DEFAULT 0.5 threshold (what .predict() gives you) ---
y_pred_default = model.predict(X_test)

# --- Evaluate at the ACTUAL PRODUCTION threshold (0.4) ---
y_prob = model.predict_proba(X_test)[:, 1]
y_pred_prod = (y_prob >= THRESHOLD).astype(int)

print("=" * 70)
print(f"Model: {type(model).__name__}")
print(f"Params: n_estimators={model.n_estimators}, max_depth={model.max_depth}, "
      f"class_weight={model.class_weight}, random_state={model.random_state}")
print(f"Test set size: {len(X_test)} rows ({y_test.sum()} actual churners)")
print("=" * 70)

print("\n--- Metrics at default threshold 0.5 (model.predict()) ---")
print(classification_report(y_test, y_pred_default, target_names=["No churn", "Churn"]))
print("Confusion matrix:\n", confusion_matrix(y_test, y_pred_default))

print(f"\n--- Metrics at PRODUCTION threshold {THRESHOLD} (what the live app uses) ---")
print(classification_report(y_test, y_pred_prod, target_names=["No churn", "Churn"]))
print("Confusion matrix:\n", confusion_matrix(y_test, y_pred_prod))

print("\n--- Summary (production threshold, for README / /version) ---")
print(f"accuracy:  {accuracy_score(y_test, y_pred_prod):.4f}")
print(f"precision: {precision_score(y_test, y_pred_prod):.4f}")
print(f"recall:    {recall_score(y_test, y_pred_prod):.4f}")
print(f"f1_score:  {f1_score(y_test, y_pred_prod):.4f}")
print(f"threshold: {THRESHOLD}")
