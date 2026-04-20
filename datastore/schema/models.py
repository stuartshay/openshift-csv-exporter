"""SQLAlchemy ORM models for OCP audit data.

Tables
------
Shared:
    clusters                          – deduplicated cluster identity
    cluster_env                       – environment label per cluster

Cluster Overview:
    cluster_overview                  – one row per cluster snapshot

OCP-1  OAuth External Auth:
    oauth_external_auth               – one row per IDP per cluster

OCP-2  ClusterRoles (normalised):
    clusterroles                      – one row per unique role
    clusterrole_rules                 – one row per RBAC rule
    clusterrole_rule_api_groups       – junction (split ';'-delimited)
    clusterrole_rule_resources        – junction
    clusterrole_rule_verbs            – junction
    clusterrole_rule_non_resource_urls – junction

OCP-2  ClusterRoleBindings:
    clusterrolebindings               – one row per binding
    clusterrolebinding_subjects       – one row per subject

OCP-2  Self-Provisioners:
    self_provisioner_bindings         – one row per cluster
    self_provisioner_subjects         – subjects of that binding
"""

from sqlalchemy import Boolean, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


# ── Shared ────────────────────────────────────────────────────────────────────


class Cluster(Base):
    __tablename__ = "clusters"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_name: Mapped[str] = mapped_column(String, nullable=False)
    cluster_context: Mapped[str] = mapped_column(String, nullable=False)
    cluster_server: Mapped[str] = mapped_column(String, nullable=False)

    __table_args__ = (
        UniqueConstraint("cluster_name", "cluster_context", "cluster_server"),
    )

    # relationships
    cluster_env = relationship("ClusterEnv", back_populates="cluster", uselist=False)
    cluster_overviews = relationship("ClusterOverview", back_populates="cluster")
    oauth_external_auths = relationship("OAuthExternalAuth", back_populates="cluster")
    clusterroles = relationship("ClusterRole", back_populates="cluster")
    clusterrolebindings = relationship("ClusterRoleBinding", back_populates="cluster")
    self_provisioner_bindings = relationship(
        "SelfProvisionerBinding", back_populates="cluster"
    )


class ClusterEnv(Base):
    __tablename__ = "cluster_env"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("clusters.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    env: Mapped[str] = mapped_column(String, nullable=False)
    friendly_name: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="cluster_env")


# ── Cluster Overview ──────────────────────────────────────────────────────────


class ClusterOverview(Base):
    __tablename__ = "cluster_overview"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False
    )
    ocp_version: Mapped[str | None] = mapped_column(String, nullable=True)
    kubernetes_version: Mapped[str | None] = mapped_column(String, nullable=True)
    cluster_id_ocp: Mapped[str | None] = mapped_column(String, nullable=True)
    install_date: Mapped[str | None] = mapped_column(String, nullable=True)
    cluster_age_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    platform: Mapped[str | None] = mapped_column(String, nullable=True)
    control_plane_topology: Mapped[str | None] = mapped_column(String, nullable=True)
    infrastructure_topology: Mapped[str | None] = mapped_column(String, nullable=True)
    master_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    worker_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    infra_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    total_node_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    network_type: Mapped[str | None] = mapped_column(String, nullable=True)
    cluster_cidrs: Mapped[str | None] = mapped_column(String, nullable=True)
    service_cidrs: Mapped[str | None] = mapped_column(String, nullable=True)
    default_ingress_domain: Mapped[str | None] = mapped_column(String, nullable=True)
    console_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    api_server_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    update_channel: Mapped[str | None] = mapped_column(String, nullable=True)
    available_updates_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    update_state: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="cluster_overviews")


# ── OCP-1: OAuth External Auth ───────────────────────────────────────────────


class OAuthExternalAuth(Base):
    __tablename__ = "oauth_external_auth"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False
    )
    external_auth_enforced: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    kubeadmin_removed: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    identity_providers_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    idp_name: Mapped[str | None] = mapped_column(String, nullable=True)
    idp_type: Mapped[str | None] = mapped_column(String, nullable=True)
    idp_mapping_method: Mapped[str | None] = mapped_column(String, nullable=True)
    idp_issuer: Mapped[str | None] = mapped_column(Text, nullable=True)
    idp_client_id: Mapped[str | None] = mapped_column(String, nullable=True)
    access_token_max_age_seconds: Mapped[int | None] = mapped_column(
        Integer, nullable=True
    )

    cluster = relationship("Cluster", back_populates="oauth_external_auths")


# ── OCP-2: ClusterRoles (normalised) ─────────────────────────────────────────


class ClusterRole(Base):
    __tablename__ = "clusterroles"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False
    )
    role_name: Mapped[str] = mapped_column(String, nullable=False)
    creation_timestamp: Mapped[str | None] = mapped_column(String, nullable=True)

    __table_args__ = (UniqueConstraint("cluster_id", "role_name"),)

    cluster = relationship("Cluster", back_populates="clusterroles")
    rules = relationship(
        "ClusterRoleRule", back_populates="clusterrole", cascade="all, delete-orphan"
    )


