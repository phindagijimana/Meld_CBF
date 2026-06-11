"""
aggregate_stats.py — Snakemake script. Concatenate per-subject CBF stats and
add an epilepsy concordance call on the whole-lesion (`all_clusters`) row.

Concordance logic (thresholds from config):
  hypoperfused       = roi_asym_pct <= asym_concordance_pct   (ipsilateral hypoperfusion)
  spatial_concordant = dice_hypo    >= dice_concordance        (cluster overlaps hypoperfused GM)
  concordance_call   = "concordant"  if (hypoperfused and spatial_concordant)
                       "partial"     if (hypoperfused or  spatial_concordant)
                       "discordant"  otherwise
"""
import sys

import pandas as pd

inputs = list(snakemake.input.csvs)
asym_thr = float(snakemake.params.asym)
dice_thr = float(snakemake.params.dice)
allow_partial = bool(snakemake.params.allow_partial)
expected = int(snakemake.params.expected)
out_csv = snakemake.output.csv
pipeline_version = snakemake.params.pipeline_version

frames = []
read_errors = []
for p in inputs:
    try:
        df = pd.read_csv(p)
        if df.empty:
            read_errors.append(f"{p}: empty")
            continue
        frames.append(df)
    except Exception as exc:  # noqa: BLE001
        read_errors.append(f"{p}: {exc}")

if read_errors:
    for msg in read_errors:
        print(f"[aggregate][WARN] {msg}", file=sys.stderr)

if not frames:
    print("[aggregate][ERROR] no readable per-subject stats", file=sys.stderr)
    sys.exit(1)

if not allow_partial and len(frames) < expected:
    print(
        f"[aggregate][ERROR] only {len(frames)}/{expected} subject(s) ready "
        f"(allow_partial_aggregate=false)",
        file=sys.stderr,
    )
    sys.exit(1)


def call_row(r):
    asym = pd.to_numeric(r.get("roi_asym_pct"), errors="coerce")
    dice = pd.to_numeric(r.get("dice_hypo"), errors="coerce")
    hypo = pd.notna(asym) and asym <= asym_thr
    spat = pd.notna(dice) and dice >= dice_thr
    return pd.Series({
        "hypoperfused": bool(hypo),
        "spatial_concordant": bool(spat),
        "concordance_call": ("concordant" if (hypo and spat)
                             else "partial" if (hypo or spat)
                             else "discordant"),
    })


cohort = pd.concat(frames, ignore_index=True)
cohort = pd.concat([cohort, cohort.apply(call_row, axis=1)], axis=1)
cohort["pipeline_version"] = pipeline_version
cohort.to_csv(out_csv, index=False)

lesion = cohort[cohort["cluster"] == "all_clusters"]
n = len(lesion)
conc = int((lesion["concordance_call"] == "concordant").sum())
part = int((lesion["concordance_call"] == "partial").sum())
print(f"[aggregate] {len(cohort)} rows from {len(frames)}/{expected} subject(s) -> {out_csv}")
print(f"[aggregate] lesion-level concordance: {conc}/{n} concordant, "
      f"{part}/{n} partial (asym<={asym_thr}%, dice>={dice_thr})")
