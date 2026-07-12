# simple-api — Docker + Helm + Argo CD

## Что это

Простое Flask-приложение (`app.py`), задеплоенное в Kubernetes через Helm-чарт
и управляемое по GitOps-модели с помощью Argo CD.

Приложение слушает порт `8080`, отдаёт два эндпоинта:
- `GET /` — JSON с `app`, `env`, `version` (значения берутся из переменных
  окружения `APP_NAME`, `ENV`, `VERSION`)
- `GET /health` — `{"status": "ok"}`, используется как liveness/readiness probe

---

## Что было сделано

### 1. Докеризация

Написан `Dockerfile` на базе `python:3.12-slim`:
- зависимости (`Flask`, `gunicorn`) ставятся отдельным слоем до копирования
  кода — для кэширования сборки;
- приложение запускается от непривилегированного пользователя `appuser`
  (`USER appuser`), не от root;
- запуск через `gunicorn`, а не встроенный dev-сервер Flask.

Образ собран и запушен в Docker Hub: `vaiz82/simple-api:0.1.0`.

### 2. Helm-чарт

Чарт лежит в `helm/simple-api/`. Ключевое требование — deployment должен
содержать **probes** и **resources**:

- `templates/deployment.yaml` объявляет `livenessProbe` и `readinessProbe`
  (HTTP GET на `/health`, порт `http` = 8080), а также блок `resources`
  (requests/limits по CPU и памяти). Все значения параметризованы через
  `values.yaml`, ничего не захардкожено в шаблоне.
- Дополнительно в чарте есть `service.yaml`, `serviceaccount.yaml`,
  `ingress.yaml` (выключен по умолчанию), `hpa.yaml` (выключен по
  умолчанию) — стандартный набор шаблонов уровня `helm create`.

### 3. Установка в кластер

Кластер — самостоятельно поднятый одноузловой Kubernetes (control-plane +
worker на одной ноде), **container runtime: cri-o**, не Docker/containerd.

```bash
helm upgrade --install simple-api ./helm/simple-api \
  --namespace simple-api \
  --set image.repository=vaiz82/simple-api \
  --set image.tag=0.1.0
```

Под успешно запущен, проверен через `port-forward` — оба эндпоинта отвечают
корректно.

### 4. Argo CD

Argo CD установлен в неймспейс `argocd` стандартным манифестом проекта.
Создан `Application`-ресурс (`argocd/application.yaml`), который:

- тянет чарт из git-репозитория (`path: helm/simple-api`, `targetRevision: main`);
- переопределяет `image.repository` / `image.tag` через `helm.parameters`;
- использует `syncPolicy.automated` с `prune: true` и `selfHeal: true` —
  то есть любое изменение в git автоматически применяется в кластере, а
  ручные правки (`kubectl edit`, `kubectl scale` и т.п.) автоматически
  откатываются к состоянию из git.

Проверено на практике:
- Push изменения `replicaCount` в git → Argo CD сам подхватил и применил
  без ручного `helm upgrade` или `kubectl apply`.
- Ручное `kubectl scale --replicas=1` → Argo CD засёк дрейф и вернул
  количество реплик к значению из git (self-heal сработал).

---

## Проблемы, с которыми столкнулись, и как решили

Эти моменты специально задокументированы — типичные грабли при первом
деплое в кластер с непривычным runtime.

**1. `docker` не был установлен.**
Решение: `sudo apt install -y docker.io`, добавление пользователя в группу
`docker`.

**2. `helm` не был установлен.**
Решение: `sudo snap install helm --classic`.

**3. Под не запускался: `CreateContainerConfigError`.**
Причина:
```
Error: container has runAsNonRoot and image has non-numeric user (appuser),
cannot verify user is non-root
```
cri-o (в отличие от containerd/Docker) требует **числовой** UID, чтобы
проверить `runAsNonRoot: true`. Dockerfile объявляет пользователя по имени
(`USER appuser`), и cri-o не может верифицировать, что это действительно
не root.

Решение — без пересборки образа, чисто на уровне Helm/Kubernetes:
```yaml
# values.yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
```
Явно заданный `runAsUser` перекрывает то, что задано (или не задано) в
образе, и cri-o проходит проверку.

