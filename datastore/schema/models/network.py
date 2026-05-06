"""Network security audit areas (OCP-30 Network Port Restriction,
OCP-31 Service Mesh Enforcement, OCP-32 Native Network Policies, and the
broader Network Security scorecard items)."""

from sqlalchemy import ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..database import Base


class NetworkSecurityMesh(Base):
    """OCP-30 / OCP-31 / OCP-32: one row per network security or service-mesh record.

    Sourced from ``export-network-security-mesh.sh``. ``record_type`` covers
    ``cni``, ``operator`` (e.g. ``servicemesh-operator``), ``smcp``
    (ServiceMeshControlPlane), ``networkpolicy_count``, and
    ``egress_firewall_count``. ``detail_1..detail_4`` carry free-form
    ``key=value`` flags emitted by the export script.
    """

    __tablename__ = "network_security_mesh"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    component_name: Mapped[str | None] = mapped_column(String, nullable=True)
    status: Mapped[str | None] = mapped_column(String, nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_1: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_2: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_3: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_4: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="network_security_mesh_records")


class IngressBoundaryProtection(Base):
    """OCP-30 / External Egress-Ingress Boundary Protection / Internal Service
    Exposure Control: one row per ingress, route, or WAF record.

    Sourced from ``export-ingress-boundary-protection.sh``. ``record_type``
    covers ``ingresscontroller``, ``route_count``, ``insecure_routes``, and
    ``waf``. ``detail_1..detail_4`` carry free-form ``key=value`` flags
    emitted by the export script.
    """

    __tablename__ = "ingress_boundary_protection"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    record_type: Mapped[str | None] = mapped_column(String, nullable=True)
    component_name: Mapped[str | None] = mapped_column(String, nullable=True)
    status: Mapped[str | None] = mapped_column(String, nullable=True)
    namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_1: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_2: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_3: Mapped[str | None] = mapped_column(String, nullable=True)
    detail_4: Mapped[str | None] = mapped_column(String, nullable=True)

    cluster = relationship("Cluster", back_populates="ingress_boundary_protection_records")
