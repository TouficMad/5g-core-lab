NS      ?= 5g
CLUSTER ?= 5g-lab
N       ?= 10
CHARTS  := oci://registry-1.docker.io/gradiantcharts

.PHONY: up cluster monitoring core ran ues test grafana down
up: cluster monitoring core ran   ## Full lab

cluster:
	kind create cluster --config cluster/kind.yaml

monitoring:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
	helm upgrade --install kps prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f monitoring/kube-prometheus-values.yaml
	kubectl -n monitoring create configmap dash-5g --from-file=monitoring/dashboards/ --dry-run=client -o yaml | kubectl label -f - --local grafana_dashboard=1 -o yaml | kubectl apply -f -

core:
	helm upgrade --install open5gs $(CHARTS)/open5gs -n $(NS) --create-namespace -f helm/open5gs-values.yaml --wait --timeout 10m

ran:
	helm upgrade --install ueransim $(CHARTS)/ueransim-gnb -n $(NS) -f helm/ueransim-values.yaml --wait

ues:          ## make ues N=100
	helm upgrade ueransim $(CHARTS)/ueransim-gnb -n $(NS) -f helm/ueransim-values.yaml --set ues.count=$(N) --wait

test:
	NS=$(NS) ./scripts/smoke-test.sh

grafana:
	kubectl -n monitoring port-forward svc/kps-grafana 3000:80

down:
	kind delete cluster --name $(CLUSTER)
