#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# config.sh — shared configuration for the MELD + CBF pipeline.
#
# Every path below can be overridden by exporting the variable before calling
# the pipeline (e.g. `T1_SESSION=ses-3 ./meld_cbf_pipeline.sh prepare`).
# Sourced by meld_cbf_pipeline.sh.
# ---------------------------------------------------------------------------
set -euo pipefail

# Directory holding this pipeline (…/Meld_CBF/pipeline)
PIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Project root (…/Meld_CBF)
PROJECT_ROOT="$(cd "${PIPE_DIR}/.." && pwd)"

# --- MELD container assets (reuse the existing institutional install) -------
MELD_INSTALL="${MELD_INSTALL:-/mnt/nfs/home/urmc-sh.rochester.edu/pndagiji/Documents/Meld_Graph/meld_graph/meld_data}"
SIF="${SIF:-${MELD_INSTALL}/docker_version/meld_graph_v2.2.4.sif}"
FS_LICENSE="${FS_LICENSE:-${MELD_INSTALL}/docker_version/freesurfer_license.txt}"
MELD_LICENSE="${MELD_LICENSE:-${MELD_INSTALL}/docker_version/meld_license.txt}"
# Shared, read-only model + parameter trees (bound to /data/models, /data/meld_params)
MODELS_SRC="${MODELS_SRC:-${MELD_INSTALL}/models}"
MELD_PARAMS_SRC="${MELD_PARAMS_SRC:-${MELD_INSTALL}/meld_params}"

# --- Pipeline data locations ------------------------------------------------
# Co-located source inputs: data/<BIDS_ID>/anat/<BIDS_ID>_T1w.nii.gz
#                           data/<BIDS_ID>/cbf/<BIDS_ID>_cbf.nii.gz
DATA_DIR="${DATA_DIR:-${PROJECT_ROOT}/data}"
# Container working tree — bound to /data. Holds input/ and output/.
WORK="${WORK:-${PROJECT_ROOT}/work}"
# EP_ID <-> BIDS_ID mapping (built earlier)
MAPPING="${MAPPING:-${PROJECT_ROOT}/CBF_BIDS_SUB.csv}"
# Per-subject CBF->BIDS session resolution (from resolve_cbf_session.py).
# Gives the BIDS session whose T1w is contemporaneous with the CBF acquisition.
RESOLUTION_CSV="${RESOLUTION_CSV:-${PIPE_DIR}/CBF_session_resolution.csv}"
# Per-run logs
LOG_DIR="${LOG_DIR:-${WORK}/logs}"

# --- Upstream raw sources (used by the `prepare` stage) ---------------------
CBF_SRC_ROOT="${CBF_SRC_ROOT:-/mnt/nfs/home/urmc-sh.rochester.edu/pndagiji/Documents/CBF_T1_rage}"
BIDS_ROOT="${BIDS_ROOT:-/mnt/nfs/home/urmc-sh.rochester.edu/pndagiji/Documents/CIDUR_BIDS/data_bids}"
# Fallback BIDS session if a subject is absent from RESOLUTION_CSV.
T1_SESSION="${T1_SESSION:-ses-1}"

# --- Container runtime ------------------------------------------------------
APPTAINER_BIN="${APPTAINER_BIN:-$(command -v apptainer 2>/dev/null || command -v singularity 2>/dev/null || true)}"
FREESURFER_HOME_IN="${FREESURFER_HOME_IN:-/opt/freesurfer-7.2.0}"

# --- SLURM defaults (used by `slurm` subcommand) ----------------------------
SLURM_MEM="${SLURM_MEM:-64G}"
SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK:-8}"
SLURM_TIME_LIMIT="${SLURM_TIME_LIMIT:-24:00:00}"
SLURM_PARTITION="${SLURM_PARTITION:-}"

# In-container path of the registration helper (PIPE_DIR is bound to /pipeline)
REGISTER_HELPER_NAME="cbf_register_in_container.sh"
