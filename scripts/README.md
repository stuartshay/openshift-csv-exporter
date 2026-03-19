# Scripts Reference

Comprehensive reference for all export scripts in the `scripts/` directory. Each script sources `common.sh`, connects to the authenticated OpenShift cluster, and writes a timestamped CSV to the `output/` directory.

## Prerequisites

| Requirement | Check Command |
|---|---|
| Bash | `bash --version` |
| `oc` CLI (authenticated) | `oc whoami` |
| `jq` | `jq --version` |

## Environment Variables

All scripts inherit these from `common.sh`:

| Variable | Default | Description |
|---|---|---|
| `OUTPUT_DIR` | `./output` | Directory where CSV files are written |
| `TIMESTAMP` | `YYYY-MM-DD-HH-MM` | Timestamp appended to output filenames |
| `DEBUG` | `false` | Set to `true` to enable debug logging |

Automatically detected:

| Variable | Description |
|---|---|
| `CLUSTER_NAME` | Cluster name derived from context or server hostname |
| `CLUSTER_NAME_SAFE` | Sanitized cluster name (lowercase, safe characters only) |
| `CLUSTER_CONTEXT` | Current `oc` context |
| `CLUSTER_SERVER` | API server URL |

## Common Columns

Every CSV includes these leading columns for multi-cluster correlation:

| Column | Description |
|---|---|
| `cluster_name` | Cluster identifier |
| `cluster_context` | `oc` context used |
| `cluster_server` | API server URL |

---

## Scripts

### common.sh

Shared library sourced by all export scripts. Not executed directly.

- Validates `oc` and `jq` are installed
- Confirms `oc` authentication
- Detects and exports cluster identity variables
- Creates the output directory

```bash
# Used internally by all scripts:
source scripts/common.sh
```

---

### test-common.sh

Diagnostic script that sources `common.sh` and prints the detected cluster variables.

```bash
./scripts/test-common.sh
```

**Output:** prints `CLUSTER_CONTEXT`, `CLUSTER_SERVER`, `CLUSTER_NAME`, `CLUSTER_NAME_SAFE`, `OUTPUT_DIR`, `TIMESTAMP` to stdout.

---

### export-clusterversion.sh

Exports cluster version and update status.

```bash
./scripts/export-clusterversion.sh
```

**OC command:** `oc get clusterversion version -o json`

**Output file:** `clusterversion-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `name` | ClusterVersion resource name |
| `cluster_id` | Unique cluster ID |
| `desired_version` | Target OCP version |
| `history_state` | Latest update state (Completed, Partial) |
| `history_version` | Latest history entry version |
| `available` | Available condition status |
| `progressing` | Progressing condition status |
| `failing` | Failing condition status |
| `observed_generation` | Observed generation number |

---

### export-clusteroperators.sh

Exports status of all cluster operators.

```bash
./scripts/export-clusteroperators.sh
```

**OC command:** `oc get clusteroperators -o json`

**Output file:** `clusteroperators-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `name` | Operator name |
| `version` | Operator version |
| `available` | Available condition |
| `progressing` | Progressing condition |
| `degraded` | Degraded condition |
| `upgradeable` | Upgradeable condition |

---

### export-infrastructure-cluster.sh

Exports cluster infrastructure details (platform, topology, API endpoints).

```bash
./scripts/export-infrastructure-cluster.sh
```

**OC command:** `oc get infrastructure cluster -o json`

**Output file:** `infrastructure-cluster-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `name` | Infrastructure resource name |
| `infrastructure_name` | Infrastructure identifier |
| `platform` | Cloud platform (AWS, Azure, GCP, etc.) |
| `api_server_url` | External API server URL |
| `api_server_internal_url` | Internal API server URL |
| `control_plane_topology` | Control plane topology (HighlyAvailable, SingleReplica) |
| `infrastructure_topology` | Infrastructure topology |

---

### export-oauth-cluster.sh

Exports OAuth configuration summary.

```bash
./scripts/export-oauth-cluster.sh
```

**OC command:** `oc get oauth cluster -o json`

**Output file:** `oauth-cluster-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `name` | OAuth resource name |
| `identity_providers_count` | Number of configured identity providers |
| `access_token_max_age_seconds` | Token expiration setting |
| `grant_config_method` | Grant approval method |
| `template_login` | Custom login template name |
| `template_provider_selection` | Custom provider selection template |
| `template_error` | Custom error template |

