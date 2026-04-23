"""OCP-2: ClusterRoles (normalised), ClusterRoleBindings, Self-Provisioners."""

from sqlalchemy import ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..database import Base


class ClusterRole(Base):
    __tablename__ = "clusterroles"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    role_name: Mapped[str] = mapped_column(String, nullable=False)
    creation_timestamp: Mapped[str | None] = mapped_column(String, nullable=True)

    __table_args__ = (UniqueConstraint("cluster_id", "role_name"),)

    cluster = relationship("Cluster", back_populates="clusterroles")
    rules = relationship("ClusterRoleRule", back_populates="clusterrole", cascade="all, delete-orphan")


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


class ClusterRoleBinding(Base):
    __tablename__ = "clusterrolebindings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
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


class SelfProvisionerBinding(Base):
    __tablename__ = "self_provisioner_bindings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
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
