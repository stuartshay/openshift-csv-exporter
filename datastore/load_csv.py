"""Load CSV export files into the OCP audit SQLite database.

Reads CSV files from a directory (default: ``data/``) and inserts rows into
the normalised schema.  Each loader function handles one report type:

- ``cluster-overview-*.csv``     -> cluster_overview
- ``oauth-external-auth-*.csv``  -> oauth_external_auth
- ``clusterroles-*.csv``         -> clusterroles + junction tables
- ``clusterrolebindings-*.csv``  -> clusterrolebindings + subjects
- ``clusterrolebinding-self-provisioners-*.csv`` -> self_provisioner + subjects
- ``apiserver-console-access-*.csv`` -> apiserver_console_access
- ``worker-node-auth-*.csv``      -> worker_node_auth
- ``credential-management-*.csv`` -> credential_management_secrets
- ``cluster-admin-bindings-*.csv`` -> cluster_admin_bindings
- ``etcd-encryption-status-*.csv`` -> etcd_encryption_status
"""

from __future__ import annotations

import csv
import glob
import os
import sys
from pathlib import Path

from schema.database import Base, SessionLocal, engine
from schema.models import (
    AdmissionControllerHardening,
    ApiServerConsoleAccess,
    BuildS2iPolicy,
    CICDPipelineDetection,
    Cluster,
    ClusterAdminBinding,
    ClusterOverview,
    ClusterRole,
    ClusterRoleBinding,
    ClusterRoleBindingSubject,
    ClusterRoleRule,
    ClusterRoleRuleApiGroup,
    ClusterRoleRuleNonResourceUrl,
    ClusterRoleRuleResource,
    ClusterRoleRuleVerb,
    ConfigurationDriftStatus,
    ControlPlaneProtection,
    CredentialManagementSecret,
    DisasterRecoveryBackup,
    EncryptionAtRest,
    EphemeralStorageLimits,
    EtcdEncryptionStatus,
    GovernancePolicyEcosystem,
    ImageSigningVerification,
    IngressBoundaryProtection,
    LogicalProjectIsolation,
    MonitoringAuditLogging,
    NetworkSecurityMesh,
    OAuthExternalAuth,
    OlmGovernance,
    PatchLifecycleCheck,
    PlatformGuardrail,
    PodSecurityAdmission,
    PolicyAsCodeConstraint,
    SccPrivileged,
    SecretsCertRotation,
    SelfProvisionerBinding,
    SelfProvisionerSubject,
    TrustedImageEnforcement,
    VulnerabilityRuntimeDetection,
    WorkerNodeAuth,
    WorkloadResourceQuota,
)
from sqlalchemy.orm import Session

DATA_DIR = os.environ.get("OCP_DATA_DIR", "data")

# Directory layout under DATA_DIR:
#   - "nested" (default): recurse into per-environment / per-cluster sub-folders,
#     e.g. data/DEV-DNA/aws-useast1-datalake-dev-1/cluster-overview-*.csv
#   - "flat": legacy layout where every CSV sits directly in DATA_DIR.
# Override with OCP_DATA_LAYOUT=flat to restore the original behaviour.
DATA_LAYOUT = os.environ.get("OCP_DATA_LAYOUT", "nested").strip().lower()


# -- Helpers ----------------------------------------------------------------


def _get_or_create_cluster(
    session: Session,
    name: str,
    context: str,
    server: str,
) -> Cluster:
    """Return existing Cluster (matched by ``cluster_server``) or create one.

    ``cluster_server`` (the OCP API URL) is the stable identity of a cluster.
    ``cluster_name`` and ``cluster_context`` vary per kubeconfig context (e.g.
    ``default/api-...`` vs ``sshay/api-...``) and must NOT be part of the
    dedup key — otherwise the same real cluster ends up with multiple rows.
    """
    cluster = session.query(Cluster).filter_by(cluster_server=server).first()
    if cluster is None:
        cluster = Cluster(
            cluster_name=name,
            cluster_context=context,
            cluster_server=server,
        )
        session.add(cluster)
        session.flush()
    return cluster


def _split(value: str) -> list[str]:
    """Split a ';'-delimited CSV cell, dropping empties."""
    if not value:
        return []
    return [v.strip() for v in value.split(";") if v.strip()]


def _to_bool(value: str) -> bool | None:
    """Convert a CSV string to a Python bool."""
    if not value:
        return None
    return value.lower() in ("true", "1", "yes")


