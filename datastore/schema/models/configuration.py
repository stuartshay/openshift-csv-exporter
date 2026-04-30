"""Configuration & Hardening audit areas (OCP-6 through OCP-14)."""

from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..database import Base


class PlatformGuardrail(Base):
    """One row per cluster: posture against unapproved OCP distribution use
    and misconfigured cluster components (degraded / unavailable operators)."""

    __tablename__ = "platform_guardrails"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    ocp_version: Mapped[str | None] = mapped_column(String, nullable=True)
    cluster_id_ocp: Mapped[str | None] = mapped_column(String, nullable=True)
    update_channel: Mapped[str | None] = mapped_column(String, nullable=True)
    update_state: Mapped[str | None] = mapped_column(String, nullable=True)
    platform: Mapped[str | None] = mapped_column(String, nullable=True)
    control_plane_topology: Mapped[str | None] = mapped_column(String, nullable=True)
    infrastructure_topology: Mapped[str | None] = mapped_column(String, nullable=True)
    total_operators: Mapped[int | None] = mapped_column(Integer, nullable=True)
    degraded_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    unavailable_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    degraded_operators: Mapped[str | None] = mapped_column(Text, nullable=True)
    unavailable_operators: Mapped[str | None] = mapped_column(Text, nullable=True)

    cluster = relationship("Cluster", back_populates="platform_guardrails")


class PolicyAsCodeConstraint(Base):
    """One row per (cluster, ConstraintTemplate, Constraint) for OPA Gatekeeper.

    When Gatekeeper is not installed a single row is written with
    ``gatekeeper_installed=False`` and the constraint fields empty.
    """

    __tablename__ = "policy_as_code_constraints"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    gatekeeper_installed: Mapped[bool | None] = mapped_column(nullable=True)
    gatekeeper_namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    constraint_template: Mapped[str | None] = mapped_column(String, nullable=True)
    constraint_name: Mapped[str | None] = mapped_column(String, nullable=True)
    enforcement_action: Mapped[str | None] = mapped_column(String, nullable=True)
    total_violations: Mapped[int | None] = mapped_column(Integer, nullable=True)
    match_kinds: Mapped[str | None] = mapped_column(Text, nullable=True)
    match_namespaces: Mapped[str | None] = mapped_column(Text, nullable=True)

    cluster = relationship("Cluster", back_populates="policy_as_code_constraints")


class CICDPipelineDetection(Base):
    """OCP-8: one row per detected CI/CD pipeline component on a cluster.

    The export script emits multiple rows per cluster covering
    OpenShift Pipelines/GitOps operators, ArgoCD instances, and Tekton
    Chains. ``detail_1..detail_6`` capture free-form ``key=value`` flags
    written by the export script.
    """

    __tablename__ = "cicd_pipeline_detections"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    detection_type: Mapped[str | None] = mapped_column(String, nullable=True)
    tool_name: Mapped[str | None] = mapped_column(String, nullable=True)
    installed: Mapped[bool | None] = mapped_column(nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    resource_name: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_1: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_2: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_3: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_4: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_5: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_6: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="cicd_pipeline_detections")


class ControlPlaneProtection(Base):
    """OCP-9: one row per control-plane protection check (etcd encryption,
    API audit profile, TLS minimum, control-plane topology).
    """

    __tablename__ = "control_plane_protections"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    check_category: Mapped[str | None] = mapped_column(String, nullable=True)
    check_name: Mapped[str | None] = mapped_column(String, nullable=True)
    status: Mapped[str | None] = mapped_column(String, nullable=True)
    details: Mapped[str | None] = mapped_column(Text, nullable=True)

    cluster = relationship("Cluster", back_populates="control_plane_protections")


class PatchLifecycleCheck(Base):
    """OCP-10: one row per patch / version lifecycle check.

    Covers the ``ClusterVersion`` row (current vs desired OpenShift release,
    update channel, pending updates) and per-MachineConfigPool rows for
    master / worker rendered config rollout state.
    """

    __tablename__ = "patch_lifecycle_checks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    check_category: Mapped[str | None] = mapped_column(String, nullable=True)
    resource_name: Mapped[str | None] = mapped_column(String, nullable=True)
    current_version: Mapped[str | None] = mapped_column(String, nullable=True)
    desired_version: Mapped[str | None] = mapped_column(String, nullable=True)
    versions_match: Mapped[bool | None] = mapped_column(nullable=True)
    update_channel: Mapped[str | None] = mapped_column(String, nullable=True)
    available_updates: Mapped[int | None] = mapped_column(Integer, nullable=True)
    update_state: Mapped[str | None] = mapped_column(String, nullable=True)
    age_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    details: Mapped[str | None] = mapped_column(Text, nullable=True)

    cluster = relationship("Cluster", back_populates="patch_lifecycle_checks")


class EtcdEncryptionStatus(Base):
    """OCP-14: one row per etcd encryption-at-rest status record.

    The export emits a cluster-level APIServer encryption config row plus
    operator status / encryption condition rows for kube-apiserver and
    openshift-apiserver.
    """

    __tablename__ = "etcd_encryption_status"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    resource_name: Mapped[str | None] = mapped_column(String, nullable=True)
    encryption_type: Mapped[str | None] = mapped_column(String, nullable=True)
    encryption_enabled: Mapped[bool | None] = mapped_column(nullable=True)
    condition_available: Mapped[bool | None] = mapped_column(nullable=True)
    condition_degraded: Mapped[bool | None] = mapped_column(nullable=True)
    condition_progressing: Mapped[bool | None] = mapped_column(nullable=True)
    condition_type: Mapped[str | None] = mapped_column(String, nullable=True)
    condition_reason: Mapped[str | None] = mapped_column(String, nullable=True)
    message: Mapped[str | None] = mapped_column(Text, nullable=True)

    cluster = relationship("Cluster", back_populates="etcd_encryption_status_records")


class GovernancePolicyEcosystem(Base):
    """OCP-15: one row per detected governance / policy product on a cluster.

    Records cover policy engines (Gatekeeper, Kyverno), Compliance Operator,
    ACS/StackRox, ACM, Quay registry policy, etc. ``record_type`` is
    typically ``operator`` or ``policy``; ``detail_1..detail_3`` capture
    free-form ``key=value`` flags emitted by the export script.
    """

    __tablename__ = "governance_policy_ecosystem"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    product_name: Mapped[str | None] = mapped_column(String, nullable=True)
    installed: Mapped[bool | None] = mapped_column(nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    operator_version: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_1: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_2: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_3: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="governance_policy_ecosystem")
