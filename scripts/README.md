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

### export-cicd-pipeline-enforcement.sh

Exports CI/CD pipeline enforcement status. Detects in-cluster GitOps tools (ArgoCD, Flux CD), pipeline operators (Tekton), and external CI/CD tool footprints (Jenkins, GitLab, GitHub Actions, Azure DevOps, etc.) via ClusterRoleBindings and namespaces.

```bash
./scripts/export-cicd-pipeline-enforcement.sh
```

**OC commands used:**

- `oc get namespace openshift-gitops` / `gitops-system` / `argocd` / `flux-system` / `openshift-pipelines` / `tekton-pipelines`
- `oc get applications.argoproj.io --all-namespaces -o json`
- `oc get gitrepositories.source.toolkit.fluxcd.io --all-namespaces -o json`
- `oc get kustomizations.kustomize.toolkit.fluxcd.io --all-namespaces -o json`
- `oc get helmreleases.helm.toolkit.fluxcd.io --all-namespaces -o json`
- `oc get clusterrolebindings -o json`
- `oc get namespaces -o json`

**Output file:** `cicd-pipeline-enforcement-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `detection_type` | Category: `gitops`, `pipeline`, `external-cicd`, or `none` |
| `tool_name` | Detected tool (argocd, fluxcd, tekton, clusterrolebinding, namespace, none) |
| `installed` | `true` if the tool was detected on the cluster |
| `namespace` | Namespace where the tool or resource was found |
| `resource_name` | Resource name (Application, GitRepository, ClusterRoleBinding, etc.) |
| `detail_1` – `detail_6` | Context-specific details (see below) |

**Detail columns by detection type:**

| detection_type | detail_1 | detail_2 | detail_3 | detail_4 | detail_5 | detail_6 |
|---|---|---|---|---|---|---|
| `gitops` (argocd) | repo URL | path | revision | sync status | health status | sync policy |
| `gitops` (fluxcd GitRepository) | type=GitRepository | url | branch | ready status | | |
| `gitops` (fluxcd Kustomization) | type=Kustomization | source name | path | ready status | prune enabled | |
| `gitops` (fluxcd HelmRelease) | type=HelmRelease | chart | version | ready status | | |
| `pipeline` (tekton) | operator namespace detected | | | | | |
| `external-cicd` (clusterrolebinding) | role name | subject kind | subject name | subject namespace | | |
| `external-cicd` (namespace) | namespace status | | | | | |

One row per detected resource. If no CI/CD tooling is found, a single row is written with `detection_type=none`.

---

### export-control-plane-protections.sh

Exports control plane protection status to verify that etcd is protected and access is restricted. Checks etcd encryption at rest, etcd operator health, etcd pod status, master node taint isolation, control plane topology, etcd namespace RBAC, etcd-related ClusterRoleBindings, and etcd TLS certificate presence.

```bash
./scripts/export-control-plane-protections.sh
```

**OC commands used:**

- `oc get apiserver cluster -o json`
- `oc get clusteroperator etcd -o json`
- `oc get pods -n openshift-etcd -l app=etcd`
- `oc get nodes -l node-role.kubernetes.io/master -o json`
- `oc get infrastructure cluster -o json`
- `oc get rolebindings -n openshift-etcd -o json`
- `oc get clusterrolebindings -o json`
- `oc get secrets -n openshift-etcd -o json`

**Output file:** `control-plane-protections-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `check_category` | Area being checked: `etcd_encryption`, `etcd_health`, `control_plane_isolation`, `etcd_access`, `etcd_certificates` |
| `check_name` | Specific check performed |
| `status` | `true` if the check passes, `false` if it fails, `info` for informational rows |
| `details` | Key=value pairs with supporting evidence |

**Checks performed:**

| check_category | check_name | Passes when |
|---|---|---|
| `etcd_encryption` | `etcd_encryption_at_rest` | Encryption type is `aescbc` or `aesgcm` (not `identity`) |
| `etcd_health` | `etcd_operator_status` | Operator is Available and not Degraded |
| `etcd_health` | `etcd_pod_status` | All etcd pods are in Running phase |
| `control_plane_isolation` | `master_node_taint` | Master node has `NoSchedule` taint (one row per master) |
| `control_plane_isolation` | `control_plane_topology` | Topology is `HighlyAvailable` |
| `etcd_access` | `etcd_namespace_rolebinding` | Informational — lists all RoleBindings in openshift-etcd |
| `etcd_access` | `etcd_clusterrolebinding` | Informational — lists etcd-related ClusterRoleBindings |
| `etcd_certificates` | `etcd_tls_secrets` | At least one TLS secret exists in openshift-etcd namespace |

