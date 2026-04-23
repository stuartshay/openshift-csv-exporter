"""OCP-5: Cluster Admin/SRE Credential Management."""

from sqlalchemy import Boolean, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..database import Base


class CredentialManagementSecret(Base):
    __tablename__ = "credential_management_secrets"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    kubeadmin_exists: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    secret_name: Mapped[str | None] = mapped_column(String, nullable=True)
    secret_type: Mapped[str | None] = mapped_column(String, nullable=True)
    creation_timestamp: Mapped[str | None] = mapped_column(String, nullable=True)
    age_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    service_account: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="credential_management_secrets")


class ClusterAdminBinding(Base):
    __tablename__ = "cluster_admin_bindings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    binding_name: Mapped[str | None] = mapped_column(String, nullable=True)
    role_ref_name: Mapped[str | None] = mapped_column(String, nullable=True)
    subject_kind: Mapped[str | None] = mapped_column(String, nullable=True)
    subject_name: Mapped[str | None] = mapped_column(String, nullable=True)
    subject_namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    creation_timestamp: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="cluster_admin_bindings")
