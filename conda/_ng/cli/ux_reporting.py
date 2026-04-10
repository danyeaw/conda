# Copyright (C) 2012 Anaconda, Inc
# SPDX-License-Identifier: BSD-3-Clause
"""Rich output patterns aligned with the conda-ng CLI design system (create/install UX)."""

from __future__ import annotations

import math
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from itertools import count
from pathlib import Path
from typing import TYPE_CHECKING, TypeVar

from rich.console import Group
from rich.live import Live
from rich.panel import Panel
from rich.text import Text

if TYPE_CHECKING:
    from collections.abc import Callable, Iterable, Sequence
    from concurrent.futures import Future

    from rattler import MatchSpec, PackageRecord
    from rich.console import Console

_T = TypeVar("_T")


def scales_bar_markup(
    pct: int,
    width: int = 28,
    *,
    fill: str = "#D4C48A",
    empty: str = "#4F5C84",
) -> str:
    pct = max(0, min(100, int(pct)))
    filled = round((pct / 100) * width)
    partial = 1 if 0 < filled < width else 0
    solid = max(0, filled - partial)
    rest = width - solid - partial
    bar = f"[{fill}]{'▓' * solid}[/]"
    if partial:
        bar += f"[{fill}]▒[/]"
    bar += f"[dim {empty}]{'░' * rest}[/]"
    return bar


def _record_size_bytes(record: object) -> int | None:
    for attr in ("size", "package_size", "noarch_size"):
        v = getattr(record, attr, None)
        if v is not None:
            try:
                return int(v)
            except (TypeError, ValueError):
                continue
    return None


def total_download_bytes(records: Iterable[PackageRecord]) -> int:
    n = 0
    total = 0
    for rec in records:
        sz = _record_size_bytes(rec)
        if sz is not None:
            total += sz
            n += 1
    return total if n else 0


