.PHONY: help env up down restart logs service psql cache-cli

-include .env

CHECK_NAME = @echo "$(name)" | grep -Eqx '[a-z][a-z0-9-]{0,40}' || { echo "использование: make $@ name=<имя из a-z, 0-9, ->"; exit 1; }
RUN = docker compose exec -T -e SERVICE=$(name)

help:
	@echo ""
	@echo "  Инфра"
	@echo "    env                       создать .env из .env.example"
	@echo "    up                        создать сеть aiip и поднять Postgres, Dragonfly, SeaweedFS, Jaeger"
	@echo "    down                      остановить, данные остаются"
	@echo "    restart                   перезапустить"
	@echo "    logs                      логи всех контейнеров"
	@echo ""
	@echo "  Микросервисы"
	@echo "    service name=<имя>        выдать сервису БД, бакет и напечатать блок для config.toml"
	@echo ""
	@echo "  Данные"
	@echo "    psql                      psql суперюзером"
	@echo "    cache-cli                 redis-cli в Dragonfly"
	@echo ""
	@echo "  Веб-интерфейсы"
	@echo "    http://localhost:8888     файлы S3"
	@echo "    http://localhost:16686    Jaeger: трейсы запросов"
	@echo ""

env:
	@test -f .env && echo ".env уже есть" || { cp .env.example .env; echo "создан .env, поменяй пароли change-me"; }

up:
	@docker network inspect aiip >/dev/null 2>&1 || docker network create aiip >/dev/null
	docker compose up -d --wait

down:
	docker compose down

restart: down up

logs:
	docker compose logs -f --tail=100

service:
	$(CHECK_NAME)
	@password=$$(openssl rand -hex 16); \
	$(RUN) -e PASSWORD=$$password postgres sh -s < postgres/provision.sh >&2 && \
	$(RUN) -e PASSWORD=$$password seaweedfs sh -s < seaweedfs/provision.sh >&2 && \
	printf '%s\n' "" \
		"[database]" \
		"postgres_host = \"postgres\"" \
		"postgres_port = 5432" \
		"postgres_db = \"$(name)\"" \
		"postgres_username = \"$(name)\"" \
		"postgres_password = \"$$password\"" \
		"" \
		"[cache]" \
		"host = \"dragonfly\"" \
		"port = 6379" \
		"password = \"$(DRAGONFLY_PASSWORD)\"" \
		"db = 0" \
		"key_prefix = \"$(name):\"" \
		"" \
		"[s3]" \
		"endpoint_url = \"http://seaweedfs:8333\"" \
		"access_key = \"$(name)\"" \
		"secret_key = \"$$password\"" \
		"bucket = \"$(name)\"" \
		"region = \"us-east-1\"" \
		"" \
		"[tracing]" \
		"otlp_endpoint = \"http://jaeger:4318\""

psql:
	docker compose exec postgres sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"'

cache-cli:
	docker compose exec dragonfly sh -c 'REDISCLI_AUTH="$$DFLY_requirepass" redis-cli'