class ClusterRoleRule(Base):
    __tablename__ = "clusterrole_rules"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    clusterrole_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("clusterroles.id", ondelete="CASCADE"), nullable=False
    )

    clusterrole = relationship("ClusterRole", back_populates="rules")
    api_groups = relationship(
        "ClusterRoleRuleApiGroup",
        back_populates="rule",
        cascade="all, delete-orphan",
    )
    resources = relationship(
        "ClusterRoleRuleResource",
        back_populates="rule",
        cascade="all, delete-orphan",
    )
    verbs = relationship(
        "ClusterRoleRuleVerb",
        back_populates="rule",
        cascade="all, delete-orphan",
    )
    non_resource_urls = relationship(
        "ClusterRoleRuleNonResourceUrl",
        back_populates="rule",
        cascade="all, delete-orphan",
    )


class ClusterRoleRuleApiGroup(Base):
    __tablename__ = "clusterrole_rule_api_groups"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    rule_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("clusterrole_rules.id", ondelete="CASCADE"),
        nullable=False,
    )
    api_group: Mapped[str] = mapped_column(String, nullable=False)

    rule = relationship("ClusterRoleRule", back_populates="api_groups")


class ClusterRoleRuleResource(Base):
    __tablename__ = "clusterrole_rule_resources"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    rule_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("clusterrole_rules.id", ondelete="CASCADE"),
        nullable=False,
    )
    resource: Mapped[str] = mapped_column(String, nullable=False)

    rule = relationship("ClusterRoleRule", back_populates="resources")


class ClusterRoleRuleVerb(Base):
    __tablename__ = "clusterrole_rule_verbs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    rule_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("clusterrole_rules.id", ondelete="CASCADE"),
        nullable=False,
    )
    verb: Mapped[str] = mapped_column(String, nullable=False)

    rule = relationship("ClusterRoleRule", back_populates="verbs")


class ClusterRoleRuleNonResourceUrl(Base):
    __tablename__ = "clusterrole_rule_non_resource_urls"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    rule_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("clusterrole_rules.id", ondelete="CASCADE"),
        nullable=False,
    )
    non_resource_url: Mapped[str] = mapped_column(String, nullable=False)

    rule = relationship("ClusterRoleRule", back_populates="non_resource_urls")


# ── OCP-2: ClusterRoleBindings ────────────────────────────────────────────────


class ClusterRoleBinding(Base):
    __tablename__ = "clusterrolebindings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False
    )
    binding_name: Mapped[str] = mapped_column(String, nullable=False)
    role_ref_kind: Mapped[str | None] = mapped_column(String, nullable=True)
    role_ref_name: Mapped[str | None] = mapped_column(String, nullable=True)

    __table_args__ = (UniqueConstraint("cluster_id", "binding_name"),)

    cluster = relationship("Cluster", back_populates="clusterrolebindings")
    subjects = relationship(
        "ClusterRoleBindingSubject",
        back_populates="clusterrolebinding",
        cascade="all, delete-orphan",
    )


class ClusterRoleBindingSubject(Base):
    __tablename__ = "clusterrolebinding_subjects"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    clusterrolebinding_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("clusterrolebindings.id", ondelete="CASCADE"),
        nullable=False,
    )
    subject_kind: Mapped[str | None] = mapped_column(String, nullable=True)
    subject_name: Mapped[str | None] = mapped_column(String, nullable=True)
    subject_namespace: Mapped[str | None] = mapped_column(String, nullable=True)

    clusterrolebinding = relationship("ClusterRoleBinding", back_populates="subjects")


# ── OCP-2: Self-Provisioners ─────────────────────────────────────────────────


class SelfProvisionerBinding(Base):
    __tablename__ = "self_provisioner_bindings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False
    )
    binding_name: Mapped[str | None] = mapped_column(String, nullable=True)
    role_ref_kind: Mapped[str | None] = mapped_column(String, nullable=True)
    role_ref_name: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="self_provisioner_bindings")
    subjects = relationship(
        "SelfProvisionerSubject",
        back_populates="binding",
        cascade="all, delete-orphan",
    )


class SelfProvisionerSubject(Base):
    __tablename__ = "self_provisioner_subjects"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    binding_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("self_provisioner_bindings.id", ondelete="CASCADE"),
        nullable=False,
    )
    subject_kind: Mapped[str | None] = mapped_column(String, nullable=True)
    subject_name: Mapped[str | None] = mapped_column(String, nullable=True)
    subject_namespace: Mapped[str | None] = mapped_column(String, nullable=True)

    binding = relationship("SelfProvisionerBinding", back_populates="subjects")