def _to_int(value: str) -> int | None:
    """Convert a CSV string to int or None."""
    if not value:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def _find_csvs(pattern: str) -> list[str]:
    """Sorted CSV files matching *pattern* inside DATA_DIR.

    When ``OCP_DATA_LAYOUT`` is ``nested`` (default) the search recurses into
    per-environment / per-cluster sub-folders, so a call with
    ``"cluster-overview-*.csv"`` will also match
    ``data/DEV-DNA/aws-useast1-datalake-dev-1/cluster-overview-*.csv``.
    When set to ``flat`` only files directly in ``DATA_DIR`` are returned.
    """
    if DATA_LAYOUT == "flat":
        return sorted(glob.glob(os.path.join(DATA_DIR, pattern)))
    # nested: match either directly in DATA_DIR or any sub-directory.
    top = glob.glob(os.path.join(DATA_DIR, pattern))
    nested = glob.glob(os.path.join(DATA_DIR, "**", pattern), recursive=True)
    return sorted(set(top) | set(nested))


# -- Loaders ----------------------------------------------------------------


def load_cluster_overview(session: Session) -> int:
    """Load cluster-overview CSVs. Returns row count."""
    files = _find_csvs("cluster-overview-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    ClusterOverview(
                        cluster_id=cluster.id,
                        ocp_version=row.get("ocp_version") or None,
                        kubernetes_version=row.get("kubernetes_version") or None,
                        cluster_id_ocp=row.get("cluster_id") or None,
                        install_date=row.get("install_date") or None,
                        cluster_age_days=_to_int(
                            row.get("cluster_age_days", ""),
                        ),
                        platform=row.get("platform") or None,
                        control_plane_topology=(row.get("control_plane_topology") or None),
                        infrastructure_topology=(row.get("infrastructure_topology") or None),
                        master_count=_to_int(row.get("master_count", "")),
                        worker_count=_to_int(row.get("worker_count", "")),
                        infra_count=_to_int(row.get("infra_count", "")),
                        total_node_count=_to_int(
                            row.get("total_node_count", ""),
                        ),
                        network_type=row.get("network_type") or None,
                        cluster_cidrs=row.get("cluster_cidrs") or None,
                        service_cidrs=row.get("service_cidrs") or None,
                        default_ingress_domain=(row.get("default_ingress_domain") or None),
                        console_url=row.get("console_url") or None,
                        api_server_url=row.get("api_server_url") or None,
                        update_channel=row.get("update_channel") or None,
                        available_updates_count=_to_int(
                            row.get("available_updates_count", ""),
                        ),
                        update_state=row.get("update_state") or None,
                    )
                )
                count += 1
    return count


def load_oauth_external_auth(session: Session) -> int:
    """Load oauth-external-auth CSVs. Returns row count."""
    files = _find_csvs("oauth-external-auth-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    OAuthExternalAuth(
                        cluster_id=cluster.id,
                        external_auth_enforced=_to_bool(
                            row["external_auth_enforced"],
                        ),
                        kubeadmin_removed=_to_bool(
                            row["kubeadmin_removed"],
                        ),
                        identity_providers_count=_to_int(
                            row["identity_providers_count"],
                        ),
                        idp_name=row.get("idp_name") or None,
                        idp_type=row.get("idp_type") or None,
                        idp_mapping_method=(row.get("idp_mapping_method") or None),
                        idp_issuer=row.get("idp_issuer") or None,
                        idp_client_id=(row.get("idp_client_id") or None),
                        access_token_max_age_seconds=_to_int(
                            row.get("access_token_max_age_seconds", ""),
                        ),
                    )
                )
                count += 1
    return count


def load_clusterroles(session: Session) -> int:
    """Load clusterroles CSVs. Returns rule-row count."""
    files = _find_csvs("clusterroles-*.csv")
    count = 0
    role_cache: dict[tuple[int, str], ClusterRole] = {}

    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                role_key = (cluster.id, row["role_name"])
                if role_key not in role_cache:
                    role = ClusterRole(
                        cluster_id=cluster.id,
                        role_name=row["role_name"],
                        creation_timestamp=(row.get("creation_timestamp") or None),
                    )
                    session.add(role)
                    session.flush()
                    role_cache[role_key] = role
                else:
                    role = role_cache[role_key]

                rule = ClusterRoleRule(clusterrole_id=role.id)
                session.add(rule)
                session.flush()

                for v in _split(row.get("api_groups", "")):
                    session.add(
                        ClusterRoleRuleApiGroup(
                            rule_id=rule.id,
                            api_group=v,
                        )
                    )
                for v in _split(row.get("resources", "")):
                    session.add(
                        ClusterRoleRuleResource(
                            rule_id=rule.id,
                            resource=v,
                        )
                    )
                for v in _split(row.get("verbs", "")):
                    session.add(
                        ClusterRoleRuleVerb(
                            rule_id=rule.id,
                            verb=v,
                        )
                    )
                for v in _split(
                    row.get("non_resource_urls", ""),
                ):
                    session.add(
                        ClusterRoleRuleNonResourceUrl(
                            rule_id=rule.id,
                            non_resource_url=v,
                        )
                    )
                count += 1
    return count


