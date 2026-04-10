# Copyright (C) 2012 Anaconda, Inc
# SPDX-License-Identifier: BSD-3-Clause
"""Regression tests for conda-ng PhaseBar output (conda_sim_standalone.html parity)."""

from __future__ import annotations

import re
from io import StringIO

from rich.console import Console

from conda._ng.cli import ux_reporting


def _export_ux(ux: ux_reporting.NgThreePhaseTransactionUX) -> str:
    console = Console(record=True, width=100, legacy_windows=False, color_system=None)
    console.print(ux.render())
    return console.export_text()


class _Prec:
    """Minimal stand-in for PackageRecord (size only)."""

    __slots__ = ("size",)

    def __init__(self, size: int) -> None:
        self.size = size


def test_render_resolve_in_progress_step_1_no_mb_suffix():
    ux = ux_reporting.NgThreePhaseTransactionUX(Console(file=StringIO()))
    ux.reset_for_transaction()
    text = _export_ux(ux)
    assert "Step 1/3" in text
    assert "Resolving dependencies..." in text
    assert "Downloading packages" not in text
    assert "Installing packages" not in text
    # mkPhases resolve suffix is empty — no MB line between label and bar row
    assert re.search(r"\d+\.\d+ / \d+\.\d+ MB", text) is None
    assert "%" in text
    assert "|" in text


def test_render_resolve_finished_still_step_1_pct_at_resolve_cap():
    ux = ux_reporting.NgThreePhaseTransactionUX(Console(file=StringIO()))
    ux.reset_for_transaction()
    ux.set_solve_finished()
    text = _export_ux(ux)
    assert "Step 1/3" in text
    assert "Resolving dependencies..." in text
    assert "33%" in text


def test_render_download_step_2_mb_suffix():
    ux = ux_reporting.NgThreePhaseTransactionUX(Console(file=StringIO()))
    ux.reset_for_transaction()
    ux.set_solve_finished()
    ux.begin_install([_Prec(2 * 1024 * 1024), _Prec(2 * 1024 * 1024)])
    with ux._lock:
        ux.bytes_done = 2 * 1024 * 1024
    text = _export_ux(ux)
    assert "Step 2/3" in text
    assert "Downloading packages..." in text
    assert "2.0 / 4.0 MB" in text


def test_render_install_step_3_package_suffix():
    ux = ux_reporting.NgThreePhaseTransactionUX(Console(file=StringIO()))
    ux.reset_for_transaction()
    ux.set_solve_finished()
    ux.begin_install([_Prec(100), _Prec(100), _Prec(100)])
    with ux._lock:
        ux._install_started = True
        ux.bytes_done = ux.bytes_total
        ux.links_done = 1
    text = _export_ux(ux)
    assert "Step 3/3" in text
    assert "Installing packages..." in text
    assert "1 / 3 packages" in text


def test_scales_bar_markup_matches_html_algorithm():
    # HTML: filled = round((pct/100)*barW), partial 1 if 0 < filled < barW
    w = 28
    for pct, want_solid, want_partial in (
        (0, 0, 0),
        (4, 0, 1),  # filled=1 → partial only
        (50, 13, 1),
        (100, 28, 0),
    ):
        s = ux_reporting.scales_bar_markup(pct, w)
        solid = s.count("▓")
        partial = s.count("▒")
        empty = s.count("░")
        assert solid == want_solid, (pct, s)
        assert partial == want_partial, (pct, s)
        assert solid + partial + empty == w


def test_pkg_table_columns_fixed_width():
    class R:
        __slots__ = ("name", "version", "channel")

        def __init__(self, n: str, v: str, c: str) -> None:
            self.name = type("N", (), {"normalized": n})()
            self.version = v
            self.channel = c

    def ch(_channel) -> str:
        return "conda-forge"

    lines = ux_reporting._pkg_grid_lines(
        [R("python", "3.14.4", ""), R("numpy", "2.4.3", "")],
        ch,
        dep_style=False,
    )
    # Same column starts for short and long names (padded/truncated inside markup).
    i0 = lines[0].index("python")
    i1 = lines[1].index("numpy")
    assert i0 == i1
    assert "3.14.4" in lines[0] and "2.4.3" in lines[1]


def test_global_pct_in_install_band():
    ux = ux_reporting.NgThreePhaseTransactionUX(Console(file=StringIO()))
    ux.reset_for_transaction()
    ux.set_solve_finished()
    ux.begin_install([_Prec(1024)])
    with ux._lock:
        ux.bytes_done = ux.bytes_total
        ux.validate_done = ux.n_pkgs
        ux._install_started = True
        ux.links_done = 0
    with ux._lock:
        p = ux._global_pct_unlocked()
    assert p == ux.W_RESOLVE + ux.W_DOWNLOAD
    with ux._lock:
        ux.links_done = ux.links_total
    with ux._lock:
        p_done = ux._global_pct_unlocked()
    assert p_done == 100
