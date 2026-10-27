# infra

Локальный стенд AIIP: k3d-кластер `aiip` (k3s в Docker, одна нода) и общая
инфраструктура для всех сервисов — Postgres, Dragonfly (Redis-совместимый
кэш), RabbitMQ (очереди задач), SeaweedFS (S3), наблюдаемость (Grafana, Loki, Tempo, Prometheus,
Alloy, kube-state-metrics), KEDA и настройки встроенного в k3s Traefik.
Сервисы сюда не входят: каждый выкатывается из своего репозитория в
namespace `apps`.

## Документация

- [docs/design.md](docs/design.md) — как устроен кластер и связаны
  компоненты, gateway, наблюдаемость, выдача ресурсов сервисам, принятые
  решения.
- [docs/requirements.md](docs/requirements.md) — что требует документация
  продукта и что из этого реализовано.

## Запуск

Нужны Docker, `k3d`, `kubectl`.

```bash
make env       # .env из .env.example; заполнить пароли
make up        # создать или запустить кластер и раскатить инфру
make status    # поды, сервисы, тома
make forward   # в отдельном терминале: инфра на localhost, Ctrl+C закрывает
```

- Вход снаружи один — Traefik на `http://localhost` и `https://localhost`
  (самоподписанный сертификат). Сервисы — на `/api/<сервис>`.
- Grafana — `http://grafana.localhost`, пользователь `admin`, пароль —
  `GRAFANA_ADMIN_PASSWORD` в `.env`.
- RabbitMQ — `http://rabbitmq.localhost`, логин и пароль —
  `RABBITMQ_DEFAULT_USER` и `RABBITMQ_DEFAULT_PASS` в `.env`.
- `make forward` открывает на `localhost` Postgres (5432), Dragonfly
  (6379), RabbitMQ (5672), S3 (8333), приём трейсов (4318), файлы S3
  (`http://localhost:8888`). Он нужен только тому, что работает на хосте.
  При перезапуске пода инфры его перезапускают.
- `make stop` / `make start` — остановить и запустить с данными.
  `make delete` удаляет кластер **вместе со всеми данными**.

## Новый сервис

```bash
make service name=<имя>
```

Создаёт сервису БД и роль в Postgres, бакет и пользователя S3, префикс
ключей в кэше, пользователя RabbitMQ в vhost `aiip` и печатает блок `config.toml` с адресами внутри кластера.
Повторный запуск данных не трогает, но выдаёт новый пароль: старый
`config.toml` сервиса после него не подключится.

Остальные цели — `make help`: `observability-apply` (конфиги и дашборды
Grafana без пересоздания), `logs`, `dashboard` (Traefik на
`http://localhost:8080/dashboard/`), `psql`, `cache-cli`.
