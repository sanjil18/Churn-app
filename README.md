# Customer Churn Prediction — End-to-End MLOps Pipeline

![Python](https://img.shields.io/badge/python-3.10%2B-blue)
![FastAPI](https://img.shields.io/badge/FastAPI-0.111-009688)
![Terraform](https://img.shields.io/badge/Terraform-AWS-844FBA)

Predicts which telecom customers are likely to cancel their subscription, so a business can intervene — with a discount, a call, a better plan — before losing them, rather than finding out after the fact.

## Live Demo

**[http://13.63.133.16:8000](http://13.63.133.16:8000)**

This is a live, running API + frontend — not a screenshot or a local-only demo. It's serving predictions from an EC2 instance provisioned entirely by Terraform, deployed automatically by GitHub Actions on every push to `main`. Interactive API docs are available at [`/docs`](http://13.63.133.16:8000/docs).

## Architecture Overview

```text
┌──────────────────────┐
│  Jupyter Notebook     │   RandomForestClassifier + SMOTE, tracked with MLflow
│  (training)           │   (params, metrics, model artifact)
└──────────┬────────────┘
           │ joblib.dump()
           ▼
┌──────────────────────┐
│  model/churn_model    │
│  .joblib               │
└──────────┬────────────┘
           │ loaded at startup
           ▼
┌──────────────────────┐        ┌──────────────────────┐
│  FastAPI              │──────▶│  Docker image         │
│  (app/main.py)        │ build │                       │
└──────────────────────┘        └──────────┬───────────┘
                                            │ push
                                            ▼
                                 ┌──────────────────────┐
                                 │  AWS ECR              │
                                 │  (image registry)     │
                                 └──────────┬───────────┘
                                            │ pull
                                            ▼
┌──────────────────────┐        ┌──────────────────────┐
│  GitHub Actions        │──SSM─▶│  AWS EC2               │
│  (CI/CD, on push)      │       │  (provisioned by       │
│                        │       │   Terraform)           │
└──────────────────────┘        └──────────────────────┘
```

Every push to `main` triggers GitHub Actions to build the image, push it to ECR, and redeploy it to the running EC2 instance via AWS Systems Manager — no manual SSH, no manual redeploy steps.

## What This Project Demonstrates

- **ML methodology done correctly**: SMOTE is applied *inside* an `imblearn` pipeline, not before the train/test split — avoiding the data leakage that comes from oversampling before cross-validation. Evaluated with precision/recall/F1, not just accuracy, because the dataset is class-imbalanced (churners are the minority class).
- **Experiment tracking with MLflow**: hyperparameters, evaluation metrics, and the trained model artifact are all logged per run, backed by a SQLite tracking store — not just numbers eyeballed in notebook output.
- **API development with FastAPI**, including Pydantic schema validation on every request field (e.g. `Contract` is constrained to the three actual values the model was trained on, not a free-text string).
- **Containerization with Docker** — a reproducible image, not "works on my machine."
- **Infrastructure as Code with Terraform** — EC2, ECR, IAM roles, security groups, and an Elastic IP are all defined as code, not clicked together in the AWS console.
- **Secure remote access via AWS Systems Manager (SSM)** for CI/CD deploys, rather than routing deploys over SSH — the security group does still permit SSH, but only from a restricted, configurable CIDR, not the public internet, and it's not part of the deploy path.
- **CI/CD with GitHub Actions** — every commit to `main` automatically builds, pushes to ECR, and redeploys, with zero manual steps after initial setup.
- **Real production debugging, not just happy-path code**: found and fixed an EC2 bootstrap script bug (Ubuntu 24.04 dropped the `awscli` apt package, silently killing the whole boot script under `set -e`) and a separate IAM credential race condition on first boot (the instance role's credentials weren't always propagated before the script tried to use them) — both diagnosed from actual boot failures and fixed with a bounded retry loop, not guessed at.

## Tech Stack

| Category | Tools |
| --- | --- |
| Language | Python 3.10+ |
| ML | scikit-learn, imbalanced-learn (SMOTE) |
| Experiment tracking | MLflow |
| API | FastAPI, Pydantic |
| Containerization | Docker |
| Infrastructure as Code | Terraform |
| Cloud | AWS (EC2, ECR, IAM, Systems Manager) |
| CI/CD | GitHub Actions |

## Project Structure

```text
churn-app/
├── app/
│   ├── main.py                    # FastAPI application and routes
│   ├── model_utils.py             # Model loading + prediction logic (incl. decision threshold)
│   └── schema.py                  # Pydantic request/response schemas
├── frontend/
│   └── index.html                 # Browser UI, calls the /predict endpoint
├── model/
│   ├── churn_model.joblib         # Trained model artifact the API loads at startup
│   └── WA_Fn-UseC_-Telco-Customer-Churn.csv   # Training dataset
├── terraform/
│   ├── ec2.tf                     # EC2 instance + user_data bootstrap script
│   ├── ecr.tf                     # Container registry
│   ├── iam.tf                     # Instance role (ECR pull, SSM access)
│   ├── security_group.tf          # Network ingress/egress rules
│   ├── outputs.tf                 # Terraform output values (URLs, IPs, etc.)
│   ├── provider.tf                # AWS provider + backend config
│   ├── user_data.sh.tpl           # EC2 first-boot script (installs Docker, AWS CLI, starts the app)
│   └── DEPLOY.md                  # Full deployment walkthrough
├── .github/workflows/
│   └── deploy.yml                 # CI/CD: build, push to ECR, redeploy via SSM
├── Tabular_classification.ipynb   # Model training notebook (MLflow-tracked)
├── Dockerfile                     # Container image definition
├── requirements.txt                # Python dependencies (app runtime only)
└── README.md
```

## Running Locally

```bash
git clone <this-repo-url>
cd churn-app

python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate

pip install -r requirements.txt
```

Make sure a trained model exists at `model/churn_model.joblib` (see [Model Details](#model-details) — you can produce this by running `Tabular_classification.ipynb`).

```bash
uvicorn app.main:app --reload
```

Visit `http://localhost:8000` for the form UI, or `http://localhost:8000/docs` for interactive Swagger docs.

## Running with Docker

```bash
docker build -t churn-app .
docker run -p 8000:8000 churn-app
```

## Deploying to AWS

Provisioning is driven entirely by Terraform — see **[terraform/DEPLOY.md](terraform/DEPLOY.md)** for the full step-by-step walkthrough. In short, `terraform apply` provisions:

- An **ECR** repository to hold the Docker image
- An **EC2** instance (`t3.micro`, free-tier eligible) that runs the container
- A **security group** opening the app port publicly
- An **IAM role** (via instance profile) granting the instance ECR pull access and SSM session access — no embedded credentials
- An **Elastic IP** so the public URL stays fixed across instance restarts

## CI/CD

Every push to `main` triggers [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml), which:

1. Builds the Docker image and tags it with the commit SHA
2. Pushes it to ECR (both the SHA tag and `latest`)
3. Sends a command to the running EC2 instance via **AWS SSM** — no SSH — that pulls the new image, stops/removes the old container, and starts the new one

No manual steps are needed after the initial `terraform apply`; every subsequent code change ships itself.

## Model Details

- **Dataset**: [Telco Customer Churn](https://www.kaggle.com/datasets/blastchar/telco-customer-churn) (Kaggle) — 7,043 customers, 21 features, binary churn label.
- **Model**: `RandomForestClassifier` (`n_estimators=500`, `max_depth=15`), with `SMOTE` oversampling applied inside an `imblearn` pipeline to correct for class imbalance without leaking test data into training.
- **Decision threshold**: predictions use a 0.4 probability threshold (rather than the default 0.5) to bias toward catching more at-risk customers — in a churn-prevention context, a missed churner is typically costlier than a false alarm.
- **Metrics** (from the MLflow-tracked run, test set):

  | Metric | Score |
  | --- | --- |
  | Accuracy | 0.791 |
  | Precision | 0.600 |
  | Recall | 0.627 |
  | F1 | 0.613 |

  Precision/recall/F1 — not just accuracy — are the metrics that matter here, since the "churn" class is a minority of the dataset.

## What I'd Improve With More Time

- **A staging environment** before production, so infra/model changes get validated on a throwaway instance before hitting the live URL.
- **ECS/Fargate instead of a single EC2 instance**, for real scaling, rolling deploys, and no single point of failure.
- **Automated tests** — unit tests for `model_utils.py`'s prediction logic and an integration test hitting `/predict`, run in CI before deploy, not just linting.
- **Tighter IAM policies**: the instance role currently uses AWS managed policies (`AmazonEC2ContainerRegistryReadOnly`, `AmazonSSMManagedInstanceCore`) rather than a hand-scoped least-privilege policy — broader than strictly necessary, and worth narrowing for a real production setup.
