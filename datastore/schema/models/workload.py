"""Workload & Application Security audit areas (OCP-39 Container Least Privilege,
OCP-40 SCC Enforcement, OCP-41 Workload Resource Quotas)."""

from sqlalchemy import ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..database import Base


class SccPrivileged(Base):
    """OCP-39 / OCP-40: one row per SecurityContextConstraint on a cluster.

    Sourced from ``export-scc-privileged.sh``. Captures the policy fields of
    each SCC (``allow_privileged_container``, ``allow_host_*``, capability
    sets, run-as / SELinux / FSGroup strategies, allowed volumes) plus the
    user/group bindings (``users_count``, ``groups_count``, semicolon-
    delimited ``users`` and ``groups`` strings).
    """

    __tablename__ = "scc_privileged"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    name: Mapped[str | None] = mapped_column(String, nullable=True)
    priority: Mapped[str | None] = mapped_column(String, nullable=True)
    allow_privileged_container: Mapped[str | None] = mapped_column(String, nullable=True)
    default_add_capabilities: Mapped[str | None] = mapped_column(String, nullable=True)
    required_drop_capabilities: Mapped[str | None] = mapped_column(String, nullable=True)
    allowed_capabilities: Mapped[str | None] = mapped_column(String, nullable=True)
    allow_host_network: Mapped[str | None] = mapped_column(String, nullable=True)
    allow_host_ports: Mapped[str | None] = mapped_column(String, nullable=True)
    allow_host_pid: Mapped[str | None] = mapped_column(String, nullable=True)
    allow_host_ipc: Mapped[str | None] = mapped_column(String, nullable=True)
    read_only_root_filesystem: Mapped[str | None] = mapped_column(String, nullable=True)
    run_as_user_type: Mapped[str | None] = mapped_column(String, nullable=True)
    se_linux_context_type: Mapped[str | None] = mapped_column(String, nullable=True)
    fs_group_type: Mapped[str | None] = mapped_column(String, nullable=True)
    supplemental_groups_type: Mapped[str | None] = mapped_column(String, nullable=True)
    volumes: Mapped[str | None] = mapped_column(String, nullable=True)
    allow_privilege_escalation: Mapped[str | None] = mapped_column(String, nullable=True)
    users_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    groups_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    users: Mapped[str | None] = mapped_column(String, nullable=True)
    groups: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="scc_privileged_records")


class WorkloadResourceQuota(Base):
    """OCP-41: one row per ResourceQuota / ClusterResourceQuota / LimitRange.

    Sourced from ``export-workload-resource-quotas.sh``. ``record_type``
    is one of ``resourcequota``, ``clusterresourcequota``, ``limitrange``.
    For quota rows, ``resource_key`` carries the resource name (e.g.
    ``requests.cpu``) with ``hard_limit`` / ``used``. For limitrange rows,
    ``limit_type`` (Container/Pod/PVC), ``default_value`` /
    ``default_request`` / ``max_value`` / ``min_value`` carry the numeric
    constraints.
    """

    __tablename__ = "workload_resource_quotas"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    name: Mapped[str | None] = mapped_column(String, nullable=True)
    resource_key: Mapped[str | None] = mapped_column(String, nullable=True)
    hard_limit: Mapped[str | None] = mapped_column(String, nullable=True)
    used: Mapped[str | None] = mapped_column(String, nullable=True)
    limit_type: Mapped[str | None] = mapped_column(String, nullable=True)
    default_value: Mapped[str | None] = mapped_column(String, nullable=True)
    default_request: Mapped[str | None] = mapped_column(String, nullable=True)
    max_value: Mapped[str | None] = mapped_column(String, nullable=True)
    min_value: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="workload_resource_quota_records")
