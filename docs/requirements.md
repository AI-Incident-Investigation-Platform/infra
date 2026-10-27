# infra и требования продукта

Сверка с документацией продукта
([AI-Incident-Investigation-Platform/docs](https://github.com/AI-Incident-Investigation-Platform/docs)),
раздел 08 и строка Infra в 10 §2, редакция baseline v2 от 2026-10-25.
Baseline предложен команде и ещё не принят.

Статусы: **есть** — реализовано; **частично**; **нет** — не начато;
**не наше** — требование к другому репозиторию, записано для полноты.

## Топология — 08 §1

| Требование | Статус | Комментарий |
|---|---|---|
| k3d-кластер `aiip`, namespaces `infra` и `apps` | есть | |
| В `infra`: Postgres, Dragonfly, SeaweedFS, Loki, Prometheus, Tempo, Alloy, Grafana | есть | плюс RabbitMQ, kube-state-metrics и KEDA |
| Traefik — вход для браузерного API, UI и Grafana | есть | UI пока нет: место — Ingress на `/` |
| Вызовы между сервисами — по DNS Service Kubernetes | есть | |
| В `apps`: main-backend, auth, ai-backend, mcp-server, demo-payment-service | частично | развёрнут `auth`; остальные выкатываются из своих репозиториев |
| `llama-server` на хосте, доступ из `ai-backend` через `host.docker.internal` | не проверено | доступность хоста из подов k3d не проверялась |

## Сбор телеметрии — 08 §2

| Требование | Статус | Комментарий |
|---|---|---|
| stdout подов → Alloy → Loki; метки `namespace`, `pod`, `container`, `app`, `level`; `trace_id` в structured metadata | есть | |
| Сбор метрик подов по аннотациям `prometheus.io/*`, интервал 15 с | есть | |
| OTLP → Alloy → Tempo для трейсов | есть | OTLP gRPC на 4317 и HTTP на 4318 |
| Datasources Loki, Prometheus, Tempo в Grafana, связка лог ↔ трейс | есть | плюс трейс → метрики |
| OTLP-метрики не обещаются | есть | метрики — только pull по `/metrics` |

## Требования к сервисам — 08 §3

Выполняет каждый сервис в своём репозитории; инфра даёт для них место:
приём логов, метрик и трейсов, Secret'ы, Ingress только для браузерных
маршрутов. Статус по сервису — в его `docs/requirements.md`.

## Hand-off и приёмка — 08 §5–§7

| Требование | Статус | Комментарий |
|---|---|---|
| Доступ MCP-сервера к Loki, Prometheus, Tempo по read-only service credentials | нет | у источников внутри кластера сейчас нет авторизации |
| Grafana и учётки источников не попадают в браузер, логи и LLM | частично | пароль Grafana только в `.env`; отдельных read-only учёток нет |
| Проверка источников реальными запросами, а не только Running-подами | частично | проверено на `auth`: лог с `trace_id`, метрики, трейс от `gateway` |
| Агент видит данные только своего project/service/namespace | нет | ограничение — на стороне MCP-сервера и учёток |
| Demo payment-service, управляемые неисправности, ground truth | не наше | Даниил |
| `make delete` удаляет всё — не использовать для обычной очистки | есть | так описано в README |
