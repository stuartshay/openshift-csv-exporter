"""
Shared styling + bootstrap helpers for the OCP audit notebooks.

Usage (in the first code cell of any notebook):

    from notebook_style import bootstrap, style_table
    session, engine = bootstrap()
    # ... run queries, then:
    style_table(df)

All notebooks in this directory share the same visual language:
    - Orange header band (#E07B39) with white bold text
    - Transparent body cells (inherits light/dark notebook theme)
    - Subtle orange hover highlight
    - Thin grey borders, compact padding
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import pandas as pd

# Populated by ``bootstrap()`` — maps cluster_name -> (env, friendly_name).
_CLUSTER_ENV_MAP: dict[str, tuple[str | None, str | None]] = {}

# --- Theme constants (shared across all notebooks) -------------------------
HEADER_BG = "#E07B39"   # warm orange from reference screenshot
HEADER_FG = "#FFFFFF"
BORDER = "1px solid #D9D9D9"
HOVER_BG = "rgba(224, 123, 57, 0.12)"
FONT_FAMILY = "Segoe UI, Arial, sans-serif"
FONT_SIZE = "13px"

_TABLE_STYLES = [
    {"selector": "thead th", "props": [
        ("background-color", HEADER_BG),
        ("color", HEADER_FG),
        ("font-weight", "600"),
        ("text-align", "left"),
        ("padding", "8px 12px"),
        ("border", BORDER),
    ]},
    {"selector": "tbody td", "props": [
        ("background-color", "transparent"),
        ("color", "inherit"),
        ("padding", "6px 12px"),
        ("border", BORDER),
    ]},
    {"selector": "tbody tr", "props": [
        ("background-color", "transparent"),
    ]},
    {"selector": "tbody tr:hover td", "props": [
        ("background-color", HOVER_BG),
    ]},
    {"selector": "table", "props": [
        ("background-color", "transparent"),
        ("border-collapse", "collapse"),
        ("font-family", FONT_FAMILY),
        ("font-size", FONT_SIZE),
    ]},
]


def _prepend_env_columns(df: pd.DataFrame) -> pd.DataFrame:
    """If ``df`` has a ``cluster_name`` column, insert ``env`` and
    ``friendly_name`` as the first two columns using the map populated by
    :func:`bootstrap`. Returns a new DataFrame; original is untouched.
    """
    if "cluster_name" not in df.columns or not _CLUSTER_ENV_MAP:
        return df
    env_vals = df["cluster_name"].map(lambda n: _CLUSTER_ENV_MAP.get(n, (None, None))[0])
    friendly_vals = df["cluster_name"].map(
        lambda n: _CLUSTER_ENV_MAP.get(n, (None, None))[1]
    )
    out = df.copy()
    # Drop any pre-existing env / friendly_name columns to avoid duplicates.
    for col in ("env", "friendly_name"):
        if col in out.columns:
            out = out.drop(columns=[col])
    out.insert(0, "friendly_name", friendly_vals)
    out.insert(0, "env", env_vals)
    return out


def _build_styler(df: pd.DataFrame, caption: str | None = None):
    """Apply the shared orange-header theme to an already-prepared DataFrame."""
    styler = df.style.hide(axis="index").set_table_styles(_TABLE_STYLES)
    if caption:
        styler = styler.set_caption(caption).set_table_styles(
            [{"selector": "caption", "props": [
                ("caption-side", "top"),
                ("text-align", "left"),
                ("font-weight", "600"),
                ("padding", "4px 0 6px 0"),
            ]}],
            overwrite=False,
        )
    return styler


def style_table(df: pd.DataFrame, caption: str | None = None):
    """Render a DataFrame as an env-filterable table.

    If the DataFrame contains a ``cluster_name`` column, ``env`` and
    ``friendly_name`` are automatically prepended as the first two columns,
    and an "Env" dropdown is shown above the grid (default: ``All``). Rows
    without a matching env are preserved when ``All`` is selected.

    Returns an ipywidgets ``VBox`` when filtering is possible, otherwise a
    plain pandas ``Styler``.
    """
    df = _prepend_env_columns(df)

    # If there is no env column to filter on, fall back to a plain styler.
    if "env" not in df.columns:
        return _build_styler(df, caption)

    try:
        import ipywidgets as widgets  # noqa: WPS433
        from IPython.display import display, clear_output  # noqa: WPS433
    except ModuleNotFoundError:
        # ipywidgets not available in current kernel — render unfiltered table.
        return _build_styler(df, caption)

    env_values = sorted(
        v for v in df["env"].dropna().unique().tolist() if str(v) != ""
    )
    options = ["All"] + env_values

    dropdown = widgets.Dropdown(
        options=options,
        value="All",
        description="Env:",
        layout=widgets.Layout(width="260px"),
        style={"description_width": "40px"},
    )
    out = widgets.Output()

    def _render(selected: str) -> None:
        filtered = df if selected == "All" else df[df["env"] == selected]
        with out:
            clear_output(wait=True)
            display(_build_styler(filtered, caption))

    def _on_change(change: dict) -> None:
        if change.get("name") == "value" and change.get("type") == "change":
            _render(change["new"])

    dropdown.observe(_on_change, names="value")
    _render("All")
    return widgets.VBox([dropdown, out])


def bootstrap(db_relpath: str = "../datastore/ocp_audit.db"):
    """Configure sys.path and OCP_AUDIT_DB, then return (session, engine).

    Must be called before any `schema.*` import. Idempotent.
    """
    notebook_dir = Path(os.path.abspath("__file__")).parent
    db_path = (notebook_dir / db_relpath).resolve()
    os.environ["OCP_AUDIT_DB"] = str(db_path)

    datastore_dir = (notebook_dir / ".." / "datastore").resolve()
    if str(datastore_dir) not in sys.path:
        sys.path.insert(0, str(datastore_dir))

    # Imported here so OCP_AUDIT_DB is set before the engine is created.
    from schema.database import SessionLocal, engine  # noqa: WPS433
    from schema.models import Cluster, ClusterEnv  # noqa: WPS433

    session = SessionLocal()

    # Build cluster_name -> (env, friendly_name) map for auto-prepend.
    _CLUSTER_ENV_MAP.clear()
    rows = (
        session.query(Cluster.cluster_name, ClusterEnv.env, ClusterEnv.friendly_name)
        .outerjoin(ClusterEnv, ClusterEnv.cluster_id == Cluster.id)
        .all()
    )
    for name, env, friendly in rows:
        _CLUSTER_ENV_MAP[name] = (env, friendly)

    pd.set_option("display.max_colwidth", 80)
    return session, engine
