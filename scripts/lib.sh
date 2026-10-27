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
