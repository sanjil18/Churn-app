FROM python:3.11-slim

WORKDIR /code

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY frontend ./frontend
COPY model ./model

# Run as an unprivileged user. The numeric UID lets Kubernetes verify runAsNonRoot.
RUN useradd --system --uid 10001 --no-create-home app
USER 10001

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