def load_clusterrolebindings(session: Session) -> int:
    """Load clusterrolebindings CSVs. Returns subject-row count."""
    files = _find_csvs("clusterrolebindings-*.csv")
    count = 0
    cache: dict[tuple[int, str], ClusterRoleBinding] = {}

    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                key = (cluster.id, row["binding_name"])
                if key not in cache:
                    binding = ClusterRoleBinding(
                        cluster_id=cluster.id,
                        binding_name=row["binding_name"],
                        role_ref_kind=(row.get("role_ref_kind") or None),
                        role_ref_name=(row.get("role_ref_name") or None),
                    )
                    session.add(binding)
                    session.flush()
                    cache[key] = binding
                else:
                    binding = cache[key]

                session.add(
                    ClusterRoleBindingSubject(
                        clusterrolebinding_id=binding.id,
                        subject_kind=(row.get("subject_kind") or None),
                        subject_name=(row.get("subject_name") or None),
                        subject_namespace=(row.get("subject_namespace") or None),
                    )
                )
                count += 1
    return count


def load_self_provisioners(session: Session) -> int:
    """Load self-provisioners CSVs. Returns subject-row count."""
    files = _find_csvs(
        "clusterrolebinding-self-provisioners-*.csv",
    )
    count = 0
    cache: dict[tuple[int, str], SelfProvisionerBinding] = {}

    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                key = (
                    cluster.id,
                    row.get("binding_name", ""),
                )
                if key not in cache:
                    binding = SelfProvisionerBinding(
                        cluster_id=cluster.id,
                        binding_name=(row.get("binding_name") or None),
                        role_ref_kind=(row.get("role_ref_kind") or None),
                        role_ref_name=(row.get("role_ref_name") or None),
                    )
                    session.add(binding)
                    session.flush()
                    cache[key] = binding
                else:
                    binding = cache[key]

                session.add(
                    SelfProvisionerSubject(
                        binding_id=binding.id,
                        subject_kind=(row.get("subject_kind") or None),
                        subject_name=(row.get("subject_name") or None),
                        subject_namespace=(row.get("subject_namespace") or None),
                    )
                )
                count += 1
    return count


def load_apiserver_console_access(session: Session) -> int:
    """Load apiserver-console-access CSVs. Returns row count."""
    files = _find_csvs("apiserver-console-access-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    ApiServerConsoleAccess(
                        cluster_id=cluster.id,
                        api_server_url=row.get("api_server_url") or None,
                        console_url=row.get("console_url") or None,
                        tls_security_profile_type=(row.get("tls_security_profile_type") or None),
                        tls_min_version=row.get("tls_min_version") or None,
                        audit_profile=row.get("audit_profile") or None,
                        client_ca_name=row.get("client_ca_name") or None,
                        encryption_type=row.get("encryption_type") or None,
                        additional_cors_origins=(row.get("additional_cors_origins") or None),
                        serving_certs_count=_to_int(
                            row.get("serving_certs_count", ""),
                        ),
                        cluster_admin_binding_count=_to_int(
                            row.get("cluster_admin_binding_count", ""),
                        ),
                    )
                )
                count += 1
    return count


def load_worker_node_auth(session: Session) -> int:
    """Load worker-node-auth CSVs. Returns row count."""
    files = _find_csvs("worker-node-auth-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    WorkerNodeAuth(
                        cluster_id=cluster.id,
                        node_name=row["node_name"],
                        node_roles=row.get("node_roles") or None,
                        kubelet_version=row.get("kubelet_version") or None,
                        ready_status=row.get("ready_status") or None,
                        internal_ip=row.get("internal_ip") or None,
                        creation_timestamp=(row.get("creation_timestamp") or None),
                        machine_config_state=(row.get("machine_config_state") or None),
                        current_config=row.get("current_config") or None,
                        desired_config=row.get("desired_config") or None,
                        configs_match=_to_bool(row.get("configs_match", "")),
                        kubelet_config_count=_to_int(
                            row.get("kubelet_config_count", ""),
                        ),
                        anonymous_auth=row.get("anonymous_auth") or None,
                        authorization_mode=(row.get("authorization_mode") or None),
                    )
                )
                count += 1
    return count


def load_credential_management(session: Session) -> int:
    """Load credential-management CSVs. Returns row count."""
    files = _find_csvs("credential-management-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    CredentialManagementSecret(
                        cluster_id=cluster.id,
                        kubeadmin_exists=_to_bool(
                            row.get("kubeadmin_exists", ""),
                        ),
                        namespace=row.get("namespace") or None,
                        secret_name=row.get("secret_name") or None,
                        secret_type=row.get("secret_type") or None,
                        creation_timestamp=(row.get("creation_timestamp") or None),
                        age_days=_to_int(row.get("age_days", "")),
                        service_account=(row.get("service_account") or None),
                    )
                )
                count += 1
    return count


