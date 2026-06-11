#!/bin/bash
# ---------------------------------------------------------------------------
# cbf_register_in_container.sh
#
# Runs INSIDE the MELD apptainer image (FreeSurfer 7.2 + meld_graph conda env).
# Registers a subject's CBF map into MELD's conformed-T1 space, which is the
# SAME grid as MELD's prediction.nii.gz.
#
#   cbf.nii.gz ──mri_coreg──► T1.mgz  (rigid, mutual-information; contrast-agnostic)
#              ──mri_vol2vol─► cbf_in_meld.nii.gz  (T1.mgz grid == prediction grid)
#              ──cbf_stats.py─► comparative CBF<->prediction stats CSV
#
# Stats: GM-normalized z, ROI-homologue L<->R asymmetry (aparc+aseg), and
# concordance (Dice + fraction hypoperfused). See cbf_stats.py.
#
# All paths below are CONTAINER paths (under /data, which is bound to $WORK).
#
# Usage (invoked by the host driver via `apptainer exec … `):
#   cbf_register_in_container.sh <subject_id>
# ---------------------------------------------------------------------------
set -euo pipefail

SUBJECT="${1:?subject id required}"
HYPO_Z="${2:-}"   # optional voxelwise hypoperfusion z threshold for cbf_stats.py

DATA=/data
FS_SUBJECTS="${DATA}/output/fs_outputs"
PRED_DIR="${DATA}/output/predictions_reports/${SUBJECT}/predictions"
CBF_IN="${DATA}/cbf/${SUBJECT}_cbf.nii.gz"
OUT_DIR="${DATA}/output/cbf_aligned/${SUBJECT}"

T1_MGZ="${FS_SUBJECTS}/${SUBJECT}/mri/T1.mgz"
PRED_NII="${PRED_DIR}/prediction.nii.gz"

REG_LTA="${OUT_DIR}/cbf_to_meldT1.lta"
CBF_OUT="${OUT_DIR}/cbf_in_meld.nii.gz"
STATS_CSV="${OUT_DIR}/cbf_in_clusters_${SUBJECT}.csv"

echo "[register] subject=${SUBJECT}"
echo "[register] CBF in : ${CBF_IN}"
echo "[register] T1 ref : ${T1_MGZ}"
echo "[register] pred   : ${PRED_NII}"

[[ -f "${CBF_IN}" ]]  || { echo "[register][ERROR] missing CBF: ${CBF_IN}"; exit 2; }
[[ -f "${T1_MGZ}" ]]  || { echo "[register][ERROR] missing MELD T1 (did MELD finish?): ${T1_MGZ}"; exit 2; }

mkdir -p "${OUT_DIR}"

# --- 1. Estimate rigid CBF -> MELD T1 transform ----------------------------
# mri_coreg uses mutual information, so it is robust to the CBF/T1 contrast
# difference (no assumption about GM/WM polarity). 6 DOF = rigid (same subject).
echo "[register] mri_coreg (rigid, MI) ..."
mri_coreg \
    --mov "${CBF_IN}" \
    --ref "${T1_MGZ}" \
    --reg "${REG_LTA}" \
    --dof 6

# --- 2. Resample CBF onto the MELD T1 grid (== prediction grid) ------------
echo "[register] mri_vol2vol -> ${CBF_OUT}"
mri_vol2vol \
    --mov "${CBF_IN}" \
    --targ "${T1_MGZ}" \
    --lta "${REG_LTA}" \
    --o "${CBF_OUT}" \
    --interp trilin

# --- 3. Sanity check: geometry of CBF-in-MELD vs prediction ----------------
if [[ -f "${PRED_NII}" ]]; then
    echo "[register] verifying grid match with prediction.nii.gz ..."
    python - "$CBF_OUT" "$PRED_NII" <<'PY'
import sys, numpy as np, nibabel as nib
a = nib.load(sys.argv[1]); b = nib.load(sys.argv[2])
same_shape = a.shape[:3] == b.shape[:3]
same_aff = np.allclose(a.affine, b.affine, atol=1e-3)
print(f"[register]   cbf_in_meld shape={a.shape[:3]} prediction shape={b.shape[:3]} -> shape_match={same_shape}")
print(f"[register]   affine_match={same_aff}")
if not (same_shape and same_aff):
    print("[register][WARNING] grids differ; overlay may be misaligned")
PY
else
    echo "[register][WARNING] no prediction.nii.gz yet — skipping grid check and cluster stats"
    echo "[register] DONE (CBF aligned to MELD T1): ${CBF_OUT}"
    exit 0
fi

# --- 4. Quantitative CBF <-> prediction statistics -------------------------
# GM-normalized z-score, ROI-based contralateral asymmetry (aparc+aseg),
# and concordance (Dice + fraction hypoperfused). See cbf_stats.py.
APARC="${FS_SUBJECTS}/${SUBJECT}/mri/aparc+aseg.mgz"
echo "[register] computing CBF<->prediction stats -> ${STATS_CSV}"
python /pipeline/cbf_stats.py "${SUBJECT}" "${CBF_OUT}" "${PRED_NII}" "${APARC}" "${STATS_CSV}" ${HYPO_Z}

echo "[register] DONE: ${CBF_OUT}"
echo "[register] STATS: ${STATS_CSV}"
