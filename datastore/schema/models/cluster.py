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
    patch_lifecycle_checks = relationship("PatchLifecycleCheck", back_populates="cluster")


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