---

### export-patch-lifecycle.sh

Exports patch and version lifecycle data to track whether cluster and image versions are current and updates are enforced. Covers the OpenShift cluster version, available updates, update history, ClusterOperator versions, MachineConfigPool rollout status, and per-node OS/kubelet/container-runtime versions.

```bash
./scripts/export-patch-lifecycle.sh
```

**OC commands used:**

- `oc get clusterversion version -o json`
- `oc get clusteroperators -o json`
- `oc get machineconfigpools -o json`
- `oc get nodes -o json`

**Output file:** `patch-lifecycle-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `check_category` | Area being checked: `cluster_version`, `update_history`, `operator_version`, `machineconfig_pool`, `node_version` |
| `resource_name` | Resource identifier (ClusterVersion name, operator name, MCP name, node name) |
| `current_version` | Currently running version / config |
| `desired_version` | Desired / target version / config |
| `versions_match` | `true` if current matches desired |
| `update_channel` | Configured update channel (e.g., stable-4.x) — cluster version rows only |
| `available_updates` | Semicolon-delimited list of available update versions |
| `update_state` | State: Completed, Partial, Healthy, Degraded, Updated, Updating |
| `age_days` | Age in days (cluster install, node creation) |
| `details` | Key=value pairs with additional context |

**Check categories:**

| check_category | What it tracks |
|---|---|
| `cluster_version` | Current OCP version, update channel, how many updates are available |
| `update_history` | Each version the cluster has been updated through, with completion age |
| `operator_version` | Per-operator version and health (degraded, available, upgradeable) |
| `machineconfig_pool` | MCP rollout status — total/ready/updated/degraded machine counts, paused state |
| `node_version` | Per-node kubelet version, OS image, kernel, container runtime, MachineConfig match |

An up-to-date cluster will show: update channel set, `available_updates` count of 0 (or low), all operators healthy and upgradeable, all MCPs fully updated with 0 degraded, and all nodes matching their desired MachineConfig.

---

### export-secrets-cert-rotation.sh

Exports TLS secrets and certificate signing requests (CSRs) across control-plane namespaces to assess whether automated certificate rotation is active and healthy.

```bash
./scripts/export-secrets-cert-rotation.sh
```

**OC commands used:**

- `oc get secrets -n <namespace> --field-selector type=kubernetes.io/tls -o json` (for each control-plane namespace)
- `oc get csr -o json`

**Namespaces scanned:**

`openshift-etcd`, `openshift-kube-apiserver`, `openshift-kube-controller-manager`, `openshift-ingress`, `openshift-authentication`, `openshift-monitoring`, `openshift-service-ca`

**Output file:** `secrets-cert-rotation-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `record_type` | `tls_secret` or `csr` |
| `namespace` | Namespace of the TLS secret (empty for CSRs) |
| `resource_name` | Secret name or CSR name |
| `secret_type` | Kubernetes secret type (e.g., `kubernetes.io/tls`) — TLS rows only |
| `creation_timestamp` | Resource creation time |
| `age_days` | Age in days since creation |
| `signer_name` | CSR signer (e.g., `kubernetes.io/kube-apiserver-client`) — CSR rows only |
| `requestor` | CSR requesting user/service account — CSR rows only |
| `condition` | CSR approval status: `Approved`, `Denied`, or `Pending` — CSR rows only |
| `annotations_rotation` | Semicolon-delimited rotation-related annotations (e.g., `certificate-not-after`) — TLS rows only |

**Console warnings:**

| Warning | Meaning |
|---|---|
| Pending CSRs > 0 | Certificate rotation may be stalled — nodes waiting for cert approval |
| TLS secrets older than 365 days | Rotation may not be active for those certificates |

**What auditors should look for:**

- **Stale TLS secrets** (age > 365 days) indicate rotation may not be functioning
- **Pending CSRs** indicate node certificate rotation is blocked
- **CSR volume and recency** provides evidence that automated rotation is active
- **Per-namespace breakdown** shows which control-plane components have fresh certificates

---

### export-disaster-recovery-backup.sh

