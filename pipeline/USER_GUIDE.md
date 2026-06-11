# MELD + CBF — User Guide

Detailed reference for the pipeline. For install and a quick start, see
[README.md](README.md).

## Pipeline overview

```
T1w ──► MELD Graph (apptainer) ──► output/fs_outputs/<sub>/mri/T1.mgz
                                   output/predictions_reports/<sub>/predictions/prediction.nii.gz
cbf.nii.gz ──register to──► MELD's T1 (T1.mgz, identical grid to prediction.nii.gz)
                                   │
                                   ▼
                         CBF resampled into MELD space
                                   │
                         aligned with prediction.nii.gz  ✓   + cbf_in_clusters_<sub>.csv
```

### Why this works

MELD writes `prediction.nii.gz` in the subject's **FreeSurfer conformed-T1
space** (`mri/orig/001.mgz`, same geometry as `mri/T1.mgz`). So if we register
CBF to `T1.mgz`, the resampled CBF lands on the prediction grid automatically —
no registration to the (sparse, label-only) prediction itself.

Registration is **rigid, mutual-information** (`mri_coreg --dof 6`), which is
robust to the CBF↔T1 contrast difference (same subject, same scan session).

## Architecture

A **Snakemake** workflow does the orchestration (DAG, resumability, SLURM,
provenance); the `meldcbf` **CLI** is a thin wrapper over it. All neuroimaging
work runs inside the **MELD apptainer image** (FreeSurfer, `mri_coreg`, the GNN,
and the `nibabel`/`nilearn` stats), so the host only needs Snakemake + a few
Python libs.

```
pipeline/
├── pyproject.toml                  `pip install -e .` -> `meldcbf` console script
├── config/
│   ├── config.yaml                 all paths + stats/SLURM params (edit me)
│   └── samples.tsv                 cohort sheet (generated: bids_id ep_id ses t1w flair cbf)
├── profiles/
│   ├── slurm/config.yaml           Snakemake SLURM executor profile
│   └── local/config.yaml           single-machine profile
├── meldcbf/cli.py                  the CLI (Click)
├── workflow/
│   ├── Snakefile                   prepare → meld → register → visualize → aggregate
│   ├── rules/*.smk                 one file per stage
│   ├── envs/meldcbf.yaml           host conda env
│   └── scripts/
│       ├── build_samples.py        builds samples.tsv from mapping + raw sources
│       └── aggregate_stats.py      cohort roll-up + epilepsy concordance call
├── cbf_register_in_container.sh    (in-container) mri_coreg + mri_vol2vol -> cbf_stats.py
├── cbf_stats.py                    (in-container) GM z-score / ROI asymmetry / concordance
└── cbf_visualize.py                (in-container) headless PNG overlays
```

Outputs (under `work/`, bound to `/data` in the container):

```
work/
├── input/<sub>/T1/<sub>_T1w.nii.gz                MELD input
├── output/fs_outputs/<sub>/mri/{T1,aparc+aseg}.mgz
├── output/predictions_reports/<sub>/predictions/prediction.nii.gz
└── output/cbf_aligned/<sub>/
    ├── cbf_in_meld.nii.gz          CBF on the prediction grid  ◄── main image output
    ├── cbf_in_clusters_<sub>.csv   per-cluster CBF stats (see below)
    └── figures/*.png               T1 / CBF / prediction overlays
work/output/cbf_cohort_stats.csv    cohort table + concordance call (from `aggregate`)
```

The workflow **reuses the institutional MELD install** for the heavy assets
(image, models, `meld_params`, licenses — see `config.yaml`) and writes only into
`work/`, so it never touches the shared `meld_data`.

## CLI reference

