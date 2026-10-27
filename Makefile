NS      ?= 5g
CLUSTER ?= 5g-lab
SLICES  := embb urllc mmtc
CHARTS  := oci://registry-1.docker.io/gradiantcharts
PROM_CRD := https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.76.2/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml

# Pinned chart versions
V_OPEN5GS := 2.3.8
V_SMF     := 2.3.4
V_UPF     := 2.3.5
V_GNB     := 0.2.6
V_UES     := 0.1.2

HELM := helm upgrade --install -n $(NS) --create-namespace --wait --timeout 10m

.PHONY: up cluster monitoring crds core slices ran ues test chaos grafana down
up: cluster monitoring core slices ran ues   ## Full lab

cluster:
	kind create cluster --config cluster/kind.yaml

monitoring:   ## Prometheus + Grafana (also installs the ServiceMonitor CRD)
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
	helm upgrade --install kps prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f monitoring/kube-prometheus-values.yaml
	kubectl -n monitoring create configmap dash-5g --from-file=monitoring/dashboards/ --dry-run=client -o yaml | kubectl label -f - --local grafana_dashboard=1 -o yaml | kubectl apply -f -

crds:         ## Only the ServiceMonitor CRD, for running without the monitoring stack (CI)
	kubectl apply --server-side -f $(PROM_CRD)

core:         ## Shared control plane: AMF, NRF, SCP, NSSF, AUSF, UDM, UDR, PCF, BSF + subscribers
	$(HELM) open5gs $(CHARTS)/open5gs --version $(V_OPEN5GS) -f helm/open5gs-values.yaml

slices:       ## Dedicated UPF + SMF per slice
	for s in $(SLICES); do \
	  $(HELM) upf-$$s $(CHARTS)/open5gs-upf --version $(V_UPF) -f helm/slices/$$s-upf.yaml && \
	  $(HELM) smf-$$s $(CHARTS)/open5gs-smf --version $(V_SMF) -f helm/slices/$$s-smf.yaml || exit 1; \
	done

ran:          ## One gNB advertising all three slices
	$(HELM) ueransim-gnb $(CHARTS)/ueransim-gnb --version $(V_GNB) -f helm/ueransim-gnb-values.yaml
	NS=$(NS) ./scripts/gnb-add-slices.sh

ues:          ## Phones, one group per slice
	for s in $(SLICES); do \
	  $(HELM) ues-$$s $(CHARTS)/ueransim-ues --version $(V_UES) -f helm/slices/$$s-ues.yaml || exit 1; \
	done

test:
	NS=$(NS) ./scripts/smoke-test.sh

chaos:        ## Kill AMF / eMBB UPF / URLLC SMF and measure per-slice outage
	NS=$(NS) ./scripts/chaos.sh

grafana:
	kubectl -n monitoring port-forward svc/kps-grafana 3000:80

down:
	kind delete cluster --name $(CLUSTER)