**4. Поды не шедулились изначально.**
Причина: единственная нода в кластере — control-plane, у неё по умолчанию
taint `node-role.kubernetes.io/control-plane:NoSchedule`, запрещающий
обычным подам на неё садиться.
Решение (нормально для одноузлового тестового кластера):
```bash
kubectl taint nodes k8s node-role.kubernetes.io/control-plane:NoSchedule-
```

**5. `image.repository` в `values.yaml` случайно содержал тег.**
Было: `repository: vaiz82/simple-api:0.1.0` — при рендере шаблон добавлял
тег ещё раз (`{{ .Values.image.tag }}`), получалось
`vaiz82/simple-api:0.1.0:0.1.0` — невалидная ссылка на образ.
Решение: `repository` должен содержать только имя образа без тега, тег —
отдельным полем.

**6. `kubectl apply` на `argocd/application.yaml` падал:
`apiVersion not set, kind not set`.**
Причина: при ручном редактировании файла в `nano` были случайно потеряны
верхнеуровневые поля (`apiVersion`, `kind`, `metadata`).
Решение: файл полностью перезаписан через heredoc (`cat > file << 'EOF'`),
что исключает риск случайной порчи форматирования при копипасте в
интерактивный редактор.

**7. `docker build -t ...` падал с `invalid argument "\u00a0"`.**
Причина: в скопированную команду попал невидимый символ
non-breaking space (характерно для копипаста из браузера/чатов с "умным"
форматированием текста).
Решение: критичные команды набирать вручную, а не вставлять из буфера
обмена, либо вставлять сначала в текстовый файл и проверять перед
использованием.

---

## Стек

- **Приложение**: Python 3.12, Flask, gunicorn
- **Контейнеризация**: Docker, образ опубликован на Docker Hub
  (`vaiz82/simple-api:0.1.0`)
- **Оркестрация**: Kubernetes (одноузловой кластер, control-plane +
  worker на одной ноде), container runtime — **cri-o**
- **Деплой**: Helm 3 (кастомный чарт с probes и resources)
- **GitOps**: Argo CD, `syncPolicy.automated` (`prune` + `selfHeal`)
- **Git**: репозиторий на GitHub, Argo CD синкается напрямую из него

---

## Структура репозитория

```
simple-api/
├── app.py                     # Flask-приложение
├── requirements.txt
├── Dockerfile
├── .dockerignore
├── README.md                  # этот файл
├── helm/
│   └── simple-api/
│       ├── Chart.yaml
│       ├── values.yaml        # образ, resources, probes, env — всё здесь
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment.yaml   # содержит probes + resources
│           ├── service.yaml
│           ├── serviceaccount.yaml
│           ├── ingress.yaml      # выключен (ingress.enabled: false)
│           ├── hpa.yaml          # выключен (autoscaling.enabled: false)
│           └── NOTES.txt
└── argocd/
    └── application.yaml       # Argo CD Application-ресурс
```

---

## Как воспроизвести с нуля

```bash
# 1. Инструменты (если ещё не установлены)
sudo apt install -y docker.io
sudo snap install helm --classic
sudo usermod -aG docker $USER && newgrp docker

# 2. Сборка и публикация образа
docker build -t <dockerhub-user>/simple-api:0.1.0 .
docker push <dockerhub-user>/simple-api:0.1.0

# 3. (если нода — control-plane и это единственная нода в кластере)
kubectl taint nodes <node-name> node-role.kubernetes.io/control-plane:NoSchedule-

# 4. Установка чарта
kubectl create namespace simple-api --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install simple-api ./helm/simple-api \
  --namespace simple-api \
  --set image.repository=<dockerhub-user>/simple-api \
  --set image.tag=0.1.0

# 5. Argo CD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# отредактировать argocd/application.yaml (repoURL, image.repository)
kubectl apply -f argocd/application.yaml
kubectl -n argocd get application simple-api   # SYNC STATUS: Synced, HEALTH STATUS: Healthy
```







<img width="1301" height="196" alt="Screenshot 2026-07-11 at 23 26 26" src="https://github.com/user-attachments/assets/6deb5cc8-5c93-4beb-b8b3-2940f15fd7e9" />





