"""Seed the ``cluster_env`` table from a CSV file.

Reads ``clusters_env.csv`` (default: ``input/clusters_env.csv``) and matches
rows by ``cluster_server`` against the ``cluster_server`` column in the
``clusters`` table to find the corresponding cluster, then creates or updates
entries in the ``cluster_env`` table.

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


def seed_clusters(csv_path: Path) -> int:
    """Match via clusters.cluster_server and upsert cluster_env rows."""
    if not csv_path.exists():
        print(f"ERROR: file not found: {csv_path}", file=sys.stderr)
        sys.exit(1)

    Base.metadata.create_all(engine)

    upserted = 0
    skipped = 0

    with SessionLocal() as session:
        with open(csv_path, newline="", encoding="utf-8") as fh:
            reader = csv.DictReader(fh)

            required = {"cluster_server", "env"}
            if not required.issubset(set(reader.fieldnames or [])):
                print(
                    f"ERROR: CSV must contain columns: {', '.join(sorted(required))}",
                    file=sys.stderr,
                )
                sys.exit(1)

            for row in reader:
                server = row["cluster_server"].strip()
                env = row["env"].strip()

                if not server or not env:
                    print(f"  Skipping empty row: {row}")
                    skipped += 1
                    continue

                # Match via clusters.cluster_server
                clusters = session.query(Cluster).filter_by(cluster_server=server).all()

                if not clusters:
                    print(f"  No match in clusters: {server}")
                    skipped += 1
                    continue

                for cluster in clusters:
                    existing = (
                        session.query(ClusterEnv)
                        .filter_by(cluster_id=cluster.id)
                        .first()
                    )
                    if existing:
                        existing.env = env
                        print(f"  Updated: {cluster.cluster_name} -> env={env}")
                    else:
                        session.add(ClusterEnv(cluster_id=cluster.id, env=env))
                        print(f"  Added:   {cluster.cluster_name} -> env={env}")
                    upserted += 1

        session.commit()

    return upserted


def main() -> None:
    csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CSV
    print(f"Seeding cluster_env from: {csv_path}")

    count = seed_clusters(csv_path)
    print(f"Done — {count} cluster(s) upserted.")


if __name__ == "__main__":
    main()
