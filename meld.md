# MELD Graph — Container Implementation Notes

How the MELD Graph container is built and how our HPC wrapper
[`docker_version/meld-docker`](../Meld_Graph/docker_version/meld-docker) drives it.

Upstream project: [MELDProject/meld_graph](https://github.com/MELDProject/meld_graph)
Official install guides:
- Docker:      <https://meld-graph.readthedocs.io/en/latest/install_docker.html>
- Singularity: <https://meld-graph.readthedocs.io/en/latest/install_singularity.html>

We use the **Apptainer/Singularity** path because BlueHive (and most HPCs) does
not support Docker.

---

## 1. What's inside the official MELD Graph image

Image: `meldproject/meld_graph:<tag>` (we pin `v2.2.4`).

The upstream
[`Dockerfile`](https://github.com/MELDProject/meld_graph/blob/main/Dockerfile)
is a two-stage build:

| Stage | What it builds |
|------|----------------|
| `micromamba` (`mambaorg/micromamba`) | Builds the `meld_graph` conda env from `environment.yml`, copied later into the final image at `/opt/conda/envs/meld_graph`. |
| `MELDgraph` (`debian:12-slim`) | Adds FreeSurfer 7.2.0 (unpacked into `/opt/freesurfer-7.2.0`), FastSurfer v1.1.2 (cloned into `/opt/fastsurfer-v1.1.2`), the MELD Graph repository under `/app`, and Python packages: `torch==1.10.0`, `torchvision==0.11.1`, `torch-scatter`, `torch-geometric==2.4.0`, `captum==0.6.0`, plus `pip install -e .` of `meld_graph`. |

Key environment baked into the image:

| Variable | Value |
|----------|-------|
| `FREESURFER_HOME` | `/opt/freesurfer-7.2.0` |
| `FASTSURFER_HOME` | `/opt/fastsurfer-v1.1.2` |
| `PATH` | `/opt/conda/envs/meld_graph/bin:/opt/freesurfer-7.2.0/bin:…` |
| `FS_LICENSE` | `/license.txt` (referenced in `~/.bashrc`) |
| `KEEP_DATA_PATH` | `1` |
| `SILENT` | `1` |
| `WORKDIR` | `/app` |
| `ENTRYPOINT` | `/bin/bash entrypoint.sh` |

### The entrypoint contract

```bash
#!/bin/bash
source $FREESURFER_HOME/FreeSurferEnv.sh
$@
```

So the runtime contract is:

> Mount **license files** and a **data directory**, then invoke any Python
> command (relative to `/app`) and it will run inside a conda env where
> `FreeSurferEnv.sh` is already sourced.

The container is *file-coupled*, not API-coupled — everything happens through
two well-known mountpoints:

- `/data`              — read/write, holds `input/`, `output/`, `models/`, `meld_params/`, `logs/`
- `/license.txt`       — FreeSurfer license (read-only)
- `/meld_license.txt`  — MELD license (read-only)

The pipeline reads `FS_LICENSE`, `MELD_LICENSE`, and uses `/data` as the
canonical project root.

### Building it for HPC

Per the [Singularity guide](https://meld-graph.readthedocs.io/en/latest/install_singularity.html),
on HPC you convert the Docker image to a SIF:

```bash
apptainer build meld_graph_v2.2.4.sif docker://meldproject/meld_graph:v2.2.4
# ~13 GB output
```

This is the file our wrapper expects at `MELD_DEPLOY_ROOT/meld_graph_v2.2.4.sif`.

---

## 2. How `docker_version/meld-docker` wraps it

Path: `/mnt/nfs/home/urmc-sh.rochester.edu/pndagiji/Documents/Meld_Graph/docker_version/meld-docker`

A single self-contained Bash script (no Python deps, no `docker` runtime
required) that turns the upstream Apptainer recipe into a small CLI for HPC use,
SLURM submission, and cohort management. It is portable: dropping the
`docker_version/` directory anywhere on disk makes everything resolve relative to
itself via `MELD_DEPLOY_ROOT`.

### Layout the wrapper assumes

```
docker_version/                       <- MELD_DEPLOY_ROOT
├── meld-docker                       Bash CLI (this file)
├── meld_production.sh                Thin wrapper → `meld-docker cohort …`
├── production.env (optional)         Site overrides, sourced if present
├── meld_graph_v2.2.4.sif             Apptainer image (built once)
├── freesurfer_license.txt
├── meld_license.txt
└── meld_data/                        MELD_DATA_DIR (default)
    ├── input/                        BIDS root mounted to /data/input
    │   ├── dataset_description.json
    │   ├── meld_bids_config.json
    │   └── sub-XXX -> ../<Cohort>/sub-XXX     (symlinked by `cohort sync`)
    ├── output/                       FS + predictions land here
    ├── logs/                         Pipeline + SLURM + recon-all tails
    ├── locks/                        Per-subject PID lockfiles
    ├── models/                       Pretrained MELD weights
    ├── meld_params/                  Norm/harmonisation params
    └── <Cohort>/sub-XXX/anat/*_T1w.nii.gz     (raw cohort layout)
```

### Configuration resolution

All paths are environment-driven; defaults are computed from
`MELD_DEPLOY_ROOT` so the bundle is movable.

| Variable | Default | Purpose |
|----------|---------|---------|
| `MELD_DEPLOY_ROOT` | dir of this script | Bundle root |
| `MELD_CONTAINER_IMAGE` | `${MELD_DEPLOY_ROOT}/meld_graph_v2.2.4.sif` | SIF path |
| `MELD_DATA_DIR` | `${MELD_DEPLOY_ROOT}/meld_data` | Mounted as `/data` |
| `MELD_PARAMS_SRC` | `${MELD_DATA_DIR}/meld_params` | Extra bind to `/data/meld_params:ro` if set |
| `MODELS_SRC` | `${MELD_DATA_DIR}/models` | Extra bind to `/data/models:ro` if set |
| `MELD_FS_LICENSE` | `${MELD_DEPLOY_ROOT}/freesurfer_license.txt` | → `/license.txt:ro` |
| `MELD_MELD_LICENSE` | `${MELD_DEPLOY_ROOT}/meld_license.txt` | → `/meld_license.txt:ro` |
| `SLURM_MEM` / `SLURM_CPUS_PER_TASK` / `SLURM_TIME_LIMIT` / `SLURM_PARTITION` / `SLURM_MAIL_*` | unset / sensible defaults | Passed to `sbatch` |

`production.env` (if present next to the script) is sourced with `set -a`, so
it can either define variables or `export` them; see
[`production.env.example`](../Meld_Graph/docker_version/production.env.example).

### The Apptainer invocation it builds

The core wrapper function `run_container`
([`meld-docker:352`](../Meld_Graph/docker_version/meld-docker)) builds this
command — which is exactly the recipe from the official Singularity guide:

```bash
apptainer exec \
  --bind  ${MELD_DATA_DIR}:/data \
  [--bind ${MELD_PARAMS_SRC}:/data/meld_params:ro] \
  [--bind ${MODELS_SRC}:/data/models:ro] \
  --bind  ${FS_LICENSE}:/license.txt:ro \
  --bind  ${MELD_LICENSE}:/meld_license.txt:ro \
  --env   FS_LICENSE=/license.txt \
  --env   MELD_LICENSE=/meld_license.txt \
  --env   FREESURFER_HOME=/opt/freesurfer-7.2.0 \
  --env   PYTHONNOUSERSITE=1 \
  ${CONTAINER_IMAGE} \
  /bin/bash -c "cd /app && source \$FREESURFER_HOME/FreeSurferEnv.sh && <cmd>"
```

Notes on each choice:

- **`PYTHONNOUSERSITE=1`** — defends against a known footgun: the container
  ships `numpy==1.22` (ABI-locked to `pandas==1.4.1`), but if the host user has
  a newer numpy in `~/.local/lib/python*/site-packages`, Apptainer's default
  user-site behaviour will leak it into the container and break imports. This
  variable disables `~/.local` discovery inside the container.
- **Re-sourcing `FreeSurferEnv.sh`** — the upstream `entrypoint.sh` does this,
  but we use `apptainer exec` (not `run`), which bypasses the entrypoint, so we
  reproduce it manually. This matches the MELD docs verbatim.
- **License paths `/license.txt` and `/meld_license.txt`** — these are the
  exact paths the container's baked-in `FS_LICENSE` and MELD code look at, so
  we never have to rewrite anything inside the SIF.
- **Optional `/data/meld_params:ro` and `/data/models:ro` overlays** — let one
  host install share large read-only assets across cohorts on NFS, while each
  cohort still gets its own writable `/data` for `input/output/logs`.

### The pipeline command it runs

For each subject, the wrapper runs (inside the container):

```bash
cd /app && source $FREESURFER_HOME/FreeSurferEnv.sh && \
  python scripts/new_patient_pipeline/new_pt_pipeline.py -id <subject> [flags]
```

Forwarded flags supported by the pipeline (passthrough):
`-harmo_code <code>`, `--fastsurfer`, `--parallelise`,
`--skip_feature_extraction`, `--no_nifti`, `--no_report`, `--debug_mode`.

### Subcommands

`meld-docker <command>` exposes the workflow primitives:

| Command | What it does |
|---------|--------------|
| `check` | Readiness report — image present, runtime on PATH, licenses present, `meld_data` populated, ≥15 GB free, SLURM available, lists detected cohorts. Exits 1 on hard errors. |
| `validate <subject>` | Walks `input/<subject>/anat/` or `input/<subject>/ses-*/anat/`, verifies a `*T1w.nii.gz` exists, FLAIR is optional, checks BIDS root metadata files. |
| `run <subject> [flags]` | Acquires a per-subject PID lock, builds a timestamped log under `meld_data/logs/`, runs the apptainer command, releases the lock. |
| `batch <sub1> <sub2> … [flags]` | Sequential `run`, with a per-subject success/failure summary. |
| `cohort sync` | Walks `meld_data/<Cohort>/sub-*/`, requires `anat/*T1w.nii.gz`, and symlinks each into `meld_data/input/sub-XXX`. Idempotent: if a correct symlink already exists it is skipped; mismatched targets/regular files are reported as errors. Also writes default `dataset_description.json` and `meld_bids_config.json` into `input/` if missing. |
| `cohort run / slurm / run-all / slurm-all` | Compose `cohort sync` + `run`/`slurm` for one subject or every `sub-*` under a cohort. |
| `slurm <subject> [flags]` | `cohort sync`, then submits one `sbatch` job that re-invokes `bash ./meld-docker run <subject>` inside the allocation. |
| `slurm cohort <Cohort> [flags]` | Same, fanned out over every `sub-*` in that cohort. |
| `status [subject]` | Inspects `output/predictions_reports/`, lock files, and `output/fs_outputs/<subject>/touch/` to report DONE / RUNNING / stale-lock / FS-progress-only / not-started. |
| `logs [subject]` | Without a subject: lists recent logs. With one: tails `MELD_pipeline_<sub>_*.log`, the matching `slurm_<sub>_*.out`, and FreeSurfer `recon-all-status.log` / `recon-all.log`. |
| `results <subject>` | Lists the report dir and prints the first lines of `info_clusters_<sub>.csv`. |
| `shell` | Opens an interactive shell inside the container with the FreeSurfer env sourced. |
| `version` | Prints script version, resolved paths, image size. |

### Locking model

A bare-bones PID lock (`meld_data/locks/<sub>.lock`) prevents accidental
double-runs:

- `acquire_lock` writes `$$` into the lockfile.
- If a lock exists and its PID is alive (`kill -0`), the run aborts with
  `subject already being processed`.
- If the PID is dead, the lock is treated as stale and removed.
- `release_lock` deletes the file unconditionally on exit.

This is enough for single-host or single-SLURM-job-per-subject use; it is
**not** a network lock — if multiple login nodes share the same NFS
`MELD_DATA_DIR`, two simultaneous `acquire_lock` calls can race. In practice
SLURM scheduling makes this unlikely.

### SLURM submission

`submit_slurm_job` builds an `sbatch --wrap=…` that simply re-enters the same
script:

```bash
sbatch \
  [--partition=$SLURM_PARTITION] \
  --export=ALL \
  [--mail-user=$SLURM_MAIL_USER --mail-type=$SLURM_MAIL_TYPE] \
  --job-name="meld_<subject>" \
  --output=meld_data/logs/slurm_<subject>_%j.out \
  --error=meld_data/logs/slurm_<subject>_%j.out \
  --time=$SLURM_TIME_LIMIT     # default 24:00:00
  --mem=$SLURM_MEM             # default 64G
  --cpus-per-task=$SLURM_CPUS_PER_TASK   # default 8
  --wrap="cd $SCRIPT_DIR && bash ./meld-docker run <subject> <flags>"
```

So inside the SLURM allocation, `meld-docker run` does all the same work — the
SLURM path is just a non-blocking submission of the local-run path. This
keeps one code path for both interactive and batch use.

### `meld_production.sh`

[`meld_production.sh`](../Meld_Graph/docker_version/meld_production.sh) is a
1-screen wrapper that rewrites three convenience verbs to `meld-docker cohort`
subcommands and `exec`s the main script:

| Wrapper verb | Translates to |
|--------------|---------------|
| `sync`          | `meld-docker cohort sync` |
| `run-cohort`    | `meld-docker cohort run-all` |
| `slurm-cohort`  | `meld-docker cohort slurm-all` |

Everything else is passed through unchanged.

### Smoke test

[`meld_docker_smoke_test.sh`](../Meld_Graph/docker_version/meld_docker_smoke_test.sh)
runs `bash -n` on both scripts, then `./meld-docker check` and
`./meld-docker cohort sync` — fast sanity check after editing the wrapper or
moving the bundle.

---

## 3. End-to-end flow for a new subject

```
host filesystem                              container view
───────────────                              ──────────────
meld_data/Meld_Owen/sub-001/anat/*_T1w.nii.gz
        │
        │ (1) ./meld-docker cohort sync
        ▼
meld_data/input/sub-001 → ../Meld_Owen/sub-001
                                              /data/input/sub-001/anat/*_T1w.nii.gz
        │
        │ (2) ./meld-docker run sub-001
        ▼
apptainer exec --bind meld_data:/data … meld_graph_v2.2.4.sif \
    /bin/bash -c "cd /app && source FreeSurferEnv.sh && \
       python scripts/new_patient_pipeline/new_pt_pipeline.py -id sub-001"
        │
        ▼
meld_data/output/fs_outputs/sub-001/         /data/output/fs_outputs/sub-001/
meld_data/output/predictions_reports/sub-001/{reports, predictions, …}
meld_data/logs/MELD_pipeline_sub-001_<ts>.log
```

(With SLURM, step 2 becomes
`./meld-docker slurm sub-001` → `sbatch --wrap='bash ./meld-docker run sub-001'`.)

---

## 4. Why not plain `docker run`?

The upstream
[`compose.yml`](https://meld-graph.readthedocs.io/en/latest/install_docker.html#configuration)
assumes root-or-equivalent Docker access (`DOCKER_USER`, secrets, `:/data`
bind). Our HPC has only Apptainer/Singularity, no Docker daemon, and SLURM as
the scheduler. The wrapper preserves every semantic from `compose.yml` (mount
points, license bind locations, env var names) while replacing `docker compose
run` with `apptainer exec` and adding cohort/SLURM ergonomics.

## 5. Where things live

| Thing | Path |
|------|------|
| Wrapper | `/mnt/nfs/home/.../Documents/Meld_Graph/docker_version/meld-docker` |
| Cohort wrapper | `…/Meld_Graph/docker_version/meld_production.sh` |
| Smoke test | `…/Meld_Graph/docker_version/meld_docker_smoke_test.sh` |
| Site-override template | `…/Meld_Graph/docker_version/production.env.example` |
| Apptainer image (built) | `…/Meld_Graph/docker_version/meld_graph_v2.2.4.sif` |
| Default data root | `…/Meld_Graph/docker_version/meld_data/` |
| Upstream repo | <https://github.com/MELDProject/meld_graph> |
| Upstream Singularity guide | <https://meld-graph.readthedocs.io/en/latest/install_singularity.html> |
