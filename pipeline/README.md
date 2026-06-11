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

## Statistics formulas

All metrics are computed in MELD's conformed T1 grid after CBF registration.
Let **ipsi** and **contra** denote ipsilateral and contralateral CBF means.

**GM-normalized z-score** (cluster hypoperfusion vs subject's own cortex):

$$z = \frac{\overline{\mathrm{CBF}}_{\mathrm{cluster}} - \mu_{\mathrm{GM}}}{\sigma_{\mathrm{GM}}}$$

**ROI asymmetry** (FreeSurfer `aparc+aseg` homologue pair — whole region):

$$\mathrm{roi\_asym\_pct} = \frac{\mathrm{CBF}_{\mathrm{ipsi\,ROI}} - \mathrm{CBF}_{\mathrm{contra\,ROI}}}{\tfrac{1}{2}(\mathrm{CBF}_{\mathrm{ipsi\,ROI}} + \mathrm{CBF}_{\mathrm{contra\,ROI}})} \times 100$$

**Cluster mirror asymmetry index** (lesion mask flipped L↔R on the registered CBF map; ipsi = mean CBF inside lesion, contra = mean CBF in the mirror location):

$$\mathrm{cluster\_mirror\_ai} = \frac{\mathrm{CBF}_{\mathrm{ipsi}} - \mathrm{CBF}_{\mathrm{contra}}}{\mathrm{CBF}_{\mathrm{ipsi}} + \mathrm{CBF}_{\mathrm{contra}}}$$

Range ~[−1, 1]; negative ⇒ ipsilateral hypoperfusion. Note: `roi_asym_pct ≈ 200 × cluster_mirror_ai` when the same pair uses the two denominators above.

**Concordance** (voxelwise hypoperfusion vs cluster, threshold `hypo_z` default −1.5):

$$\mathrm{frac\_hypo} = \frac{\#\{\mathrm{cluster\ voxels\ with\ } z < \mathrm{hypo\_z}\}}{\#\mathrm{cluster\ voxels}}$$

$$\mathrm{dice\_hypo} = \frac{2\,|\mathrm{cluster} \cap \mathrm{hypo\_GM}|}{|\mathrm{cluster}| + |\mathrm{hypo\_GM}|}$$

Cohort concordance call (`meldcbf aggregate`): **hypoperfused** if `roi_asym_pct ≤ asym_concordance_pct` (default −8%); **spatial_concordant** if `dice_hypo ≥ dice_concordance` (default 0.10).

## More

See **[USER_GUIDE.md](USER_GUIDE.md)** for the method rationale, full CLI
reference, the statistics dictionary, CBF↔BIDS session resolution, the project
layout, and assumptions/notes.
