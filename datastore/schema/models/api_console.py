"""OCP-3: API & Console Access Restriction."""

from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..database import Base


class ApiServerConsoleAccess(Base):
    __tablename__ = "apiserver_console_access"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    api_server_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    console_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    tls_security_profile_type: Mapped[str | None] = mapped_column(String, nullable=True)
    tls_min_version: Mapped[str | None] = mapped_column(String, nullable=True)
    audit_profile: Mapped[str | None] = mapped_column(String, nullable=True)
    client_ca_name: Mapped[str | None] = mapped_column(String, nullable=True)
    encryption_type: Mapped[str | None] = mapped_column(String, nullable=True)
    additional_cors_origins: Mapped[str | None] = mapped_column(Text, nullable=True)
    serving_certs_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    cluster_admin_binding_count: Mapped[int | None] = mapped_column(Integer, nullable=True)

    cluster = relationship("Cluster", back_populates="apiserver_console_access")
