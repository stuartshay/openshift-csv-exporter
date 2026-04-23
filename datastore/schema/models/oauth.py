"""OCP-1: OAuth External Auth."""

from sqlalchemy import Boolean, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..database import Base


class OAuthExternalAuth(Base):
    __tablename__ = "oauth_external_auth"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    external_auth_enforced: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    kubeadmin_removed: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    identity_providers_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    idp_name: Mapped[str | None] = mapped_column(String, nullable=True)
    idp_type: Mapped[str | None] = mapped_column(String, nullable=True)
    idp_mapping_method: Mapped[str | None] = mapped_column(String, nullable=True)
    idp_issuer: Mapped[str | None] = mapped_column(Text, nullable=True)
    idp_client_id: Mapped[str | None] = mapped_column(String, nullable=True)
    access_token_max_age_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)

    cluster = relationship("Cluster", back_populates="oauth_external_auths")
