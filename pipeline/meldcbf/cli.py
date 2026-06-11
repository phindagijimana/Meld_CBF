#!/usr/bin/env python3
"""
meldcbf — command-line interface for the MELD + CBF pipeline.

Thin, dependency-light wrapper around Snakemake that exposes the pipeline as
stage subcommands. Examples:

    meldcbf check                       # validate container assets / runtime
    meldcbf samples                     # (re)build the cohort sample sheet
    meldcbf run sub-002                 # full pipeline for one subject
    meldcbf meld                        # MELD for every sample (use --profile slurm)
    meldcbf register sub-002 sub-008    # CBF -> MELD space + stats
    meldcbf aggregate                   # cohort roll-up + concordance call
    meldcbf status                      # per-subject progress table
    meldcbf run --profile slurm         # whole cohort on SLURM
    meldcbf -n all                      # dry-run the full DAG
"""
import csv
import os
import shutil
import subprocess
import sys
from pathlib import Path

import click
import yaml

PIPE = Path(__file__).resolve().parent.parent          # …/Meld_CBF/pipeline
SNAKEFILE = PIPE / "workflow" / "Snakefile"
DEFAULT_CONFIG = PIPE / "config" / "config.yaml"
BUILD_SAMPLES = PIPE / "workflow" / "scripts" / "build_samples.py"
PROFILES = PIPE / "profiles"

STAGES = ("prepare", "meld", "register", "visualize")


# --------------------------------------------------------------------------- helpers
def _load_config(cfg_path):
    with open(cfg_path) as f:
        return yaml.safe_load(f)


def _load_samples(cfg):
    path = cfg["samples"]
    if not os.path.isfile(path):
        return []
    with open(path) as f:
        return [r["bids_id"] for r in csv.DictReader(f, delimiter="\t") if r.get("bids_id")]


def _target(cfg, stage, sub):
    w = cfg["work"]
    return {
        "prepare": f"{w}/input/{sub}/T1/{sub}_T1w.nii.gz",
        "meld": f"{w}/output/predictions_reports/{sub}/predictions/prediction.nii.gz",
        "register": f"{w}/output/cbf_aligned/{sub}/cbf_in_meld.nii.gz",
        "visualize": f"{w}/output/cbf_aligned/{sub}/figures/.done",
    }[stage]


def _resolve_subjects(cfg, subs):
    available = _load_samples(cfg)
    if not subs:
        return available
    unknown = [s for s in subs if s not in available]
    if unknown:
        raise click.ClickException(
            f"Unknown subject(s): {', '.join(unknown)}.\n"
            f"Known: {', '.join(available) or '(none — run `meldcbf samples`)'}"
        )
    return list(subs)


def _snakemake(ctx, targets, extra=None):
    o = ctx.obj
    cmd = ["snakemake", "-s", str(SNAKEFILE), "--configfile", o["configfile"]]
    if o["profile"]:
        prof = o["profile"]
        # allow shorthand name -> profiles/<name>
        if not os.path.isdir(prof) and (PROFILES / prof).is_dir():
            prof = str(PROFILES / prof)
        cmd += ["--profile", prof]
        if o["jobs"]:
            cmd += ["-j", str(o["jobs"])]
    else:
        cmd += ["--cores", str(o["cores"])]
        if o["jobs"]:
            cmd += ["-j", str(o["jobs"])]
    if o["dry_run"]:
        cmd += ["-n"]
    cmd += list(extra or [])
    cmd += list(targets)
    click.secho("$ " + " ".join(cmd), fg="cyan")
    return subprocess.run(cmd).returncode


def _run_stage(ctx, stage, subs):
    cfg = _load_config(ctx.obj["configfile"])
    subjects = _resolve_subjects(cfg, subs)
    if not subjects:
        raise click.ClickException("No samples. Run `meldcbf samples` first.")
    targets = [_target(cfg, stage, s) for s in subjects]
    sys.exit(_snakemake(ctx, targets))


# --------------------------------------------------------------------------- CLI
@click.group(context_settings={"help_option_names": ["-h", "--help"]})
@click.option("--configfile", default=str(DEFAULT_CONFIG), show_default=False,
              help="Snakemake config (default: pipeline/config/config.yaml).")
@click.option("--profile", default=None,
              help="Snakemake profile dir or name under profiles/ (e.g. slurm).")
@click.option("-j", "--jobs", default=None, type=int,
              help="Max concurrent jobs (cluster) .")
@click.option("--cores", default=1, show_default=True, type=int,
              help="Local cores (ignored when --profile is set).")
@click.option("-n", "--dry-run", is_flag=True, help="Show the plan, run nothing.")
@click.pass_context
def cli(ctx, configfile, profile, jobs, cores, dry_run):
    """MELD + CBF pipeline driver."""
    if not os.path.isfile(configfile):
        raise click.ClickException(f"Config not found: {configfile}")
    ctx.obj = dict(configfile=configfile, profile=profile, jobs=jobs,
                   cores=cores, dry_run=dry_run)


@cli.command()
@click.pass_context
def samples(ctx):
    """(Re)build the cohort sample sheet from the mapping + raw sources."""
    rc = subprocess.run([sys.executable, str(BUILD_SAMPLES),
                         "--config", ctx.obj["configfile"]]).returncode
    sys.exit(rc)


