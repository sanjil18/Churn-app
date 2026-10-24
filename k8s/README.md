# Running the churn API on Kubernetes

These manifests run the churn prediction API on a local [kind](https://kind.sigs.k8s.io/) cluster. Nothing here needs a cloud account.

| File | What it creates |
|---|---|
| `configmap.yaml` | `churn-config`: non-secret settings, injected as environment variables |
| `deployment.yaml` | `churn-api`: the API pods, with probes, resource limits and a rolling-update strategy |
| `service.yaml` | `churn-api`: a stable ClusterIP address (port 80 to container port 8000) |
| `hpa.yaml` | `churn-api`: a Horizontal Pod Autoscaler (2 to 4 pods, 50% CPU target) |

## Design choices

- **Startup probe.** The app loads its model at startup. The startup probe allows up to 150 seconds (30 tries every 5s) before the readiness and liveness probes begin, so a slow model load is not mistaken for a crash.
- **Readiness vs liveness.** Both call `GET /health`. A failing readiness probe removes a pod from the Service without restarting it. A failing liveness probe restarts the container.
- **Zero-downtime updates.** `maxSurge: 1` and `maxUnavailable: 0` mean a working pod is only removed after its replacement is ready.
- **Resources.** Requests are 100m CPU and 320Mi memory. Limits are 500m CPU and 768Mi memory. Measured on the local cluster, an idle pod uses roughly 300Mi memory and under 10m CPU.
- **No `replicas:` field.** The HPA owns the pod count, so re-applying the Deployment does not fight with the autoscaler.
- **`imagePullPolicy: IfNotPresent`.** The image is loaded straight into the kind node, not pulled from a registry.

## Run it

1. Create the cluster:
   ```bash
   kind create cluster --name dev
   ```
2. Build the image from the repo root and load it into the cluster:
   ```bash
   docker build -t churn-app:latest .
   kind load docker-image churn-app:latest --name dev
   ```
3. Install metrics-server (the HPA needs it). On kind it needs `--kubelet-insecure-tls`:
   ```bash
   curl -L -o metrics-server.yaml https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   kubectl apply -f metrics-server.yaml
   kubectl patch deployment metrics-server -n kube-system --type=json \
     -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
   ```
4. Deploy:
   ```bash
   kubectl create namespace churn
   kubectl apply -f k8s/
   kubectl rollout status deployment churn-api -n churn --timeout=180s
   ```
5. Try it:
   ```bash
   kubectl port-forward -n churn svc/churn-api 8090:80
   curl -s localhost:8090/health
   ```
   Open `http://localhost:8090/docs` to send a request to `POST /predict`.

## What was tested

| Test | Command | Observed |
|---|---|---|
| Startup | `kubectl get pods -n churn -w` | A new pod stays `0/1` for roughly 55 to 80 seconds while the model loads, then becomes ready |
| Self-healing | `kubectl delete pod <name> -n churn` | A replacement is created; the other pod keeps serving |
| Bad release | `kubectl set image deployment/churn-api churn-api=churn-app:does-not-exist -n churn` | The new pod goes to `ErrImagePull`; the two working pods stay `1/1` |
| Rollback | `kubectl rollout undo deployment churn-api -n churn` | Back to the previous version; then re-run `kubectl apply -f k8s/deployment.yaml` so the file and the cluster agree |
| Autoscaling | one `POST /predict` from the docs page | The HPA scaled 2 to 3 pods, then back to 2 after its 60-second stabilization window |

## Troubleshooting

| Symptom | First thing to check |
|---|---|
| Pod `Pending` | `kubectl describe pod -n churn`, then the Events (for example insufficient memory) |
| `ErrImagePull` / `ImagePullBackOff` | The Event text: `not found`, `i/o timeout` and `pull access denied` are three different causes |
| `CrashLoopBackOff` | `kubectl logs -n churn deploy/churn-api --previous` |
| `Running` but `0/1` | The readiness probe path; `kubectl describe pod` shows the probe failures |
| HPA shows `<unknown>` | metrics-server is not running, or the pods have no CPU request |

## Known limitations

- The image in these tests was built from an earlier model. The deployment setup is what is demonstrated here, not the latest model's accuracy.
- The model was saved with scikit-learn 1.6.1 but the image installs 1.5.0, which produces an `InconsistentVersionWarning` at startup. Pin one version in `requirements.txt` for both training and serving.
