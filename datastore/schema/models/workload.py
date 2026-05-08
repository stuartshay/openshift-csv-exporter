"""Workload & Application Security audit areas (OCP-39 Container Least Privilege,
OCP-40 SCC Enforcement, OCP-41 Workload Resource Quotas, OCP-42 Trusted Image
Enforcement, OCP-43 Pod Security Admission, OCP-45 Logical Project Isolation,
OCP-46 Encryption at Rest, OCP-47 Build/Source-to-Image Policy, OCP-48 Image
Signing & Verification, OCP-49 Ephemeral Storage Limits, OCP-50 Admission
Controller Hardening)."""

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


class TrustedImageEnforcement(Base):
    """OCP-42: image admission, signing and mirror policy.

    Sourced from ``export-trusted-image-enforcement.sh``. ``record_type`` is
    one of ``image_config`` (the cluster-scoped ``image.config.openshift.io``
    resource), ``cluster_image_policy`` / ``image_policy`` (signature-
    verification policies), ``image_content_source_policy`` (registry
    mirroring), or ``admission_plugin`` (image-policy webhook detection).
    The ``detail_*`` columns carry record-type-specific evidence — see
    ``scripts/README.md`` for the full mapping.
    """

    __tablename__ = "trusted_image_enforcement"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    name: Mapped[str | None] = mapped_column(String, nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_1: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_2: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_3: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_4: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_5: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_6: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="trusted_image_enforcement_records")


class PodSecurityAdmission(Base):
    """OCP-43: per-namespace Pod Security Admission labels.

    One row per namespace, capturing the
    ``pod-security.kubernetes.io/{enforce,audit,warn}`` levels and
    versions. ``is_system_namespace`` flags ``openshift-*``, ``kube-*``
    and ``default`` namespaces so notebooks can scope verdicts to user
    workloads only.
    """

    __tablename__ = "pod_security_admission"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    is_system_namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    enforce_level: Mapped[str | None] = mapped_column(String, nullable=True)
    enforce_version: Mapped[str | None] = mapped_column(String, nullable=True)
    audit_level: Mapped[str | None] = mapped_column(String, nullable=True)
    audit_version: Mapped[str | None] = mapped_column(String, nullable=True)
    warn_level: Mapped[str | None] = mapped_column(String, nullable=True)
    warn_version: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="pod_security_admission_records")


class LogicalProjectIsolation(Base):
    """OCP-45: per-namespace logical isolation evidence.

    One row per namespace. Captures whether a default-deny NetworkPolicy
    is present, ResourceQuota / LimitRange enforcement, an ownership
    label, and counts of RoleBindings and distinct ServiceAccounts so
    notebooks can verify each user namespace is genuinely isolated.
    """

    __tablename__ = "logical_project_isolation"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    is_system_namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    has_default_deny_netpol: Mapped[str | None] = mapped_column(String, nullable=True)
    netpol_count: Mapped[str | None] = mapped_column(String, nullable=True)
    has_resourcequota: Mapped[str | None] = mapped_column(String, nullable=True)
    has_limitrange: Mapped[str | None] = mapped_column(String, nullable=True)
    has_owner_label: Mapped[str | None] = mapped_column(String, nullable=True)
    rolebinding_count: Mapped[str | None] = mapped_column(String, nullable=True)
    distinct_serviceaccounts: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="logical_project_isolation_records")


class EncryptionAtRest(Base):
    """OCP-46: cluster encryption-at-rest posture.

    ``record_type`` is one of ``etcd_encryption`` (cluster-scoped),
    ``storage_class``, ``machine_config_luks`` (LUKS / Tang / Clevis),
    or ``persistent_volume``. The ``detail_*`` columns carry record-type-
    specific evidence — see ``scripts/README.md``.
    """

    __tablename__ = "encryption_at_rest"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    name: Mapped[str | None] = mapped_column(String, nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_1: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_2: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_3: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_4: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_5: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_6: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="encryption_at_rest_records")


