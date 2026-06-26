# MELD + CBF pipeline

Runs **MELD Graph** lesion prediction on a subject's T1w, registers that
subject's **CBF** map into MELD's T1 space, and computes **CBF asymmetry index
(AI)** with a cohort-level roll-up.

Orchestrated by **Snakemake** and driven by the **`meldcbf` CLI**. All
neuroimaging runs inside the existing MELD apptainer image.

## Install

```bash
cd Meld_CBF/pipeline
conda env create -f workflow/envs/meldcbf.yaml && conda activate meldcbf
pip install -e .            # provides the `meldcbf` command
```

## Quick start

```bash
meldcbf check                 # validate image / licenses / models / runtime
meldcbf samples               # build the cohort sheet (config/samples.tsv)

meldcbf run sub-002           # one subject, end-to-end (MELD recon is slow)
meldcbf run --profile slurm   # whole cohort on SLURM
meldcbf aggregate             # cohort stats table + concordance call
meldcbf status                # per-subject progress
```

Stage subcommands (`prepare`, `meld`, `register`, `visualize`) accept any subset
of subjects, or none for the full cohort. Everything is config-driven via
`pipeline/config/config.yaml`.

## Key outputs (under `work/output/`)

- `cbf_aligned/<sub>/cbf_in_meld.nii.gz` — CBF on the prediction grid
- `cbf_aligned/<sub>/cbf_in_clusters_<sub>.csv` — per-lesion CBF stats
- `cbf_aligned/<sub>/figures/*.png` — T1 / CBF / prediction overlays
- `cbf_cohort_ai.csv` — cohort AI table (`meldcbf aggregate`)

## Repository layout

- **[pipeline/](pipeline/)** — the Snakemake workflow, `meldcbf` CLI, configs, and SLURM profiles
- **[pipeline/README.md](pipeline/README.md)** — pipeline quick start
- **[pipeline/USER_GUIDE.md](pipeline/USER_GUIDE.md)** — method rationale, full CLI
  reference, statistics dictionary, CBF↔BIDS session resolution, layout, and notes
- **[meld.md](meld.md)** — how the MELD Graph apptainer/docker image is built and run

## Notes

Patient imaging and subject-identifier tables are **never** committed — see
[`.gitignore`](.gitignore). The repository contains code and documentation only.
