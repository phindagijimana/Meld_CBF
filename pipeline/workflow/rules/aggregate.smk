# aggregate.smk — roll every subject's stats into one cohort table and add an
# epilepsy concordance call (see scripts/aggregate_stats.py).
rule aggregate:
    input:
        csvs=expand(cbf_stats_csv("{sub}"), sub=SUBJECTS),
    output:
        csv=COHORT_CSV,
    params:
        asym=config["asym_concordance_pct"],
        dice=config["dice_concordance"],
    log:
        os.path.join(LOG_DIR, "aggregate.log"),
    script:
        "../scripts/aggregate_stats.py"
