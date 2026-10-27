# Устройство infra

## Кластер

- k3d-кластер `aiip`: k3s `v1.34.1` в Docker, одна нода, kubectl-контекст
  `k3d-aiip`. Описан в `cluster.yaml`, создаётся `make up`.
- Namespace `infra` — общая инфраструктура, `apps` — сервисы, `keda` —
  KEDA, `kube-system` — Traefik и metrics-server из k3s.
- Компоненты по одному экземпляру, без операторов и репликации:
  StatefulSet с томом у всех, кроме kube-state-metrics (Deployment).
  Манифесты — kustomize в `k8s/`, конфиги компонентов — файлы в
  `k8s/config/`, из них kustomize собирает ConfigMap'ы.

| Компонент | Версия | Адрес в кластере |
|---|---|---|
| Postgres | 18.6 | `postgres.infra:5432` |
| Dragonfly | 2.0.2 | `dragonfly.infra:6379` |
| SeaweedFS (S3) | 4.48 | `seaweedfs.infra:8333` |
| Alloy | 1.21.1 | `alloy.infra:4317` (OTLP gRPC), `alloy.infra:4318` (OTLP HTTP) |
| Loki | 3.7.9 | `loki.infra` |
| Tempo | 3.1.1 | `tempo.infra` |
| Prometheus | 3.15.1 | `prometheus.infra:9090` |
| Grafana | 13.2.4 | `http://grafana.localhost` через Traefik |
| KEDA | чарт 2.21.0 | namespace `keda` |

- Пароли инфры — в `.env` (не в git). `make up` сверяет его с
  `.env.example` и переносит в Secret `infra`.
- Namespace `apps` ограничен `ResourceQuota` (`requests` 6 CPU и 4608Mi,
  `limits` памяти 5Gi) и `LimitRange` (по умолчанию 50m/64Mi запрос,
  500m/256Mi лимит): один сервис не может забрать машину у соседей.
- Флаг частоты HPA (5 с) задан в `cluster.yaml` и применяется только при
  создании кластера.

## Сеть и gateway

- Наружу на `127.0.0.1` k3d публикует только Traefik (`:80`, `:443`) и API
  Kubernetes (`:6443`). Инфра и сервисы — `ClusterIP`, портов на хосте у них
  нет. С хоста к инфре ходят через `make forward`.
- Внутри кластера сервисы ходят в инфру по `<имя>.infra`, друг к другу — по
  короткому имени Service: `http://auth:8001`. Service балансирует на
  готовые поды.
- Gateway — Traefik, встроенный в k3s. Его настройки (JSON-логи, access
  log, трейсы в Alloy под именем `gateway`) — `traefik.yaml`
  (HelmChartConfig).
- Реестра сервисов нет. Как сервис виден снаружи, описывают манифесты в его
  `k8s/`: Ingress с префиксом пути и Middleware Traefik с rate limit.
  Traefik читает их через API Kubernetes и шлёт трафик только на поды с
  пройденной readiness.
- Фронт и API живут на одном домене за Traefik: фронт — на `/`, сервисы — на
  `/api/<сервис>`; так `HttpOnly`-куки работают без CORS.
- Ответы, которые отдаёт сам Traefik (нет маршрута, rate limit, нет готовых
  подов), идут без `X-Request-ID`: id есть только в его access log и в Tempo.

## Выдача ресурсов сервису

`make service name=<имя>` запускает `postgres/provision.sh` и
`seaweedfs/provision.sh` внутри подов инфры: роль и БД в Postgres, бакет и
S3-пользователь, префикс ключей `<имя>:` в кэше. Суперпароль Postgres
сервисам не выдаётся. Роль `monitoring` с `pg_monitor` для экспортёра
создаёт `make up` (`postgres/monitoring.sh`).

## Наблюдаемость

Всё смотрится в Grafana. Источники данных и дашборды лежат файлами в
`k8s/config/`, правки в UI пересоздание кластера не переживают;
`make observability-apply` применяет файлы без пересоздания.

- **Alloy** — единственный сборщик, один экземпляр:
  - читает stdout всех подов через API Kubernetes и шлёт в Loki;
  - принимает OTLP (`alloy.infra:4317` gRPC, `:4318` HTTP) и шлёт трейсы
    в Tempo;
  - собирает `/metrics` с подов с аннотацией `prometheus.io/scrape: "true"`
    (порт — `prometheus.io/port`, путь — `prometheus.io/path`), метрики
    контейнеров из kubelet и kube-state-metrics и пишет в Prometheus.