---

### export-oauth-external-auth.sh

Reports whether external authentication is enforced. Checks both identity provider configuration and kubeadmin secret removal.

```bash
./scripts/export-oauth-external-auth.sh
```

**OC commands:**

- `oc get oauth cluster -o json`
- `oc get secret kubeadmin -n kube-system`

**Output file:** `oauth-external-auth-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `external_auth_enforced` | `true` if IDP configured **and** kubeadmin removed |
| `kubeadmin_removed` | Whether the kubeadmin secret has been deleted |
| `identity_providers_count` | Number of configured identity providers |
| `idp_name` | Identity provider name (e.g., `okta`) |
| `idp_type` | Provider type (OpenID, LDAP, HTPasswd, etc.) |
| `idp_mapping_method` | Mapping method (claim, lookup, add) |
| `idp_issuer` | OIDC issuer URL / LDAP URL |
| `idp_client_id` | OAuth client ID |
| `access_token_max_age_seconds` | Token expiration setting |

One row per identity provider is produced.

---

### export-clusterrolebindings.sh

Exports all ClusterRoleBindings with their subjects.

```bash
./scripts/export-clusterrolebindings.sh
```

**OC command:** `oc get clusterrolebindings -o json`

**Output file:** `clusterrolebindings-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `binding_name` | ClusterRoleBinding name |
| `role_ref_kind` | Role reference kind (ClusterRole) |
| `role_ref_name` | Referenced role name |
| `subject_kind` | Subject type (User, Group, ServiceAccount) |
| `subject_name` | Subject name |
| `subject_namespace` | Subject namespace (ServiceAccounts only) |

One row per subject per binding.

---

### export-clusterrolebinding-self-provisioners.sh

Exports the `self-provisioners` ClusterRoleBinding specifically. Indicates whether users can self-provision projects.

```bash
./scripts/export-clusterrolebinding-self-provisioners.sh
```

**OC command:** `oc get clusterrolebinding self-provisioners -o json`

**Output file:** `clusterrolebinding-self-provisioners-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `binding_name` | Should be `self-provisioners` |
| `role_ref_kind` | Role reference kind |
| `role_ref_name` | Referenced role name |
| `subject_kind` | Subject type |
| `subject_name` | Subject name |
| `subject_namespace` | Subject namespace |

---

### export-cluster-admin-bindings.sh

Exports only ClusterRoleBindings that grant `cluster-admin` access. Answers: **who has administrator access to the API and console?**

```bash
./scripts/export-cluster-admin-bindings.sh
```

**OC command:** `oc get clusterrolebindings -o json` (filtered to `cluster-admin`)

**Output file:** `cluster-admin-bindings-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `binding_name` | ClusterRoleBinding name |
| `role_ref_name` | Always `cluster-admin` |
| `subject_kind` | Subject type (User, Group, ServiceAccount) |
| `subject_name` | Subject name |
| `subject_namespace` | Subject namespace |
| `creation_timestamp` | When the binding was created |

---

### export-clusterroles.sh

Exports all ClusterRoles with their permission rules. Answers: **what permissions does each role grant?**

```bash
./scripts/export-clusterroles.sh
```

**OC command:** `oc get clusterroles -o json`