class NgThreePhaseTransactionUX:
    """Terminal PhaseBar aligned with ``conda_sim_standalone.html`` (PhaseBar).

    Same structure as the HTML: dim ``Step k/3``, primary-colored label + ``...``,
    optional dim suffix, then scales bar with a single global ``pct``, ``%``, ``|``,
    elapsed. ``conda.ng install`` uses one ``Live`` for solve + install (paused around
    plan output and ``confirm_yn``) so the PhaseBar is continuous; ``transient=True``
    clears when the transaction Live stops at the end.
    """

    W_RESOLVE = 33
    W_DOWNLOAD = 41
    W_INSTALL = 26
    N_PHASES = 3

    def __init__(self, console: Console, *, verbose_style: bool = False) -> None:
        self.console = console
        self.verbose_style = verbose_style
        self.t0 = time.perf_counter()
        self.phase = 0
        self.bytes_done = 0
        self.bytes_total = 1
        self.links_done = 0
        self.links_total = 1
        self.validate_done = 0
        self.n_pkgs = 1
        self._install_started = False
        self._solve_finished = False
        self._live: Live | None = None
        self._lock = threading.RLock()

    def reset_for_transaction(self) -> None:
        """Reset phase/progress and start the wall clock (one run: solve → install)."""
        with self._lock:
            self.phase = 0
            self.t0 = time.perf_counter()
            self._solve_finished = False
            self.bytes_done = 0
            self.bytes_total = 1
            self.links_done = 0
            self.links_total = 1
            self.validate_done = 0
            self.n_pkgs = 1
            self._install_started = False

    def _bar_width(self) -> int:
        return 24 if self.verbose_style else 28

    def _fill_empty(self) -> tuple[str, str]:
        if self.verbose_style:
            return "#f9e2af", "#4F5C84"
        return "#D4C48A", "#4F5C84"

    def _label_style(self) -> str:
        return "#f9e2af" if self.verbose_style else "#D4C48A"

    def _ui_phase_unlocked(self) -> int:
        """0 resolve, 1 downloading, 2 installing.

        Show Step 3 (installing) as soon as linking starts (``on_link_start``), even if
        byte totals have not caught up yet — otherwise the UI can stay on Step 2 until
        Live exits and the user never sees Step 3.

        Bar fill is still driven by bytes until ``bytes_done >= bytes_total`` so the
        download slice keeps moving when Rattler overlaps link and download callbacks.
        """
        if self.phase == 0:
            return 0
        if self._install_started or self.links_done > 0:
            return 2
        return 1

    def _global_pct_unlocked(self) -> int:
        ui = self._ui_phase_unlocked()
        if ui == 0:
            if self._solve_finished:
                return self.W_RESOLVE
            # HTML passes overall ``progress`` into PhaseBar; it rises during resolve too.
            # We have no solver %; use a soft time ramp capped below the resolve slice.
            elapsed = time.perf_counter() - self.t0
            r = 1.0 - math.exp(-elapsed / 12.0)
            return max(0, min(self.W_RESOLVE - 1, int(self.W_RESOLVE * r)))
        # Download band: validate/cache + bytes. Also used for ui "installing" while
        # bytes are still in flight so the bar does not freeze.
        n = max(self.n_pkgs, 1)
        b = min(self.bytes_done / max(self.bytes_total, 1), 1.0)
        v_part = 0.35 * min(self.validate_done / n, 1.0)
        b_part = 0.65 * b
        if self.validate_done >= n:
            dl_frac = min(1.0, 0.35 + b_part)
        else:
            dl_frac = min(1.0, v_part + b_part)
        if ui == 1 or self.bytes_done < self.bytes_total:
            return self.W_RESOLVE + int(self.W_DOWNLOAD * dl_frac)
        frac = min(1.0, self.links_done / max(self.links_total, 1))
        return min(
            100,
            self.W_RESOLVE + self.W_DOWNLOAD + int(self.W_INSTALL * frac),
        )

    def set_solve_finished(self) -> None:
        """Solver returned; keep ``phase == 0`` until :meth:`begin_install` (no bogus download UI)."""
        with self._lock:
            self._solve_finished = True

    def begin_install(self, link_records: Sequence[PackageRecord]) -> None:
        bt = total_download_bytes(link_records)
        with self._lock:
            if self.phase == 0:
                self.phase = 1
            self._solve_finished = False
            self.bytes_total = max(bt, 1)
            self.links_total = max(len(link_records), 1)
            self.n_pkgs = max(len(link_records), 1)
            self.bytes_done = 0
            self.links_done = 0
            self.validate_done = 0
            self._install_started = False

    def finalize_install_progress(self) -> None:
        with self._lock:
            self.bytes_done = self.bytes_total
            self.links_done = self.links_total
            self._install_started = True

    def attach_live(self, live: Live | None) -> None:
        """Bind the Rich Live used for polling (used for one continuous transaction in install)."""
        self._live = live

    def wait_future_with_live(self, live: Live, fut: Future[_T]) -> _T:
        while not fut.done():
            live.update(self.render(), refresh=True)
            time.sleep(0.05)
        return fut.result()

    def render(self) -> Group:
        with self._lock:
            ui_phase = self._ui_phase_unlocked()
            pct = self._global_pct_unlocked()
            vs = self.verbose_style
            t0 = self.t0
            nps = self.N_PHASES
            if ui_phase == 0:
                label, sfx = "Resolving dependencies", ""
            elif ui_phase == 1:
                label = "Downloading packages"
                mb_t = self.bytes_total / (1024 * 1024)
                mb_d = self.bytes_done / (1024 * 1024)
                sfx = f"{mb_d:.1f} / {mb_t:.1f} MB"
            else:
                label = "Installing packages"
                sfx = f"{self.links_done} / {self.links_total} packages"
            fill, empty = self._fill_empty()
            bw = self._bar_width()
            ls = self._label_style()
        elapsed = time.perf_counter() - t0
        bar = scales_bar_markup(pct, bw, fill=fill, empty=empty)
        lines = [
            Text.from_markup(f"[dim #A89E94]Step {ui_phase + 1}/{nps}[/]"),
            Text.from_markup(f"[{ls}]{label}...[/]"),
        ]
        if sfx:
            lines.append(Text.from_markup(f"[dim #A89E94]{sfx}[/]"))
        # HTML PhaseBar: flex gap ~10px between bar, %, |, s (T.textMuted for % | s).
        gap = " " * 3
        if vs:
            tail = f"{bar}{gap}[dim #f9e2af]{pct}%[/]{gap}[dim #f9e2af]|[/]{gap}[dim #f9e2af]{elapsed:.1f}s[/]"
        else:
            tail = f"{bar}{gap}[dim]{pct}%[/]{gap}[dim]|[/]{gap}[dim]{elapsed:.1f}s[/]"
        lines.append(Text.from_markup(tail))
        return Group(*lines)

    def run_solve_with_live(self, solve_fn: Callable[[], _T]) -> _T:
        """Run blocking solve on a worker thread so the main thread can refresh Live."""
        self.reset_for_transaction()

        def work() -> _T:
            return solve_fn()

        with Live(
            self.render(),
            console=self.console,
            refresh_per_second=12,
            transient=True,
        ) as live:
            self._live = live
            with ThreadPoolExecutor(max_workers=1) as pool:
                fut = pool.submit(work)
                result = self.wait_future_with_live(live, fut)
            self.set_solve_finished()
            live.update(self.render(), refresh=True)
        self._live = None
        return result

    def run_install_with_live(
        self,
        link_records: Sequence[PackageRecord],
        run_install: Callable[[object], None],
    ) -> None:
        """Run install on a worker thread; main thread polls Live (same fix as solve).

        Rattler invokes reporter callbacks while ``asyncio.run`` blocks the thread that
        runs the install. Doing that on the main thread prevented Rich from redrawing
        between callbacks, so downloads looked instantaneous even on a cold cache.
        """
        self.begin_install(link_records)
        reporter = NgUnifiedPhaseReporter(self)

        def work() -> None:
            run_install(reporter)

        with Live(
            self.render(),
            console=self.console,
            refresh_per_second=12,
            transient=True,
        ) as live:
            self._live = live
            with ThreadPoolExecutor(max_workers=1) as pool:
                fut = pool.submit(work)
                self.wait_future_with_live(live, fut)
            self.finalize_install_progress()
            live.update(self.render(), refresh=True)
        self._live = None


