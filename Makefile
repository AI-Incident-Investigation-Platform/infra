.PHONY: observability-apply help env up start stop delete namespaces secret apply status logs dashboard forward service psql cache-cli

-include .env

CLUSTER := aiip
CONTEXT := k3d-$(CLUSTER)
NS := infra
APPS_NS := apps
KUBECTL := kubectl --context $(CONTEXT) -n $(NS)
STATEFUL := postgres dragonfly seaweedfs loki tempo prometheus alloy grafana

CHECK_NAME = @echo "$(name)" | grep -Eqx '[a-z][a-z0-9-]{0,40}' || { echo "использование: make $@ name=<имя из a-z, 0-9, ->"; exit 1; }
RUN = $(KUBECTL) exec -i statefulset/$(1) -c $(1) -- env SERVICE=$(name)

help:
	@echo ""
	@echo "  Кластер k3d"
	@echo "    env                       создать .env из .env.example"
	@echo "    up                        создать или запустить кластер, раскатить Postgres, Dragonfly,"
	@echo "                              SeaweedFS, наблюдаемость и настройки Traefik"
	@echo "    stop                      остановить кластер, данные остаются"
	@echo "    start                     запустить остановленный кластер"
	@echo "    delete                    удалить кластер вместе со всеми данными"
	@echo "    status                    поды, сервисы и тома инфры"
	@echo "    observability-apply       применить конфигурацию и обновить дашборды Grafana"
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
	@echo "    http://localhost, https://localhost   единственный вход: Traefik"
	@echo "    http://grafana.localhost  Grafana: логи, трейсы, метрики; пароль admin в .env"
	@echo "    forward                   пока работает, открывает инфру на localhost:"
	@echo "                              5432 / 6379 / 8333 Postgres / Dragonfly / S3,"
	@echo "                              4318 приём трейсов, http://localhost:8888 файлы S3;"
	@echo "                              Ctrl+C закрывает"
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
	@missing=$$(for key in $$(grep -o '^[A-Z0-9_]*=' .env.example); do grep -q "^$$key" .env || printf ' %s' "$${key%=}"; done); \
	[ -z "$$missing" ] || { echo "в .env нет:$$missing — перенеси из .env.example и задай значения"; exit 1; }
	@$(KUBECTL) create secret generic infra --from-env-file=.env --dry-run=client -o yaml | $(KUBECTL) apply -f -

apply:
	kubectl --context $(CONTEXT) apply -k k8s
	kubectl --context $(CONTEXT) apply -f traefik.yaml
	@for s in $(STATEFUL); do $(KUBECTL) rollout status statefulset/$$s --timeout=300s || exit 1; done
	@$(KUBECTL) exec -i statefulset/postgres -c postgres -- env PASSWORD=$(POSTGRES_MONITORING_PASSWORD) sh -s < postgres/monitoring.sh
	$(KUBECTL) rollout status deploy/kube-state-metrics --timeout=300s

status:
	$(KUBECTL) get pods,svc,pvc -o wide

logs:
	$(KUBECTL) logs -l 'app in (postgres,dragonfly,seaweedfs,loki,tempo,prometheus,alloy,grafana,kube-state-metrics)' --prefix --tail=100 -f

dashboard:
	kubectl --context $(CONTEXT) -n kube-system port-forward deploy/traefik 8080:8080

forward:
	@trap 'kill 0' INT TERM; \
	$(KUBECTL) port-forward svc/postgres 5432 >/dev/null & \
	$(KUBECTL) port-forward svc/dragonfly 6379 >/dev/null & \
	$(KUBECTL) port-forward svc/seaweedfs 8333 8888 >/dev/null & \
	$(KUBECTL) port-forward svc/alloy 4318 >/dev/null & \
	echo "инфра открыта на localhost: 5432 6379 8333 8888 4318, Ctrl+C закрывает"; \
	wait

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
		"otlp_endpoint = \"http://alloy.$(NS):4318\""

psql:
	$(KUBECTL) exec -it statefulset/postgres -c postgres -- sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"'

cache-cli:
	$(KUBECTL) exec -it statefulset/dragonfly -- sh -c 'REDISCLI_AUTH="$$DFLY_requirepass" redis-cli'

observability-apply:
	kubectl --context $(CONTEXT) apply -k k8s
	$(KUBECTL) rollout status statefulset/grafana --timeout=180s
