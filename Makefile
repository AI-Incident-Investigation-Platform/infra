.PHONY: help env up down restart logs service service-drop registry psql cache-cli

-include .env

SERVICE_HOST ?= localhost
CHECK_NAME = @echo "$(name)" | grep -Eqx '[a-z][a-z0-9-]{0,40}' || { echo "использование: make $@ name=<имя из a-z, 0-9, ->"; exit 1; }
RUN = docker compose exec -T -e SERVICE=$(name)

help:
	@echo ""
	@echo "  Инфра"
	@echo "    env                       создать .env из .env.example"
	@echo "    up                        поднять Postgres, Dragonfly, SeaweedFS, Consul"
	@echo "    down                      остановить, данные остаются"
	@echo "    restart                   перезапустить"
	@echo "    logs                      логи всех контейнеров"
	@echo ""
	@echo "  Микросервисы"
	@echo "    service name=<имя>        выдать сервису БД, бакет и напечатать блок для config.toml"
	@echo "    service-drop name=<имя>   снести сервис: БД, роль, бакет, S3-юзер, ключи кэша, записи в Consul"
	@echo "    registry                  экземпляры в Consul и их статус"
	@echo ""
	@echo "  Данные"
	@echo "    psql                      psql суперюзером"
	@echo "    cache-cli                 redis-cli в Dragonfly"
	@echo ""
	@echo "  Веб-интерфейсы"
	@echo "    http://localhost:8500     Consul"
	@echo "    http://localhost:8888     файлы S3"
	@echo ""

env:
	@test -f .env && echo ".env уже есть" || { cp .env.example .env; echo "создан .env, поменяй пароли change-me"; }

up:
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
		"postgres_host = \"$(SERVICE_HOST)\"" \
		"postgres_port = 5432" \
		"postgres_db = \"$(name)\"" \
		"postgres_username = \"$(name)\"" \
		"postgres_password = \"$$password\"" \
		"" \
		"[cache]" \
		"url = \"redis://default:$(DRAGONFLY_PASSWORD)@$(SERVICE_HOST):6379/0\"" \
		"key_prefix = \"$(name):\"" \
		"" \
		"[s3]" \
		"endpoint_url = \"http://$(SERVICE_HOST):8333\"" \
		"access_key = \"$(name)\"" \
		"secret_key = \"$$password\"" \
		"bucket = \"$(name)\"" \
		"region = \"us-east-1\"" \
		"" \
		"[registry]" \
		"consul_url = \"http://$(SERVICE_HOST):8500\""

service-drop:
	$(CHECK_NAME)
	@printf 'Удалятся БД, бакет и кэш сервиса $(name) без возможности вернуть. Введи имя для подтверждения: '; \
	read answer; [ "$$answer" = "$(name)" ] || { echo "отменено"; exit 1; }
	@$(RUN) postgres sh -s < postgres/drop.sh
	@$(RUN) seaweedfs sh -s < seaweedfs/drop.sh
	@$(RUN) dragonfly sh -s < dragonfly/drop.sh
	@$(RUN) consul sh -s < consul/drop.sh

registry:
	@docker compose exec -T consul sh -s < consul/registry.sh

psql:
	docker compose exec postgres sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"'

cache-cli:
	docker compose exec dragonfly sh -c 'REDISCLI_AUTH="$$DFLY_requirepass" redis-cli'