class NgUnifiedPhaseReporter:
    """Feeds :class:`NgThreePhaseTransactionUX` from rattler :class:`InstallerReporter` callbacks."""

    def __init__(self, ux: NgThreePhaseTransactionUX) -> None:
        self._ux = ux
        self._cache_tok = count(0)
        self._dl_tok = count(0)
        self._pkg_by_cache: dict[int, str] = {}
        self._pkg_by_download_idx: dict[int, str] = {}
        self._bytes_by_dl: dict[int, int] = {}
        with ux._lock:
            self._byte_floor = ux.bytes_total

    def on_transaction_start(self, total_operations: int) -> None:
        return None

    def on_transaction_operation_start(self, operation: int) -> None:
        return None

    def on_populate_cache_start(self, operation: int, package_name: str) -> int:
        tok = next(self._cache_tok)
        self._pkg_by_cache[tok] = package_name
        return tok

    def on_validate_start(self, cache_entry: int) -> int:
        return 0

    def on_validate_complete(self, validate_idx: int) -> None:
        with self._ux._lock:
            self._ux.validate_done = min(self._ux.validate_done + 1, self._ux.n_pkgs)

    def on_download_start(self, cache_entry: int) -> int:
        did = next(self._dl_tok)
        self._pkg_by_download_idx[did] = self._pkg_by_cache.get(cache_entry, "")
        return did

    def on_download_progress(
        self, download_idx: int, progress: int, total: int | None
    ) -> None:
        self._bytes_by_dl[download_idx] = progress
        done = sum(self._bytes_by_dl.values())
        with self._ux._lock:
            cap = self._byte_floor
            if done > cap:
                cap = done
                self._byte_floor = cap
                self._ux.bytes_total = cap
            self._ux.bytes_done = min(done, cap)

    def on_download_completed(self, download_idx: int) -> None:
        return None

    def on_populate_cache_complete(self, cache_entry: int) -> None:
        return None

    def on_unlink_start(self, operation: int, package_name: str) -> int:
        return 0

    def on_unlink_complete(self, index: int) -> None:
        return None

    def on_link_start(self, operation: int, package_name: str) -> int:
        # Cache hits often emit no download byte callbacks; snap bytes so the download
        # band can complete. Do not set phase=2 here — _ui_phase stays on Downloading
        # until bytes_done catches bytes_total so the bar keeps tracking real progress.
        with self._ux._lock:
            self._ux._install_started = True
            self._ux.validate_done = max(self._ux.validate_done, self._ux.n_pkgs)
            bt = max(self._ux.bytes_total, 1)
            ratio = self._ux.bytes_done / bt
            if self._ux.bytes_done == 0 or ratio < 0.02:
                self._ux.bytes_done = self._ux.bytes_total
        return 0

    def on_link_complete(self, index: int) -> None:
        with self._ux._lock:
            self._ux.links_done = min(self._ux.links_done + 1, self._ux.links_total)

    def on_transaction_operation_complete(self, operation: int) -> None:
        return None

    def on_transaction_complete(self) -> None:
        with self._ux._lock:
            self._ux.bytes_done = self._ux.bytes_total
            self._ux.links_done = self._ux.links_total
            self._ux._install_started = True

    def on_post_link_start(self, package_name: str, script_path: str) -> int:
        return 0

    def on_post_link_complete(self, index: int, success: bool) -> None:
        return None

    def on_pre_unlink_start(self, package_name: str, script_path: str) -> int:
        return 0

    def on_pre_unlink_complete(self, index: int, success: bool) -> None:
        return None


