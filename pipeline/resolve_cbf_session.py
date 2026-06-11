#!/usr/bin/env python3
"""
resolve_cbf_session.py

For every subject in CBF_BIDS_SUB.csv, determine which BIDS session the CBF was
acquired in, by matching the raw imaging session that contains the CBF scan
(under CIDUR_data) to the BIDS session assignments in COMPLETE_BIDS_MAPPING_FINAL.xlsx.

Logic per subject:
  1. Find the raw <EP>_* session folder that contains a *CBF* scan (CIDUR_data).
  2. Collect the structural T1/MPRAGE series in that same session.
  3. Match those series (normalised) against the subject's BIDS T1w SeriesDescriptions.
  4. The matching BIDS session is the CBF-contemporaneous session -> use it for MELD.

Outputs: CBF_session_resolution.csv
"""
import os
import re
import glob
import csv
import sys
import pandas as pd

CIDUR_DATA = os.environ.get("CIDUR_DATA",
    "/mnt/nfs/home/urmc-sh.rochester.edu/pndagiji/Documents/CIDUR_data")
XLSX = os.environ.get("BIDS_XLSX",
    "/mnt/nfs/home/urmc-sh.rochester.edu/pndagiji/Documents/CIDUR_BIDS/COMPLETE_BIDS_MAPPING_FINAL.xlsx")
MAPPING = os.environ.get("MAPPING",
    "/mnt/nfs/home/urmc-sh.rochester.edu/pndagiji/Documents/Meld_CBF/CBF_BIDS_SUB.csv")
OUT = os.environ.get("OUT",
    "/mnt/nfs/home/urmc-sh.rochester.edu/pndagiji/Documents/Meld_CBF/pipeline/CBF_session_resolution.csv")

T1_RE = re.compile(r"(mprage|mp_rage|mp-rage|sag.*t1|t1.*mprage)", re.I)


def norm(s: str) -> str:
    """lowercase, drop leading 'NN-' series number, strip non-alphanumerics."""
    s = re.sub(r"^\d+-", "", s)
    return re.sub(r"[^a-z0-9]", "", s.lower())


def find_cbf_session(ep: str):
    """Return (session_path, session_name, [t1_series_dirnames]) for the CBF session."""
    cbf_dirs = glob.glob(os.path.join(CIDUR_DATA, ep, "**", "scans", "*CBF*"), recursive=True)
    if not cbf_dirs:
        return None, None, []
    # session folder is the parent of 'scans'
    sess_path = os.path.dirname(os.path.dirname(cbf_dirs[0]))
    sess_name = os.path.basename(sess_path)
    scans = os.path.join(sess_path, "scans")
    t1_series = []
    if os.path.isdir(scans):
        for d in sorted(os.listdir(scans)):
            if T1_RE.search(d) and "reformat" not in d.lower() and "mpr_cor" not in d.lower():
                t1_series.append(d)
    return sess_path, sess_name, t1_series


def main():
    mp = pd.read_csv(MAPPING)
    ac = pd.read_excel(XLSX, sheet_name="All_Converted")
    t1w = ac[ac["Modality"] == "T1w"].copy()

    rows = []
    for _, r in mp.iterrows():
        ep, bids = r["EP_ID"], r["BIDS_ID"]
        sess_path, sess_name, t1_series = find_cbf_session(ep)

        # BIDS T1w options for this subject: {session: SeriesDescription}
        opts = t1w[t1w["EP_ID"] == ep][["Session", "SeriesDescription"]].values.tolist()

        resolved, how = "", ""
        if sess_name and t1_series and opts:
            raw_norm = [norm(s) for s in t1_series]
            best = None
            for sess, desc in opts:
                dn = norm(str(desc))
                for rn in raw_norm:
                    if dn and (dn in rn or rn in dn):
                        best = (sess, desc)
                        break
                if best:
                    break
            if best:
                resolved, how = best[0], f"matched '{best[1]}'"
            else:
                # fall back: if only one BIDS T1w session exists, use it
                sessions = sorted({s for s, _ in opts})
                if len(sessions) == 1:
                    resolved, how = sessions[0], "single BIDS T1w session"
                else:
                    how = "AMBIGUOUS - no series match"
        elif opts:
            sessions = sorted({s for s, _ in opts})
            if len(sessions) == 1:
                resolved, how = sessions[0], "single BIDS T1w session (no raw CBF session found)"
            else:
                how = "AMBIGUOUS - no raw CBF session found"
        else:
            how = "no BIDS T1w"

        rows.append({
            "EP_ID": ep,
            "BIDS_ID": bids,
            "raw_cbf_session": sess_name or "",
            "raw_t1_series": ";".join(t1_series),
            "bids_t1w_sessions": ";".join(sorted({s for s, _ in opts})),
            "resolved_session": resolved,
            "method": how,
        })

    fields = ["EP_ID", "BIDS_ID", "raw_cbf_session", "raw_t1_series",
              "bids_t1w_sessions", "resolved_session", "method"]
    with open(OUT, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    # console summary
    df = pd.DataFrame(rows)
    with pd.option_context("display.max_colwidth", 40, "display.width", 200):
        print(df[["EP_ID", "BIDS_ID", "raw_cbf_session",
                  "bids_t1w_sessions", "resolved_session", "method"]].to_string(index=False))
    amb = df[df["resolved_session"] == ""]
    print(f"\nResolved: {len(df) - len(amb)}/{len(df)}   Ambiguous/failed: {len(amb)}")
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    sys.exit(main())
