"""Backwards-compatible facade for the :mod:`notebook_helpers` package.

The implementation was split into ``notebook_helpers/`` for clarity:

- :mod:`notebook_helpers.theme`       — orange-header CSS + Styler builder
- :mod:`notebook_helpers.formatters`  — value formatters (e.g. age in y/d)
- :mod:`notebook_helpers.env_columns` — ``env`` / ``friendly_name`` prepender
- :mod:`notebook_helpers.grid`        — interactive ``style_table`` widget
- :mod:`notebook_helpers.bootstrap`   — ``bootstrap`` / ``reset`` helpers

Existing notebooks that do ``from notebook_style import bootstrap, style_table``
continue to work unchanged. New code should import directly from
``notebook_helpers``.
"""
from __future__ import annotations

from notebook_helpers import (
    bootstrap,
    format_age_years_days,
    reset,
    style_table,
)

__all__ = [
    "bootstrap",
    "reset",
    "style_table",
    "format_age_years_days",
]
