#!/usr/bin/env python3
"""
cbf_stats.py — runs INSIDE the MELD container (numpy + nibabel).

Quantitative CBF ↔ MELD-prediction statistics, all in MELD's conformed grid:

  per cluster (and 'all_clusters'):
    - raw CBF       : mean / std / median / min / max, volume
    - gm_z          : (cluster CBF mean − cortical-GM mean) / GM SD     [normalized]
    - host_roi      : dominant Desikan/Destrieux region the cluster sits in
    - ipsi/contra ROI CBF + roi_asym_pct : ROI-level L↔R asymmetry (aparc+aseg homologue)
    - cluster_vs_contra_pct : cluster CBF vs its contralateral ROI
    - frac_hypo     : fraction of cluster voxels with voxelwise z < HYPO_Z
    - dice_hypo     : Dice(cluster, hypoperfused cortical GM at z < HYPO_Z)   [concordance]

Cortical GM and L↔R homologues come from MELD's aparc+aseg (lh=base, rh=base+1000;
Desikan 1000–1035/2000–2035, Destrieux 11100–11175/12100–12175).

Usage:
  cbf_stats.py <subject> <cbf_in_meld.nii.gz> <prediction.nii.gz> <aparc+aseg.mgz> <out_csv> [hypo_z]
"""
import sys
import os
import csv
import numpy as np
import nibabel as nib

HYPO_Z_DEFAULT = -1.5


def load_like(path, ref_img):
    """Load an image; nearest-resample onto ref grid if geometry differs."""
    img = nib.load(path)
    if img.shape[:3] == ref_img.shape[:3] and np.allclose(img.affine, ref_img.affine, atol=1e-3):
        return np.asarray(img.get_fdata())
    try:
        from nilearn.image import resample_to_img
        img = resample_to_img(img, ref_img, interpolation="nearest")
    except Exception as e:
        print(f"[stats][WARN] could not resample {os.path.basename(path)}: {e}")
    return np.asarray(img.get_fdata())


def is_cortical(lbl):
    lbl = int(lbl)
    return (1000 <= lbl <= 1035) or (2000 <= lbl <= 2035) or \
           (11100 <= lbl <= 11175) or (12100 <= lbl <= 12175)


def homologue(lbl):
    """Contralateral label for a cortical aparc+aseg label (L↔R offset 1000)."""
    lbl = int(lbl)
    if (1000 <= lbl <= 1035) or (11100 <= lbl <= 11175):
        return lbl + 1000
    if (2000 <= lbl <= 2035) or (12100 <= lbl <= 12175):
        return lbl - 1000
    return None


def load_lut():
    """label -> region name from FreeSurferColorLUT.txt (best-effort)."""
    fs = os.environ.get("FREESURFER_HOME", "")
    path = os.path.join(fs, "FreeSurferColorLUT.txt")
    lut = {}
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split()
                if len(parts) >= 2 and parts[0].isdigit():
                    lut[int(parts[0])] = parts[1]
    except Exception:
        pass
    return lut


def pct_asym(a, b):
    """Asymmetry index in %: (a−b)/mean(a,b)*100. Negative = a < b."""
    if a is None or b is None:
        return ""
    denom = (a + b) / 2.0
    if denom == 0:
        return ""
    return round((a - b) / denom * 100.0, 2)


