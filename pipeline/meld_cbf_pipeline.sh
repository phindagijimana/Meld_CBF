#!/usr/bin/env bash
# ===========================================================================
# meld_cbf_pipeline.sh  — DEPRECATED: use `meldcbf` CLI + Snakemake instead.
#
# End-to-end pipeline: run MELD Graph on a subject, then bring that subject's
# CBF map into MELD's prediction space.
#
#   T1w  ──► MELD Graph (apptainer) ──► fs_outputs/<sub>/mri/T1.mgz
#                                       predictions_reports/<sub>/predictions/prediction.nii.gz
#   cbf.nii.gz ──register to──► MELD's T1 (T1.mgz, == prediction grid)
#                                       │
#                                       ▼
#                              CBF resampled into MELD space
#                                       │
#                              aligned with prediction.nii.gz  ✓  + per-cluster CBF CSV
#
# Subjects are BIDS IDs (e.g. sub-002) from CBF_BIDS_SUB.csv. Each maps to an
# EP_ID whose CBF lives under CBF_T1_rage/.
#
# USAGE:
#   ./meld_cbf_pipeline.sh prepare [sub-XXX ...]   Copy T1w + CBF into data/ (all subjects if none given)
#   ./meld_cbf_pipeline.sh run     <sub-XXX>       Full pipeline for one subject (blocking)
#   ./meld_cbf_pipeline.sh meld    <sub-XXX>       MELD only
#   ./meld_cbf_pipeline.sh register <sub-XXX>      CBF->MELD registration + stats only (needs MELD done)
#   ./meld_cbf_pipeline.sh visualize <sub-XXX>     Headless overlay PNGs (T1+CBF+prediction)
#   ./meld_cbf_pipeline.sh all     [sub-XXX ...]   `run` for every subject (sequential)
#   ./meld_cbf_pipeline.sh slurm   <sub-XXX>       Submit one `run` as a SLURM job
#   ./meld_cbf_pipeline.sh slurm all               Submit one SLURM job per subject
#   ./meld_cbf_pipeline.sh aggregate               Merge per-subject stats into cohort CSV
#   ./meld_cbf_pipeline.sh check                   Verify image/licenses/models/runtime
#   ./meld_cbf_pipeline.sh status [sub-XXX]        Show progress
# ===========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/config.sh"

c_red=$'\033[0;31m'; c_grn=$'\033[0;32m'; c_ylw=$'\033[1;33m'; c_cyn=$'\033[0;36m'; c_off=$'\033[0m'
info()  { echo "${c_cyn}[INFO]${c_off} $*"; }
ok()    { echo "${c_grn}[ OK ]${c_off} $*"; }
warn()  { echo "${c_ylw}[WARN]${c_off} $*"; }
err()   { echo "${c_red}[FAIL]${c_off} $*" >&2; }
die()   { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# ep_for_bids — look up EP_ID for a BIDS_ID in the mapping CSV
# ---------------------------------------------------------------------------
ep_for_bids() {
    local bids="$1"
    awk -F, -v b="$bids" 'NR>1 && $2==b {print $1; exit}' "${MAPPING}"
}

all_bids_ids() {
    awk -F, 'NR>1 && $2!="" {print $2}' "${MAPPING}"
}

# ---------------------------------------------------------------------------
# find_cbf_src / find_t1_src — resolve raw source files
# ---------------------------------------------------------------------------
find_cbf_src() {
    local ep="$1"
    ls "${CBF_SRC_ROOT}/${ep}"/*/scans/CBF/cbf.nii.gz 2>/dev/null | head -1 || true
}

# resolved_session_for_bids — BIDS session whose T1w is contemporaneous with the
# CBF (from CBF_session_resolution.csv). Falls back to ${T1_SESSION}.
resolved_session_for_bids() {
    local bids="$1" sess=""
    if [[ -f "${RESOLUTION_CSV}" ]]; then
        sess=$(awk -F, -v b="${bids}" 'NR>1 && $2==b {print $6; exit}' "${RESOLUTION_CSV}")
    fi
    echo "${sess:-${T1_SESSION}}"
}

find_t1_src() {
    local bids="$1" sess="$2"
    # Prefer the resolved/CBF session, else first available session.
    local f
    f=$(ls "${BIDS_ROOT}/${bids}/${sess}/anat/${bids}_${sess}_T1w.nii.gz" 2>/dev/null | head -1 || true)
    if [[ -z "${f}" ]]; then
        f=$(ls "${BIDS_ROOT}/${bids}"/ses-*/anat/"${bids}"_ses-*_T1w.nii.gz 2>/dev/null | head -1 || true)
    fi
    echo "${f}"
}

