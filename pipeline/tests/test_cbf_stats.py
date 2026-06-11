"""Tests for cbf_stats asymmetry and helper functions."""
import importlib.util
import sys
from pathlib import Path

import numpy as np
import pytest

PIPE = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("cbf_stats", PIPE / "cbf_stats.py")
cbf_stats = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cbf_stats)


def test_pct_asym_negative_when_ipsi_lower():
    assert cbf_stats.pct_asym(80, 100) == -22.22


def test_mirror_asym_index_range():
    ai = cbf_stats.mirror_asym_index(80, 100)
    assert ai == pytest.approx(-0.1111, abs=1e-4)


def test_pct_asym_scales_with_mirror_ai():
    ai = cbf_stats.mirror_asym_index(80, 100)
    pct = cbf_stats.pct_asym(80, 100)
    assert pct == pytest.approx(200 * ai, abs=0.01)


def test_homologue_left_to_right():
    assert cbf_stats.homologue(1003) == 2003
    assert cbf_stats.homologue(2003) == 1003


def test_mirror_flip_finds_contralateral_cbf():
    cbf = np.ones((10, 10, 10)) * 100.0
    cbf[:5, :, :] = 80.0
    mask = np.zeros((10, 10, 10), bool)
    mask[2:4, 4:6, 4:6] = True
    lr = cbf_stats.lr_axis(np.diag([1, 1, 1, 1]))
    mirror = np.flip(mask, axis=lr)
    ipsi = float(np.mean(cbf[mask]))
    contra = float(np.mean(cbf[mirror]))
    assert ipsi == 80.0
    assert contra == 100.0


def test_mirror_asym_index_empty_inputs():
    assert cbf_stats.mirror_asym_index(None, 100) == ""
    assert cbf_stats.mirror_asym_index(0, 0) == ""
