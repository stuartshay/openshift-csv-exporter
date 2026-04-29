"""Operations & lifecycle audit areas (OCP-11 through OCP-13)."""

from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..database import Base


class SecretsCertRotation(Base):
    """OCP-11: one row per secret / CSR captured by ``export-secrets-cert-rotation.sh``.

    ``record_type`` is either ``secret`` (TLS / cert secret in a control-plane
    namespace) or ``csr`` (kubelet-client CertificateSigningRequest).
    """

    __tablename__ = "secrets_cert_rotations"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    resource_name: Mapped[str | None] = mapped_column(String, nullable=True)
    secret_type: Mapped[str | None] = mapped_column(String, nullable=True)
    creation_timestamp: Mapped[str | None] = mapped_column(String, nullable=True)
    age_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    signer_name: Mapped[str | None] = mapped_column(String, nullable=True)
    requestor: Mapped[str | None] = mapped_column(String, nullable=True)
    condition: Mapped[str | None] = mapped_column(String, nullable=True)
    annotations_rotation: Mapped[str | None] = mapped_column(Text, nullable=True)

    cluster = relationship("Cluster", back_populates="secrets_cert_rotations")


class DisasterRecoveryBackup(Base):
    """OCP-12: one row per disaster-recovery / backup record.

    ``record_type`` covers ``operator`` (OADP install posture),
    ``backup_location``, ``backup``, and ``etcd_backup`` rows.
    """

    __tablename__ = "disaster_recovery_backups"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    resource_name: Mapped[str | None] = mapped_column(String, nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    condition_available: Mapped[bool | None] = mapped_column(nullable=True)
    condition_degraded: Mapped[bool | None] = mapped_column(nullable=True)
    condition_progressing: Mapped[bool | None] = mapped_column(nullable=True)
    detail: Mapped[str | None] = mapped_column(Text, nullable=True)
    message: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_transition: Mapped[str | None] = mapped_column(String, nullable=True)
    age_days: Mapped[int | None] = mapped_column(Integer, nullable=True)

    cluster = relationship("Cluster", back_populates="disaster_recovery_backups")


class OlmGovernance(Base):
    """OCP-13: one row per OLM resource (CatalogSource, Subscription, CSV).

    ``detail_1`` .. ``detail_7`` capture free-form ``key=value`` flags written
    by ``export-olm-governance.sh``.
    """

    __tablename__ = "olm_governance"

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
    detail_7: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="olm_governance")
