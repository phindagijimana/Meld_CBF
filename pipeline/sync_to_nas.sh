#!/usr/bin/env bash
# Sync MELD / MELD+CBF results to the lab NAS share.
#
# Destination defaults to config nas_dest (set in config/config.yaml).
#
# Copies per-subject deliverables (predictions, CBF stats/figures) plus the
# cohort table when present. Safe to rerun while jobs are in flight.
#
# Usage:
#   ./sync_to_nas.sh --config config/config.yaml
#   ./sync_to_nas.sh --config config/config.yaml sub-002
#   ./sync_to_nas.sh --config config/config.yaml --fs --dry-run
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${ROOT}/pipeline/config/config.yaml"
OUT="${ROOT}/work/output"
LOGS="${ROOT}/work/logs"

INCLUDE_FS=0
DRY_RUN=0
SUBS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--fs) INCLUDE_FS=1; shift ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    --config) CONFIG="$2"; shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) SUBS+=("$1"); shift ;;
  esac
done

read_config() {
  python3 - "$CONFIG" "$1" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
print(cfg.get(sys.argv[2], ""))
PY
}

DEST="$(read_config nas_dest)"
[[ -z "$DEST" ]] && { echo "[sync][ERROR] nas_dest not set in config" >&2; exit 2; }
WORK="$(read_config work)"
OUT="${WORK}/output"
LOGS="${WORK}/logs"

SYNC_LOG="${LOGS}/sync_to_nas.log"
mkdir -p "$LOGS" "$DEST"
exec >> >(tee -a "$SYNC_LOG") 2>&1

RSYNC=(rsync -avh --no-perms --no-owner --no-group --omit-dir-times)
[[ $DRY_RUN -eq 1 ]] && RSYNC+=(--dry-run)

echo "[sync] $(date '+%F %T') destination=$DEST dry_run=$DRY_RUN"

# Default to every subject with a finished prediction.
if [[ ${#SUBS[@]} -eq 0 ]]; then
  while IFS= read -r d; do SUBS+=("$(basename "$d")"); done \
    < <(find "$OUT/predictions_reports" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
fi

for s in "${SUBS[@]}"; do
  pred="$OUT/predictions_reports/$s/predictions/prediction.nii.gz"
  if [[ ! -f "$pred" ]]; then
    echo "[sync] SKIP $s (no prediction.nii.gz)"
    continue
  fi
  echo "[sync] === $s ==="
  mkdir -p "$DEST/$s"
  "${RSYNC[@]}" "$OUT/predictions_reports/$s/" "$DEST/$s/predictions_reports/"
  if [[ -d "$OUT/cbf_aligned/$s" ]]; then
    "${RSYNC[@]}" "$OUT/cbf_aligned/$s/" "$DEST/$s/cbf_aligned/"
  fi
  if [[ $INCLUDE_FS -eq 1 && -d "$OUT/fs_outputs/$s" ]]; then
    "${RSYNC[@]}" "$OUT/fs_outputs/$s/" "$DEST/$s/fs_outputs/"
  fi
  log=$(ls -t "$LOGS"/*"$s"*.out 2>/dev/null | head -1 || true)
  [[ -n "$log" && $DRY_RUN -eq 0 ]] && cp -f "$log" "$DEST/$s/"
done

COHORT="$OUT/cbf_cohort_stats.csv"
if [[ -f "$COHORT" ]]; then
  echo "[sync] cohort table -> $DEST/"
  "${RSYNC[@]}" "$COHORT" "$DEST/"
fi

echo "[sync] done"