def main():
    if len(sys.argv) < 6:
        print(__doc__)
        return 1
    subject, cbf_path, pred_path, aparc_path, out_csv = sys.argv[1:6]
    hypo_z = float(sys.argv[6]) if len(sys.argv) > 6 else HYPO_Z_DEFAULT

    cbf_img = nib.load(cbf_path)
    cbf = np.asarray(cbf_img.get_fdata())
    pred = load_like(pred_path, cbf_img)
    vox = float(abs(np.linalg.det(cbf_img.affine[:3, :3])))

    have_aparc = os.path.isfile(aparc_path)
    if have_aparc:
        aparc = load_like(aparc_path, cbf_img).astype(int)
        cortical = np.vectorize(is_cortical)(aparc) if aparc.size else np.zeros_like(aparc, bool)
        gm_mask = cortical & np.isfinite(cbf)
        gm_vals = cbf[gm_mask]
        gm_mean = float(np.mean(gm_vals)) if gm_vals.size else float("nan")
        gm_sd = float(np.std(gm_vals)) if gm_vals.size else float("nan")
        # voxelwise z within GM, hypoperfused cortical GM mask
        hypo_gm = np.zeros_like(cbf, bool)
        if gm_sd and np.isfinite(gm_sd) and gm_sd > 0:
            z = (cbf - gm_mean) / gm_sd
            hypo_gm = gm_mask & (z < hypo_z)
        lut = load_lut()
    else:
        print(f"[stats][WARN] aparc+aseg not found ({aparc_path}); ROI/GM metrics skipped")
        gm_mean = gm_sd = float("nan")
        hypo_gm = np.zeros_like(cbf, bool)
        aparc = None
        lut = {}

    labels = np.unique(pred[pred > 0]).astype(int)
    rows = []

    def roi_mean(lbl):
        if aparc is None or lbl is None:
            return None
        m = (aparc == int(lbl)) & np.isfinite(cbf)
        return float(np.mean(cbf[m])) if m.any() else None

    def summarize(name, mask):
        vals = cbf[mask & np.isfinite(cbf)]
        n = int(vals.size)
        row = {"subject": subject, "cluster": name, "n_voxels": n,
               "volume_mm3": round(n * vox, 1)}
        if n:
            cmean = float(np.mean(vals))
            row.update({
                "cbf_mean": round(cmean, 4),
                "cbf_std": round(float(np.std(vals)), 4),
                "cbf_median": round(float(np.median(vals)), 4),
                "gm_z": round((cmean - gm_mean) / gm_sd, 3) if (gm_sd and np.isfinite(gm_sd) and gm_sd > 0) else "",
            })
            # host ROI = dominant cortical label among cluster voxels
            host = host_name = ipsi = contra = ""
            roi_asym = clus_vs_contra = ""
            if aparc is not None:
                labs = aparc[mask]
                labs = labs[np.vectorize(is_cortical)(labs)] if labs.size else labs
                if labs.size:
                    host = int(np.bincount(labs).argmax())
                    host_name = lut.get(host, str(host))
                    h = homologue(host)
                    ipsi = roi_mean(host)
                    contra = roi_mean(h)
                    roi_asym = pct_asym(ipsi, contra)
                    clus_vs_contra = pct_asym(cmean, contra)
            # concordance
            frac_hypo = round(float(np.mean(hypo_gm[mask])), 3) if mask.any() else ""
            inter = int(np.sum(mask & hypo_gm))
            dice = round(2 * inter / (int(mask.sum()) + int(hypo_gm.sum())), 3) if (mask.sum() + hypo_gm.sum()) else ""
            row.update({
                "host_roi": host, "host_roi_name": host_name,
                "ipsi_roi_cbf": round(ipsi, 4) if isinstance(ipsi, float) else "",
                "contra_roi_cbf": round(contra, 4) if isinstance(contra, float) else "",
                "roi_asym_pct": roi_asym,
                "cluster_vs_contra_pct": clus_vs_contra,
                "frac_hypo": frac_hypo, "dice_hypo": dice,
            })
        return row

    if labels.size:
        rows.append(summarize("all_clusters", pred > 0))
        for lab in labels:
            rows.append(summarize(f"cluster_{lab}", pred == lab))
    else:
        rows.append({"subject": subject, "cluster": "none", "n_voxels": 0, "volume_mm3": 0})

    fields = ["subject", "cluster", "n_voxels", "volume_mm3",
              "cbf_mean", "cbf_std", "cbf_median", "gm_z",
              "host_roi", "host_roi_name", "ipsi_roi_cbf", "contra_roi_cbf",
              "roi_asym_pct", "cluster_vs_contra_pct", "frac_hypo", "dice_hypo"]
    with open(out_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    print(f"[stats] GM mean={gm_mean:.2f} sd={gm_sd:.2f}  | {len(labels)} cluster(s); wrote {out_csv}")
    for r in rows:
        print("[stats]  ", {k: r.get(k, "") for k in
                            ("cluster", "n_voxels", "cbf_mean", "gm_z", "roi_asym_pct", "frac_hypo", "dice_hypo")})
    return 0


if __name__ == "__main__":
    sys.exit(main())