Exports disaster recovery and backup readiness data — etcd member health, control plane operator revision status, OADP/Velero backup infrastructure detection, and volume snapshot readiness.

```bash
./scripts/export-disaster-recovery-backup.sh
```

**OC commands used:**

- `oc get etcd cluster -o json`
- `oc get kubeapiserver cluster -o json`
- `oc get kubecontrollermanager cluster -o json`
- `oc get kubescheduler cluster -o json`
- `oc get namespace openshift-adp -o json`
- `oc get backupstoragelocations -n openshift-adp -o json`
- `oc get backups.velero.io -n openshift-adp -o json`
- `oc get volumesnapshotclasses -o json`
- `oc get volumesnapshots -A -o json`

**Output file:** `disaster-recovery-backup-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `record_type` | `etcd_member`, `cp_operator`, `oadp_backup`, or `volume_snapshot` |
| `resource_name` | Resource identifier (e.g., `etcd-cluster`, `kubeapiserver`, BSL name, snapshot name) |
| `namespace` | Namespace where applicable (e.g., `openshift-adp`, `openshift-etcd`) |
| `condition_available` | `True`/`False` — resource availability status |
| `condition_degraded` | `True`/`False` — degraded condition (etcd, CP operators) |
| `condition_progressing` | `True`/`False` — rollout in progress |
| `detail` | Context-specific: member count, node revisions, provider/bucket, driver/policy, snapshot size |
| `message` | Condition message or phase status |
| `last_transition` | Last condition transition or validation timestamp |
| `age_days` | Resource age in days |

**Console warnings:**

| Warning | Meaning |
|---|---|
| etcd DEGRADED | etcd cluster is unhealthy — backup/restore operations may fail |
| etcd < 3 members | Quorum at risk — single member failure could be unrecoverable |
| Control plane operator DEGRADED | Unsafe backup window — API server, controller manager, or scheduler unhealthy |
| OADP not detected | No external backup tooling installed on the cluster |
| OADP installed but no BSL | Backup storage not configured despite OADP being present |
| No VolumeSnapshotClasses | Cloud-native PV snapshot backups not available |

**What auditors should look for:**

- **etcd degraded or < 3 members** indicates the cluster cannot safely recover from failures
- **Control plane operators degraded** means backup operations may produce inconsistent snapshots
- **OADP absent** means no external backup/restore capability — only etcd snapshots are available
- **OADP with no backups** suggests backup tooling was installed but never configured or run
- **VolumeSnapshotClass presence** indicates cloud provider snapshot integration is available for PV recovery

---

### export-olm-governance.sh

Exports Operator Lifecycle Management governance data — OperatorHub default source restrictions, CatalogSource inventory, Subscription approval policies (Automatic vs Manual), InstallPlan approval status, and OperatorGroup namespace scopes.

```bash
./scripts/export-olm-governance.sh
```

**OC commands used:**

- `oc get operatorhub cluster -o json`
- `oc get catalogsources -A -o json`
- `oc get subscriptions.operators.coreos.com -A -o json`
- `oc get installplans -A -o json`
- `oc get operatorgroups -A -o json`

**Output file:** `olm-governance-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `record_type` | `operatorhub_config`, `catalog_source`, `subscription`, `install_plan`, or `operator_group` |
| `name` | Resource name (e.g., catalog name, subscription name, InstallPlan name) |
| `namespace` | Namespace (e.g., `openshift-marketplace`, operator namespace) |
| `detail_1` | **operatorhub_config**: `disableAllDefaultSources=<bool>` or `disabled=<bool>` · **catalog_source**: display name · **subscription**: install plan approval (`Automatic`/`Manual`) · **install_plan**: approved (`true`/`false`) · **operator_group**: target namespaces (`;`-delimited) |
| `detail_2` | **catalog_source**: source type (`grpc`/`image`) · **subscription**: source catalog name · **install_plan**: phase (`Complete`/`Failed`/`Installing`/`RequiresApproval`) · **operator_group**: scope (`AllNamespaces`/`SingleNamespace`/`MultiNamespace`) |
| `detail_3` | **catalog_source**: image/address · **subscription**: source namespace · **install_plan**: CSV names (`;`-delimited) |
| `detail_4` | **catalog_source**: connection state (`READY`/`CONNECTING`/`TRANSIENT_FAILURE`) · **subscription**: channel |
| `detail_5` | **catalog_source**: security context config · **subscription**: current CSV |
| `detail_6` | **catalog_source**: registry poll interval · **subscription**: installed CSV |
| `detail_7` | **subscription**: state (`AtLatestKnown`/`UpgradePending`/`UpgradeAvailable`) |

