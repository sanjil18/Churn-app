"""
Logs a corrected MLflow run that reflects the model ACTUALLY deployed to
production (model/churn_model.joblib) -- including class_weight="balanced"
and evaluated at the real production threshold (0.4), not the notebook's
earlier uncorrected 0.5-threshold logging.
"""
import mlflow
import joblib
import pandas as pd
from pathlib import Path
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score

mlflow.set_tracking_uri("sqlite:///mlflow.db")
mlflow.set_experiment("Default")

DATA_PATH = Path("model") / "WA_Fn-UseC_-Telco-Customer-Churn.csv"
MODEL_PATH = Path("model") / "churn_model.joblib"
THRESHOLD = 0.4

df = pd.read_csv(DATA_PATH)
df["TotalCharges"] = pd.to_numeric(df["TotalCharges"], errors="coerce").fillna(0)
df = df.drop("customerID", axis=1)
df["Churn"] = df["Churn"].map({"Yes": 1, "No": 0})
df = pd.get_dummies(df, drop_first=True)

X = df.drop("Churn", axis=1)
y = df["Churn"]
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

model = joblib.load(MODEL_PATH)
X_test = X_test.reindex(columns=model.feature_names_in_, fill_value=0)
y_prob = model.predict_proba(X_test)[:, 1]
y_pred = (y_prob >= THRESHOLD).astype(int)

with mlflow.start_run(run_name="random-forest-smote-v1-deployed"):
    mlflow.log_params({
        "n_estimators": model.n_estimators,
        "max_depth": model.max_depth,
        "min_samples_split": model.min_samples_split,
        "class_weight": model.class_weight,
        "random_state": model.random_state,
        "resampling": "SMOTE",
        "decision_threshold": THRESHOLD,
    })
    mlflow.log_metrics({
        "accuracy": accuracy_score(y_test, y_pred),
        "precision": precision_score(y_test, y_pred),
        "recall": recall_score(y_test, y_pred),
        "f1_score": f1_score(y_test, y_pred),
    })
    mlflow.set_tags({
        "deployed": "true",
        "model_path": "model/churn_model.joblib",
        "note": "Reflects the actual artifact deployed to production, evaluated at the real decision threshold used by app/model_utils.py",
    })
    print("Logged run:", mlflow.active_run().info.run_id)