def load_cluster_admin_bindings(session: Session) -> int:
    """Load cluster-admin-bindings CSVs. Returns row count."""
    files = _find_csvs("cluster-admin-bindings-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    ClusterAdminBinding(
                        cluster_id=cluster.id,
                        binding_name=row.get("binding_name") or None,
                        role_ref_name=row.get("role_ref_name") or None,
                        subject_kind=row.get("subject_kind") or None,
                        subject_name=row.get("subject_name") or None,
                        subject_namespace=(row.get("subject_namespace") or None),
                        creation_timestamp=(row.get("creation_timestamp") or None),
                    )
                )
                count += 1
    return count


def load_platform_guardrails(session: Session) -> int:
    """Load platform-guardrails CSVs (OCP-6). Returns row count."""
    files = _find_csvs("platform-guardrails-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    PlatformGuardrail(
                        cluster_id=cluster.id,
                        ocp_version=row.get("ocp_version") or None,
                        cluster_id_ocp=row.get("cluster_id") or None,
                        update_channel=row.get("update_channel") or None,
                        update_state=row.get("update_state") or None,
                        platform=row.get("platform") or None,
                        control_plane_topology=(row.get("control_plane_topology") or None),
                        infrastructure_topology=(row.get("infrastructure_topology") or None),
                        total_operators=_to_int(row.get("total_operators", "")),
                        degraded_count=_to_int(row.get("degraded_count", "")),
                        unavailable_count=_to_int(row.get("unavailable_count", "")),
                        degraded_operators=(row.get("degraded_operators") or None),
                        unavailable_operators=(row.get("unavailable_operators") or None),
                    )
                )
                count += 1
    return count


def load_policy_as_code(session: Session) -> int:
    """Load policy-as-code CSVs (OCP-7). Returns row count."""
    files = _find_csvs("policy-as-code-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    PolicyAsCodeConstraint(
                        cluster_id=cluster.id,
                        gatekeeper_installed=_to_bool(
                            row.get("gatekeeper_installed", ""),
                        ),
                        gatekeeper_namespace=(row.get("gatekeeper_namespace") or None),
                        constraint_template=(row.get("constraint_template") or None),
                        constraint_name=(row.get("constraint_name") or None),
                        enforcement_action=(row.get("enforcement_action") or None),
                        total_violations=_to_int(row.get("total_violations", "")),
                        match_kinds=row.get("match_kinds") or None,
                        match_namespaces=row.get("match_namespaces") or None,
                    )
                )
                count += 1
    return count


def load_cicd_pipeline_enforcement(session: Session) -> int:
    """Load CI/CD pipeline enforcement CSVs (OCP-8). Returns row count."""
    files = _find_csvs("cicd-pipeline-enforcement-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    CICDPipelineDetection(
                        cluster_id=cluster.id,
                        detection_type=(row.get("detection_type") or None),
                        tool_name=(row.get("tool_name") or None),
                        installed=_to_bool(row.get("installed", "")),
                        namespace=(row.get("namespace") or None),
                        resource_name=(row.get("resource_name") or None),
                        detail_1=(row.get("detail_1") or None),
                        detail_2=(row.get("detail_2") or None),
                        detail_3=(row.get("detail_3") or None),
                        detail_4=(row.get("detail_4") or None),
                        detail_5=(row.get("detail_5") or None),
                        detail_6=(row.get("detail_6") or None),
                    )
                )
                count += 1
    return count


def load_control_plane_protections(session: Session) -> int:
    """Load control plane protection CSVs (OCP-9). Returns row count."""
    files = _find_csvs("control-plane-protections-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    ControlPlaneProtection(
                        cluster_id=cluster.id,
                        check_category=(row.get("check_category") or None),
                        check_name=(row.get("check_name") or None),
                        status=(row.get("status") or None),
                        details=(row.get("details") or None),
                    )
                )
                count += 1
    return count


def load_patch_lifecycle(session: Session) -> int:
    """Load patch lifecycle CSVs (OCP-10). Returns row count."""
    files = _find_csvs("patch-lifecycle-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    PatchLifecycleCheck(
                        cluster_id=cluster.id,
                        check_category=(row.get("check_category") or None),
                        resource_name=(row.get("resource_name") or None),
                        current_version=(row.get("current_version") or None),
                        desired_version=(row.get("desired_version") or None),
                        versions_match=_to_bool(row.get("versions_match", "")),
                        update_channel=(row.get("update_channel") or None),
                        available_updates=_to_int(row.get("available_updates", "")),
                        update_state=(row.get("update_state") or None),
                        age_days=_to_int(row.get("age_days", "")),
                        details=(row.get("details") or None),
                    )
                )
                count += 1
    return count


def load_secrets_cert_rotation(session: Session) -> int:
    """Load secrets-cert-rotation CSVs (OCP-11). Returns row count."""
    files = _find_csvs("secrets-cert-rotation-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    SecretsCertRotation(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        namespace=(row.get("namespace") or None),
                        resource_name=(row.get("resource_name") or None),
                        secret_type=(row.get("secret_type") or None),
                        creation_timestamp=(row.get("creation_timestamp") or None),
                        age_days=_to_int(row.get("age_days", "")),
                        signer_name=(row.get("signer_name") or None),
                        requestor=(row.get("requestor") or None),
                        condition=(row.get("condition") or None),
                        annotations_rotation=(row.get("annotations_rotation") or None),
                    )
                )
                count += 1
    return count


