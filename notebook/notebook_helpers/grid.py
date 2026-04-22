"""Interactive ipywidgets grid: env/cluster filters, pagination, export, reset."""
from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path

import pandas as pd

from . import _state
from .env_columns import prepend_env_columns
from .theme import build_styler


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
    result sets stay readable. A **Reset** button clears filters, restores
    the default page size, and jumps back to page 1.

    Returns an ipywidgets ``VBox`` when widgets are available, otherwise a
    plain pandas ``Styler``.
    """
    df = prepend_env_columns(df)

    try:
        import ipywidgets as widgets  # noqa: WPS433
    except ModuleNotFoundError:
        # ipywidgets not available in current kernel — render unfiltered table.
        return build_styler(df, caption)

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

    reset_btn = widgets.Button(
        description="Reset",
        icon="refresh",
        tooltip="Clear filters, restore default page size, and jump back to page 1",
        layout=widgets.Layout(width="100px"),
    )

    out = widgets.HTML(value="")

    # Current page index (0-based). Mutable via dict to avoid `nonlocal`.
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

        out.value = build_styler(view, caption).to_html()

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
        out_dir = _state.OUTPUT_DIR or (Path.cwd() / "output")
        out_dir.mkdir(parents=True, exist_ok=True)
        slug = re.sub(r"[^a-z0-9]+", "-", (caption or "export").lower()).strip("-")
        if not slug:
            slug = "export"
        stamp = datetime.now().strftime("%Y-%m-%d-%H-%M")
        fname = f"{slug}-{stamp}.csv"
        fpath = out_dir / fname
        filtered.to_csv(fpath, index=False)
        export_status.value = f"Saved {len(filtered)} rows → {fpath}"

    def _on_reset(_btn) -> None:
        """Clear filters, restore default page size, and jump back to page 1."""
        # Silence change handlers while we reset widget values so _render()
        # is only invoked once at the end.
        if env_dropdown is not None:
            env_dropdown.unobserve(_on_env_change, names="value")
        if cluster_dropdown is not None:
            cluster_dropdown.unobserve(_on_cluster_change, names="value")
        page_size_dropdown.unobserve(_on_page_size_change, names="value")

        if env_dropdown is not None:
            env_dropdown.value = "All"
        if cluster_dropdown is not None:
            # Restore the full cluster list (env was just reset to All).
            cluster_dropdown.options = ["All"] + _clusters_for_env("All")
            cluster_dropdown.value = "All"
        page_size_dropdown.value = 25
        state["page"] = 0
        export_status.value = ""

        if env_dropdown is not None:
            env_dropdown.observe(_on_env_change, names="value")
        if cluster_dropdown is not None:
            cluster_dropdown.observe(_on_cluster_change, names="value")
        page_size_dropdown.observe(_on_page_size_change, names="value")

        _render()

    if env_dropdown is not None:
        env_dropdown.observe(_on_env_change, names="value")
    if cluster_dropdown is not None:
        cluster_dropdown.observe(_on_cluster_change, names="value")
    page_size_dropdown.observe(_on_page_size_change, names="value")
    prev_btn.on_click(_on_prev)
    next_btn.on_click(_on_next)
    export_btn.on_click(_on_export)
    reset_btn.on_click(_on_reset)

    filter_row = [w for w in (env_dropdown, cluster_dropdown) if w is not None]
    page_row = [page_size_dropdown, prev_btn, next_btn, page_label]
    export_row = [export_btn, reset_btn, export_status]

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
