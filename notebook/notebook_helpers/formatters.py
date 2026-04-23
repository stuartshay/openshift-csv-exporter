"""Value formatters used by the notebooks when deriving display columns."""
from __future__ import annotations

import pandas as pd


def format_age_years_days(days) -> str:
    """Format a cluster age in days as ``"Ny Md"`` (e.g. ``"2y 34d"``).

    Accepts int/float/str/None. Returns an empty string for missing/invalid
    values. Negative values are treated as ``0``. ``365`` days per year
    (calendar-agnostic) matches how ``cluster_age_days`` is exported.
    """
    try:
        if days is None:
            return ""
        if isinstance(days, float) and pd.isna(days):
            return ""
        n = int(float(days))
    except (TypeError, ValueError):
        return ""
    if n < 0:
        n = 0
    years, rem = divmod(n, 365)
    if years and rem:
        return f"{years}y {rem}d"
    if years:
        return f"{years}y"
    return f"{rem}d"
