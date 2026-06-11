# visualize.smk — headless overlay PNGs (T1 + CBF + prediction) via nilearn.
# Output is a flag file (the PNG set lives alongside it in figures/).
rule visualize:
    input:
        cbf=cbf_in_meld("{sub}"),
        pred=meld_pred("{sub}"),
        t1mgz=meld_t1mgz("{sub}"),
    output:
        flag=viz_flag("{sub}"),
    params:
        cmd=lambda wc: apptainer_cmd(
            f"python /pipeline/cbf_visualize.py {wc.sub} "
            f"/data/output/fs_outputs/{wc.sub}/mri/T1.mgz "
            f"/data/output/predictions_reports/{wc.sub}/predictions/prediction.nii.gz "
            f"/data/output/cbf_aligned/{wc.sub}/cbf_in_meld.nii.gz "
            f"/data/output/cbf_aligned/{wc.sub}/figures"
        ),
    log:
        os.path.join(LOG_DIR, "visualize_{sub}.log"),
    resources:
        mem_mb=res("visualize", "mem_mb", 8000),
        runtime=res("visualize", "runtime", 30),
        cpus_per_task=res("visualize", "cpus_per_task", 1),
    shell:
        "{params.cmd} > {log} 2>&1 && touch {output.flag}"
