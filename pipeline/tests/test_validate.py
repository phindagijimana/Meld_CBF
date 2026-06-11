"""Tests for config validation."""
from meldcbf.validate import validate_config


def test_validate_config_missing_keys():
    errors, warnings = validate_config({})
    assert any("missing required key" in e for e in errors)


def test_validate_config_numeric_thresholds():
    cfg = {k: "/tmp/x" for k in (
        "project_root", "pipeline_dir", "data_dir", "work", "mapping",
        "resolution_csv", "samples", "bids_root", "cbf_src_root",
        "sif", "fs_license", "meld_license", "models_src", "meld_params_src",
        "apptainer_bin",
    )}
    cfg.update({"hypo_z": "not-a-number", "asym_concordance_pct": -8, "dice_concordance": 0.1})
    errors, _ = validate_config(cfg)
    assert any("hypo_z" in e for e in errors)