**Output file:** `clusterroles-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `role_name` | ClusterRole name |
| `creation_timestamp` | When the role was created |
| `api_groups` | API groups (`;`-delimited) |
| `resources` | Resources (`;`-delimited) |
| `verbs` | Allowed verbs (`;`-delimited) |
| `non_resource_urls` | Non-resource URLs (`;`-delimited) |

One row per rule per role.

---

### export-apiserver-console-access.sh

Exports API server and console access restriction configuration. Answers: **are the API and console properly secured?**

```bash
./scripts/export-apiserver-console-access.sh
```

**OC commands:**

- `oc get apiserver cluster -o json`
- `oc get consoles.config.openshift.io cluster`
- `oc get clusterrolebindings -o json`

**Output file:** `apiserver-console-access-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `api_server_url` | External API server URL |
| `console_url` | Web console URL |
| `tls_security_profile_type` | TLS profile (Custom, Intermediate, Modern) |
| `tls_min_version` | Minimum TLS version |
| `audit_profile` | Audit logging level (Default, WriteRequestBodies, AllRequestBodies) |
| `client_ca_name` | Custom client CA bundle name |
| `encryption_type` | etcd encryption type (aescbc, aesgcm) |
| `additional_cors_origins` | Allowed CORS origins (`;`-delimited) |
| `serving_certs_count` | Number of named serving certificates |
| `cluster_admin_binding_count` | Total subjects with cluster-admin role |

---

### export-scc-privileged.sh

Exports the `privileged` SecurityContextConstraints configuration.

```bash
./scripts/export-scc-privileged.sh
```

**OC command:** `oc get scc privileged -o json`

**Output file:** `scc-privileged-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `name` | SCC name |
| `allow_privileged_container` | Privileged containers allowed |
| `allow_host_network` | Host network access allowed |
| `allow_host_pid` | Host PID namespace allowed |
| `allow_host_ipc` | Host IPC allowed |
| `read_only_root_filesystem` | Read-only root filesystem enforced |
| `run_as_user_type` | RunAsUser strategy |
| `se_linux_context_type` | SELinux context strategy |
| `users_count` | Number of users granted this SCC |
| `groups_count` | Number of groups granted this SCC |

---

### export-worker-node-auth.sh

Exports worker node authentication and authorization enforcement status. Verifies that each node has its desired machine config applied and checks for any KubeletConfig overrides to default authentication/authorization settings.

```bash
./scripts/export-worker-node-auth.sh
```

**OC commands:**

- `oc get kubeletconfig -o json`
- `oc get nodes -o json`

**Output file:** `worker-node-auth-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `node_name` | Node hostname |
| `node_roles` | Node roles (`;`-delimited: worker, master, infra) |
| `kubelet_version` | Kubelet version running on the node |
| `ready_status` | Node Ready condition (True, False, Unknown) |
| `internal_ip` | Node internal IP address |
| `creation_timestamp` | When the node was created |
| `machine_config_state` | MachineConfig rollout state (Done, Working, Degraded) |
| `current_config` | Currently applied MachineConfig name |
| `desired_config` | Desired MachineConfig name |
| `configs_match` | `true` if current config matches desired config |
| `kubelet_config_count` | Number of KubeletConfig override CRs |
| `anonymous_auth` | Anonymous authentication override (`default` if not overridden) |
| `authorization_mode` | Authorization mode override (`default` if not overridden) |

One row per node. Columns `kubelet_config_count`, `anonymous_auth`, and `authorization_mode` reflect cluster-level KubeletConfig overrides. OpenShift defaults enforce webhook authentication and Webhook authorization mode.

---

### export-credential-management.sh

Exports secrets from critical cluster namespaces to audit credential management. Checks whether the kubeadmin secret still exists and enumerates secrets in `kube-system`, `openshift-config`, and `openshift-config-managed` to verify that infrastructure provider keys and admin credentials are properly managed.

```bash
./scripts/export-credential-management.sh
```

**OC commands:**

- `oc get secret kubeadmin -n kube-system`
- `oc get secrets -n kube-system -o json`
- `oc get secrets -n openshift-config -o json`
- `oc get secrets -n openshift-config-managed -o json`

