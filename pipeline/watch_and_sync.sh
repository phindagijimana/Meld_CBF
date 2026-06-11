#!/usr/bin/env bash
# Watch subjects and sync each to NAS when deliverables are ready.
#
# Usage:
#   ./watch_and_sync.sh --config config/config.yaml sub-001 sub-003
#   ./watch_and_sync.sh --config config/config.yaml --full sub-001   # wait for CBF stats too
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${ROOT}/pipeline/config/config.yaml"
SYNC="${ROOT}/pipeline/sync_to_nas.sh"
POLL=180
FULL=0
SUBS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --full) FULL=1; shift ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) SUBS+=("$1"); shift ;;
  esac
done

[[ ${#SUBS[@]} -eq 0 ]] && { echo "Usage: $0 [--config CFG] [--full] sub-001 ..." >&2; exit 2; }

WORK=$(python3 - "$CONFIG" <<'PY'
import sys, yaml
print(yaml.safe_load(open(sys.argv[1]))["work"])
PY
)
OUT="$WORK/output"
USER="$(whoami)"

declare -A DONE
echo "[watch] tracking: ${SUBS[*]} poll=${POLL}s full=$FULL"
while :; do
  for s in "${SUBS[@]}"; do
    [[ -n "${DONE[$s]:-}" ]] && continue
    ready=0
    if [[ -f "$OUT/predictions_reports/$s/predictions/prediction.nii.gz" ]]; then
      if [[ $FULL -eq 0 ]]; then
        ready=1
      elif [[ -f "$OUT/cbf_aligned/$s/cbf_in_clusters_${s}.csv" ]]; then
        ready=1
      fi
    fi
    if [[ $ready -eq 1 ]]; then
      echo "[watch] $(date '+%F %T') $s ready -> syncing"
      bash "$SYNC" --config "$CONFIG" "$s" && DONE[$s]=1
      continue
    fi
    if squeue -u "$USER" -h -o "%j" 2>/dev/null | grep -q "$s"; then
      :
    else
      echo "[watch] $(date '+%F %T') $s no deliverables and no job -> stop tracking"
      DONE[$s]=skip
    fi
  done
  remaining=0
  for s in "${SUBS[@]}"; do [[ -z "${DONE[$s]:-}" ]] && remaining=1; done
  [[ $remaining -eq 0 ]] && break
  sleep "$POLL"
done
echo "[watch] all subjects resolved"
