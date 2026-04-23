"""OCP-4: Worker Node AuthN/AuthZ."""

from sqlalchemy import Boolean, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..database import Base


class WorkerNodeAuth(Base):
    __tablename__ = "worker_node_auth"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    node_name: Mapped[str] = mapped_column(String, nullable=False)
    node_roles: Mapped[str | None] = mapped_column(String, nullable=True)
    kubelet_version: Mapped[str | None] = mapped_column(String, nullable=True)
    ready_status: Mapped[str | None] = mapped_column(String, nullable=True)
    internal_ip: Mapped[str | None] = mapped_column(String, nullable=True)
    creation_timestamp: Mapped[str | None] = mapped_column(String, nullable=True)
    machine_config_state: Mapped[str | None] = mapped_column(String, nullable=True)
    current_config: Mapped[str | None] = mapped_column(String, nullable=True)
    desired_config: Mapped[str | None] = mapped_column(String, nullable=True)
    configs_match: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    kubelet_config_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    anonymous_auth: Mapped[str | None] = mapped_column(String, nullable=True)
    authorization_mode: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="worker_node_auths")