```bash
meldcbf check                    # validate image / licenses / models / samples / runtime
meldcbf samples                  # (re)build config/samples.tsv from the mapping + raw data

# One subject, end-to-end (MELD recon is the long part — hours):
meldcbf run sub-002

# Stage by stage (any subset of subjects; omit for the whole cohort):
meldcbf prepare sub-002
meldcbf meld sub-002
meldcbf register sub-002 sub-008
meldcbf visualize sub-002
meldcbf aggregate                # cohort roll-up + concordance call

# Whole cohort on SLURM (one job per rule, MELD gets 64G/8cpu/24h):
meldcbf run --profile slurm -j 16

meldcbf status                   # per-subject progress table
meldcbf -n all                   # dry-run the full DAG
meldcbf dag -o dag.svg           # render the DAG
meldcbf smk -- --report rep.html # passthrough to raw snakemake
```

Everything is config-driven: edit `config/config.yaml` (or override on the fly,
e.g. `meldcbf run --config work=/scratch/$USER/work`). Re-run `meldcbf samples`
after changing source paths. Because it's Snakemake, re-running only does the
missing/outdated work, and a failed subject never blocks the others.

> The legacy `meld_cbf_pipeline.sh` + `config.sh` bash driver still works and
> shares the same in-container scripts, but the Snakemake/CLI path is the
> supported, production entrypoint.

## CBF ↔ MELD statistics (`cbf_stats.py`)

The registration only lands CBF on MELD's grid; the analytical value is here.
For the whole predicted lesion (`all_clusters`) **and** each discrete cluster,
`cbf_in_clusters_<sub>.csv` reports — all in MELD's conformed space, using the
MELD run's own `aparc+aseg`:

| Column | Meaning |
|--------|---------|
| `cbf_mean/std/median`, `volume_mm3` | raw CBF inside the cluster |
| `gm_z` | **GM-normalized z-score**: `(cluster mean − cortical-GM mean)/GM SD`. <0 ⇒ hypoperfused vs the subject's own cortex. |
| `host_roi`, `host_roi_name` | dominant Desikan/Destrieux region the cluster sits in |
| `ipsi_roi_cbf`, `contra_roi_cbf` | mean CBF in that ROI vs its mirror-hemisphere homologue |
| `roi_asym_pct` | **ROI contralateral asymmetry** `(ipsi−contra)/mean×100`. The classic perfusion-lesion sign; negative ⇒ ipsilateral hypoperfusion. |
| `cluster_vs_contra_pct` | cluster CBF vs the contralateral ROI |
| `cluster_mirror_ipsi_cbf` | mean CBF inside the lesion (same as `cbf_mean`) |
| `cluster_mirror_contra_cbf` | mean CBF in the **mirror** of the lesion (cluster mask flipped L↔R on the registered CBF map) |
| `cluster_mirror_ai` | **mirror asymmetry index** `(ipsi−contra)/(ipsi+contra)`. Range ~[−1, 1]; negative ⇒ ipsilateral hypoperfusion vs homotopic mirror. Note: `roi_asym_pct ≈ 200 × cluster_mirror_ai` when comparing the same pair with different denominators. |
| `frac_hypo` | fraction of cluster voxels that are hypoperfused (`z < −1.5`) |
| `dice_hypo` | **concordance**: Dice overlap between the MELD cluster and hypoperfused cortical GM. High ⇒ CBF independently corroborates MELD. |

`meldcbf aggregate` concatenates every subject's CSV into
`output/cbf_cohort_stats.csv` and adds an **epilepsy concordance call** on each
lesion (thresholds in `config.yaml`):

| Column | Meaning |
|--------|---------|
| `hypoperfused` | `roi_asym_pct ≤ asym_concordance_pct` (default −8%) |
| `spatial_concordant` | `dice_hypo ≥ dice_concordance` (default 0.10) |
| `concordance_call` | `concordant` (both) / `partial` (either) / `discordant` (neither) |

This yields a one-line-per-patient table for group analysis, e.g. *"MELD lesions
showed concordant hypoperfusion in N/28"* — the kind of result that supports a
surgical-outcome study. Tune `hypo_z`, `asym_concordance_pct`, and
`dice_concordance` in `config.yaml`.

## CBF ↔ BIDS session resolution