- **Логи** — Loki, 14 дней. Метки: `app` (метка пода `app`), `namespace`,
  `pod`, `container`, `level` (`info`/`warn`/`error`). `trace_id` из JSON
  (у Traefik — `TraceId`) — structured metadata:
  `{app="auth"} | trace_id="…"`.
- **Трейсы** — Tempo, 7 дней. Трейс начинается в Traefik (`gateway`) и
  продолжается в сервисах. Из трейсов Tempo считает span-метрики и карту
  сервисов в Prometheus. Сэмплирование — 100%.
- **Метрики** — Prometheus, 15 дней и не больше 4 ГБ; сам ничего не
  собирает, только принимает от Alloy и Tempo. Метрики отдают сервисы,
  Traefik, Postgres (экспортёр в поде Postgres), Dragonfly, SeaweedFS.
- **Связки в Grafana**: из строки лога по `trace_id` — в трейс, из спана —
  в логи запроса, из трейса — в метрики сервиса.
- Сквозной идентификатор — `trace_id` OpenTelemetry. Сервисы отдают его
  наружу как `X-Request-ID` и `request_id` в ошибке.

## Масштабирование сервисов

KEDA ставится чартом (`keda.yaml`) и масштабирует сервисы по их
`ScaledObject`: по метрикам из Prometheus и CPU из metrics-server
(встроен в k3s). Границы числа подов задаёт сервис у себя в `k8s/`.

## Соглашения

- В файлах инфры (Makefile, манифесты, yaml, `.env`) комментариев нет:
  объяснения живут в этой документации.
- Название — AIIP заглавными; `aiip` — только там, где этого требует
  техника (имена образов, кластера, контекстов).

## Решения

- **Kubernetes через k3d на одной машине** (2026-10-21). k3s — самый лёгкий
  вариант для слабого мака; инфра по одному экземпляру, без операторов,
  Envoy и репликации БД. Compose, Swarm и kind с операторами отброшены.
- **Наружу торчит только gateway, как на сервере** (2026-10-21): локальный
  стенд повторяет боевую схему, переезд на сервер не меняет манифестов.
  Инфра доступна с хоста через port-forward, а не через опубликованные
  порты.
- **Gateway — встроенный в k3s Traefik**, а не отдельный компонент.
- **Сервисы stateless**, экземпляров несколько, все одинаковые.
- **Выдача ресурсов — sh-скрипты, а не операторы**: операторы тяжёлые, а
  суперпароль Postgres сервисам не выдаётся. Отдельного сноса данных
  сервиса нет: чистый лист — `make delete` и `make up`.
- **SeaweedFS вместо MinIO.**
- **Наблюдаемость — Grafana + Loki + Tempo + Prometheus со сборщиком
  Alloy** (2026-10-22): лёгкий стек (~0,6 ГБ на маке) с одним UI и связками
  лог ↔ трейс ↔ метрики. Elastic/OpenSearch и SigNoz (ClickHouse) тяжёлые,
  OpenObserve — свой UI вместо Grafana. Логи приложений в Postgres не
  пишутся: журнал событий, нужный продукту, — данные сервиса в его таблицах.
  Alloy — один экземпляр; на нескольких нодах станет DaemonSet.
- **Автоскейлинг KEDA по нагрузке** (2026-10-25): до ~12 сервисов на одной
  ноде, поэтому производительность — за счёт гибкости (дешёвые `requests`,
  масштабирование по насыщению), а не выделенных ресурсов.

## Чего пока нет

- Алертов: сценарии, пороги и канал доставки не выбраны.
- Registry образов: образы грузятся в ноду через `k3d image import`, старые
  теги копятся до пересоздания кластера.
- Overlay для сервера: `minReplicas: 2`, ресурсы по замерам на его железе,
  домен и TLS.
- Домена и TLS-сертификата: Ingress без `host` отвечает на любой адрес, на
  `:443` — самоподписанный сертификат Traefik.
- Rate limit по IP клиента на маке: Traefik видит у всех запросов адрес
  балансировщика k3d, поэтому лимит общий на всех.
- Хвостового сэмплирования трейсов: при 100% Tempo падает по памяти под
  нагрузочным тестом.