def load_disaster_recovery_backup(session: Session) -> int:
    """Load disaster-recovery-backup CSVs (OCP-12). Returns row count."""
    files = _find_csvs("disaster-recovery-backup-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    DisasterRecoveryBackup(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        resource_name=(row.get("resource_name") or None),
                        namespace=(row.get("namespace") or None),
                        condition_available=_to_bool(row.get("condition_available", "")),
                        condition_degraded=_to_bool(row.get("condition_degraded", "")),
                        condition_progressing=_to_bool(row.get("condition_progressing", "")),
                        detail=(row.get("detail") or None),
                        message=(row.get("message") or None),
                        last_transition=(row.get("last_transition") or None),
                        age_days=_to_int(row.get("age_days", "")),
                    )
                )
                count += 1
    return count


def load_olm_governance(session: Session) -> int:
    """Load olm-governance CSVs (OCP-13). Returns row count."""
    files = _find_csvs("olm-governance-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    OlmGovernance(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        name=(row.get("name") or None),
                        namespace=(row.get("namespace") or None),
                        detail_1=(row.get("detail_1") or None),
                        detail_2=(row.get("detail_2") or None),
                        detail_3=(row.get("detail_3") or None),
                        detail_4=(row.get("detail_4") or None),
                        detail_5=(row.get("detail_5") or None),
                        detail_6=(row.get("detail_6") or None),
                        detail_7=(row.get("detail_7") or None),
                    )
                )
                count += 1
    return count


def load_governance_policy_ecosystem(session: Session) -> int:
    """Load governance-policy-ecosystem CSVs (OCP-15). Returns row count."""
    files = _find_csvs("governance-policy-ecosystem-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    GovernancePolicyEcosystem(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        product_name=(row.get("product_name") or None),
                        installed=_to_bool(row.get("installed", "")),
                        namespace=(row.get("namespace") or None),
                        operator_version=(row.get("operator_version") or None),
                        detail_1=(row.get("detail_1") or None),
                        detail_2=(row.get("detail_2") or None),
                        detail_3=(row.get("detail_3") or None),
                    )
                )
                count += 1
    return count


def load_etcd_encryption_status(session: Session) -> int:
    """Load etcd-encryption-status CSVs (OCP-14). Returns row count."""
    files = _find_csvs("etcd-encryption-status-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    EtcdEncryptionStatus(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        resource_name=(row.get("resource_name") or None),
                        encryption_type=(row.get("encryption_type") or None),
                        encryption_enabled=_to_bool(row.get("encryption_enabled", "")),
                        condition_available=_to_bool(row.get("condition_available", "")),
                        condition_degraded=_to_bool(row.get("condition_degraded", "")),
                        condition_progressing=_to_bool(row.get("condition_progressing", "")),
                        condition_type=(row.get("condition_type") or None),
                        condition_reason=(row.get("condition_reason") or None),
                        message=(row.get("message") or None),
                    )
                )
                count += 1
    return count


def load_monitoring_audit_logging(session: Session) -> int:
    """Load monitoring-audit-logging CSVs (OCP-24/26). Returns row count."""
    files = _find_csvs("monitoring-audit-logging-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    MonitoringAuditLogging(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        component_name=(row.get("component_name") or None),
                        status=(row.get("status") or None),
                        namespace=(row.get("namespace") or None),
                        detail_1=(row.get("detail_1") or None),
                        detail_2=(row.get("detail_2") or None),
                        detail_3=(row.get("detail_3") or None),
                        detail_4=(row.get("detail_4") or None),
                    )
                )
                count += 1
    return count


def load_configuration_drift_status(session: Session) -> int:
    """Load configuration-drift-status CSVs (OCP-25). Returns row count."""
    files = _find_csvs("configuration-drift-status-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    ConfigurationDriftStatus(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        component_name=(row.get("component_name") or None),
                        status=(row.get("status") or None),
                        namespace=(row.get("namespace") or None),
                        detail_1=(row.get("detail_1") or None),
                        detail_2=(row.get("detail_2") or None),
                        detail_3=(row.get("detail_3") or None),
                        detail_4=(row.get("detail_4") or None),
                    )
                )
                count += 1
    return count


def load_vulnerability_runtime_detection(session: Session) -> int:
    """Load vulnerability-runtime-detection CSVs (OCP-28/29). Returns row count."""
    files = _find_csvs("vulnerability-runtime-detection-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    VulnerabilityRuntimeDetection(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        component_name=(row.get("component_name") or None),
                        status=(row.get("status") or None),
                        namespace=(row.get("namespace") or None),
                        detail_1=(row.get("detail_1") or None),
                        detail_2=(row.get("detail_2") or None),
                        detail_3=(row.get("detail_3") or None),
                        detail_4=(row.get("detail_4") or None),
                    )
                )
                count += 1
    return count


