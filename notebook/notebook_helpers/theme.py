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
    "prod": "#1E40AF",   # deep indigo (neutral-but-distinct; red reserved for errors)
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


def _env_prefix_format(value: object) -> str:
    """Wrap known env-prefixed values in an inline-styled ``<span>``.

    Using inline styles (instead of a ``<style>`` block keyed on the table
    id) ensures the colors survive when the rendered HTML is embedded in an
    ``ipywidgets.HTML`` widget, which strips/scopes top-level ``<style>``
    tags in some notebook renderers (notably VS Code).
    """
    from html import escape as _html_escape

    if value is None:
        return ""
    text = str(value)
    css = _env_prefix_color(text)
    safe = _html_escape(text)
    if not css:
        return safe
    return f'<span style="{css}">{safe}</span>'


# --- US datetime formatting -----------------------------------------------
# Columns whose values should be rendered in US format (``MM/DD/YYYY
# hh:MM AM/PM``) when present. Matched by exact name or by suffix.
_US_DATE_COLUMN_NAMES = {"install_date", "created_at", "updated_at", "timestamp"}
_US_DATE_COLUMN_SUFFIXES = ("_date", "_at", "_time", "_timestamp")


def _is_date_like_column(name: str) -> bool:
    if name in _US_DATE_COLUMN_NAMES:
        return True
    return any(name.endswith(s) for s in _US_DATE_COLUMN_SUFFIXES)


def _format_us_datetime(value: object) -> str:
    """Render a value as ``M/D/YYYY`` (US style, date only).

    Returns the original string representation unchanged if the value is
    empty or not parseable as a timestamp. ISO 8601 strings with ``Z`` or
    offset are accepted.
    """
    if value is None:
        return ""
    # Treat NaN/NaT as empty
    try:
        if pd.isna(value):  # type: ignore[arg-type]
            return ""
    except (TypeError, ValueError):
        pass
    ts = pd.to_datetime(value, errors="coerce", utc=False)
    if pd.isna(ts):
        return str(value)
    # Cross-platform: build date string manually to avoid platform-specific
    # strftime tokens like ``%-m``/``%-d`` (not supported on Windows).
    return f"{ts.month}/{ts.day}/{ts.year}"


# --- Boolean column coloring ----------------------------------------------
# Columns whose values are True/False (or the strings "True"/"False") get
# colored inline: green for True, red for False. Applied only to columns
# whose non-null values are entirely boolean-like, so integer or free-text
# columns remain untouched.
_BOOL_TRUE_COLOR = "#2E7D32"   # green
_BOOL_FALSE_COLOR = "#C62828"  # red
_BOOL_TRUE_STRINGS = {"true"}
_BOOL_FALSE_STRINGS = {"false"}


def _is_bool_like_column(series: pd.Series) -> bool:
    """Return True when every non-null value is a bool or 'true'/'false' string."""
    if pd.api.types.is_bool_dtype(series):
        return True
    non_null = series.dropna()
    if non_null.empty:
        return False
    for v in non_null:
        if isinstance(v, bool):
            continue
        if isinstance(v, str) and v.strip().lower() in (_BOOL_TRUE_STRINGS | _BOOL_FALSE_STRINGS):
            continue
        return False
    return True


def _format_bool(value: object) -> str:
    """Render a boolean-like value as a colored ``<span>``.

    - ``True`` / ``"true"``  → green ``True``
    - ``False`` / ``"false"`` → red ``False``
    - Anything else is returned as its (HTML-escaped) string form.
    """
    from html import escape as _html_escape

    if value is None:
        return ""
    try:
        if pd.isna(value):  # type: ignore[arg-type]
            return ""
    except (TypeError, ValueError):
        pass
    if isinstance(value, bool):
        is_true = value
    elif isinstance(value, str):
        v = value.strip().lower()
        if v in _BOOL_TRUE_STRINGS:
            is_true = True
        elif v in _BOOL_FALSE_STRINGS:
            is_true = False
        else:
            return _html_escape(value)
    else:
        return _html_escape(str(value))
    color = _BOOL_TRUE_COLOR if is_true else _BOOL_FALSE_COLOR
    label = "True" if is_true else "False"
    return f'<span style="color: {color}; font-weight: 600;">{label}</span>'


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
    # ``env`` and ``friendly_name`` columns when they are present. We use
    # ``Styler.format`` to emit an inline-styled ``<span>`` so the colors
    # survive when the HTML is embedded in an ``ipywidgets.HTML`` widget
    # (VS Code's notebook renderer strips/scopes top-level ``<style>``
    # blocks, which would otherwise hide ``Styler.map`` rules).
    tint_cols = [c for c in ("env", "friendly_name") if c in df.columns]
    if tint_cols:
        styler = styler.format(
            _env_prefix_format,
            subset=tint_cols,
            escape=None,
        )
    # Format date-like columns in US style (e.g. ``6/20/2024 9:45 AM``).
    date_cols = [c for c in df.columns if _is_date_like_column(str(c))]
    if date_cols:
        styler = styler.format(_format_us_datetime, subset=date_cols)
    # Color True/False values in boolean-like columns (green/red). Skip
    # columns already claimed by other formatters.
    claimed = set(tint_cols) | set(date_cols)
    bool_cols = [
        c for c in df.columns
        if c not in claimed and _is_bool_like_column(df[c])
    ]
    if bool_cols:
        styler = styler.format(_format_bool, subset=bool_cols, escape=None)
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
