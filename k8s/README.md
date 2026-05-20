# Tropia — Kubernetes manifests

Deploys the SRS + Go backend + Postgres + Redis + Prometheus + Grafana
stack into a `tropia` namespace.

## What's in here

| File | Purpose |
|------|---------|
| `namespace.yaml` | Creates the `tropia` namespace. |
| `secrets.example.yaml` | Template — copy to `secrets.yaml`, fill, apply. |
| `postgres.yaml` | StatefulSet + headless Service + 20Gi PVC. |
| `postgres-init-configmap.yaml` | Mounts `infra/postgres/init.sql` for first boot. Regenerate before deploying — see header comment. |
| `redis.yaml` | Single-replica Deployment + Service. |
| `srs.yaml` | SRS 5 with ConfigMap-mounted srs.conf, LoadBalancer Service (RTMP / HLS / WHIP / SRT). |
| `backend.yaml` | Go API Deployment (2 replicas), HPA (2–20 on CPU 70%), `prometheus.io/scrape` annotations. |
| `ingress.yaml` | NGINX Ingress + cert-manager TLS for api.tropia.vn / hls.tropia.vn. |
| `prometheus.yaml` | Self-contained Prometheus that scrapes any pod with the `prometheus.io/scrape: "true"` annotation. |
| `grafana.yaml` | Grafana with the Prometheus data source pre-provisioned. |

## Deploy from scratch

```bash
# 1. Namespace
kubectl apply -f k8s/namespace.yaml

# 2. Secrets — copy the template, edit, apply (DO NOT commit the real file)
cp k8s/secrets.example.yaml k8s/secrets.yaml
$EDITOR k8s/secrets.yaml
kubectl apply -f k8s/secrets.yaml

# 3. Postgres init script — bake init.sql into a ConfigMap
kubectl create configmap postgres-init \
  --from-file=init.sql=infra/postgres/init.sql \
  -n tropia --dry-run=client -o yaml > k8s/postgres-init-configmap.yaml

# 4. Build & push the backend image (replace registry with yours)
docker build -t registry.tropia.vn/backend:dev ./backend
docker push registry.tropia.vn/backend:dev
# then update k8s/backend.yaml `image:` accordingly

# 5. Apply everything else
kubectl apply -f k8s/

# 6. Watch it come up
kubectl -n tropia get pods -w
```

## Local cluster (Docker Desktop K8s)

Same manifests work with Docker Desktop's built-in Kubernetes:

1. Docker Desktop → Settings → Kubernetes → Enable.
2. `docker build -t tropia/backend:dev ./backend` (local image; skip push).
3. `kubectl apply -f k8s/`.
4. `kubectl -n tropia port-forward svc/backend 3000:3000` to reach the API.
5. `kubectl -n tropia port-forward svc/grafana 3001:3000` to open Grafana
   at http://localhost:3001 (admin / value of `grafana-admin-password`).

## Observability

The backend exposes Prometheus metrics at `/metrics`:

- `tropia_http_requests_total{method,path,status}` — counter.
- `tropia_http_request_duration_seconds_bucket{method,path}` — histogram.
- Plus all the default Go process metrics (`go_*`, `process_*`).

Path labels use Gin's `c.FullPath()` (the route pattern), not the
concrete URL, so cardinality stays bounded.

## Production extras (not in this folder)

- **Cloudflare CDN** in front of the `hls.tropia.vn` Ingress — cache
  `*.m3u8` (short TTL ≈ 2s) and `*.ts` (1h+). Set the SRS HLS playlist's
  `#EXT-X-VERSION` to something CDN-friendly.
- **kube-prometheus-stack** Helm chart for AlertManager + dashboards
  + ServiceMonitor CRDs. The current manifests are minimal so they fit
  in this repo.
- **SRS edge cluster** when viewer count grows: add a separate
  Deployment with `mode remote` SRS pods and put a Service in front for
  the player-facing HLS.