def load_network_security_mesh(session: Session) -> int:
    """Load network-security-mesh CSVs (OCP-30/31/32). Returns row count."""
    files = _find_csvs("network-security-mesh-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    NetworkSecurityMesh(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        component_name=(row.get("component_name") or None),
                        status=(row.get("status") or None),
                        namespace=(row.get("namespace") or None),
                        detail_1=(row.get("detail_1") or None),
                        detail_2=(row.get("detail_2") or None),
                        detail_3=(row.get("detail_3") or None),
                        detail_4=(row.get("detail_4") or None),
                    )
                )
                count += 1
    return count


def load_ingress_boundary_protection(session: Session) -> int:
    """Load ingress-boundary-protection CSVs (OCP-30 / boundary protection). Returns row count."""
    files = _find_csvs("ingress-boundary-protection-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    IngressBoundaryProtection(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        component_name=(row.get("component_name") or None),
                        status=(row.get("status") or None),
                        namespace=(row.get("namespace") or None),
                        detail_1=(row.get("detail_1") or None),
                        detail_2=(row.get("detail_2") or None),
                        detail_3=(row.get("detail_3") or None),
                        detail_4=(row.get("detail_4") or None),
                    )
                )
                count += 1
    return count


def load_scc_privileged(session: Session) -> int:
    """Load scc-privileged CSVs (OCP-39 / OCP-40). Returns row count."""
    files = _find_csvs("scc-privileged-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    SccPrivileged(
                        cluster_id=cluster.id,
                        name=(row.get("name") or None),
                        priority=(row.get("priority") or None),
                        allow_privileged_container=(row.get("allow_privileged_container") or None),
                        default_add_capabilities=(row.get("default_add_capabilities") or None),
                        required_drop_capabilities=(row.get("required_drop_capabilities") or None),
                        allowed_capabilities=(row.get("allowed_capabilities") or None),
                        allow_host_network=(row.get("allow_host_network") or None),
                        allow_host_ports=(row.get("allow_host_ports") or None),
                        allow_host_pid=(row.get("allow_host_pid") or None),
                        allow_host_ipc=(row.get("allow_host_ipc") or None),
                        read_only_root_filesystem=(row.get("read_only_root_filesystem") or None),
                        run_as_user_type=(row.get("run_as_user_type") or None),
                        se_linux_context_type=(row.get("se_linux_context_type") or None),
                        fs_group_type=(row.get("fs_group_type") or None),
                        supplemental_groups_type=(row.get("supplemental_groups_type") or None),
                        volumes=(row.get("volumes") or None),
                        allow_privilege_escalation=(row.get("allow_privilege_escalation") or None),
                        users_count=_to_int(row.get("users_count", "")),
                        groups_count=_to_int(row.get("groups_count", "")),
                        users=(row.get("users") or None),
                        groups=(row.get("groups") or None),
                    )
                )
                count += 1
    return count


def load_workload_resource_quotas(session: Session) -> int:
    """Load workload-resource-quotas CSVs (OCP-41). Returns row count."""
    files = _find_csvs("workload-resource-quotas-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    WorkloadResourceQuota(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        namespace=(row.get("namespace") or None),
                        name=(row.get("name") or None),
                        resource_key=(row.get("resource_key") or None),
                        hard_limit=(row.get("hard_limit") or None),
                        used=(row.get("used") or None),
                        limit_type=(row.get("limit_type") or None),
                        default_value=(row.get("default_value") or None),
                        default_request=(row.get("default_request") or None),
                        max_value=(row.get("max_value") or None),
                        min_value=(row.get("min_value") or None),
                    )
                )
                count += 1
    return count


def load_trusted_image_enforcement(session: Session) -> int:
    """Load trusted-image-enforcement CSVs (OCP-42). Returns row count."""
    files = _find_csvs("trusted-image-enforcement-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    TrustedImageEnforcement(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        name=(row.get("name") or None),
                        namespace=(row.get("namespace") or None),
                        detail_1=(row.get("detail_1") or None),
                        detail_2=(row.get("detail_2") or None),
                        detail_3=(row.get("detail_3") or None),
                        detail_4=(row.get("detail_4") or None),
                        detail_5=(row.get("detail_5") or None),
                        detail_6=(row.get("detail_6") or None),
                    )
                )
                count += 1
    return count


def load_pod_security_admission(session: Session) -> int:
    """Load pod-security-admission CSVs (OCP-43). Returns row count."""
    files = _find_csvs("pod-security-admission-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    PodSecurityAdmission(
                        cluster_id=cluster.id,
                        namespace=(row.get("namespace") or None),
                        is_system_namespace=(row.get("is_system_namespace") or None),
                        enforce_level=(row.get("enforce_level") or None),
                        enforce_version=(row.get("enforce_version") or None),
                        audit_level=(row.get("audit_level") or None),
                        audit_version=(row.get("audit_version") or None),
                        warn_level=(row.get("warn_level") or None),
                        warn_version=(row.get("warn_version") or None),
                    )
                )
                count += 1
    return count


