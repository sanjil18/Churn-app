import joblib
import pandas as pd
from pathlib import Path

MODEL_PATH = Path(__file__).parent.parent / "model" / "churn_model.joblib"

_model = None


def load_model():
    """
    Loads the model once at startup and caches it.

    IMPORTANT: this assumes you saved a single scikit-learn Pipeline that
    includes BOTH preprocessing (encoding/scaling) AND the classifier, e.g.:

        from sklearn.pipeline import Pipeline
        pipeline = Pipeline([
            ("preprocessor", your_column_transformer),
            ("classifier", your_trained_model),
        ])
        pipeline.fit(X_train, y_train)
        joblib.dump(pipeline, "churn_model.joblib")

    If you instead saved the encoder/scaler and model separately, load both
    here and apply the encoder inside predict_churn() before calling
    model.predict_proba().
    """
    global _model
    if _model is None:
        if not MODEL_PATH.exists():
            raise FileNotFoundError(
                f"No model found at {MODEL_PATH}. "
                "Drop your churn_model.joblib file into the model/ folder."
            )
        _model = joblib.load(MODEL_PATH)
    return _model


def predict_churn(customer: dict) -> dict:
    model = load_model()

    # Model expects a DataFrame with the same column names used in training
    input_df = pd.DataFrame([customer])

    # The saved model is a bare RandomForestClassifier trained on
    # pd.get_dummies(df, drop_first=True) output, not a Pipeline with a
    # preprocessor baked in. Reproduce that one-hot encoding here, then
    # align to the exact columns/order the model was fit on.
    encoded_df = pd.get_dummies(input_df, drop_first=True)
    encoded_df = encoded_df.reindex(columns=model.feature_names_in_, fill_value=0)

    prediction = model.predict(encoded_df)[0]
    probability = model.predict_proba(encoded_df)[0][1]  # probability of "Yes" class

    return {
        "churn_prediction": "Yes" if prediction == 1 or prediction == "Yes" else "No",
        "churn_probability": round(float(probability), 4),
    }
