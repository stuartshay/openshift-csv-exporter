"""Session + sys.path bootstrap for the OCP audit notebooks."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pandas as pd

from . import _state


def reset() -> None:
    """Close all open ipywidgets and the previous SQLAlchemy session.

    Useful when sharing a single Jupyter kernel across multiple notebooks —
    call :func:`reset` (or simply re-run the bootstrap cell, which calls it
    automatically) to guarantee a clean widget registry and drop any stale
    session state. Safe to call when nothing has been initialised yet.
    """
    if _state.LAST_SESSION is not None:
        try:
            _state.LAST_SESSION.close()
        except Exception:
            pass
        _state.LAST_SESSION = None
    _state.CLUSTER_ENV_MAP.clear()
    try:
        import ipywidgets as widgets  # noqa: WPS433

        widgets.Widget.close_all()
    except Exception:
        pass


def bootstrap(db_relpath: str = "../datastore/ocp_audit.db"):
    """Configure sys.path and OCP_AUDIT_DB, then return (session, engine).

    Must be called before any ``schema.*`` import. Idempotent, and safe to
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
    _state.OUTPUT_DIR = (notebook_dir / ".." / "output").resolve()
    _state.OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Imported here so OCP_AUDIT_DB is set before the engine is created.
    from schema.database import SessionLocal, engine  # noqa: WPS433
    from schema.models import ClusterEnv  # noqa: WPS433

    session = SessionLocal()
    _state.LAST_SESSION = session

    # Build cluster_server -> (env, friendly_name) map for auto-prepend.
    # ClusterEnv is keyed on cluster_server directly, so one row per real
    # cluster regardless of how many kubeconfig contexts reference it.
    _state.CLUSTER_ENV_MAP.clear()
    rows = session.query(ClusterEnv.cluster_server, ClusterEnv.env, ClusterEnv.friendly_name).all()
    for server, env, friendly in rows:
        _state.CLUSTER_ENV_MAP[server] = (env, friendly)

    pd.set_option("display.max_colwidth", 80)
    return session, engine