**Output file:** `credential-management-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `kubeadmin_exists` | `true` if kubeadmin secret is still present |
| `namespace` | Namespace where the secret resides |
| `secret_name` | Secret resource name |
| `secret_type` | Secret type (Opaque, kubernetes.io/tls, etc.) |
| `creation_timestamp` | When the secret was created |
| `age_days` | Age of the secret in days |
| `service_account` | Associated service account (if token secret) |

One row per secret across the three critical namespaces.

---

### export-platform-guardrails.sh

Exports platform guardrails data to detect unapproved distributions and misconfigured cluster components.

**OC commands used:**

- `oc get clusterversion version -o json`
- `oc get infrastructure cluster -o json`
- `oc get clusteroperators -o json`

**Output file:** `platform-guardrails-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `ocp_version` | Current desired OpenShift version |
| `cluster_id` | Unique cluster identifier from ClusterVersion spec |
| `update_channel` | Configured update channel (e.g., stable-4.x, fast-4.x) |
| `update_state` | State of the most recent version history entry |
| `platform` | Infrastructure platform type (AWS, Azure, None, etc.) |
| `control_plane_topology` | Control plane topology (HighlyAvailable, SingleReplica) |
| `infrastructure_topology` | Infrastructure topology (HighlyAvailable, SingleReplica) |
| `total_operators` | Total number of cluster operators |
| `degraded_count` | Number of operators in Degraded state |
| `unavailable_count` | Number of operators in Unavailable state |
| `degraded_operators` | Semicolon-delimited list of degraded operator names |
| `unavailable_operators` | Semicolon-delimited list of unavailable operator names |

One summary row per cluster. A valid OpenShift distribution will show a recognized update channel (stable-X.Y, fast-X.Y, eus-X.Y, candidate-X.Y), a populated cluster ID, and zero degraded/unavailable operators.

---

### export-policy-as-code.sh

Exports OPA Gatekeeper policy-as-code enforcement status, constraint templates, and active constraints.

**OC commands used:**

- `oc get namespace openshift-gatekeeper-system` / `oc get namespace gatekeeper-system`
- `oc get constrainttemplates -o json`
- `oc get <constraint-kind> -o json` (for each template)

**Output file:** `policy-as-code-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `gatekeeper_installed` | `true` if Gatekeeper namespace exists, `false` otherwise |
| `gatekeeper_namespace` | Detected Gatekeeper namespace (openshift-gatekeeper-system or gatekeeper-system) |
| `constraint_template` | ConstraintTemplate name defining the policy type |
| `constraint_name` | Constraint resource name (instance of a template) |
| `enforcement_action` | Enforcement action: deny, warn, or dryrun |
| `total_violations` | Number of current violations for the constraint |
| `match_kinds` | Semicolon-delimited Kubernetes resource kinds the constraint applies to |
| `match_namespaces` | Semicolon-delimited namespaces the constraint is scoped to |

One row per constraint. If Gatekeeper is not installed, a single row is written with `gatekeeper_installed=false`. If templates exist but have no constraints, a row per template is written with empty constraint fields.

---

## Usage Examples

Run all reports at once:

```bash
./run-all.sh
```

Run a single report:

```bash
./scripts/export-clusteroperators.sh
```

Custom output directory:

```bash
OUTPUT_DIR=/tmp/audit ./run-all.sh
```

Enable debug logging:

```bash
DEBUG=true ./scripts/export-oauth-external-auth.sh
```

## Audit Coverage Matrix

| Audit Area | Script(s) |
|---|---|
| **External Authentication Enforced** | `export-oauth-external-auth.sh`, `export-oauth-cluster.sh` |
| **Granular Role-Based Access Controls** | `export-clusterroles.sh`, `export-clusterrolebindings.sh`, `export-clusterrolebinding-self-provisioners.sh` |
| **API & Console Access Restriction** | `export-apiserver-console-access.sh`, `export-cluster-admin-bindings.sh` |
| **Privileged Container Controls** | `export-scc-privileged.sh` |
| **Worker Node AuthN/AuthZ** | `export-worker-node-auth.sh` |
| **Cluster Admin/SRE Credential Management** | `export-credential-management.sh`, `export-oauth-external-auth.sh` |
| **Cluster Version & Health** | `export-clusterversion.sh`, `export-clusteroperators.sh` |
| **Infrastructure & Platform** | `export-infrastructure-cluster.sh` |
| **Platform Usage Guardrails** | `export-platform-guardrails.sh` |
| **Policy-as-Code Enforcement** | `export-policy-as-code.sh` |