The CBF must be paired with the T1w from the **same scan session**. BIDS
sessions are renumbered, so this is resolved from the raw data:
`resolve_cbf_session.py` finds the raw `CIDUR_data/<EP>/…/<EP>_MR_*` session that
contains the `*-CBF` scan, reads its structural T1 series, and matches them to
the BIDS T1w session assignments in `COMPLETE_BIDS_MAPPING_FINAL.xlsx`. Result:
`CBF_session_resolution.csv` (one row per subject, column `resolved_session`).

All 28 subjects resolved: **27 → ses-1**, **sub-002 → ses-3** (its CBF was in the
second MR session, which BIDS labelled ses-3). The pipeline reads this CSV during
`samples`/`prepare`, so each subject automatically gets the correct,
CBF-contemporaneous T1w (and FLAIR from that session if present). Re-run the
resolver if the cohort changes:

```bash
python3 resolve_cbf_session.py
```

## Notes / assumptions

- **T1w session**: taken per-subject from `CBF_session_resolution.csv`. If a
  subject is missing there, falls back to `fallback_session` in `config.yaml`
  (default `ses-1`). The resolution is baked into `samples.tsv` by `meldcbf samples`.
- **CBF used**: the raw `scans/CBF/cbf.nii.gz` (ASL/perfusion native space).
  Registration handles bringing it into MELD space.
- **Idempotent / resumable**: Snakemake only (re)builds missing or outdated
  outputs; a failed subject doesn't block the rest of the cohort.
- **Overlay check**: `register` verifies `cbf_in_meld.nii.gz` shares shape +
  affine with `prediction.nii.gz` and warns if not.
- To inspect: load `output/fs_outputs/<sub>/mri/T1.mgz`,
  `output/cbf_aligned/<sub>/cbf_in_meld.nii.gz`, and
  `output/predictions_reports/<sub>/predictions/prediction.nii.gz` together in
  freeview — all three are on the same grid.

## Production operations

### First-time setup

1. Copy `config/config.example.yaml` → `config/config.yaml` and set all paths.
2. Generate session resolution: `python3 resolve_cbf_session.py`
3. Build cohort sheet: `meldcbf samples`
4. Preflight: `meldcbf check` (or `meldcbf validate-config`)

**Security:** do not commit `config.yaml` with real institutional paths to a
public repository. Patient imaging and identifier tables are gitignored
(`data/`, `work/`, `CBF_BIDS_SUB.csv`, `samples.tsv`).

### Partial cohorts

`allow_partial_aggregate: true` (default) lets `meldcbf aggregate` build the
cohort table from whichever subjects finished `register`, without blocking on
failures. Set to `false` to require every subject in `samples.tsv`.

### NAS delivery

Results are synced to `nas_dest` (default `/mnt/nfs/Gugger_Lab/MELD_CBF`):

```bash
meldcbf sync                    # all completed subjects + cohort CSV
meldcbf sync sub-002            # one subject
meldcbf sync --dry-run          # preview rsync plan
meldcbf sync --fs sub-002       # include FreeSurfer recon (~1.2 GB/subject)
```

Background watcher (optional): `pipeline/watch_and_sync.sh --config config/config.yaml --full sub-001`

Logs: `work/logs/sync_to_nas.log`

### Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| MELD aborts immediately | Stale partial recon | Re-run `meldcbf meld <sub>` (auto-cleans stale outputs) |
| `register` fails | MELD not finished | Check `work/logs/meld_<sub>.log` |
| Empty stats CSV | MELD-negative subject | Expected — `cluster=none` |
| Aggregate empty | No register outputs | `meldcbf register` on at least one subject |
| SLURM pending forever | Queue priority | Check `squeue`; reduce `-j` concurrency |
| Viz fails | Missing inputs | Ensure `register` completed; check `visualize_<sub>.log` |

### CI / testing

```bash
pip install -e ".[dev]"
pytest -q
```

GitHub Actions runs tests on push to `main` (`.github/workflows/ci.yml`).
