#!/usr/bin/env bash
# The ueransim-gnb chart renders a single S-NSSAI into gnb.yaml.
# Replace that list with all three slices and restart the gNB.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
CM=ueransim-gnb

kubectl -n "$NS" get configmap "$CM" -o jsonpath='{.data.gnb\.yaml}' \
  | python3 -c '
import re, sys
cfg = sys.stdin.read()
slices = "slices:\n  - { sst: 1, sd: 0x000001 }\n  - { sst: 2, sd: 0x000002 }\n  - { sst: 3, sd: 0x000003 }\n"
new, n = re.subn(r"slices:\n(?:[ -].*\n)+", slices, cfg)
if n != 1:
    sys.exit("could not find the slices block in gnb.yaml")
sys.stdout.write(new)
' > /tmp/gnb.yaml

kubectl -n "$NS" create configmap "$CM" --from-file=gnb.yaml=/tmp/gnb.yaml \
  --dry-run=client -o yaml | kubectl -n "$NS" apply -f -
restart_and_settle "$CM"
echo "gNB now advertises slices: eMBB (1/000001), URLLC (2/000002), mMTC (3/000003)"