@cli.command()
@click.pass_context
def check(ctx):
    """Validate container assets, licenses, mapping and runtime."""
    cfg = _load_config(ctx.obj["configfile"])
    ok = True

    def chk(label, cond, detail=""):
        nonlocal ok
        ok = ok and cond
        mark = click.style("OK  ", fg="green") if cond else click.style("MISS", fg="red")
        click.echo(f"  [{mark}] {label}{(' — ' + detail) if detail else ''}")

    chk("apptainer runtime", bool(shutil.which(cfg.get("apptainer_bin", "apptainer"))),
        cfg.get("apptainer_bin", "apptainer"))
    chk("snakemake", bool(shutil.which("snakemake")))
    for key in ("sif", "fs_license", "meld_license", "mapping"):
        chk(key, os.path.isfile(cfg[key]), cfg[key])
    for key in ("models_src", "meld_params_src"):
        chk(key, os.path.isdir(cfg[key]), cfg[key])
    n = len(_load_samples(cfg))
    chk("samples.tsv", n > 0, f"{n} sample(s)" if n else "run `meldcbf samples`")
    chk("sbatch (SLURM)", bool(shutil.which("sbatch")), "optional")
    if not ok:
        raise click.ClickException("check failed — fix the MISS items above.")
    click.secho("check passed.", fg="green")


@cli.command()
@click.argument("subjects", nargs=-1)
@click.pass_context
def prepare(ctx, subjects):
    """Stage T1w/FLAIR/CBF for SUBJECTS (default: all)."""
    _run_stage(ctx, "prepare", subjects)


@cli.command()
@click.argument("subjects", nargs=-1)
@click.pass_context
def meld(ctx, subjects):
    """Run MELD Graph for SUBJECTS (default: all). Long; use --profile slurm."""
    _run_stage(ctx, "meld", subjects)


@cli.command()
@click.argument("subjects", nargs=-1)
@click.pass_context
def register(ctx, subjects):
    """CBF -> MELD-space registration + stats for SUBJECTS (default: all)."""
    _run_stage(ctx, "register", subjects)


@cli.command()
@click.argument("subjects", nargs=-1)
@click.pass_context
def visualize(ctx, subjects):
    """Render overlay PNGs for SUBJECTS (default: all)."""
    _run_stage(ctx, "visualize", subjects)


@cli.command()
@click.argument("subjects", nargs=-1)
@click.pass_context
def run(ctx, subjects):
    """Full pipeline (through visualize) for SUBJECTS (default: all)."""
    cfg = _load_config(ctx.obj["configfile"])
    subjects = _resolve_subjects(cfg, subjects)
    if not subjects:
        raise click.ClickException("No samples. Run `meldcbf samples` first.")
    targets = [_target(cfg, "visualize", s) for s in subjects]
    sys.exit(_snakemake(ctx, targets))


@cli.command()
@click.pass_context
def aggregate(ctx):
    """Build the cohort stats table + epilepsy concordance call."""
    cfg = _load_config(ctx.obj["configfile"])
    sys.exit(_snakemake(ctx, [f"{cfg['work']}/output/cbf_cohort_stats.csv"]))


@cli.command(name="all")
@click.pass_context
def all_(ctx):
    """Run the default target (whole cohort: stats + figures)."""
    sys.exit(_snakemake(ctx, []))


@cli.command()
@click.pass_context
def status(ctx):
    """Per-subject progress (prepared / meld / registered / figures)."""
    cfg = _load_config(ctx.obj["configfile"])
    subs = _load_samples(cfg)
    if not subs:
        raise click.ClickException("No samples. Run `meldcbf samples` first.")
    cols = ("prepared", "meld", "registered", "figures")
    click.echo(f"{'subject':<12}" + "".join(f"{c:<12}" for c in cols))
    tally = {c: 0 for c in cols}
    for s in subs:
        st = {
            "prepared": os.path.isfile(_target(cfg, "prepare", s)),
            "meld": os.path.isfile(_target(cfg, "meld", s)),
            "registered": os.path.isfile(_target(cfg, "register", s)),
            "figures": os.path.isfile(_target(cfg, "visualize", s)),
        }
        for c in cols:
            tally[c] += st[c]
        row = "".join(
            (click.style(f"{'yes':<12}", fg="green") if st[c]
             else click.style(f"{'-':<12}", fg="yellow")) for c in cols)
        click.echo(f"{s:<12}" + row)
    click.echo(f"{'TOTAL':<12}" + "".join(f"{str(tally[c]) + '/' + str(len(subs)):<12}" for c in cols))


@cli.command()
@click.option("-o", "--out", default="dag.svg", show_default=True)
@click.pass_context
def dag(ctx, out):
    """Render the workflow DAG to SVG (needs graphviz `dot`)."""
    o = ctx.obj
    p1 = subprocess.run(["snakemake", "-s", str(SNAKEFILE), "--configfile",
                         o["configfile"], "--dag"], capture_output=True, text=True)
    if p1.returncode != 0:
        click.echo(p1.stderr)
        raise click.ClickException("snakemake --dag failed")
    if not shutil.which("dot"):
        Path(out).with_suffix(".dot").write_text(p1.stdout)
        click.echo(f"graphviz `dot` not found; wrote {Path(out).with_suffix('.dot')}")
        return
    subprocess.run(["dot", "-Tsvg", "-o", out], input=p1.stdout, text=True, check=True)
    click.secho(f"wrote {out}", fg="green")


@cli.command(context_settings={"ignore_unknown_options": True})
@click.argument("args", nargs=-1, type=click.UNPROCESSED)
@click.pass_context
def smk(ctx, args):
    """Passthrough: run raw snakemake with the pipeline Snakefile/config."""
    sys.exit(_snakemake(ctx, [], extra=list(args)))


def main():
    cli()


if __name__ == "__main__":
    main()
