"""Seed the ``cluster_env`` table from a CSV file.

Reads ``clusters_env.csv`` (default: ``input/clusters_env.csv``) and matches
rows by ``cluster_server`` against the ``cluster_server`` column in the
``clusters`` table to find the corresponding cluster, then creates or updates
entries in the ``cluster_env`` table.

The CSV is validated against the ``clusters`` table BEFORE any writes:

- Every distinct ``cluster_server`` in ``clusters`` must be present in the CSV.
- Every ``cluster_server`` in the CSV must match at least one row in
  ``clusters``.
- The CSV must not contain duplicate ``cluster_server`` rows.
- Row counts must match exactly.

Any mismatch raises ``SeedValidationError`` and aborts the run with a
non-zero exit code; no rows are upserted.

Usage::

    python seed_clusters.py                            # reads input/clusters_env.csv
    python seed_clusters.py /path/to/clusters_env.csv  # custom path
"""

from __future__ import annotations

import csv
import sys
from pathlib import Path

from schema.database import Base, SessionLocal, engine
from schema.models import Cluster, ClusterEnv

DEFAULT_CSV = Path("input") / "clusters_env.csv"


class SeedValidationError(Exception):
    """Raised when ``clusters_env.csv`` does not exactly cover ``clusters``."""


def _read_csv_rows(csv_path: Path) -> list[dict]:
    with open(csv_path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        required = {"cluster_server", "env"}
        if not required.issubset(set(reader.fieldnames or [])):
            raise SeedValidationError(f"CSV must contain columns: {', '.join(sorted(required))}")
        rows = []
        for idx, row in enumerate(reader, start=2):  # start=2 accounts for header
            server = (row.get("cluster_server") or "").strip()
            env = (row.get("env") or "").strip()
            friendly_name = (row.get("friendly_name") or "").strip() or None
            if not server:
                raise SeedValidationError(f"Row {idx}: empty cluster_server")
            if not env:
                raise SeedValidationError(f"Row {idx}: empty env for cluster_server={server!r}")
            rows.append(
                {
                    "cluster_server": server,
                    "env": env,
                    "friendly_name": friendly_name,
                    "_row_num": idx,
                }
            )
        return rows


def _validate_coverage(csv_rows: list[dict], db_servers: set[str]) -> None:
    """Raise ``SeedValidationError`` unless the CSV exactly covers ``clusters``."""
    csv_servers: list[str] = [r["cluster_server"] for r in csv_rows]
    csv_server_set: set[str] = set(csv_servers)

    # Duplicate cluster_server values in the CSV.
    duplicates = sorted({s for s in csv_servers if csv_servers.count(s) > 1})
    missing_in_csv = sorted(db_servers - csv_server_set)
    extra_in_csv = sorted(csv_server_set - db_servers)

    if duplicates or missing_in_csv or extra_in_csv or len(csv_servers) != len(db_servers):
        lines = [
            "clusters_env.csv does not exactly match the clusters table:",
            f"  clusters rows (distinct cluster_server): {len(db_servers)}",
            f"  CSV rows:                                {len(csv_servers)}",
        ]
        if duplicates:
            lines.append(f"  duplicate cluster_server in CSV ({len(duplicates)}):")
            lines.extend(f"    - {s}" for s in duplicates)
        if missing_in_csv:
            lines.append(f"  missing from CSV (present in clusters) ({len(missing_in_csv)}):")
            lines.extend(f"    - {s}" for s in missing_in_csv)
        if extra_in_csv:
            lines.append(f"  extra in CSV (not in clusters) ({len(extra_in_csv)}):")
            lines.extend(f"    - {s}" for s in extra_in_csv)
        raise SeedValidationError("\n".join(lines))


def seed_clusters(csv_path: Path) -> int:
    """Match via clusters.cluster_server and upsert cluster_env rows.

    Validates coverage first; raises ``SeedValidationError`` if the CSV does
    not exactly match the ``clusters`` table.
    """
    if not csv_path.exists():
        raise SeedValidationError(f"file not found: {csv_path}")

    Base.metadata.create_all(engine)

    csv_rows = _read_csv_rows(csv_path)
    upserted = 0

    with SessionLocal() as session:
        db_servers = {s for (s,) in session.query(Cluster.cluster_server).distinct().all() if s}
        _validate_coverage(csv_rows, db_servers)

        for row in csv_rows:
            server = row["cluster_server"]
            env = row["env"]
            friendly_name = row["friendly_name"]

            existing = session.query(ClusterEnv).filter_by(cluster_server=server).first()
            if existing:
                existing.env = env
                existing.friendly_name = friendly_name
                print(f"  Updated: {server} -> env={env}, friendly_name={friendly_name}")
            else:
                session.add(
                    ClusterEnv(
                        cluster_server=server,
                        env=env,
                        friendly_name=friendly_name,
                    )
                )
                print(f"  Added:   {server} -> env={env}, friendly_name={friendly_name}")
            upserted += 1

        session.commit()

    return upserted


def main() -> None:
    csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CSV
    print(f"Seeding cluster_env from: {csv_path}")

    try:
        count = seed_clusters(csv_path)
    except SeedValidationError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
    print(f"Done — {count} cluster(s) upserted.")


if __name__ == "__main__":
    main()
