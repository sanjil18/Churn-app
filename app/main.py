from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

from app.schema import CustomerInput, PredictionOutput
from app.model_utils import predict_churn, load_model

app = FastAPI(
    title="Customer Churn Prediction API",
    description="Predicts whether a telecom customer is likely to churn.",
    version="1.0.0",
)

# Allow the frontend (or anyone testing the API) to call it from a browser
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def startup_event():
    # Load model once when the container starts, not on every request
    try:
        load_model()
        print("Model loaded successfully.")
    except FileNotFoundError as e:
        print(f"WARNING: {e}")


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.post("/predict", response_model=PredictionOutput)
def predict(customer: CustomerInput):
    try:
        result = predict_churn(customer.model_dump())
        return result
    except FileNotFoundError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Prediction failed: {e}")


# Serve the simple HTML frontend at the root
app.mount("/static", StaticFiles(directory="frontend"), name="static")


@app.get("/")
def serve_frontend():
    return FileResponse("frontend/index.html")
