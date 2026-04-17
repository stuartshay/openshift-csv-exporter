"""Seed the ``env`` column on existing clusters from a CSV file.

Reads ``clusters.csv`` (default: ``input/clusters.csv``) and matches rows by
``cluster_server`` to set the ``env`` label on existing clusters.

Usage::

    python seed_clusters.py                       # reads input/clusters.csv
    python seed_clusters.py /path/to/clusters.csv # custom path
"""

from __future__ import annotations

import csv
import sys
from pathlib import Path

from schema.database import Base, SessionLocal, engine
from schema.models import Cluster

DEFAULT_CSV = Path("input") / "clusters.csv"


def seed_clusters(csv_path: Path) -> int:
    """Match clusters by server URL and set env. Return update count."""
    if not csv_path.exists():
        print(f"ERROR: file not found: {csv_path}", file=sys.stderr)
        sys.exit(1)

    Base.metadata.create_all(engine)

    updated = 0
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

                clusters = session.query(Cluster).filter_by(cluster_server=server).all()

                if not clusters:
                    print(f"  No match: {server}")
                    skipped += 1
                else:
                    for cluster in clusters:
                        cluster.env = env
                        updated += 1
                        print(f"  Updated: {cluster.cluster_name} -> env={env}")

        session.commit()

    return updated


def main() -> None:
    csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CSV
    print(f"Seeding clusters from: {csv_path}")

    count = seed_clusters(csv_path)
    print(f"Done — {count} cluster(s) updated.")


if __name__ == "__main__":
    main()
