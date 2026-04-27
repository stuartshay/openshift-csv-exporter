"""OCP-6 (Platform Usage Guardrails) and OCP-7 (Policy-as-Code Enforcement)."""

from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..database import Base


class PlatformGuardrail(Base):
    """One row per cluster: posture against unapproved OCP distribution use
    and misconfigured cluster components (degraded / unavailable operators)."""

    __tablename__ = "platform_guardrails"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    ocp_version: Mapped[str | None] = mapped_column(String, nullable=True)
    cluster_id_ocp: Mapped[str | None] = mapped_column(String, nullable=True)
    update_channel: Mapped[str | None] = mapped_column(String, nullable=True)
    update_state: Mapped[str | None] = mapped_column(String, nullable=True)
    platform: Mapped[str | None] = mapped_column(String, nullable=True)
    control_plane_topology: Mapped[str | None] = mapped_column(String, nullable=True)
    infrastructure_topology: Mapped[str | None] = mapped_column(String, nullable=True)
    total_operators: Mapped[int | None] = mapped_column(Integer, nullable=True)
    degraded_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    unavailable_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    degraded_operators: Mapped[str | None] = mapped_column(Text, nullable=True)
    unavailable_operators: Mapped[str | None] = mapped_column(Text, nullable=True)

    cluster = relationship("Cluster", back_populates="platform_guardrails")


class PolicyAsCodeConstraint(Base):
    """One row per (cluster, ConstraintTemplate, Constraint) for OPA Gatekeeper.

    When Gatekeeper is not installed a single row is written with
    ``gatekeeper_installed=False`` and the constraint fields empty.
    """

    __tablename__ = "policy_as_code_constraints"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cluster_id: Mapped[int] = mapped_column(Integer, ForeignKey("clusters.id", ondelete="CASCADE"), nullable=False)
    gatekeeper_installed: Mapped[bool | None] = mapped_column(nullable=True)
    gatekeeper_namespace: Mapped[str | None] = mapped_column(String, nullable=True)
    constraint_template: Mapped[str | None] = mapped_column(String, nullable=True)
    constraint_name: Mapped[str | None] = mapped_column(String, nullable=True)
    enforcement_action: Mapped[str | None] = mapped_column(String, nullable=True)
    total_violations: Mapped[int | None] = mapped_column(Integer, nullable=True)
    match_kinds: Mapped[str | None] = mapped_column(Text, nullable=True)
    match_namespaces: Mapped[str | None] = mapped_column(Text, nullable=True)

    cluster = relationship("Cluster", back_populates="policy_as_code_constraints")
