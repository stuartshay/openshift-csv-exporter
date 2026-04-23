"""Cluster Overview snapshot table."""

from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..database import Base


class ClusterOverview(Base):
    __tablename__ = "cluster_overview"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
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
