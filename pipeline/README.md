# MELD + CBF pipeline

Runs **MELD Graph** lesion prediction on a subject's T1w, registers that
subject's **CBF** map into MELD's T1 space, and computes **CBF asymmetry index
(AI)** metrics with a cohort-level roll-up.

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
cp config/config.example.yaml config/config.yaml   # first-time site setup
meldcbf check                 # validate image / licenses / paths / runtime
meldcbf samples               # build the cohort sheet (config/samples.tsv)

meldcbf run sub-002           # one subject, end-to-end (MELD recon is slow)
meldcbf run --aggregate sub-002   # through cohort roll-up
meldcbf run --profile slurm   # whole cohort on SLURM
meldcbf aggregate             # cohort AI table (partial cohort OK)
meldcbf sync                  # deliver results to NAS (config: nas_dest)
meldcbf status                # per-subject progress
```

Stage subcommands (`prepare`, `meld`, `register`, `visualize`) accept any subset
of subjects, or none for the full cohort. Everything is config-driven via
`config/config.yaml`.

## Key outputs (under `work/output/`)

- `cbf_aligned/<sub>/cbf_in_meld.nii.gz` — CBF on the prediction grid
- `cbf_aligned/<sub>/cbf_in_clusters_<sub>.csv` — per-lesion AI + supporting fields
- `cbf_aligned/<sub>/figures/*.png` — T1 / CBF / prediction overlays
- `cbf_cohort_ai.csv` — cohort AI table (`meldcbf aggregate`)

## Asymmetry index (primary analysis)

All AI metrics are computed in MELD's conformed T1 grid after CBF registration.
Let **ipsi** and **contra** denote ipsilateral and contralateral CBF means.

**ROI asymmetry** (FreeSurfer `aparc+aseg` homologue pair — whole region):

$$\mathrm{roi\_asym\_pct} = \frac{\mathrm{CBF}_{\mathrm{ipsi\,ROI}} - \mathrm{CBF}_{\mathrm{contra\,ROI}}}{\tfrac{1}{2}(\mathrm{CBF}_{\mathrm{ipsi\,ROI}} + \mathrm{CBF}_{\mathrm{contra\,ROI}})} \times 100$$

**Cluster mirror asymmetry index** (lesion mask flipped L↔R on the registered CBF map):

$$\mathrm{cluster\_mirror\_ai} = \frac{\mathrm{CBF}_{\mathrm{ipsi}} - \mathrm{CBF}_{\mathrm{contra}}}{\mathrm{CBF}_{\mathrm{ipsi}} + \mathrm{CBF}_{\mathrm{contra}}}$$

Range ~[−1, 1]; negative ⇒ ipsilateral hypoperfusion.

Cohort AI flags (`meldcbf aggregate`, threshold `asym_concordance_pct` default −8%):

- `roi_hypoperfused` — `roi_asym_pct ≤` threshold
- `mirror_hypoperfused` — `cluster_mirror_ai < 0`
- `ai_hypoperfused` — either flag true

## Production checklist

| Step | Command |
|------|---------|
| Site config | `cp config/config.example.yaml config/config.yaml` and edit paths |
| Preflight | `meldcbf check` |
| Cohort sheet | `meldcbf samples` |
| Run (SLURM) | `meldcbf run --profile slurm --aggregate` |
| Monitor | `meldcbf status` / `squeue -u $USER` |
| Partial cohort table | `meldcbf aggregate` (uses completed subjects only) |
| Deliver to NAS | `meldcbf sync` |
| Tests (dev) | `pytest -q` |

Config keys for production: `allow_partial_aggregate`, `nas_dest`, `container_tag`.
See **[USER_GUIDE.md](USER_GUIDE.md)** for troubleshooting, security, and NAS sync.

## More

See **[USER_GUIDE.md](USER_GUIDE.md)** for the method rationale, full CLI
reference, the statistics dictionary, CBF↔BIDS session resolution, the project
layout, and assumptions/notes.