def total_download_mb(records: Iterable[PackageRecord]) -> float | None:
    total = 0
    n = 0
    for rec in records:
        sz = _record_size_bytes(rec)
        if sz is not None:
            total += sz
            n += 1
    if n == 0:
        return None
    return total / (1024 * 1024)


def _channel_label(record: PackageRecord, channel_name_or_url) -> str:
    return channel_name_or_url(record.channel)


def _primary_channel_label(channels: Sequence[str | object]) -> str:
    if not channels:
        return "—"
    ch0 = channels[0]
    return str(ch0).split("/")[-1] if ch0 else "—"


def create_env_yml_line(prefix: str | Path, *, env_title: str) -> str:
    """Match conda_sim ``~/envs/<name>/environment.yml`` for named creates."""
    return f"~/envs/{env_title}/environment.yml"


def display_prefix(prefix: str | Path) -> str:
    p = Path(prefix).expanduser()
    try:
        home = Path.home()
        if p.is_relative_to(home):
            rel = p.relative_to(home).as_posix()
            return "~/" + rel if rel != "." else "~/"
    except (ValueError, AttributeError):
        pass
    return p.as_posix()


def requested_vs_dependencies(
    link_precs: Sequence[PackageRecord],
    requested_specs: Iterable[MatchSpec],
) -> tuple[list[PackageRecord], list[PackageRecord]]:
    req_names = {s.name.normalized for s in requested_specs}
    requested: list[PackageRecord] = []
    deps: list[PackageRecord] = []
    seen: set[str] = set()
    for rec in link_precs:
        key = rec.name.normalized
        if key in seen:
            continue
        seen.add(key)
        if key in req_names:
            requested.append(rec)
        else:
            deps.append(rec)
    return requested, deps


def print_phase_footer(
    console: Console,
    *,
    step: int,
    n_steps: int,
    label: str,
    suffix: str | None,
    pct: int,
    elapsed_s: float,
) -> None:
    lines = [
        Text.from_markup(f"[dim #A89E94]Step {step}/{n_steps}[/]"),
        Text.from_markup(f"[#D4C48A]{label}[/]"),
    ]
    if suffix:
        lines.append(Text.from_markup(f"[dim #A89E94]{suffix}[/]"))
    bar_line = Text.from_markup(
        f"{scales_bar_markup(pct)}  [dim]{pct}%[/]  [dim]|[/]  [dim]{elapsed_s:.1f}s[/]"
    )
    lines.append(bar_line)
    for line in lines:
        console.print(line)
    console.print()


def print_dry_run_banner(console: Console) -> None:
    body = Text.from_markup("[dim #A89E94]No changes will be made[/]")
    title = Text.from_markup("[bold #89b4fa]◎ Dry run[/]")
    console.print(
        Panel(
            body,
            title=title,
            border_style="rgb(137,180,250)",
            padding=(0, 1),
            expand=False,
        )
    )
    console.print()


def print_dry_run_would_create(
    console: Console, *, prefix: str | Path, write_env_yml_hint: bool
) -> None:
    p = display_prefix(prefix)
    console.print(Text.from_markup(f"[dim]  Would create   {p}[/]"))
    if write_env_yml_hint:
        console.print(Text.from_markup("[dim]  Would write    ./environment.yml[/]"))
    console.print()


def print_dry_run_done(console: Console) -> None:
    body = Text.from_markup("[dim #A89E94]Run without --dry-run to apply.[/]")
    title = Text.from_markup("[bold #89b4fa]◎ No changes made[/]")
    console.print(
        Panel(
            body,
            title=title,
            border_style="rgb(137,180,250)",
            padding=(0, 1),
            expand=False,
        )
    )


