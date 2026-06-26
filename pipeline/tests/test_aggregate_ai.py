"""Tests for cohort AI flag logic (mirrors aggregate_stats.py)."""
import pandas as pd


def ai_flags(r, asym_thr=-8.0):
    roi_asym = pd.to_numeric(r.get("roi_asym_pct"), errors="coerce")
    mirror_ai = pd.to_numeric(r.get("cluster_mirror_ai"), errors="coerce")
    roi_hypo = pd.notna(roi_asym) and roi_asym <= asym_thr
    mirror_hypo = pd.notna(mirror_ai) and mirror_ai < 0
    return bool(roi_hypo or mirror_hypo)


def test_roi_hypoperfused_at_threshold():
    assert ai_flags({"roi_asym_pct": -8.0, "cluster_mirror_ai": 0.1}) is True
    assert ai_flags({"roi_asym_pct": -7.9, "cluster_mirror_ai": 0.1}) is False


def test_mirror_hypoperfused_negative_ai():
    assert ai_flags({"roi_asym_pct": 0.0, "cluster_mirror_ai": -0.05}) is True
    assert ai_flags({"roi_asym_pct": 0.0, "cluster_mirror_ai": 0.0}) is False


def test_either_flag_triggers():
    assert ai_flags({"roi_asym_pct": -10.0, "cluster_mirror_ai": 0.2}) is True
    assert ai_flags({"roi_asym_pct": 5.0, "cluster_mirror_ai": -0.1}) is True


def test_missing_values_no_flag():
    assert ai_flags({"roi_asym_pct": "", "cluster_mirror_ai": ""}) is False
