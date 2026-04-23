"""Shared visual theme (orange header band) and pandas ``Styler`` builder."""
from __future__ import annotations

import pandas as pd

# --- Theme constants (shared across all notebooks) -------------------------
HEADER_BG = "#E07B39"  # warm orange from reference screenshot
HEADER_FG = "#FFFFFF"
BORDER = "1px solid #D9D9D9"
HOVER_BG = "rgba(224, 123, 57, 0.12)"
FONT_FAMILY = "Segoe UI, Arial, sans-serif"
FONT_SIZE = "13px"

# Env-prefix colors. Matched case-insensitively against a leading
# ``PROD-`` / ``STAGE-`` / ``DEV-`` prefix on the env value (and the
# ``friendly_name`` column, which embeds the same prefix in production).
ENV_PREFIX_COLORS = {
    "prod": "#C62828",   # red
    "stage": "#F59E0B",  # amber
    "dev": "#2E7D32",    # green
}


def _env_prefix_color(value: object) -> str:
    """Return a CSS ``color:...;font-weight:600`` rule for known env prefixes.

    Matches ``PROD-...`` / ``STAGE-...`` / ``DEV-...`` case-insensitively,
    as well as a bare ``prod`` / ``stage`` / ``dev`` value. Unknown values
    get no styling.
    """
    if not isinstance(value, str) or not value:
        return ""
    head = value.split("-", 1)[0].strip().lower()
    color = ENV_PREFIX_COLORS.get(head)
    if not color:
        return ""
    return f"color: {color}; font-weight: 600;"

TABLE_STYLES = [
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


def build_styler(df: pd.DataFrame, caption: str | None = None):
    """Apply the shared orange-header theme to an already-prepared DataFrame."""
    styler = df.style.hide(axis="index").set_table_styles(TABLE_STYLES)
    # Colorize env prefixes (PROD-/STAGE-/DEV-, case-insensitive) on the
    # ``env`` and ``friendly_name`` columns when they are present.
    tint_cols = [c for c in ("env", "friendly_name") if c in df.columns]
    if tint_cols:
        styler = styler.map(_env_prefix_color, subset=tint_cols)
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