**Console warnings:**

| Warning | Meaning |
|---|---|
| community-operators ENABLED | Default community catalog is active — untrusted operators may be installable |
| CatalogSource not READY | One or more catalogs have connection failures |
| Automatic approval subscriptions | Operators can auto-upgrade without manual review threshold |
| InstallPlans awaiting approval | Pending operator upgrades need manual intervention |
| Failed InstallPlans | Operator installations stuck in failed state |
| AllNamespaces OperatorGroups | Operators deployed with cluster-wide scope rather than namespace-scoped |

**What auditors should look for:**

- **`disableAllDefaultSources=false` with community-operators enabled** means unapproved operators are installable from public catalogs
- **Automatic approval subscriptions** bypass manual upgrade thresholds — look for `installPlanApproval=Automatic` in `subscription` rows
- **Manual approval with pending InstallPlans** is security-positive — confirms upgrade gating is working
- **AllNamespaces OperatorGroups** grant operators cluster-wide reach — verify this is intentional for each case
- **Custom CatalogSources** pointing to enterprise registries indicate curated operator catalogs (good governance)
- **Failed InstallPlans** may indicate blocked or incompatible operator upgrades needing remediation

---

### export-etcd-encryption-status.sh

Exports etcd encryption at rest status — global encryption configuration, kubeapiserver and openshiftapiserver operator health, and per-resource encryption migration conditions.

```bash
./scripts/export-etcd-encryption-status.sh
```

**OC commands used:**

- `oc get apiserver cluster -o json`
- `oc get kubeapiserver cluster -o json`
- `oc get openshiftapiserver cluster -o json`

**Output file:** `etcd-encryption-status-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `record_type` | `encryption_config`, `operator_status`, or `encryption_condition` |
| `resource_name` | `apiserver-cluster`, `kubeapiserver`, or `openshiftapiserver` |
| `encryption_type` | Configured encryption type: `aescbc`, `aesgcm`, `identity`, or empty |
| `encryption_enabled` | `true` if type is not `identity`/empty; `false` otherwise |
| `condition_available` | Operator `Available` condition (`True`/`False`) — operator_status rows only |
| `condition_degraded` | Operator `Degraded` condition (`True`/`False`) — operator_status rows only |
| `condition_progressing` | Operator `Progressing` condition (`True`/`False`) — operator_status rows only |
| `condition_type` | Encryption-specific condition type and status (e.g., `EncryptionMigrationControllerDegraded=False`) — encryption_condition rows only |
| `condition_reason` | Reason field from encryption condition |
| `message` | Condition message (degradation details, migration progress) |

**Console warnings:**

| Warning | Meaning |
|---|---|
| Encryption DISABLED | `.spec.encryption.type` is `identity` or empty — etcd data is not encrypted at rest |
| Operator DEGRADED | kubeapiserver or openshiftapiserver is degraded — may indicate encryption migration failure |
| Operator progressing | Encryption migration may be in progress — operator is rolling out new config |

**What auditors should look for:**

- **`encryption_enabled=false`** is a critical finding — etcd stores Secrets, ConfigMaps, OAuth tokens in plaintext
- **Operator degraded during migration** indicates encryption rollout stalled — check message for which resources are affected
- **Operator progressing** after enabling encryption is expected and temporary — recheck after rollout completes
- **No encryption_condition rows** when encryption is enabled and operators are healthy means migration completed successfully
- **encryption_condition rows present** detail per-resource migration status — look for `Degraded=True` conditions
- Cross-reference with `export-control-plane-protections.sh` which captures the same `.spec.encryption.type` as a boolean check

---

### export-governance-policy-ecosystem.sh

Discovery script that inventories governance and policy tooling deployed on the cluster. Probes for 7 products/capabilities and reports what is installed, its version, and key metrics (policy counts, scan status, enforcement modes).

**Record types:** `policy_engine`, `compliance_framework`, `runtime_security`, `multicluster_governance`, `image_registry`, `image_policy`

**Commands used:**

```bash
# CRD detection (per product)
oc get crd constrainttemplates.templates.gatekeeper.sh
oc get crd clusterpolicies.kyverno.io
oc get crd compliancesuites.compliance.openshift.io
oc get crd centrals.platform.stackrox.io
oc get crd securedclusters.platform.stackrox.io
oc get crd policies.policy.open-cluster-management.io
oc get crd quayregistries.quay.redhat.com

