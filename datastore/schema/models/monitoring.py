"""Monitoring & detection audit areas (OCP-24 through OCP-29)."""

from sqlalchemy import ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..database import Base


class MonitoringAuditLogging(Base):
    """OCP-24 / OCP-26: one row per monitoring, logging or audit record.

    Sourced from ``export-monitoring-audit-logging.sh``. ``record_type`` covers
    ``operator``, ``monitoring_config``, ``user_workload_monitoring``,
    ``external_monitoring``, ``alerting_rules``, ``alertmanager`` (OCP-24) and
    ``audit_profile``, ``cluster_logging``, ``log_forwarder``,
    ``log_forwarder_output``, ``audit_forwarding``, ``log_retention``,
    ``lokistack`` (OCP-26). ``detail_1..detail_4`` carry free-form
    ``key=value`` flags emitted by the export script.
    """

    __tablename__ = "monitoring_audit_logging"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    component_name: Mapped[str | None] = mapped_column(String, nullable=True)
    status: Mapped[str | None] = mapped_column(String, nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_1: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_2: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_3: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_4: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="monitoring_audit_logging_records")


class ConfigurationDriftStatus(Base):
    """OCP-25: one row per configuration drift / consistency record.

    Sourced from ``export-configuration-drift-status.sh``. ``record_type``
    covers ``machineconfigpool``, ``clusteroperator``, ``argocd``,
    ``gitops_summary``, ``gitops_drift``, ``flux_summary``, ``flux_drift``,
    ``compliance_scan``, ``compliance_results_summary``, ``node_consistency``,
    and ``operator_consistency``. ``detail_1..detail_4`` carry free-form
    ``key=value`` flags emitted by the export script.
    """

    __tablename__ = "configuration_drift_status"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    component_name: Mapped[str | None] = mapped_column(String, nullable=True)
    status: Mapped[str | None] = mapped_column(String, nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_1: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_2: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_3: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_4: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="configuration_drift_status_records")


class VulnerabilityRuntimeDetection(Base):
    """OCP-28 / OCP-29: one row per vulnerability-scanning or runtime-threat record.

    Sourced from ``export-vulnerability-runtime-detection.sh``. ``record_type``
    covers ``operator`` (e.g. ``rhacs-central``, ``rhacs-secured-cluster``,
    ``falco``) and ``quay_registry``. ``detail_1..detail_4`` carry free-form
    ``key=value`` flags emitted by the export script.
    """

    __tablename__ = "vulnerability_runtime_detection"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    component_name: Mapped[str | None] = mapped_column(String, nullable=True)
    status: Mapped[str | None] = mapped_column(String, nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_1: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_2: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_3: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_4: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="vulnerability_runtime_detection_records")
