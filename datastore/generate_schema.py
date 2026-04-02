#!/usr/bin/env python3
"""Generate the OCP audit SQLite database schema.

Creates all tables defined in schema/models.py using SQLAlchemy's
``Base.metadata.create_all()``.  The resulting database file defaults to
``ocp_audit.db`` in the current directory (override via the ``OCP_AUDIT_DB``
or ``DATABASE_URL`` environment variables).
"""

from schema.database import Base, engine

# Import models so they register with Base.metadata.
from schema.models import (  # noqa: F401
    Cluster,
    ClusterRole,
    ClusterRoleBinding,
    ClusterRoleBindingSubject,
    ClusterRoleRule,
    ClusterRoleRuleApiGroup,
    ClusterRoleRuleNonResourceUrl,
    ClusterRoleRuleResource,
    ClusterRoleRuleVerb,
    OAuthExternalAuth,
    SelfProvisionerBinding,
    SelfProvisionerSubject,
)


def main() -> None:
    Base.metadata.create_all(engine)
    tables = Base.metadata.sorted_tables
    print(f"Created {len(tables)} tables in {engine.url}:")
    for table in tables:
        print(f"  - {table.name}")


if __name__ == "__main__":
    main()
