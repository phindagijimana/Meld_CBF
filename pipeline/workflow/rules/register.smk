# register.smk — rigid CBF -> MELD T1 registration, resample onto the prediction
# grid, and compute CBF<->prediction statistics (cbf_register_in_container.sh ->
# cbf_stats.py). hypo_z is threaded through from config.
rule register:
    input:
        pred=meld_pred("{sub}"),
        t1mgz=meld_t1mgz("{sub}"),
        cbf=cbf_staged("{sub}"),
    output:
        cbf=cbf_in_meld("{sub}"),
        csv=cbf_stats_csv("{sub}"),
    params:
        cmd=lambda wc: apptainer_cmd(
            f"bash /pipeline/cbf_register_in_container.sh {wc.sub} {config['hypo_z']}"
        ),
    log:
        os.path.join(LOG_DIR, "register_{sub}.log"),
    resources:
        mem_mb=res("register", "mem_mb", 16000),
        runtime=res("register", "runtime", 120),
        cpus_per_task=res("register", "cpus_per_task", 2),
    shell:
        "{params.cmd} > {log} 2>&1"
