# common.smk — config, sample sheet, and the shared apptainer command builder.
import os
import csv

WORK = config["work"]
DATA = config["data_dir"]
PIPELINE_DIR = config["pipeline_dir"]
LOG_DIR = os.path.join(WORK, "logs")

# --- Cohort sample sheet ----------------------------------------------------
SAMPLES = {}
with open(config["samples"]) as _fh:
    for _row in csv.DictReader(_fh, delimiter="\t"):
        SAMPLES[_row["bids_id"]] = _row
SUBJECTS = list(SAMPLES)

if not SUBJECTS:
    raise WorkflowError(
        f"No samples in {config['samples']}. Run `meldcbf samples` first."
    )

wildcard_constraints:
    sub=r"sub-[A-Za-z0-9]+",


# --- Output path templates (single source of truth) ------------------------
def meld_input_t1(sub):
    return os.path.join(WORK, "input", sub, "T1", f"{sub}_T1w.nii.gz")


def cbf_staged(sub):
    return os.path.join(WORK, "cbf", f"{sub}_cbf.nii.gz")


def meld_pred(sub):
    return os.path.join(WORK, "output", "predictions_reports", sub,
                        "predictions", "prediction.nii.gz")


def meld_t1mgz(sub):
    return os.path.join(WORK, "output", "fs_outputs", sub, "mri", "T1.mgz")


def cbf_in_meld(sub):
    return os.path.join(WORK, "output", "cbf_aligned", sub, "cbf_in_meld.nii.gz")


def cbf_stats_csv(sub):
    return os.path.join(WORK, "output", "cbf_aligned", sub,
                        f"cbf_in_clusters_{sub}.csv")


def viz_flag(sub):
    return os.path.join(WORK, "output", "cbf_aligned", sub, "figures", ".done")


COHORT_CSV = os.path.join(WORK, "output", "cbf_cohort_stats.csv")


# --- Resource lookup --------------------------------------------------------
def res(rule_name, key, default):
    return config.get("resources", {}).get(rule_name, {}).get(key, default)


# --- Apptainer command builder (mirrors the original bind layout) ----------
def apptainer_cmd(inner):
    c = config
    binds = [
        f'{WORK}:/data',
        f'{c["models_src"]}:/data/models:ro',
        f'{c["meld_params_src"]}:/data/meld_params:ro',
        f'{c["fs_license"]}:/license.txt:ro',
        f'{c["meld_license"]}:/meld_license.txt:ro',
        f'{PIPELINE_DIR}:/pipeline:ro',
    ]
    bind_args = " ".join(f"--bind {b}" for b in binds)
    envs = (
        "--env FS_LICENSE=/license.txt "
        "--env MELD_LICENSE=/meld_license.txt "
        f'--env FREESURFER_HOME={c["freesurfer_home_in"]} '
        "--env PYTHONNOUSERSITE=1"
    )
    fsenv = f'source {c["freesurfer_home_in"]}/FreeSurferEnv.sh'
    return (
        f'{c["apptainer_bin"]} exec {bind_args} {envs} {c["sif"]} '
        f'/bin/bash -c "cd /app && {fsenv} && {inner}"'
    )
