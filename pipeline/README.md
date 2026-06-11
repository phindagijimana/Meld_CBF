# MELD + CBF pipeline

Runs **MELD Graph** lesion prediction on a subject's T1w, registers that
subject's **CBF** map into MELD's prediction space, and computes quantitative
CBF ↔ prediction statistics (GM-normalized z-score, contralateral asymmetry,
and concordance) with a cohort-level epilepsy concordance call.

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
`config/config.yaml`.

## Key outputs (under `work/output/`)

- `cbf_aligned/<sub>/cbf_in_meld.nii.gz` — CBF on the prediction grid
- `cbf_aligned/<sub>/cbf_in_clusters_<sub>.csv` — per-lesion CBF stats
- `cbf_aligned/<sub>/figures/*.png` — T1 / CBF / prediction overlays
- `cbf_cohort_stats.csv` — cohort table + per-patient concordance call

## More

See **[USER_GUIDE.md](USER_GUIDE.md)** for the method rationale, full CLI
reference, the statistics dictionary, CBF↔BIDS session resolution, the project
layout, and assumptions/notes.
