"""Evaluation-coverage summary badges.

Filtered grids (e.g. "clusters with degraded operators") hide the clusters
that passed, which can mislead a reader into thinking the missing clusters
weren't audited. ``evaluation_summary`` renders a small badge bar above the
grid showing the full evaluated population, the number flagged in the
filtered grid, and the clean clusters by name.
"""
from __future__ import annotations

from html import escape
from typing import Iterable

from IPython.display import HTML, display

from .theme import FONT_FAMILY, FONT_SIZE, HEADER_BG

_BADGE_BG = {
    "evaluated": "#374151",  # slate
    "flagged": HEADER_BG,    # orange (matches grid header)
    "clean": "#2E7D32",      # green
}


def _badge(label: str, count: int, kind: str) -> str:
    bg = _BADGE_BG.get(kind, "#374151")
    return (
        f'<span style="display:inline-block;padding:2px 10px;margin-right:6px;'
        f'border-radius:10px;background:{bg};color:#fff;font-weight:600;'
        f'font-size:{FONT_SIZE};font-family:{FONT_FAMILY};">'
        f"{escape(label)}: {count}</span>"
    )


def evaluation_summary(
    evaluated: Iterable[str],
    flagged: Iterable[str],
    *,
    flagged_label: str = "Flagged",
    clean_label: str = "Clean",
    show_clean_list: bool = True,
) -> None:
    """Render a small badge bar summarising evaluation coverage.

    Parameters
    ----------
    evaluated:
        Cluster names that were evaluated (the full population behind the
        filtered grid).
    flagged:
        Cluster names that appear in the filtered grid (i.e. failed the
        check). Order does not matter; deduplicated internally.
    flagged_label:
        Badge label for the filtered count (e.g. ``"Degraded"``).
    clean_label:
        Badge label for the passing count.
    show_clean_list:
        When ``True`` (default) and there are clean clusters, list their
        names beneath the badges so a reader can see exactly which clusters
        passed.
    """
    evaluated_sorted = sorted({c for c in evaluated if c})
    flagged_set = {c for c in flagged if c}
    clean = [c for c in evaluated_sorted if c not in flagged_set]

    badges = (
        _badge("Evaluated", len(evaluated_sorted), "evaluated")
        + _badge(flagged_label, len(flagged_set), "flagged")
        + _badge(clean_label, len(clean), "clean")
    )

    parts = [f'<div style="margin:4px 0 8px 0;">{badges}</div>']
    if show_clean_list and clean:
        clean_html = ", ".join(escape(c) for c in clean)
        parts.append(
            f'<div style="font-family:{FONT_FAMILY};font-size:{FONT_SIZE};'
            f'color:#374151;margin-bottom:8px;">'
            f"<b>{escape(clean_label)} ({len(clean)}):</b> {clean_html}"
            "</div>"
        )

    display(HTML("".join(parts)))