class ImageSigningVerification(Base):
    """OCP-48: image signing & verification posture.

    ``record_type`` is one of ``cluster_image_policy_signature``,
    ``build_config``, ``tekton_signing_task``, or
    ``registry_signature_config``. The ``detail_*`` columns carry
    record-type-specific evidence — see ``scripts/README.md``.
    """

    __tablename__ = "image_signing_verification"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    name: Mapped[str | None] = mapped_column(String, nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_1: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_2: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_3: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_4: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_5: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_6: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="image_signing_verification_records")


class BuildS2iPolicy(Base):
    """OCP-47: Build / Source-to-Image policy posture.

    ``record_type`` is one of ``build_default_config`` (cluster-scoped
    ``build.config.openshift.io``), ``build_config`` (per-namespace
    ``BuildConfig``), or ``image_stream_policy`` (``ImageStream``
    ``lookupPolicy.local`` and per-tag ``referencePolicy`` /
    ``importPolicy.insecure``). The ``detail_*`` columns carry record-
    type-specific evidence — see ``scripts/README.md``.
    """

    __tablename__ = "build_s2i_policy"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    name: Mapped[str | None] = mapped_column(String, nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_1: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_2: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_3: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_4: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_5: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_6: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="build_s2i_policy_records")


class EphemeralStorageLimits(Base):
    """OCP-49: per-namespace ephemeral-storage governance.

    One row per namespace. Captures whether a LimitRange supplies a
    default request / default limit / max for ``ephemeral-storage``,
    whether a ResourceQuota caps ``requests.ephemeral-storage`` and
    ``limits.ephemeral-storage``, and counts of pods with ``emptyDir``
    volumes (total and those without ``sizeLimit``) so notebooks can
    flag namespaces that allow unbounded ephemeral disk usage.
    """

    __tablename__ = "ephemeral_storage_limits"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    is_system_namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    has_lr_default_request: Mapped[str | None] = mapped_column(String, nullable=True)
    has_lr_default_limit: Mapped[str | None] = mapped_column(String, nullable=True)
    has_lr_max: Mapped[str | None] = mapped_column(String, nullable=True)
    lr_default_request: Mapped[str | None] = mapped_column(String, nullable=True)
    lr_default_limit: Mapped[str | None] = mapped_column(String, nullable=True)
    lr_max: Mapped[str | None] = mapped_column(String, nullable=True)
    has_quota_request: Mapped[str | None] = mapped_column(String, nullable=True)
    has_quota_limit: Mapped[str | None] = mapped_column(String, nullable=True)
    quota_request_hard: Mapped[str | None] = mapped_column(String, nullable=True)
    quota_limit_hard: Mapped[str | None] = mapped_column(String, nullable=True)
    emptydir_pods_total: Mapped[int | None] = mapped_column(Integer, nullable=True)
    emptydir_pods_without_sizelimit: Mapped[int | None] = mapped_column(Integer, nullable=True)

    cluster = relationship("Cluster", back_populates="ephemeral_storage_limits_records")


class AdmissionControllerHardening(Base):
    """OCP-50: admission controller hardening posture.

    ``record_type`` is one of ``apiserver_config`` (cluster-scoped
    ``apiserver`` resource), ``apiserver_admission_plugin`` (raw
    enable/disable plugin lists from ``kubeapiserver/cluster``),
    ``default_admission_plugin`` (per-plugin enabled/disabled/default
    state for the OCP 4.18 hardening defaults — LimitRanger,
    ResourceQuota, PodSecurity, NodeRestriction,
    MutatingAdmissionWebhook, ValidatingAdmissionWebhook), or
    ``validating_webhook`` / ``mutating_webhook`` (one row per webhook
    in each ValidatingWebhookConfiguration / MutatingWebhookConfiguration
    capturing failurePolicy, timeoutSeconds, sideEffects, scope,
    resources, namespaceSelector). The ``detail_*`` columns carry
    record-type-specific evidence — see ``scripts/README.md``.
    """

    __tablename__ = "admission_controller_hardening"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    name: Mapped[str | None] = mapped_column(String, nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_1: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_2: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_3: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_4: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_5: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_6: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="admission_controller_hardening_records")
