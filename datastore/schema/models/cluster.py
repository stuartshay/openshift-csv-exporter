"""Shared cluster identity and environment labels."""

from sqlalchemy import Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..database import Base


class Cluster(Base):
    __tablename__ = "clusters"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_name: Mapped[str] = mapped_column(String, nullable=False)
    cluster_context: Mapped[str] = mapped_column(String, nullable=False)
    cluster_server: Mapped[str] = mapped_column(String, nullable=False, unique=True)

    __table_args__ = (UniqueConstraint("cluster_server"),)

    # relationships
    cluster_overviews = relationship("ClusterOverview", back_populates="cluster")
    oauth_external_auths = relationship("OAuthExternalAuth", back_populates="cluster")
    clusterroles = relationship("ClusterRole", back_populates="cluster")
    clusterrolebindings = relationship("ClusterRoleBinding", back_populates="cluster")
    self_provisioner_bindings = relationship("SelfProvisionerBinding", back_populates="cluster")
    apiserver_console_access = relationship("ApiServerConsoleAccess", back_populates="cluster")
    worker_node_auths = relationship("WorkerNodeAuth", back_populates="cluster")
    credential_management_secrets = relationship("CredentialManagementSecret", back_populates="cluster")
    cluster_admin_bindings = relationship("ClusterAdminBinding", back_populates="cluster")
    platform_guardrails = relationship("PlatformGuardrail", back_populates="cluster")
    policy_as_code_constraints = relationship("PolicyAsCodeConstraint", back_populates="cluster")
    cicd_pipeline_detections = relationship("CICDPipelineDetection", back_populates="cluster")
    control_plane_protections = relationship("ControlPlaneProtection", back_populates="cluster")
    etcd_encryption_status_records = relationship("EtcdEncryptionStatus", back_populates="cluster")
    patch_lifecycle_checks = relationship("PatchLifecycleCheck", back_populates="cluster")
    secrets_cert_rotations = relationship("SecretsCertRotation", back_populates="cluster")
    disaster_recovery_backups = relationship("DisasterRecoveryBackup", back_populates="cluster")
    olm_governance = relationship("OlmGovernance", back_populates="cluster")
    governance_policy_ecosystem = relationship("GovernancePolicyEcosystem", back_populates="cluster")
    monitoring_audit_logging_records = relationship("MonitoringAuditLogging", back_populates="cluster")
    configuration_drift_status_records = relationship("ConfigurationDriftStatus", back_populates="cluster")
    vulnerability_runtime_detection_records = relationship("VulnerabilityRuntimeDetection", back_populates="cluster")
    network_security_mesh_records = relationship("NetworkSecurityMesh", back_populates="cluster")
    ingress_boundary_protection_records = relationship("IngressBoundaryProtection", back_populates="cluster")
    scc_privileged_records = relationship("SccPrivileged", back_populates="cluster")
    workload_resource_quota_records = relationship("WorkloadResourceQuota", back_populates="cluster")
    trusted_image_enforcement_records = relationship("TrustedImageEnforcement", back_populates="cluster")
    pod_security_admission_records = relationship("PodSecurityAdmission", back_populates="cluster")
    logical_project_isolation_records = relationship("LogicalProjectIsolation", back_populates="cluster")
    encryption_at_rest_records = relationship("EncryptionAtRest", back_populates="cluster")
    image_signing_verification_records = relationship("ImageSigningVerification", back_populates="cluster")


class ClusterEnv(Base):
    """Environment label keyed on ``cluster_server`` (the OCP API URL).

    One row per real cluster, independent of how many kubeconfig contexts
    (and therefore ``clusters`` rows) reference that same API URL.
    """

    __tablename__ = "cluster_env"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_server: Mapped[str] = mapped_column(String, nullable=False, unique=True)
    env: Mapped[str] = mapped_column(String, nullable=False)
    friendly_name: Mapped[str | None] = mapped_column(String, nullable=True)
