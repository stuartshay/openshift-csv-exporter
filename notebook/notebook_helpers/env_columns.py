"""Prepend ``env`` / ``friendly_name`` columns based on ``cluster_server``."""

from __future__ import annotations

import pandas as pd

from . import _state


def prepend_env_columns(df: pd.DataFrame) -> pd.DataFrame:
    """If ``df`` has a ``cluster_server`` column, insert ``env`` and
    ``friendly_name`` as the first two columns using the map populated by
    :func:`notebook_helpers.bootstrap.bootstrap`. Returns a new DataFrame;
    the original is untouched.

    Keyed by ``cluster_server`` (the API URL) because ``cluster_name`` may
    include the kube context suffix and is not a stable identifier.

    When ``df`` only has ``cluster_name`` (no ``cluster_server``) — typical
    for queries that don't select the API URL — ``cluster_server`` is
    derived via :data:`_state.CLUSTER_NAME_MAP` so env / friendly_name can
    still be prepended and the Cluster filter on the grid still works. The
    derived ``cluster_server`` column is attached to the returned frame
    (as the third column, after env / friendly_name) so downstream
    filtering by ``cluster_server`` keeps working; callers that don't want
    it on screen are responsible for hiding it (the grid keeps it but the
    visible column set otherwise matches what the caller asked for).
    """
    if not _state.CLUSTER_ENV_MAP:
        return df

    derived_server = False
    if "cluster_server" not in df.columns:
        if "cluster_name" not in df.columns or not _state.CLUSTER_NAME_MAP:
            return df
        name_map = _state.CLUSTER_NAME_MAP
        df = df.copy()
        df["cluster_server"] = df["cluster_name"].map(lambda n: name_map.get(n) if isinstance(n, str) else None)
        derived_server = True

    env_map = _state.CLUSTER_ENV_MAP
    env_vals = df["cluster_server"].map(lambda s: env_map.get(s, (None, None))[0])
    friendly_vals = df["cluster_server"].map(lambda s: env_map.get(s, (None, None))[1])
    out = df if derived_server else df.copy()
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
    if derived_server:
        # Mark the column so the grid knows to filter on it but not display it.
        out.attrs["_derived_cluster_server"] = True
    return out
