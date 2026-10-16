#!/usr/bin/env bash
# Verify a UE registered and can reach the internet through the UPF.
set -euo pipefail
NS=${NS:-5g}
echo "Waiting for UERANSIM pod..."
kubectl -n "$NS" wait --for=condition=Ready pod -l app.kubernetes.io/name=ueransim-gnb --timeout=300s
POD=$(kubectl -n "$NS" get pod -l app.kubernetes.io/component=ues -o jsonpath='{.items[0].metadata.name}')
for _ in $(seq 1 30); do
  kubectl -n "$NS" exec "$POD" -- ip addr show uesimtun0 >/dev/null 2>&1 && break
  sleep 5
done
kubectl -n "$NS" exec "$POD" -- ip -4 addr show uesimtun0
kubectl -n "$NS" exec "$POD" -- ping -c 3 -I uesimtun0 8.8.8.8
echo "✅ UE registered, PDU session up, data flowing through UPF"
