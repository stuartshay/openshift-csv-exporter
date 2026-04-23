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
"""

from __future__ import annotations

import csv
import glob
import os
import sys
from pathlib import Path

from sqlalchemy.orm import Session

from schema.database import Base, SessionLocal, engine
from schema.models import (
    ApiServerConsoleAccess,
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
    CredentialManagementSecret,
    OAuthExternalAuth,
    SelfProvisionerBinding,
    SelfProvisionerSubject,
    WorkerNodeAuth,
)

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

        session.commit()
        print("Done -- all data committed.")
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


if __name__ == "__main__":
    main()
