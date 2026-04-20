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


def style_table(df: pd.DataFrame, caption: str | None = None):
    """Return a pandas Styler with the shared orange-header theme.

    Parameters
    ----------
    df : pd.DataFrame
        The DataFrame to render.
    caption : str, optional
        Optional caption rendered above the table.
    """
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

    pd.set_option("display.max_colwidth", 80)
    return SessionLocal(), engine
