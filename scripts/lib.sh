#!/usr/bin/env bash
# shellcheck disable=SC2034  # variables are used by the scripts that source this file
# Shared slice definitions: name, UE count, UPF gateway (reachable only through the slice's tunnel)
NS=${NS:-5g}
SLICES=(embb urllc mmtc)
declare -A UE_COUNT=([embb]=3 [urllc]=3 [mmtc]=10)
declare -A GW=([embb]=10.45.0.1 [urllc]=10.46.0.1 [mmtc]=10.47.0.1)

ue_exec() { local s=$1; shift; kubectl -n "$NS" exec "deploy/ues-$s" -- "$@"; }

# Ping the slice's UPF through the first UE tunnel; prints "transmitted received"
ping_stats() {
  local s=$1 secs=$2
  ue_exec "$s" ping -i 0.2 -w "$secs" -I uesimtun0 "${GW[$s]}" 2>/dev/null \
    | awk '/packets transmitted/ {print $1, $4}' || true
}

# Restart a deployment and wait until its OLD pods are gone, not just until the
# new one is Ready. UEs resolve the gNB by DNS at startup; while the old gNB pod
# is still terminating they can latch onto it and end up with no cell.
restart_and_settle() {
  local deploy=$1 sel old
  # shellcheck disable=SC2016  # go-template, not shell
  sel=$(kubectl -n "$NS" get deploy "$deploy" \
    -o go-template='{{range $k, $v := .spec.selector.matchLabels}}{{$k}}={{$v}},{{end}}')
  old=$(kubectl -n "$NS" get pod -l "${sel%,}" -o name)
  kubectl -n "$NS" rollout restart "deploy/$deploy" >/dev/null
  kubectl -n "$NS" rollout status "deploy/$deploy" --timeout=180s >/dev/null
  # shellcheck disable=SC2086
  [ -n "$old" ] && kubectl -n "$NS" wait --for=delete $old --timeout=120s >/dev/null 2>&1
  return 0
}