def print_verbose_working_header(console: Console) -> None:
    """Yellow 'Working' panel from the HTML prototype (--verbose transaction)."""
    title = Text.from_markup("[bold #f9e2af]⚠ Working[/]")
    body = Group(
        Text.from_markup("[dim #f9e2af]✓ Resolving dependencies[/]"),
        Text.from_markup("[#f9e2af]Downloading packages...[/]"),
        Text.from_markup("[#f9e2af]Installing packages...[/]"),
    )
    console.print(
        Panel(
            body,
            title=title,
            border_style="rgb(249,226,175)",
            padding=(0, 1),
            expand=False,
        )
    )
    console.print()


def print_quiet_done(
    console: Console,
    *,
    env_label: str,
    n_packages: int,
    mb: float | None,
    activate_cmd: str,
) -> None:
    if mb is not None:
        summary = f"{env_label} · {n_packages} packages · {mb:.1f} MB"
    else:
        summary = f"{env_label} · {n_packages} packages"
    body = Text.assemble(
        Text(summary + "\n", style="dim #A89E94"),
        Text("→ ", style="dim #A89E94"),
        Text(activate_cmd, style="#89b4fa"),
    )
    title = Text.from_markup("[bold #a6e3a1]✓ Done[/]")
    console.print(
        Panel(
            body,
            title=title,
            border_style="rgb(166,227,161)",
            padding=(0, 1),
            expand=False,
        )
    )


# Monospace package table (aligned with conda_sim_standalone.html COL3-style grid).
_PKG_ROW_PREFIX = "  "  # before "+"
_PKG_COL_NAME_W = 18
_PKG_COL_VER_W = 14


def _pkg_cell(text: str, width: int) -> str:
    t = str(text)
    if len(t) > width:
        return t[: max(0, width - 1)] + "…"
    return t.ljust(width)


def pkg_table_header_markup() -> str:
    """Dim header row; leading spaces line up with ``  +  `` on data rows."""
    lead = (
        _PKG_ROW_PREFIX + " " * 3
    )  # same visual offset as ``  +  `` (5 cells to Package)
    return (
        f"[dim #A89E94]{lead}"
        f"{_pkg_cell('Package', _PKG_COL_NAME_W)}"
        f"{_pkg_cell('Version', _PKG_COL_VER_W)}"
        f"Channel[/]"
    )


def _pkg_grid_lines(
    records: Sequence[PackageRecord],
    channel_name_or_url,
    *,
    dep_style: bool = False,
) -> list[str]:
    lines = []
    name_style = "dim #A89E94" if dep_style else "#a6e3a1"
    ver_style = "dim #A89E94" if dep_style else "#a6e3a1"
    for rec in records:
        ch = _channel_label(rec, channel_name_or_url)
        nm = _pkg_cell(rec.name.normalized, _PKG_COL_NAME_W)
        vr = _pkg_cell(rec.version, _PKG_COL_VER_W)
        lines.append(
            f"{_PKG_ROW_PREFIX}[{name_style}]+[/]  [{name_style}]{nm}[/]"
            f"[{ver_style}]{vr}[/] [dim #A89E94]{ch}[/]"
        )
    return lines


def _dependency_summary_markup(n_dep: int) -> str:
    """Single summary row: ``+`` column lines up with package rows."""
    msg = f"{n_dep} dependency packages"
    return f"{_PKG_ROW_PREFIX}[#a6e3a1]+[/]  [#a6e3a1]{msg}[/]"


def _print_success_summary_panel(
    console: Console, *, title_markup: str, body_parts: list
) -> None:
    body = Group(*body_parts)
    console.print(
        Panel(
            body,
            title=Text.from_markup(title_markup),
            border_style="rgb(166,227,161)",
            padding=(0, 1),
            expand=False,
        )
    )


