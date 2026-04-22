"""Prepend ``env`` / ``friendly_name`` columns based on ``cluster_name``."""
from __future__ import annotations

import pandas as pd

from . import _state


def prepend_env_columns(df: pd.DataFrame) -> pd.DataFrame:
    """If ``df`` has a ``cluster_name`` column, insert ``env`` and
    ``friendly_name`` as the first two columns using the map populated by
    :func:`notebook_helpers.bootstrap.bootstrap`. Returns a new DataFrame;
    the original is untouched.
    """
    if "cluster_name" not in df.columns or not _state.CLUSTER_ENV_MAP:
        return df
    env_map = _state.CLUSTER_ENV_MAP
    env_vals = df["cluster_name"].map(lambda n: env_map.get(n, (None, None))[0])
    friendly_vals = df["cluster_name"].map(lambda n: env_map.get(n, (None, None))[1])
    out = df.copy()
    # Drop any pre-existing env / friendly_name columns to avoid duplicates.
    for col in ("env", "friendly_name"):
        if col in out.columns:
            out = out.drop(columns=[col])
    out.insert(0, "friendly_name", friendly_vals)
    out.insert(0, "env", env_vals)
    # Default sort: env, then friendly_name (case-insensitive, NaNs last).
    # Stable sort preserves original row order within ties.
    out = out.sort_values(
        by=["env", "friendly_name"],
        key=lambda col: col.astype(str).str.lower(),
        kind="stable",
        na_position="last",
    ).reset_index(drop=True)
    return out
