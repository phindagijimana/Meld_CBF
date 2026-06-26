"""
aggregate_stats.py — Snakemake script. Concatenate per-subject CBF stats into an
AI-focused cohort table (roi_asym_pct + cluster_mirror_ai).

Primary endpoint: ipsilateral hypoperfusion via asymmetry index (AI).
  roi_hypoperfused    = roi_asym_pct <= asym_threshold_pct
  mirror_hypoperfused = cluster_mirror_ai < 0
  ai_hypoperfused     = either flag true (lesion / ROI level)
"""
import sys

import pandas as pd

inputs = list(snakemake.input.csvs)
asym_thr = float(snakemake.params.asym)
allow_partial = bool(snakemake.params.allow_partial)
expected = int(snakemake.params.expected)
out_csv = snakemake.output.csv
pipeline_version = snakemake.params.pipeline_version

AI_COLUMNS = [
    "subject",
    "cluster",
    "n_voxels",
    "volume_mm3",
    "host_roi",
    "host_roi_name",
    "ipsi_roi_cbf",
    "contra_roi_cbf",
    "roi_asym_pct",
    "cluster_mirror_ipsi_cbf",
    "cluster_mirror_contra_cbf",
    "cluster_mirror_ai",
    "roi_hypoperfused",
    "mirror_hypoperfused",
    "ai_hypoperfused",
    "pipeline_version",
]

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


def ai_flags(r):
    roi_asym = pd.to_numeric(r.get("roi_asym_pct"), errors="coerce")
    mirror_ai = pd.to_numeric(r.get("cluster_mirror_ai"), errors="coerce")
    roi_hypo = pd.notna(roi_asym) and roi_asym <= asym_thr
    mirror_hypo = pd.notna(mirror_ai) and mirror_ai < 0
    return pd.Series({
        "roi_hypoperfused": bool(roi_hypo),
        "mirror_hypoperfused": bool(mirror_hypo),
        "ai_hypoperfused": bool(roi_hypo or mirror_hypo),
    })


cohort = pd.concat(frames, ignore_index=True)
cohort = pd.concat([cohort, cohort.apply(ai_flags, axis=1)], axis=1)
cohort["pipeline_version"] = pipeline_version
cohort[AI_COLUMNS].to_csv(out_csv, index=False)

lesion = cohort[cohort["cluster"] == "all_clusters"]
n_lesion = len(lesion)
roi_n = int(lesion["roi_hypoperfused"].sum()) if n_lesion else 0
mir_n = int(lesion["mirror_hypoperfused"].sum()) if n_lesion else 0
ai_n = int(lesion["ai_hypoperfused"].sum()) if n_lesion else 0
neg = cohort[cohort["cluster"] == "none"]
print(f"[aggregate] {len(cohort)} rows from {len(frames)}/{expected} subject(s) -> {out_csv}")
print(f"[aggregate] AI (all_clusters): roi_hypo {roi_n}/{n_lesion}, "
      f"mirror_hypo {mir_n}/{n_lesion}, either {ai_n}/{n_lesion} "
      f"(roi_asym<={asym_thr}%, mirror_ai<0)")
if len(neg):
    print(f"[aggregate] MELD-negative (cluster=none): {len(neg)}")
