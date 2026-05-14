"""Shared helpers for the OCP audit notebooks.

Public API (re-exported for convenience):

    from notebook_helpers import bootstrap, style_table, format_age_years_days

Submodules:

- :mod:`notebook_helpers.theme`       — colour/CSS constants and Styler builder
- :mod:`notebook_helpers.formatters`  — value formatters (age, etc.)
- :mod:`notebook_helpers.env_columns` — env/friendly_name column prepending
- :mod:`notebook_helpers.grid`        — interactive ``style_table`` widget
- :mod:`notebook_helpers.bootstrap`   — ``bootstrap`` / ``reset`` session helpers
"""
from __future__ import annotations

from .bootstrap import bootstrap, reset
from .formatters import format_age_years_days
from .grid import style_table
from .summary import evaluation_summary

__all__ = [
    "bootstrap",
    "reset",
    "style_table",
    "format_age_years_days",
    "evaluation_summary",
]
