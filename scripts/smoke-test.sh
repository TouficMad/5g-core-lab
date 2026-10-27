#!/usr/bin/env bash
# For every slice: all UEs registered, each got a PDU session from its own
# slice's subnet, and user-plane traffic reaches that slice's UPF.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

fail=0
for s in "${SLICES[@]}"; do
  kubectl -n "$NS" rollout status "deploy/ues-$s" --timeout=300s >/dev/null
  prefix=${GW[$s]%.*.*}   # e.g. 10.45
  want=${UE_COUNT[$s]}
  got=0 tx=0 rx=0
  # UEs attach asynchronously after their pods start: retry both checks for up to 3 min
  for _ in $(seq 1 36); do
    got=$(ue_exec "$s" ip -4 -o addr show 2>/dev/null | grep -c "uesimtun.* inet $prefix\." || true)
    if [ "$got" -ge "$want" ]; then
      read -r tx rx <<<"$(ping_stats "$s" 3)" || true
      [ "${rx:-0}" -gt 0 ] && break
    fi
    sleep 5
  done
  printf '%-6s sessions %s/%s in %s.0.0/16, ping to UPF %s/%s\n' "$s" "$got" "$want" "$prefix" "${rx:-0}" "${tx:-0}"
  if [ "$got" -lt "$want" ] || [ "${rx:-0}" -eq 0 ]; then fail=1; fi
done

if [ "$fail" -ne 0 ]; then
  echo "❌ smoke test failed"; kubectl -n "$NS" get pods; exit 1
fi
echo "✅ all slices up: UEs registered, PDU sessions on the right SMF/UPF, data flowing"