find_flair_src() {
    local bids="$1" sess="$2"
    ls "${BIDS_ROOT}/${bids}/${sess}/anat/${bids}_${sess}_FLAIR.nii.gz" 2>/dev/null | head -1 || true
}

# ---------------------------------------------------------------------------
# cmd_prepare — populate data/<bids>/{anat,cbf} from raw sources
# ---------------------------------------------------------------------------
cmd_prepare() {
    local -a subs
    if [[ $# -gt 0 ]]; then subs=("$@"); else mapfile -t subs < <(all_bids_ids); fi

    info "Preparing ${#subs[@]} subject(s) into ${DATA_DIR}"
    local prepared=0 skipped=0
    for bids in "${subs[@]}"; do
        local ep; ep=$(ep_for_bids "${bids}")
        if [[ -z "${ep}" ]]; then warn "${bids}: not in mapping — skip"; ((skipped+=1)); continue; fi

        local sess t1_src cbf_src flair_src
        sess=$(resolved_session_for_bids "${bids}")
        t1_src=$(find_t1_src "${bids}" "${sess}")
        flair_src=$(find_flair_src "${bids}" "${sess}")
        cbf_src=$(find_cbf_src "${ep}")

        if [[ -z "${t1_src}" ]];  then warn "${bids} (${ep}): no T1w source — skip";  ((skipped+=1)); continue; fi
        if [[ -z "${cbf_src}" ]]; then warn "${bids} (${ep}): no CBF source — skip";  ((skipped+=1)); continue; fi

        # BIDS session layout: data/<sub>/<ses>/{anat,perf}/<sub>_<ses>_*.nii.gz
        local sdir="${DATA_DIR}/${bids}/${sess}"
        mkdir -p "${sdir}/anat" "${sdir}/perf"
        cp -f "${t1_src}"  "${sdir}/anat/${bids}_${sess}_T1w.nii.gz"
        cp -f "${cbf_src}" "${sdir}/perf/${bids}_${sess}_cbf.nii.gz"
        local extra=""
        if [[ -n "${flair_src}" ]]; then
            cp -f "${flair_src}" "${sdir}/anat/${bids}_${sess}_FLAIR.nii.gz"
            extra=" + FLAIR"
        fi
        ok "${bids} (${ep}): ${sess} T1w${extra} + CBF staged"
        ((prepared+=1))
    done
    info "prepare summary: ${prepared} prepared, ${skipped} skipped"
}

# ---------------------------------------------------------------------------
# stage_meld_input — link the prepared T1w into the MELD input tree (MELD format)
#   work/input/<sub>/T1/<sub>_T1w.nii.gz
# ---------------------------------------------------------------------------
stage_meld_input() {
    local bids="$1"
    local t1 flair cbf
    t1=$(ls "${DATA_DIR}/${bids}"/ses-*/anat/"${bids}"_ses-*_T1w.nii.gz 2>/dev/null | head -1 || true)
    [[ -n "${t1}" ]] || die "${bids}: prepared T1w not found under ${DATA_DIR}/${bids}/ses-*/anat/; run 'prepare' first"

    mkdir -p "${WORK}/input/${bids}/T1" "${WORK}/output" "${WORK}/cbf" "${LOG_DIR}"
    ln -sfn "${t1}" "${WORK}/input/${bids}/T1/${bids}_T1w.nii.gz"

    # FLAIR is optional; include if it was prepared.
    flair=$(ls "${DATA_DIR}/${bids}"/ses-*/anat/"${bids}"_ses-*_FLAIR.nii.gz 2>/dev/null | head -1 || true)
    if [[ -n "${flair}" ]]; then
        mkdir -p "${WORK}/input/${bids}/FLAIR"
        ln -sfn "${flair}" "${WORK}/input/${bids}/FLAIR/${bids}_FLAIR.nii.gz"
    fi

    # CBF is co-located in the working tree so it is visible at /data/cbf inside the container.
    cbf=$(ls "${DATA_DIR}/${bids}"/ses-*/perf/"${bids}"_ses-*_cbf.nii.gz 2>/dev/null | head -1 || true)
    [[ -n "${cbf}" ]] || die "${bids}: prepared CBF not found under ${DATA_DIR}/${bids}/ses-*/perf/"
    ln -sfn "${cbf}" "${WORK}/cbf/${bids}_cbf.nii.gz"
}

# ---------------------------------------------------------------------------
# apptainer_exec — run a command inside the MELD image with MELD's bind layout
# ---------------------------------------------------------------------------
apptainer_exec() {
    local cmd="$1"
    "${APPTAINER_BIN}" exec \
        --bind "${WORK}:/data" \
        --bind "${MODELS_SRC}:/data/models:ro" \
        --bind "${MELD_PARAMS_SRC}:/data/meld_params:ro" \
        --bind "${FS_LICENSE}:/license.txt:ro" \
        --bind "${MELD_LICENSE}:/meld_license.txt:ro" \
        --bind "${SCRIPT_DIR}:/pipeline:ro" \
        --env FS_LICENSE=/license.txt \
        --env MELD_LICENSE=/meld_license.txt \
        --env FREESURFER_HOME="${FREESURFER_HOME_IN}" \
        --env PYTHONNOUSERSITE=1 \
        "${SIF}" \
        /bin/bash -c "cd /app && source \$FREESURFER_HOME/FreeSurferEnv.sh && ${cmd}"
}

# ---------------------------------------------------------------------------
# cmd_meld — run MELD Graph for one subject (skips if prediction already exists)
# ---------------------------------------------------------------------------
cmd_meld() {
    local bids="${1:?subject id required}"
    local pred="${WORK}/output/predictions_reports/${bids}/predictions/prediction.nii.gz"
    if [[ -f "${pred}" ]]; then
        ok "${bids}: MELD prediction already present — skipping MELD run"
        return 0
    fi
    stage_meld_input "${bids}"
    local log="${LOG_DIR}/meld_${bids}_$(date +%Y%m%d-%H%M%S).log"
    info "${bids}: running MELD Graph (log: ${log})"
    apptainer_exec "python scripts/new_patient_pipeline/new_pt_pipeline.py -id ${bids}" 2>&1 | tee "${log}"
    [[ -f "${pred}" ]] || die "${bids}: MELD finished but prediction.nii.gz missing — check ${log}"
    ok "${bids}: MELD complete"
}

# ---------------------------------------------------------------------------
# cmd_register — CBF -> MELD T1 registration + cluster stats
# ---------------------------------------------------------------------------
cmd_register() {
    local bids="${1:?subject id required}"
    stage_meld_input "${bids}"   # ensures /data/cbf/<sub>_cbf.nii.gz link exists
    local t1="${WORK}/output/fs_outputs/${bids}/mri/T1.mgz"
    [[ -f "${t1}" ]] || die "${bids}: MELD T1.mgz not found (${t1}); run 'meld' first"
    local log="${LOG_DIR}/register_${bids}_$(date +%Y%m%d-%H%M%S).log"
    info "${bids}: registering CBF into MELD space (log: ${log})"
    apptainer_exec "bash /pipeline/${REGISTER_HELPER_NAME} ${bids}" 2>&1 | tee "${log}"
    ok "${bids}: CBF aligned -> ${WORK}/output/cbf_aligned/${bids}/cbf_in_meld.nii.gz"
}

# ---------------------------------------------------------------------------
# cmd_visualize — headless overlay PNGs (T1 + CBF + prediction) via nilearn
# ---------------------------------------------------------------------------
cmd_visualize() {
    local bids="${1:?subject id required}"
    local out="${WORK}/output/cbf_aligned/${bids}"
    local t1="${WORK}/output/fs_outputs/${bids}/mri/T1.mgz"
    local pred="${WORK}/output/predictions_reports/${bids}/predictions/prediction.nii.gz"
    local cbf="${out}/cbf_in_meld.nii.gz"
    [[ -f "${t1}" ]] || die "${bids}: T1.mgz not found (run 'meld' first)"
    mkdir -p "${out}/figures"
    info "${bids}: rendering overlay figures -> ${out}/figures"
    apptainer_exec "python /pipeline/cbf_visualize.py ${bids} /data/output/fs_outputs/${bids}/mri/T1.mgz /data/output/predictions_reports/${bids}/predictions/prediction.nii.gz /data/output/cbf_aligned/${bids}/cbf_in_meld.nii.gz /data/output/cbf_aligned/${bids}/figures"
    ok "${bids}: figures in ${out}/figures"
}

# ---------------------------------------------------------------------------
# cmd_run — full per-subject pipeline
# ---------------------------------------------------------------------------
cmd_run() {
    local bids="${1:?subject id required}"
    cmd_prepare "${bids}"
    cmd_meld "${bids}"
    cmd_register "${bids}"
    cmd_visualize "${bids}" || warn "${bids}: visualization step failed (non-fatal)"
    ok "${bids}: pipeline complete"
}

cmd_all() {
    local -a subs
    if [[ $# -gt 0 ]]; then subs=("$@"); else mapfile -t subs < <(all_bids_ids); fi
    local failed=()
    for bids in "${subs[@]}"; do
        info "===== ${bids} ====="
        if cmd_run "${bids}"; then ok "${bids} done"; else err "${bids} failed"; failed+=("${bids}"); fi
    done
    if [[ ${#failed[@]} -gt 0 ]]; then die "Failed: ${failed[*]}"; fi
    ok "All subjects complete"
}

# ---------------------------------------------------------------------------
# cmd_slurm — submit `run` as a batch job (re-invokes this script)
# ---------------------------------------------------------------------------
cmd_slurm() {
    command -v sbatch &>/dev/null || die "sbatch not on PATH"
    mkdir -p "${LOG_DIR}"
    local part=(); [[ -n "${SLURM_PARTITION}" ]] && part=(--partition="${SLURM_PARTITION}")

    if [[ "${1:-}" == "all" ]]; then
        shift
        local -a subs
        if [[ $# -gt 0 ]]; then subs=("$@"); else mapfile -t subs < <(all_bids_ids); fi
        for bids in "${subs[@]}"; do cmd_slurm "${bids}"; done
        return 0
    fi

    local bids="${1:?subject id required}"
    local jid
    jid=$(sbatch "${part[@]}" --export=ALL \
        --job-name="meldcbf_${bids}" \
        --output="${LOG_DIR}/slurm_${bids}_%j.out" \
        --error="${LOG_DIR}/slurm_${bids}_%j.out" \
        --time="${SLURM_TIME_LIMIT}" --mem="${SLURM_MEM}" --cpus-per-task="${SLURM_CPUS_PER_TASK}" \
        --wrap="cd ${SCRIPT_DIR} && bash ./meld_cbf_pipeline.sh run ${bids}" | awk '{print $NF}')
    ok "${bids}: submitted SLURM job ${jid}  (log: ${LOG_DIR}/slurm_${bids}_${jid}.out)"
}

# ---------------------------------------------------------------------------
# cmd_aggregate — concatenate per-subject stats CSVs into one cohort table
# ---------------------------------------------------------------------------
cmd_aggregate() {
    local master="${WORK}/output/cbf_cohort_stats.csv"
    local first=1 n=0
    : > "${master}.tmp"
    while IFS= read -r bids; do
        local csv="${WORK}/output/cbf_aligned/${bids}/cbf_in_clusters_${bids}.csv"
        [[ -f "${csv}" ]] || continue
        if [[ ${first} -eq 1 ]]; then
            head -1 "${csv}" > "${master}.tmp"; first=0
        fi
        tail -n +2 "${csv}" >> "${master}.tmp"
        ((n+=1))
    done < <(all_bids_ids)
    if [[ ${n} -eq 0 ]]; then
        rm -f "${master}.tmp"
        warn "No per-subject stats found yet (run 'register' first)."
        return 0
    fi
    mv "${master}.tmp" "${master}"
    ok "Aggregated ${n} subject(s) -> ${master}"
    info "Lesion (all_clusters) rows:"
    awk -F, 'NR==1 || $2=="all_clusters"' "${master}" | column -s, -t | head -40
}

# ---------------------------------------------------------------------------
# cmd_check / cmd_status
# ---------------------------------------------------------------------------
cmd_check() {
    local crit=0
    [[ -n "${APPTAINER_BIN}" ]] && ok "container runtime: ${APPTAINER_BIN}" || { err "apptainer/singularity not found"; crit=1; }
    [[ -f "${SIF}" ]]          && ok "image: ${SIF}"            || { err "missing image: ${SIF}"; crit=1; }
    [[ -f "${FS_LICENSE}" ]]   && ok "freesurfer license"       || { err "missing: ${FS_LICENSE}"; crit=1; }
    [[ -f "${MELD_LICENSE}" ]] && ok "meld license"             || { err "missing: ${MELD_LICENSE}"; crit=1; }
    [[ -d "${MODELS_SRC}" ]]   && ok "models: ${MODELS_SRC}"    || { err "missing models: ${MODELS_SRC}"; crit=1; }
    [[ -d "${MELD_PARAMS_SRC}" ]] && ok "meld_params: ${MELD_PARAMS_SRC}" || { err "missing meld_params: ${MELD_PARAMS_SRC}"; crit=1; }
    [[ -f "${MAPPING}" ]]      && ok "mapping: ${MAPPING} ($(($(wc -l < "${MAPPING}")-1)) subjects)" || { err "missing mapping: ${MAPPING}"; crit=1; }
    command -v sbatch &>/dev/null && ok "sbatch available" || warn "sbatch not found (local runs only)"
    [[ "${crit}" -eq 0 ]] && ok "check passed" || die "check failed — fix the items above"
}

cmd_status() {
    local bids="${1:-}"
    if [[ -n "${bids}" ]]; then
        local pred="${WORK}/output/predictions_reports/${bids}/predictions/prediction.nii.gz"
        local cbf="${WORK}/output/cbf_aligned/${bids}/cbf_in_meld.nii.gz"
        echo "  ${bids}: data=$( ls ${DATA_DIR}/${bids}/ses-*/anat/${bids}_ses-*_T1w.nii.gz >/dev/null 2>&1 && echo yes || echo no )" \
             "meld=$( [[ -f ${pred} ]] && echo yes || echo no )" \
             "cbf_aligned=$( [[ -f ${cbf} ]] && echo yes || echo no )"
        return 0
    fi
    info "Pipeline status (data / meld / cbf_aligned):"
    while IFS= read -r b; do cmd_status "${b}"; done < <(all_bids_ids)
}

# ---------------------------------------------------------------------------
main() {
    local cmd="${1:-help}"; shift || true
    case "${cmd}" in
        prepare)  cmd_prepare "$@" ;;
        meld)     cmd_meld "$@" ;;
        register) cmd_register "$@" ;;
        visualize|viz) cmd_visualize "$@" ;;
        run)      cmd_run "$@" ;;
        all)      cmd_all "$@" ;;
        slurm)    cmd_slurm "$@" ;;
        aggregate|agg) cmd_aggregate ;;
        check)    cmd_check ;;
        status)   cmd_status "$@" ;;
        help|-h|--help)
            sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
        *) die "Unknown command: ${cmd} (try: help)" ;;
    esac
}
main "$@"
