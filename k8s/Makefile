.PHONY: help up down cluster-up cluster-down platform status \
        lint example example-down \
        psql pg-forward pg-status cache-cli s3-forward \
        headlamp-token

CLUSTER := aiip
SCHEMAS := https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json
KUBECONFORM := kubeconform -strict -summary -ignore-missing-schemas -schema-location default -schema-location '$(SCHEMAS)'

help:
	@echo ""
	@echo "  Кластер"
	@echo "    up                        создать кластер и раскатить платформу"
	@echo "    down                      удалить кластер вместе со всеми данными"
	@echo "    cluster-up                только kind-кластер"
	@echo "    platform                  раскатить/обновить платформу (helmfile sync)"
	@echo "    status                    ноды и поды платформы"
	@echo ""
	@echo "  Качество"
	@echo "    lint                      helm lint + kubeconform для чартов"
	@echo ""
	@echo "  Пример сервиса"
	@echo "    example                   задеплоить whoami: 4 реплики, БД, бакет, кэш, http://localhost/whoami/"
	@echo "    example-down              удалить whoami"
	@echo ""
	@echo "  Данные"
	@echo "    psql                      psql суперюзером в primary Postgres"
	@echo "    pg-status                 кто primary, кто реплика, лаг репликации"
	@echo "    pg-forward                Postgres на localhost:5432 (для DataGrip и т.п.)"
	@echo "    cache-cli                 redis-cli в master Dragonfly"
	@echo "    s3-forward                S3 на localhost:8333, браузер файлов на localhost:8888"
	@echo ""
	@echo "  Веб-интерфейс"
	@echo "    http://localhost/headlamp/  Headlamp"
	@echo "    headlamp-token            токен для входа (живёт 24 часа)"
	@echo ""

up: cluster-up platform

down:
	kind delete cluster --name $(CLUSTER)

cluster-up:
	@kind get clusters | grep -qx $(CLUSTER) || kind create cluster --config cluster/kind.yaml

cluster-down: down

platform:
	helmfile sync
	kubectl wait --for=condition=Ready cluster/pg -n data --timeout=300s
	kubectl wait --for=jsonpath='{.status.phase}'=Ready dragonfly/cache -n data --timeout=300s
	kubectl wait --for=condition=Programmed gateway/main -n gateway --timeout=300s

status:
	@kubectl get nodes
	@echo ""
	@kubectl get pods -o wide -n data
	@echo ""
	@kubectl get pods -o wide -n apps

lint:
	helm lint charts/service -f examples/whoami.yaml
	helm lint platform
	helm template whoami charts/service -n apps -f examples/whoami.yaml | $(KUBECONFORM)
	helm template platform platform -n data | $(KUBECONFORM)

example:
	helm upgrade --install whoami charts/service -n apps -f examples/whoami.yaml --wait

example-down:
	helm uninstall whoami -n apps

psql:
	kubectl exec -it -n data $$(kubectl get pod -n data -l cnpg.io/cluster=pg,cnpg.io/instanceRole=primary -o name) -- psql

pg-status:
	@kubectl get pods -n data -l cnpg.io/cluster=pg -L cnpg.io/instanceRole
	@kubectl exec -n data $$(kubectl get pod -n data -l cnpg.io/cluster=pg,cnpg.io/instanceRole=primary -o name) -- \
		psql -tAc "select application_name, state, replay_lag from pg_stat_replication"

pg-forward:
	kubectl port-forward -n data svc/pg-rw 5432:5432

cache-cli:
	kubectl exec -it -n data $$(kubectl get pod -n data -l app=cache,role=master -o name) -- \
		sh -c 'redis-cli -a "$$DFLY_requirepass" --no-auth-warning'

s3-forward:
	kubectl port-forward -n data svc/seaweedfs-all-in-one 8333:8333 8888:8888

headlamp-token:
	@kubectl create token headlamp -n headlamp --duration=24h
