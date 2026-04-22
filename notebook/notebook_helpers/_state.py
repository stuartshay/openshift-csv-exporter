"""Process-global state shared by :mod:`notebook_helpers` submodules.

Kept in a dedicated module so ``grid`` / ``env_columns`` can read values
written by ``bootstrap`` without creating circular imports. Values are
mutated via attribute access (``state.CLUSTER_ENV_MAP`` etc.), never
re-bound inside consumers.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

# Populated by ``bootstrap()`` — maps cluster_server -> (env, friendly_name).
# Keyed by cluster_server (the API URL) rather than cluster_name, because
# cluster_name often has the kube context appended and is not a stable key.
CLUSTER_ENV_MAP: dict[str, tuple[str | None, str | None]] = {}

# Populated by ``bootstrap()`` — absolute path to the repo ``output/`` dir.
OUTPUT_DIR: Path | None = None

# Tracks the most recent SQLAlchemy session returned by ``bootstrap()`` so it
# can be closed cleanly when the same kernel is reused across notebooks.
LAST_SESSION: Any = None