def load_logical_project_isolation(session: Session) -> int:
    """Load logical-project-isolation CSVs (OCP-45). Returns row count."""
    files = _find_csvs("logical-project-isolation-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    LogicalProjectIsolation(
                        cluster_id=cluster.id,
                        namespace=(row.get("namespace") or None),
                        is_system_namespace=(row.get("is_system_namespace") or None),
                        has_default_deny_netpol=(row.get("has_default_deny_netpol") or None),
                        netpol_count=(row.get("netpol_count") or None),
                        has_resourcequota=(row.get("has_resourcequota") or None),
                        has_limitrange=(row.get("has_limitrange") or None),
                        has_owner_label=(row.get("has_owner_label") or None),
                        rolebinding_count=(row.get("rolebinding_count") or None),
                        distinct_serviceaccounts=(row.get("distinct_serviceaccounts") or None),
                    )
                )
                count += 1
    return count


def load_encryption_at_rest(session: Session) -> int:
    """Load encryption-at-rest CSVs (OCP-46). Returns row count."""
    files = _find_csvs("encryption-at-rest-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    EncryptionAtRest(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        name=(row.get("name") or None),
                        namespace=(row.get("namespace") or None),
                        detail_1=(row.get("detail_1") or None),
                        detail_2=(row.get("detail_2") or None),
                        detail_3=(row.get("detail_3") or None),
                        detail_4=(row.get("detail_4") or None),
                        detail_5=(row.get("detail_5") or None),
                        detail_6=(row.get("detail_6") or None),
                    )
                )
                count += 1
    return count


def load_image_signing_verification(session: Session) -> int:
    """Load image-signing-verification CSVs (OCP-48). Returns row count."""
    files = _find_csvs("image-signing-verification-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    ImageSigningVerification(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        name=(row.get("name") or None),
                        namespace=(row.get("namespace") or None),
                        detail_1=(row.get("detail_1") or None),
                        detail_2=(row.get("detail_2") or None),
                        detail_3=(row.get("detail_3") or None),
                        detail_4=(row.get("detail_4") or None),
                        detail_5=(row.get("detail_5") or None),
                        detail_6=(row.get("detail_6") or None),
                    )
                )
                count += 1
    return count


def load_build_s2i_policy(session: Session) -> int:
    """Load build-s2i-policy CSVs (OCP-47). Returns row count."""
    files = _find_csvs("build-s2i-policy-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    BuildS2iPolicy(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        name=(row.get("name") or None),
                        namespace=(row.get("namespace") or None),
                        detail_1=(row.get("detail_1") or None),
                        detail_2=(row.get("detail_2") or None),
                        detail_3=(row.get("detail_3") or None),
                        detail_4=(row.get("detail_4") or None),
                        detail_5=(row.get("detail_5") or None),
                        detail_6=(row.get("detail_6") or None),
                    )
                )
                count += 1
    return count


def _opt_int(value: str | None) -> int | None:
    if value is None or value == "":
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def load_ephemeral_storage_limits(session: Session) -> int:
    """Load ephemeral-storage-limits CSVs (OCP-49). Returns row count."""
    files = _find_csvs("ephemeral-storage-limits-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    EphemeralStorageLimits(
                        cluster_id=cluster.id,
                        namespace=(row.get("namespace") or None),
                        is_system_namespace=(row.get("is_system_namespace") or None),
                        has_lr_default_request=(row.get("has_lr_default_request") or None),
                        has_lr_default_limit=(row.get("has_lr_default_limit") or None),
                        has_lr_max=(row.get("has_lr_max") or None),
                        lr_default_request=(row.get("lr_default_request") or None),
                        lr_default_limit=(row.get("lr_default_limit") or None),
                        lr_max=(row.get("lr_max") or None),
                        has_quota_request=(row.get("has_quota_request") or None),
                        has_quota_limit=(row.get("has_quota_limit") or None),
                        quota_request_hard=(row.get("quota_request_hard") or None),
                        quota_limit_hard=(row.get("quota_limit_hard") or None),
                        emptydir_pods_total=_opt_int(row.get("emptydir_pods_total")),
                        emptydir_pods_without_sizelimit=_opt_int(row.get("emptydir_pods_without_sizelimit")),
                    )
                )
                count += 1
    return count


