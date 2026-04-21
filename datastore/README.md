# OCP Audit Datastore

SQLite database schema for OpenShift audit CSV data, built with SQLAlchemy 2.0+.

## Prerequisites

- Python 3.14+
- `make`

## Quick Start

```bash
cd datastore

# Generate the empty database with all tables
make schema

# Load CSV data into the database
make load

# Verify
sqlite3 ocp_audit.db ".tables"

# Clean up (removes DB and virtualenv)
make clean
```

## Makefile Targets

| Target   | Description                                  |
|----------|----------------------------------------------|
| `help`   | Show available targets                       |
| `venv`   | Create virtualenv and install dependencies   |
| `schema` | Generate the SQLite database schema          |
| `load`   | Load CSV data from `data/` into the database |
| `clean`  | Remove database, virtualenv, and `__pycache__` |

## CSV Data Directory

Place CSV export files in `datastore/data/`. The loader matches files by glob pattern:

| Pattern                                      | Target Table(s)                        |
|----------------------------------------------|----------------------------------------|
| `cluster-overview-*.csv`                     | `cluster_overview`                     |
| `oauth-external-auth-*.csv`                  | `oauth_external_auth`                  |
| `clusterroles-*.csv`                         | `clusterroles`, rules, junction tables |
| `clusterrolebindings-*.csv`                  | `clusterrolebindings`, subjects        |
| `clusterrolebinding-self-provisioners-*.csv` | `self_provisioner_bindings`, subjects  |

Override the data directory with the `OCP_DATA_DIR` environment variable:

```bash
OCP_DATA_DIR=../output make load
```

## Configuration

| Environment Variable | Default                  | Description                                                  |
|----------------------|--------------------------|--------------------------------------------------------------|
| `OCP_AUDIT_DB`       | `ocp_audit.db`           | SQLite database file path                                    |
| `DATABASE_URL`       | `sqlite:///ocp_audit.db` | Full SQLAlchemy URL (overrides `OCP_AUDIT_DB`; for Postgres) |
| `OCP_DATA_DIR`       | `data`                   | Directory containing CSV export files                        |

## Schema Overview

### Shared

| Table      | Description                              |
|------------|------------------------------------------|
| `clusters` | Deduplicated cluster identity (name, context, server). All report tables reference this via FK. |

### Cluster Overview

| Table              | Description                                                     |
|--------------------|-----------------------------------------------------------------|
| `cluster_overview` | One row per cluster snapshot — version, platform, topology, nodes, network, endpoints, update posture |

### OCP-1: OAuth External Auth

| Table                  | Description                        |
|------------------------|------------------------------------|
| `oauth_external_auth`  | One row per identity provider per cluster — external auth enforcement status, IDP configuration |

### OCP-2: Granular RBAC

| Table                              | Description                                               |
|------------------------------------|-----------------------------------------------------------|
| `clusterroles`                     | One row per unique ClusterRole per cluster                |
| `clusterrole_rules`                | One row per RBAC rule within a ClusterRole                |
| `clusterrole_rule_api_groups`      | Junction — individual API groups (split from `;`-delimited CSV) |
| `clusterrole_rule_resources`       | Junction — individual resources                           |
| `clusterrole_rule_verbs`           | Junction — individual verbs                               |
| `clusterrole_rule_non_resource_urls` | Junction — individual non-resource URLs                 |
| `clusterrolebindings`              | One row per unique ClusterRoleBinding per cluster         |
| `clusterrolebinding_subjects`      | One row per subject within a binding                      |
| `self_provisioner_bindings`        | Self-provisioners binding status per cluster              |
| `self_provisioner_subjects`        | Subjects of the self-provisioners binding                 |

### OCP-3: API & Console Access Restriction

| Table                      | Description                                                            |
|----------------------------|------------------------------------------------------------------------|
| `apiserver_console_access` | One row per cluster — TLS profile, audit profile, encryption, client CA, CORS allow-list, custom serving certs, cluster-admin subject count |

### OCP-4: Worker Node AuthN/AuthZ

| Table              | Description                                                                 |
|--------------------|-----------------------------------------------------------------------------|
| `worker_node_auth` | One row per node per cluster — kubelet version, ready status, MachineConfig drift, kubelet anonymous auth + authorization mode overrides |

### OCP-5: Cluster Admin/SRE Credential Management

| Table                           | Description                                                   |
|---------------------------------|---------------------------------------------------------------|
| `credential_management_secrets` | One row per secret in the critical admin namespaces (`kube-system`, `openshift-config`, `openshift-config-managed`) with kubeadmin presence flag and age in days |
| `cluster_admin_bindings`        | One row per subject currently bound to the `cluster-admin` role |

## Future: Postgres Migration

Switch the dialect by setting `DATABASE_URL`:

```bash
export DATABASE_URL="postgresql+psycopg2://user:pass@host:5432/ocp_audit"  # pragma: allowlist secret
make schema
```

No model changes required — SQLAlchemy handles the dialect swap.
