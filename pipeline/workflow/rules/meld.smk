# meld.smk — run MELD Graph (FreeSurfer/FastSurfer recon + GNN lesion prediction)
# inside the apptainer image. This is the long, resource-heavy rule.
rule meld:
    input:
        t1=meld_input_t1("{sub}"),
    output:
        pred=meld_pred("{sub}"),
        t1mgz=meld_t1mgz("{sub}"),
    params:
        cmd=lambda wc: apptainer_cmd(
            "python scripts/new_patient_pipeline/new_pt_pipeline.py "
            f"-id {wc.sub}{' -fastsurfer' if config.get('meld_fastsurfer') else ''}"
        ),
        # MELD aborts if a partial recon exists; snakemake only runs this rule
        # when outputs are missing/stale, so clearing partial state is safe.
        stale=lambda wc: " ".join([
            os.path.join(WORK, "output", "fs_outputs", wc.sub),
            os.path.join(WORK, "output", "predictions_reports", wc.sub),
            os.path.join(WORK, "output", "preprocessed_surf_data", wc.sub),
        ]),
    log:
        os.path.join(LOG_DIR, "meld_{sub}.log"),
    resources:
        mem_mb=res("meld", "mem_mb", 64000),
        runtime=res("meld", "runtime", 1440),
        cpus_per_task=res("meld", "cpus_per_task", 8),
    shell:
        "rm -rf {params.stale} && {params.cmd} > {log} 2>&1"
