#!/usr/bin/env bash
# Chaos experiments against the sliced core. Each one kills a network function
# while UEs are probing their UPF, then reports user-plane outage per slice.
# Results go to stdout, results/chaos.md and the GitHub job summary.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

WINDOW=${WINDOW:-60}   # seconds of probing per experiment
OUT=results/chaos.md
mkdir -p results
tmp=$(mktemp -d)

# Probe every slice in the background for WINDOW seconds
probe_all() {
  for s in "${SLICES[@]}"; do ping_stats "$s" "$WINDOW" >"$tmp/$s" & done
}

# outage seconds = lost probes x 0.2s interval
summarize() {
  local exp=$1 target=$2 recovery=$3
  local row="| $exp | \`$target\` | $recovery |"
  local s tx rx cell
  for s in "${SLICES[@]}"; do
    read -r tx rx <"$tmp/$s" || { tx=0; rx=0; }
    if [ "${tx:-0}" -eq 0 ]; then row+=" n/a |"; continue; fi
    cell=$(awk -v t="$tx" -v r="$rx" 'BEGIN{printf "%.1fs (%.0f%%)", (t-r)*0.2, 100*(t-r)/t}')
    [ -f "$tmp/$s.reattach" ] && cell+=" ⚠️ no auto-recovery (back after operator recovery: $(cat "$tmp/$s.reattach"))"
    row+=" $cell |"
  done
  echo "$row" >>"$OUT"
  echo "$row"
}

slice_ok() { ue_exec "$1" ping -c 3 -W 1 -I uesimtun0 "${GW[$1]}" >/dev/null 2>&1; }

# Any slice still down after the window gets operator-style recovery, timed:
#  - gNB restart: UERANSIM's gNB does not redo NG Setup when the AMF comes back,
#    so after an AMF restart no UE can register until the gNB reconnects
#  - SMF restart for the down slice: Open5GS resolves the UPF address once at
#    startup, so a recreated UPF pod (new IP) is never re-associated
#  - UE restart on every slice (the gNB restart drops all radio connections)
# The next experiment then starts from a healthy network.
# Wait until a restarted NF has registered with the NRF. UEs that attach before
# their slice's SMF is registered get a session from another slice's SMF.
wait_nrf_registered() {
  local deploy=$1 i
  for i in $(seq 1 60); do
    kubectl -n "$NS" logs "deploy/$deploy" 2>/dev/null | grep -q 'NF registered \[Heartbeat' && return 0
    sleep 1
  done
  echo "❌ $deploy did not register with the NRF within ${i}s"; exit 1
}

heal() {
  local s start down=()
  rm -f "$tmp"/*.reattach
  for s in "${SLICES[@]}"; do slice_ok "$s" || down+=("$s"); done
  [ ${#down[@]} -eq 0 ] && return 0
  echo "  not recovered on their own: ${down[*]} -> restarting gNB, SMF(s), UEs"
  start=$(date +%s)
  kubectl -n "$NS" rollout restart deploy/ueransim-gnb >/dev/null
  for s in "${down[@]}"; do kubectl -n "$NS" rollout restart "deploy/smf-$s" >/dev/null; done
  kubectl -n "$NS" rollout status deploy/ueransim-gnb --timeout=180s >/dev/null
  for s in "${down[@]}"; do
    kubectl -n "$NS" rollout status "deploy/smf-$s" --timeout=180s >/dev/null
    wait_nrf_registered "smf-$s"
  done
  for s in "${SLICES[@]}"; do kubectl -n "$NS" rollout restart "deploy/ues-$s" >/dev/null; done
  for s in "${SLICES[@]}"; do
    kubectl -n "$NS" rollout status "deploy/ues-$s" --timeout=180s >/dev/null
    until slice_ok "$s"; do
      [ $(( $(date +%s) - start )) -gt 300 ] && { echo "❌ $s still down after recovery"; exit 1; }
      sleep 2
    done
  done
  for s in "${down[@]}"; do echo "$(( $(date +%s) - start ))s" >"$tmp/$s.reattach"; done
}

# Kill a deployment's pod, return seconds until its replacement is Ready
kill_and_time() {
  local deploy=$1 sel old start
  # shellcheck disable=SC2016  # go-template, not shell
  sel=$(kubectl -n "$NS" get deploy "$deploy" \
    -o go-template='{{range $k, $v := .spec.selector.matchLabels}}{{$k}}={{$v}},{{end}}')
  sel=${sel%,}
  old=$(kubectl -n "$NS" get pod -l "$sel" -o name)
  start=$(date +%s)
  # shellcheck disable=SC2086
  kubectl -n "$NS" delete $old --wait=false >/dev/null
  # shellcheck disable=SC2086
  kubectl -n "$NS" wait --for=delete $old --timeout=120s >/dev/null
  kubectl -n "$NS" wait --for=condition=Ready pod -l "$sel" --timeout=180s >/dev/null
  echo "$(( $(date +%s) - start ))s"
}

run() {
  local exp=$1 target=$2 recovery
  echo "▶ $exp: killing $target"
  probe_all; sleep 3
  recovery=$(kill_and_time "$target")
  wait
  heal
  summarize "$exp" "$target" "$recovery"
}

cat >"$OUT" <<HDR
| Experiment | Killed | NF back in | eMBB outage | URLLC outage | mMTC outage |
|---|---|---|---|---|---|
HDR

run "Control plane loss (AMF)" open5gs-amf
run "eMBB user plane failure"  upf-embb
run "URLLC session manager restart" smf-urllc

echo
cat "$OUT"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && { echo "## Chaos results"; cat "$OUT"; } >>"$GITHUB_STEP_SUMMARY"
rm -rf "$tmp"
