# aggregate.smk — roll every subject's stats into one AI-focused cohort table
# (roi_asym_pct + cluster_mirror_ai; see scripts/aggregate_stats.py).
#
# Uses only *existing* per-subject CSVs so a partial cohort does not block the
# cohort table (see config: allow_partial_aggregate).

def stats_csvs_available(wildcards):
    files = [cbf_stats_csv(s) for s in SUBJECTS if os.path.isfile(cbf_stats_csv(s))]
    if not files:
        raise WorkflowError(
            "No per-subject stats CSVs found. Run `meldcbf register` for at least one subject."
        )
    allow = config.get("allow_partial_aggregate", True)
    if not allow:
        missing = [s for s in SUBJECTS if not os.path.isfile(cbf_stats_csv(s))]
        if missing:
            raise WorkflowError(
                f"allow_partial_aggregate=false but missing stats for: {', '.join(missing)}"
            )
    return files


rule aggregate:
    input:
        csvs=stats_csvs_available,
    output:
        csv=COHORT_CSV,
    params:
        asym=config["asym_concordance_pct"],
        allow_partial=config.get("allow_partial_aggregate", True),
        expected=len(SUBJECTS),
        pipeline_version=config.get("container_tag", "unknown"),
    log:
        os.path.join(LOG_DIR, "aggregate.log"),
    script:
        "../scripts/aggregate_stats.py"