def load_admission_controller_hardening(session: Session) -> int:
    """Load admission-controller-hardening CSVs (OCP-50). Returns row count."""
    files = _find_csvs("admission-controller-hardening-*.csv")
    count = 0
    for filepath in files:
        print(f"  Loading {Path(filepath).name}")
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                cluster = _get_or_create_cluster(
                    session,
                    row["cluster_name"],
                    row["cluster_context"],
                    row["cluster_server"],
                )
                session.add(
                    AdmissionControllerHardening(
                        cluster_id=cluster.id,
                        record_type=(row.get("record_type") or None),
                        name=(row.get("name") or None),
                        namespace=(row.get("namespace") or None),
                        detail_1=(row.get("detail_1") or None),
                        detail_2=(row.get("detail_2") or None),
                        detail_3=(row.get("detail_3") or None),
                        detail_4=(row.get("detail_4") or None),
                        detail_5=(row.get("detail_5") or None),
                        detail_6=(row.get("detail_6") or None),
                    )
                )
                count += 1
    return count


# -- Main -------------------------------------------------------------------


def main() -> None:
    data_path = os.path.abspath(DATA_DIR)
    if not os.path.isdir(data_path):
        print(
            f"ERROR: Data directory not found: {data_path}",
            file=sys.stderr,
        )
        sys.exit(1)

    Base.metadata.create_all(engine)

    session = SessionLocal()
    try:
        print(f"Loading CSV files from {data_path} ...")
        print(f"  Layout: {DATA_LAYOUT} (set OCP_DATA_LAYOUT=flat to disable recursion)")

        n = load_cluster_overview(session)
        print(f"  -> cluster_overview: {n} rows")

        n = load_oauth_external_auth(session)
        print(f"  -> oauth_external_auth: {n} rows")

        n = load_clusterroles(session)
        print(f"  -> clusterroles/rules: {n} rows")

        n = load_clusterrolebindings(session)
        print(f"  -> clusterrolebindings: {n} rows")

        n = load_self_provisioners(session)
        print(f"  -> self_provisioners: {n} rows")

        n = load_apiserver_console_access(session)
        print(f"  -> apiserver_console_access: {n} rows")

        n = load_worker_node_auth(session)
        print(f"  -> worker_node_auth: {n} rows")

        n = load_credential_management(session)
        print(f"  -> credential_management_secrets: {n} rows")

        n = load_cluster_admin_bindings(session)
        print(f"  -> cluster_admin_bindings: {n} rows")

        n = load_platform_guardrails(session)
        print(f"  -> platform_guardrails: {n} rows")

        n = load_policy_as_code(session)
        print(f"  -> policy_as_code_constraints: {n} rows")

        n = load_cicd_pipeline_enforcement(session)
        print(f"  -> cicd_pipeline_detections: {n} rows")

        n = load_control_plane_protections(session)
        print(f"  -> control_plane_protections: {n} rows")

        n = load_patch_lifecycle(session)
        print(f"  -> patch_lifecycle_checks: {n} rows")

        n = load_secrets_cert_rotation(session)
        print(f"  -> secrets_cert_rotations: {n} rows")

        n = load_disaster_recovery_backup(session)
        print(f"  -> disaster_recovery_backups: {n} rows")

        n = load_olm_governance(session)
        print(f"  -> olm_governance: {n} rows")

        n = load_etcd_encryption_status(session)
        print(f"  -> etcd_encryption_status: {n} rows")

        n = load_governance_policy_ecosystem(session)
        print(f"  -> governance_policy_ecosystem: {n} rows")

        n = load_monitoring_audit_logging(session)
        print(f"  -> monitoring_audit_logging: {n} rows")

        n = load_configuration_drift_status(session)
        print(f"  -> configuration_drift_status: {n} rows")

        n = load_vulnerability_runtime_detection(session)
        print(f"  -> vulnerability_runtime_detection: {n} rows")

        n = load_network_security_mesh(session)
        print(f"  -> network_security_mesh: {n} rows")

        n = load_ingress_boundary_protection(session)
        print(f"  -> ingress_boundary_protection: {n} rows")

        n = load_scc_privileged(session)
        print(f"  -> scc_privileged: {n} rows")

        n = load_workload_resource_quotas(session)
        print(f"  -> workload_resource_quotas: {n} rows")

        n = load_trusted_image_enforcement(session)
        print(f"  -> trusted_image_enforcement: {n} rows")

        n = load_pod_security_admission(session)
        print(f"  -> pod_security_admission: {n} rows")

        n = load_logical_project_isolation(session)
        print(f"  -> logical_project_isolation: {n} rows")

        n = load_encryption_at_rest(session)
        print(f"  -> encryption_at_rest: {n} rows")

        n = load_image_signing_verification(session)
        print(f"  -> image_signing_verification: {n} rows")

        n = load_build_s2i_policy(session)
        print(f"  -> build_s2i_policy: {n} rows")

        n = load_ephemeral_storage_limits(session)
        print(f"  -> ephemeral_storage_limits: {n} rows")

        n = load_admission_controller_hardening(session)
        print(f"  -> admission_controller_hardening: {n} rows")

        session.commit()
        print("Done -- all data committed.")
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


if __name__ == "__main__":
    main()