# Per-product resource queries (only if CRD exists)
oc get constrainttemplates -o json
oc get <constraint-type> -o json            # per template
oc get clusterpolicies.kyverno.io -o json
oc get policies.kyverno.io -A -o json
oc get compliancesuites -A -o json
oc get centrals -A -o json
oc get securedclusters -A -o json
oc get policies.policy.open-cluster-management.io -A -o json
oc get policysets.policy.open-cluster-management.io -A -o json
oc get quayregistries -A -o json
oc get csv -n <namespace> -o json            # operator version lookup
oc get image.config.openshift.io cluster -o json
```

**Output file:** `governance-policy-ecosystem-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `cluster_name` | Cluster display name |
| `cluster_context` | `oc` context |
| `cluster_server` | API server URL |
| `record_type` | `policy_engine`, `compliance_framework`, `runtime_security`, `multicluster_governance`, `image_registry`, `image_policy` |
| `product_name` | `gatekeeper`, `kyverno`, `compliance-operator`, `acs-stackrox`, `acm`, `quay`, `image-config` |
| `installed` | `true` or `false` |
| `namespace` | Namespace(s) where the product is deployed |
| `operator_version` | OLM CSV version if available |
| `detail_1` | Product-specific: template/policy/suite/registry count |
| `detail_2` | Product-specific: constraint count, policy modes, profiles, secured clusters |
| `detail_3` | Product-specific: enforcement breakdown, scan status |

**`detail_1` / `detail_2` / `detail_3` by product:**

| Product | detail_1 | detail_2 | detail_3 |
|---|---|---|---|
| Gatekeeper | `templates:<N>` | `constraints:<N>` | `deny:<N>;warn:<N>;dryrun:<N>` |
| Kyverno | `cluster_policies:<N>` | `namespace_policies:<N>` | `enforce:<N>;audit:<N>` |
| Compliance Operator | `suites:<N>` | `profiles:<list>` | `status:<suite>=<phase>;...` |
| ACS/StackRox | `centrals:<ns/name>` | `secured_clusters:<ns/name>` | |
| ACM | `policies:<N>` | `policy_sets:<N>` | |
| Quay | `registries:<N>` | | |
| Image Policy | `allowed:<registries>` | `blocked:<registries>` | `insecure:<registries>` |

**Console warnings:**

| Warning | Meaning |
|---|---|
| CRITICAL: No policy engine detected | Neither Gatekeeper nor Kyverno is installed — no admission policy enforcement |
| CRITICAL: Zero governance products detected | No products at all — cluster has no policy tooling |
| WARNING: Compliance Operator not detected | No automated compliance scanning (CIS, NIST, etc.) |
| WARNING: ACS/StackRox not detected | No runtime security enforcement |
| WARNING: No image registry allow/block lists | `image.config.openshift.io` has no registry restrictions |

**What auditors should look for:**

- **Zero policy engines** is a critical finding — the cluster cannot enforce admission policies
- **Gatekeeper or Kyverno installed but zero policies** means the engine is deployed but unused
- **Compliance Operator absent** means no automated CIS/NIST benchmarking
- **ACS/StackRox absent** means no runtime threat detection or network policy enforcement
- **ACM absent** on a hub cluster means no centralized multi-cluster policy propagation
- **Image policy not configured** means any container registry can be used — supply chain risk
- **Compare across clusters** — all clusters should have the same governance toolbox
- Cross-reference with `export-policy-as-code.sh` for detailed Gatekeeper constraint-level data

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
| **CI/CD Pipeline Enforcement** | `export-cicd-pipeline-enforcement.sh` |
| **Control Plane Protections** | `export-control-plane-protections.sh` |
| **Patch & Version Lifecycle Management** | `export-patch-lifecycle.sh` |
| **Secrets & Certificate Rotation** | `export-secrets-cert-rotation.sh` |
| **Disaster Recovery & Cluster Backup** | `export-disaster-recovery-backup.sh` |
| **Operator Lifecycle Management (OLM) Control** | `export-olm-governance.sh` |
| **Etcd Encryption At Rest** | `export-etcd-encryption-status.sh` |
| **Governance & Policy Ecosystem** | `export-governance-policy-ecosystem.sh` |
