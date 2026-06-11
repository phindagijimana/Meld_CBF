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
            f"python scripts/new_patient_pipeline/new_pt_pipeline.py -id {wc.sub}"
        ),
    log:
        os.path.join(LOG_DIR, "meld_{sub}.log"),
    resources:
        mem_mb=res("meld", "mem_mb", 64000),
        runtime=res("meld", "runtime", 1440),
        cpus_per_task=res("meld", "cpus_per_task", 8),
    shell:
        "{params.cmd} > {log} 2>&1"