def print_create_success_card(
    console: Console,
    *,
    env_title: str,
    prefix: str | Path,
    channels: Sequence[str | object],
    platform: str,
    requested: Sequence[PackageRecord],
    dependencies: Sequence[PackageRecord],
    elapsed_s: float,
    channel_name_or_url,
    activate_cmd: str,
    verbose: bool = False,
) -> None:
    title_markup = (
        f"[bold #a6e3a1]✓ Created Environment '{env_title}'[/] "
        f"[dim #b8d0b8]({elapsed_s:.1f}s)[/]"
    )
    n_dep = len(dependencies)
    total_pkgs = len(requested) + n_dep
    env_yml_disp = create_env_yml_line(prefix, env_title=env_title)
    body_parts: list = [
        Text.from_markup(f"[dim #A89E94]{env_yml_disp}[/]"),
        Text.from_markup(
            f"[dim #A89E94]Channel: {_primary_channel_label(channels)}[/]"
        ),
        Text.from_markup(f"[dim #A89E94]Platform: {platform}[/]"),
        Text(""),
    ]
    col_header = pkg_table_header_markup()
    if verbose and (requested or dependencies):
        if requested:
            body_parts.append(Text.from_markup("[bold #a6e3a1]Requested[/]"))
            body_parts.append(Text.from_markup(col_header))
            for line in _pkg_grid_lines(
                requested, channel_name_or_url, dep_style=False
            ):
                body_parts.append(Text.from_markup(line))
        if dependencies:
            body_parts.append(Text(""))
            body_parts.append(
                Text.from_markup(f"[bold #a6e3a1]Dependencies[/] · {n_dep}")
            )
            body_parts.append(Text.from_markup(col_header))
            for line in _pkg_grid_lines(
                dependencies, channel_name_or_url, dep_style=True
            ):
                body_parts.append(Text.from_markup(line))
    else:
        body_parts.append(
            Text.from_markup(f"[bold #a6e3a1]Installed[/] [#a6e3a1]· {total_pkgs}[/]")
        )
        body_parts.append(Text.from_markup(col_header))
        for line in _pkg_grid_lines(requested, channel_name_or_url, dep_style=False):
            body_parts.append(Text.from_markup(line))
        if n_dep:
            body_parts.append(Text.from_markup(_dependency_summary_markup(n_dep)))
    body_parts.append(Text(""))
    body_parts.append(Text.from_markup("[dim #A89E94]→ Suggested next step[/]"))
    # HTML: padded row; only the activate command uses accent blue.
    body_parts.append(Text.from_markup(f"    [#89b4fa]{activate_cmd}[/]"))

    _print_success_summary_panel(
        console, title_markup=title_markup, body_parts=body_parts
    )


def print_install_success_card(
    console: Console,
    *,
    requested: Sequence[PackageRecord],
    dependencies: Sequence[PackageRecord],
    elapsed_s: float,
    channel_name_or_url,
    verbose: bool = False,
) -> None:
    n_req = len(requested)
    if n_req == 1:
        label = f"Installed {requested[0].name.normalized}"
    elif n_req == 0:
        label = "Installed packages"
    else:
        label = f"Installed {n_req} Packages"
    title_markup = f"[bold #a6e3a1]✓ {label}[/] [dim #b8d0b8]({elapsed_s:.1f}s)[/]"
    n_dep = len(dependencies)
    col_header = pkg_table_header_markup()
    body_parts: list = []
    if verbose and (requested or dependencies):
        if requested:
            body_parts.append(Text.from_markup("[bold #a6e3a1]Install requested[/]"))
            body_parts.append(Text.from_markup(col_header))
            for line in _pkg_grid_lines(
                requested, channel_name_or_url, dep_style=False
            ):
                body_parts.append(Text.from_markup(line))
        if dependencies:
            body_parts.append(Text(""))
            body_parts.append(
                Text.from_markup(f"[bold #a6e3a1]Dependencies[/] · {n_dep}")
            )
            body_parts.append(Text.from_markup(col_header))
            for line in _pkg_grid_lines(
                dependencies, channel_name_or_url, dep_style=True
            ):
                body_parts.append(Text.from_markup(line))
    else:
        body_parts.append(
            Text.from_markup(f"[bold #a6e3a1]Installed[/] [#a6e3a1]· {n_req}[/]")
        )
        body_parts.append(Text.from_markup(col_header))
        for line in _pkg_grid_lines(requested, channel_name_or_url, dep_style=False):
            body_parts.append(Text.from_markup(line))
        if n_dep:
            body_parts.append(Text.from_markup(_dependency_summary_markup(n_dep)))

    _print_success_summary_panel(
        console, title_markup=title_markup, body_parts=body_parts
    )
