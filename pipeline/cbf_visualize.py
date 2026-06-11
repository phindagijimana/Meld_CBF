#!/usr/bin/env python3
"""
cbf_visualize.py  — runs INSIDE the MELD container (nilearn + matplotlib).

Generates headless overlay PNGs for a subject after MELD + CBF registration:
  1. prediction_on_T1.png   MELD lesion prediction over the conformed T1
  2. cbf_on_T1.png          CBF (in MELD space) over the T1, lesion contour in green
  3. cbf_with_pred.png      CBF heatmap focused on the lesion, prediction contour

All inputs share the conformed-T1 grid, so overlays are exact. Figures are
centred on the lesion centre-of-mass when a prediction is present.

Usage:
  cbf_visualize.py <subject> <T1.mgz> <prediction.nii.gz> <cbf_in_meld.nii.gz> <out_dir>
"""
import sys
import os
import numpy as np
import matplotlib
matplotlib.use("Agg")  # headless
import nibabel as nib
from nilearn import plotting, image


def lesion_cut_coords(pred_img):
    """Center-of-mass (world mm) of nonzero prediction voxels, else None."""
    data = np.asarray(pred_img.get_fdata())
    mask = data > 0
    if not mask.any():
        return None
    ijk = np.array(np.where(mask)).mean(axis=1)
    xyz = nib.affines.apply_affine(pred_img.affine, ijk)
    return tuple(xyz)


def require_file(path, label):
    if not os.path.isfile(path):
        print(f"[viz][ERROR] missing {label}: {path}", file=sys.stderr)
        return False
    return True


def main():
    if len(sys.argv) != 6:
        print(__doc__)
        return 1
    subject, t1_path, pred_path, cbf_path, out_dir = sys.argv[1:6]
    os.makedirs(out_dir, exist_ok=True)

    if not require_file(t1_path, "T1"):
        return 1

    written = []
    t1 = image.load_img(t1_path)
    has_pred = require_file(pred_path, "prediction")
    has_cbf = require_file(cbf_path, "CBF")
    pred = image.load_img(pred_path) if has_pred else None
    cut = lesion_cut_coords(pred) if has_pred else None
    disp_mode = "ortho"

    # 1. Prediction over T1
    if has_pred:
        out = os.path.join(out_dir, f"{subject}_prediction_on_T1.png")
        d = plotting.plot_roi(
            image.math_img("img > 0", img=pred), bg_img=t1,
            cut_coords=cut, display_mode=disp_mode, title=f"{subject}: MELD prediction",
            cmap="autumn", alpha=0.7, black_bg=True)
        d.savefig(out, dpi=150); d.close()
        written.append(out)
        print(f"[viz] wrote {out}")

    # 2. CBF over T1 with lesion contour
    if has_cbf:
        cbf = image.load_img(cbf_path)
        out = os.path.join(out_dir, f"{subject}_cbf_on_T1.png")
        d = plotting.plot_stat_map(
            cbf, bg_img=t1, cut_coords=cut, display_mode=disp_mode,
            title=f"{subject}: CBF in MELD space", cmap="hot",
            colorbar=True, black_bg=True)
        if has_pred and cut is not None:
            d.add_contours(image.math_img("img > 0", img=pred),
                           levels=[0.5], colors="lime", linewidths=1.5)
        d.savefig(out, dpi=150); d.close()
        written.append(out)
        print(f"[viz] wrote {out}")

        # 3. Multi-slice axial CBF through the lesion, with prediction contour
        if has_pred and cut is not None:
            out = os.path.join(out_dir, f"{subject}_cbf_with_pred.png")
            d = plotting.plot_stat_map(
                cbf, bg_img=t1, display_mode="z", cut_coords=6,
                title=f"{subject}: CBF @ lesion", cmap="hot",
                colorbar=True, black_bg=True)
            d.add_contours(image.math_img("img > 0", img=pred),
                           levels=[0.5], colors="lime", linewidths=1.5)
            d.savefig(out, dpi=150); d.close()
            written.append(out)
            print(f"[viz] wrote {out}")
    elif has_pred:
        print("[viz] no cbf_in_meld.nii.gz — prediction figure only")

    if not written:
        print("[viz][ERROR] no figures produced", file=sys.stderr)
        return 1

    print(f"[viz] DONE: {len(written)} figure(s) in {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
