#!/usr/bin/env python3
"""
build_samples.py — generate the cohort sample sheet (samples.tsv) for the
MELD + CBF Snakemake workflow.

For every BIDS_ID in the EP↔BIDS mapping it resolves, from the raw sources:
  - session : CBF-contemporaneous BIDS session (CBF_session_resolution.csv,
              else config fallback_session)
  - t1w     : <bids_root>/<sub>/<ses>/anat/<sub>_<ses>_T1w.nii.gz   (required)
  - flair   : …_FLAIR.nii.gz                                         (optional)
  - cbf     : <cbf_src_root>/<EP>/*/scans/CBF/cbf.nii.gz             (required)

Subjects missing a required input are dropped with a warning so the workflow
DAG only contains runnable samples.

Usage:
  build_samples.py --config config/config.yaml [--out path] [--quiet]
"""
import argparse
import csv
import glob
import os
import sys

import yaml


def first_glob(pattern):
    hits = sorted(glob.glob(pattern))
    return hits[0] if hits else ""


def load_mapping(path):
    rows = []
    with open(path) as f:
        for r in csv.DictReader(f):
            if r.get("BIDS_ID"):
                rows.append((r["EP_ID"], r["BIDS_ID"]))
    return rows


def load_resolution(path):
    sess = {}
    if path and os.path.isfile(path):
        with open(path) as f:
            for r in csv.DictReader(f):
                if r.get("BIDS_ID") and r.get("resolved_session"):
                    sess[r["BIDS_ID"]] = r["resolved_session"]
    return sess


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--out", default=None)
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()

    with open(a.config) as f:
        cfg = yaml.safe_load(f)

    out = a.out or cfg["samples"]
    bids_root = cfg["bids_root"]
    cbf_root = cfg["cbf_src_root"]
    fallback = cfg.get("fallback_session", "ses-1")

    mapping = load_mapping(cfg["mapping"])
    resolved = load_resolution(cfg.get("resolution_csv"))

    rows, kept, dropped = [], 0, 0
    for ep, sub in mapping:
        ses = resolved.get(sub, fallback)
        t1 = first_glob(f"{bids_root}/{sub}/{ses}/anat/{sub}_{ses}_T1w.nii.gz")
        if not t1:  # fall back to any session's T1w
            t1 = first_glob(f"{bids_root}/{sub}/ses-*/anat/{sub}_ses-*_T1w.nii.gz")
        flair = first_glob(f"{bids_root}/{sub}/{ses}/anat/{sub}_{ses}_FLAIR.nii.gz")
        cbf = first_glob(f"{cbf_root}/{ep}/*/scans/CBF/cbf.nii.gz")

        if not t1 or not cbf:
            dropped += 1
            if not a.quiet:
                miss = ("T1w" if not t1 else "") + ("/CBF" if not cbf else "")
                print(f"[samples] DROP {sub} ({ep}): missing {miss}", file=sys.stderr)
            continue
        rows.append({"bids_id": sub, "ep_id": ep, "session": ses,
                     "t1w": t1, "flair": flair, "cbf": cbf})
        kept += 1

    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    fields = ["bids_id", "ep_id", "session", "t1w", "flair", "cbf"]
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, delimiter="\t")
        w.writeheader()
        w.writerows(rows)

    print(f"[samples] wrote {kept} sample(s) -> {out}  ({dropped} dropped)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
