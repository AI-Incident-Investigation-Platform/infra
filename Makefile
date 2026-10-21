.PHONY: help env up start stop delete namespaces secret apply status logs dashboard service psql cache-cli

-include .env

CLUSTER := aiip
CONTEXT := k3d-$(CLUSTER)
NS := infra
APPS_NS := apps
KUBECTL := kubectl --context $(CONTEXT) -n $(NS)
STATEFUL := postgres dragonfly seaweedfs

CHECK_NAME = @echo "$(name)" | grep -Eqx '[a-z][a-z0-9-]{0,40}' || { echo "использование: make $@ name=<имя из a-z, 0-9, ->"; exit 1; }
RUN = $(KUBECTL) exec -i statefulset/$(1) -- env SERVICE=$(name)

help:
	@echo ""
	@echo "  Кластер k3d"
	@echo "    env                       создать .env из .env.example"
	@echo "    up                        создать или запустить кластер, раскатить Postgres, Dragonfly,"
	@echo "                              SeaweedFS, Jaeger и настройки Traefik"
	@echo "    stop                      остановить кластер, данные остаются"
	@echo "    start                     запустить остановленный кластер"
	@echo "    delete                    удалить кластер вместе со всеми данными"
	@echo "    status                    поды, сервисы и тома инфры"
	@echo "    logs                      логи инфры"
	@echo "    dashboard                 дашборд Traefik на http://localhost:8080/dashboard/"
	@echo ""
	@echo "  Микросервисы"
	@echo "    service name=<имя>        выдать сервису БД, бакет и напечатать блок для config.toml"
	@echo ""
	@echo "  Данные"
	@echo "    psql                      psql суперюзером"
	@echo "    cache-cli                 redis-cli в Dragonfly"
	@echo ""
	@echo "  С хоста"
	@echo "    http://localhost          вход в систему через Traefik"
	@echo "    localhost:5432 / 6379 / 8333   Postgres / Dragonfly / S3"
	@echo "    http://localhost:8888     файлы S3"
	@echo "    http://localhost:16686    Jaeger: трейсы запросов"
	@echo ""

env:
	@test -f .env && echo ".env уже есть" || { cp .env.example .env; echo "создан .env, поменяй пароли change-me"; }

up:
	@command -v k3d >/dev/null || { echo "нужен k3d: brew install k3d"; exit 1; }
	@test -f .env || { echo "нет .env: make env"; exit 1; }
	@if k3d cluster list $(CLUSTER) >/dev/null 2>&1; then k3d cluster start $(CLUSTER); else k3d cluster create --config cluster.yaml; fi
	@$(MAKE) --no-print-directory namespaces secret apply

start:
	k3d cluster start $(CLUSTER)

stop:
	k3d cluster stop $(CLUSTER)

delete:
	@printf 'Удалится кластер $(CLUSTER) со всеми сервисами, БД, бакетами и кэшем без возможности вернуть. Введи $(CLUSTER) для подтверждения: '; \
	read answer; [ "$$answer" = "$(CLUSTER)" ] || { echo "отменено"; exit 1; }
	k3d cluster delete $(CLUSTER)

namespaces:
	@for ns in $(NS) $(APPS_NS); do kubectl --context $(CONTEXT) create namespace $$ns --dry-run=client -o yaml | kubectl --context $(CONTEXT) apply -f - >/dev/null; done

secret:
	@$(KUBECTL) create secret generic infra --from-env-file=.env --dry-run=client -o yaml | $(KUBECTL) apply -f -

apply:
	kubectl --context $(CONTEXT) apply -k k8s
	kubectl --context $(CONTEXT) apply -f traefik.yaml
	@for s in $(STATEFUL); do $(KUBECTL) rollout status statefulset/$$s --timeout=300s || exit 1; done
	$(KUBECTL) rollout status deploy/jaeger --timeout=300s

status:
	$(KUBECTL) get pods,svc,pvc -o wide

logs:
	$(KUBECTL) logs -l 'app in (postgres,dragonfly,seaweedfs,jaeger)' --prefix --tail=100 -f

dashboard:
	kubectl --context $(CONTEXT) -n kube-system port-forward deploy/traefik 8080:8080

service:
	$(CHECK_NAME)
	@password=$$(openssl rand -hex 16); \
	$(call RUN,postgres) PASSWORD=$$password sh -s < postgres/provision.sh >&2 && \
	$(call RUN,seaweedfs) PASSWORD=$$password sh -s < seaweedfs/provision.sh >&2 && \
	printf '%s\n' "" \
		"[database]" \
		"postgres_host = \"postgres.$(NS)\"" \
		"postgres_port = 5432" \
		"postgres_db = \"$(name)\"" \
		"postgres_username = \"$(name)\"" \
		"postgres_password = \"$$password\"" \
		"" \
		"[cache]" \
		"host = \"dragonfly.$(NS)\"" \
		"port = 6379" \
		"password = \"$(DRAGONFLY_PASSWORD)\"" \
		"db = 0" \
		"key_prefix = \"$(name):\"" \
		"" \
		"[s3]" \
		"endpoint_url = \"http://seaweedfs.$(NS):8333\"" \
		"access_key = \"$(name)\"" \
		"secret_key = \"$$password\"" \
		"bucket = \"$(name)\"" \
		"region = \"us-east-1\"" \
		"" \
		"[tracing]" \
		"otlp_endpoint = \"http://jaeger.$(NS):4318\""

psql:
	$(KUBECTL) exec -it statefulset/postgres -- sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"'

cache-cli:
	$(KUBECTL) exec -it statefulset/dragonfly -- sh -c 'REDISCLI_AUTH="$$DFLY_requirepass" redis-cli'
