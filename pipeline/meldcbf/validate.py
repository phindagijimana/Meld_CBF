"""Config validation for the MELD + CBF pipeline."""
from __future__ import annotations

import os
from typing import Any

REQUIRED_KEYS = (
    "project_root",
    "pipeline_dir",
    "data_dir",
    "work",
    "mapping",
    "resolution_csv",
    "samples",
    "bids_root",
    "cbf_src_root",
    "sif",
    "fs_license",
    "meld_license",
    "models_src",
    "meld_params_src",
    "apptainer_bin",
    "hypo_z",
    "asym_concordance_pct",
    "dice_concordance",
)

OPTIONAL_KEYS = (
    "fallback_session",
    "meld_fastsurfer",
    "allow_partial_aggregate",
    "nas_dest",
    "container_tag",
    "resources",
    "meld_install",
    "freesurfer_home_in",
)


def validate_config(cfg: dict[str, Any]) -> tuple[list[str], list[str]]:
    """Return (errors, warnings) for a loaded config dict."""
    errors: list[str] = []
    warnings: list[str] = []

    for key in REQUIRED_KEYS:
        if key not in cfg:
            errors.append(f"missing required key: {key}")

    for key, path in (
        ("sif", cfg.get("sif")),
        ("fs_license", cfg.get("fs_license")),
        ("meld_license", cfg.get("meld_license")),
        ("mapping", cfg.get("mapping")),
        ("resolution_csv", cfg.get("resolution_csv")),
    ):
        if path and not os.path.isfile(path):
            errors.append(f"{key} not found: {path}")

    for key, path in (
        ("bids_root", cfg.get("bids_root")),
        ("cbf_src_root", cfg.get("cbf_src_root")),
        ("models_src", cfg.get("models_src")),
        ("meld_params_src", cfg.get("meld_params_src")),
    ):
        if path and not os.path.isdir(path):
            errors.append(f"{key} not a directory: {path}")

    work = cfg.get("work")
    if work:
        if os.path.exists(work) and not os.access(work, os.W_OK):
            errors.append(f"work not writable: {work}")
        elif not os.path.exists(work):
            try:
                os.makedirs(work, exist_ok=True)
            except OSError as exc:
                errors.append(f"cannot create work dir {work}: {exc}")

    samples = cfg.get("samples")
    if samples and not os.path.isfile(samples):
        warnings.append(f"samples.tsv missing — run `meldcbf samples`: {samples}")

    for key in ("hypo_z", "asym_concordance_pct", "dice_concordance"):
        val = cfg.get(key)
        if val is not None:
            try:
                float(val)
            except (TypeError, ValueError):
                errors.append(f"{key} must be numeric, got {val!r}")

    dice = cfg.get("dice_concordance")
    if dice is not None:
        try:
            if not 0.0 <= float(dice) <= 1.0:
                warnings.append(f"dice_concordance={dice} is outside [0, 1]")
        except (TypeError, ValueError):
            pass

    return errors, warnings
