# simple-api — Docker + Helm + Argo CD


















simple-api/
├── app.py
├── requirements.txt
├── Dockerfile
├── .dockerignore
├── README.md
├── helm/
│   └── simple-api/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── serviceaccount.yaml
│           ├── ingress.yaml
│           ├── hpa.yaml
│           └── NOTES.txt
└── argocd/
    └── application.yaml





















See helm/simple-api for the chart and argocd/application.yaml for GitOps deployment.

Build:
  docker build -t <user>/simple-api:0.1.0 .
  docker push <user>/simple-api:0.1.0

Install:
  helm upgrade --install simple-api ./helm/simple-api -n simple-api --create-namespace \
    --set image.repository=<user>/simple-api --set image.tag=0.1.0

Argo CD:
  kubectl apply -f argocd/application.yaml
