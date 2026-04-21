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
import re
import sys
from datetime import datetime
from pathlib import Path

import pandas as pd

# Populated by ``bootstrap()`` — maps cluster_name -> (env, friendly_name).
_CLUSTER_ENV_MAP: dict[str, tuple[str | None, str | None]] = {}

# Populated by ``bootstrap()`` — absolute path to the repo ``output/`` dir.
_OUTPUT_DIR: Path | None = None

# Tracks the most recent SQLAlchemy session returned by ``bootstrap()`` so it
# can be closed cleanly when the same kernel is reused across notebooks.
_LAST_SESSION = None


def reset() -> None:
    """Close all open ipywidgets and the previous SQLAlchemy session.

    Useful when sharing a single Jupyter kernel across multiple notebooks —
    call :func:`reset` (or simply re-run the bootstrap cell, which calls it
    automatically) to guarantee a clean widget registry and drop any stale
    session state. Safe to call when nothing has been initialised yet.
    """
    global _LAST_SESSION
    if _LAST_SESSION is not None:
        try:
            _LAST_SESSION.close()
        except Exception:
            pass
        _LAST_SESSION = None
    _CLUSTER_ENV_MAP.clear()
    try:
        import ipywidgets as widgets  # noqa: WPS433

        widgets.Widget.close_all()
    except Exception:
        pass

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
    # Default sort: env, then friendly_name (case-insensitive, NaNs last).
    # Stable sort preserves original row order within ties.
    out = out.sort_values(
        by=["env", "friendly_name"],
        key=lambda col: col.astype(str).str.lower(),
        kind="stable",
        na_position="last",
    ).reset_index(drop=True)
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
    """Render a DataFrame as an env-filterable, paginated table.

    If the DataFrame contains a ``cluster_name`` column, ``env`` and
    ``friendly_name`` are automatically prepended as the first two columns,
    and two dropdowns are shown above the grid (both default to ``All``):

    - **Env:** filters rows by environment (prod/stage/dev/…)
    - **Cluster:** filters rows by a specific cluster_name; its options are
      narrowed to the clusters available in the currently selected env.

    A **Rows:** dropdown (10 / 25 / 50 / 100 / All, default 25) and Prev /
    Next buttons are always shown when ipywidgets is available so large
    result sets stay readable.

    Returns an ipywidgets ``VBox`` when widgets are available, otherwise a
    plain pandas ``Styler``.
    """
    df = _prepend_env_columns(df)

    try:
        import ipywidgets as widgets  # noqa: WPS433
        from IPython.display import display, clear_output  # noqa: WPS433
    except ModuleNotFoundError:
        # ipywidgets not available in current kernel — render unfiltered table.
        return _build_styler(df, caption)

    has_env_col = "env" in df.columns
    has_cluster_col = "cluster_name" in df.columns

    env_dropdown = None
    if has_env_col:
        env_values = sorted(
            v for v in df["env"].dropna().unique().tolist() if str(v) != ""
        )
        env_dropdown = widgets.Dropdown(
            options=["All"] + env_values,
            value="All",
            description="Env:",
            layout=widgets.Layout(width="220px"),
            style={"description_width": "60px"},
        )

    cluster_dropdown = None
    if has_cluster_col:
        all_clusters = sorted(
            v for v in df["cluster_name"].dropna().unique().tolist() if str(v) != ""
        )
        cluster_dropdown = widgets.Dropdown(
            options=["All"] + all_clusters,
            value="All",
            description="Cluster:",
            layout=widgets.Layout(width="300px"),
            style={"description_width": "60px"},
        )

    page_size_dropdown = widgets.Dropdown(
        options=[("10", 10), ("25", 25), ("50", 50), ("100", 100), ("All", 0)],
        value=25,
        description="Rows:",
        layout=widgets.Layout(width="140px"),
        style={"description_width": "45px"},
    )
    prev_btn = widgets.Button(
        description="◀ Prev", layout=widgets.Layout(width="80px")
    )
    next_btn = widgets.Button(
        description="Next ▶", layout=widgets.Layout(width="80px")
    )
    page_label = widgets.Label(value="")

    export_btn = widgets.Button(
        description="Export CSV",
        icon="download",
        tooltip="Export the currently filtered rows to output/<name>-YYYY-MM-DD-HH-MM.csv",
        layout=widgets.Layout(width="140px"),
    )
    export_status = widgets.Label(value="")

    out = widgets.Output()

    # Current page index (0-based). Mutable via list to avoid `nonlocal`.
    state = {"page": 0}

    def _clusters_for_env(env_sel: str) -> list:
        if not has_cluster_col:
            return []
        if env_sel == "All" or not has_env_col:
            pool = df
        else:
            pool = df[df["env"] == env_sel]
        return sorted(
            v for v in pool["cluster_name"].dropna().unique().tolist()
            if str(v) != ""
        )

    def _filtered_df() -> pd.DataFrame:
        filtered = df
        if env_dropdown is not None and env_dropdown.value != "All":
            filtered = filtered[filtered["env"] == env_dropdown.value]
        if cluster_dropdown is not None and cluster_dropdown.value != "All":
            filtered = filtered[filtered["cluster_name"] == cluster_dropdown.value]
        return filtered

    def _render() -> None:
        filtered = _filtered_df()
        total = len(filtered)
        page_size = page_size_dropdown.value  # 0 means "All"

        if page_size and page_size > 0:
            last_page = max(0, (total - 1) // page_size) if total else 0
            if state["page"] > last_page:
                state["page"] = last_page
            start = state["page"] * page_size
            end = min(start + page_size, total)
            view = filtered.iloc[start:end]
            prev_btn.disabled = state["page"] <= 0
            next_btn.disabled = state["page"] >= last_page
            if total == 0:
                page_label.value = "0 rows"
            else:
                page_label.value = (
                    f"{start + 1}–{end} of {total}  "
                    f"(page {state['page'] + 1}/{last_page + 1})"
                )
        else:
            view = filtered
            prev_btn.disabled = True
            next_btn.disabled = True
            page_label.value = f"{total} rows"

        with out:
            clear_output(wait=True)
            display(_build_styler(view, caption))

    def _reset_and_render() -> None:
        state["page"] = 0
        _render()

    def _on_env_change(change: dict) -> None:
        if change.get("name") != "value" or change.get("type") != "change":
            return
        if cluster_dropdown is not None:
            new_opts = ["All"] + _clusters_for_env(change["new"])
            current = cluster_dropdown.value
            # Reset Cluster to "All" whenever Env is set to "All"; otherwise
            # preserve the current selection if still valid for the new env.
            if change["new"] == "All":
                new_value = "All"
            else:
                new_value = current if current in new_opts else "All"
            cluster_dropdown.unobserve(_on_cluster_change, names="value")
            cluster_dropdown.options = new_opts
            cluster_dropdown.value = new_value
            cluster_dropdown.observe(_on_cluster_change, names="value")
        _reset_and_render()

    def _on_cluster_change(change: dict) -> None:
        if change.get("name") == "value" and change.get("type") == "change":
            _reset_and_render()

    def _on_page_size_change(change: dict) -> None:
        if change.get("name") == "value" and change.get("type") == "change":
            _reset_and_render()

    def _on_prev(_btn) -> None:
        if state["page"] > 0:
            state["page"] -= 1
            _render()

    def _on_next(_btn) -> None:
        state["page"] += 1
        _render()

    def _on_export(_btn) -> None:
        filtered = _filtered_df()
        out_dir = _OUTPUT_DIR or (Path.cwd() / "output")
        out_dir.mkdir(parents=True, exist_ok=True)
        slug = re.sub(r"[^a-z0-9]+", "-", (caption or "export").lower()).strip("-")
        if not slug:
            slug = "export"
        stamp = datetime.now().strftime("%Y-%m-%d-%H-%M")
        fname = f"{slug}-{stamp}.csv"
        fpath = out_dir / fname
        filtered.to_csv(fpath, index=False)
        export_status.value = f"Saved {len(filtered)} rows → {fpath}"

    if env_dropdown is not None:
        env_dropdown.observe(_on_env_change, names="value")
    if cluster_dropdown is not None:
        cluster_dropdown.observe(_on_cluster_change, names="value")
    page_size_dropdown.observe(_on_page_size_change, names="value")
    prev_btn.on_click(_on_prev)
    next_btn.on_click(_on_next)
    export_btn.on_click(_on_export)

    filter_row = [w for w in (env_dropdown, cluster_dropdown) if w is not None]
    page_row = [page_size_dropdown, prev_btn, next_btn, page_label]
    export_row = [export_btn, export_status]

    if filter_row:
        controls = widgets.VBox([
            widgets.HBox(filter_row),
            widgets.HBox(page_row),
            widgets.HBox(export_row),
        ])
    else:
        controls = widgets.VBox([
            widgets.HBox(page_row),
            widgets.HBox(export_row),
        ])

    _render()
    return widgets.VBox([controls, out])


def bootstrap(db_relpath: str = "../datastore/ocp_audit.db"):
    """Configure sys.path and OCP_AUDIT_DB, then return (session, engine).

    Must be called before any `schema.*` import. Idempotent, and safe to
    re-run in a kernel that is shared across notebooks: any previously
    returned session is closed and all open ipywidgets are released before
    a fresh session is created.
    """
    # Drop any prior session + widgets from an earlier notebook using this
    # same kernel so we don't leak state or duplicate grid displays.
    reset()

    notebook_dir = Path(os.path.abspath("__file__")).parent
    db_path = (notebook_dir / db_relpath).resolve()
    os.environ["OCP_AUDIT_DB"] = str(db_path)

    datastore_dir = (notebook_dir / ".." / "datastore").resolve()
    if str(datastore_dir) not in sys.path:
        sys.path.insert(0, str(datastore_dir))

    # Resolve and remember the repo-level ``output/`` directory for CSV exports.
    global _OUTPUT_DIR, _LAST_SESSION
    _OUTPUT_DIR = (notebook_dir / ".." / "output").resolve()
    _OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Imported here so OCP_AUDIT_DB is set before the engine is created.
    from schema.database import SessionLocal, engine  # noqa: WPS433
    from schema.models import Cluster, ClusterEnv  # noqa: WPS433

    session = SessionLocal()
    _LAST_SESSION = session

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
