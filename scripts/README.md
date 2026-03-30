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

## `export-secrets-integration.sh`

Discovers enterprise secrets integration on the cluster — External Secrets Operator, Secrets Store CSI Driver, HashiCorp Vault, CyberArk Conjur — and provides a native Kubernetes secrets summary by type.

**`oc` commands used:**

```bash
oc get crd externalsecrets.external-secrets.io
oc get secretstores.external-secrets.io -A -o json
oc get clustersecretstores.external-secrets.io -o json
oc get externalsecrets.external-secrets.io -A -o json
oc get crd secretproviderclasses.secrets-store.csi.x-k8s.io
oc get secretproviderclasses.secrets-store.csi.x-k8s.io -A -o json
oc get crd vaultconnections.secrets.hashicorp.com
oc get vaultconnections.secrets.hashicorp.com -A -o json
oc get vaultstaticsecrets.secrets.hashicorp.com -A -o json
oc get vaultdynamicsecrets.secrets.hashicorp.com -A -o json
oc get pods -n <vault-ns> -o json
oc get pods -n <conjur-ns> -o json
oc get configmaps -A -o json
oc get secrets -A -o json
oc get csv -n <ns> -o json
```

**Output file:** `secrets-integration-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `cluster_name` | Cluster display name |
| `cluster_context` | `oc` context |
| `cluster_server` | API server URL |
| `record_type` | `external_secrets`, `csi_secrets`, `vault`, `conjur`, `native_summary` |
| `product_name` | `external-secrets-operator`, `secrets-store-csi-driver`, `hashicorp-vault`, `cyberark-conjur`, `kubernetes-secrets` |
| `installed` | `true` or `false` |
| `namespace` | Namespace(s) where the product is deployed |
| `operator_version` | OLM CSV version if available |
| `detail_1` | Product-specific: store counts, instance counts, secret type breakdown |
| `detail_2` | Product-specific: external secret count, provider types, follower/authenticator counts |
| `detail_3` | Product-specific: sync status, pod counts, seal status |

**`detail_1` / `detail_2` / `detail_3` by product:**

| Product | detail_1 | detail_2 | detail_3 |
|---|---|---|---|
| External Secrets Operator | `secret_stores:<N>;cluster_stores:<N>` | `external_secrets:<N>` | `synced:<N>;not_synced:<N>` |
| Secrets Store CSI Driver | `provider_classes:<N>` | `providers:<list>` | `driver_pods:<N>` |
| HashiCorp Vault | `total:<N>;running:<N>[;vso_connections:<N>;static_secrets:<N>;dynamic_secrets:<N>]` | `injector_pods:<N>` | `sealed:<N\|unknown>` |
| CyberArk Conjur | `followers:<N>` or `sidecar_mode` | `configmaps_detected:<N>` or `configmaps:<N>` | |
| Kubernetes Secrets (native) | `total:<N>;opaque:<N>;tls:<N>` | `sa_token:<N>;dockercfg:<N>;other:<N>` | `namespaces_with_secrets:<N>` |

**Console warnings:**

| Warning | Meaning |
|---|---|
| CRITICAL: No external secrets provider detected | No ESO, Vault, CSI Driver, or Conjur — all secrets are stored natively in etcd |
| WARNING: N Opaque secrets with no external provider | Opaque secrets exist without an enterprise secrets manager |
| WARNING: External Secrets Operator installed but zero ExternalSecrets | ESO is deployed but not in use |
| WARNING: Secrets Store CSI Driver installed but zero SecretProviderClasses | CSI driver is deployed but not in use |

**What auditors should look for:**

- **Zero external providers** is a critical finding — the organization has no enterprise secrets management integration
- **ESO or CSI driver installed but unused** means tooling is deployed but not adopted by application teams
- **HashiCorp Vault deployed with sealed instances** indicates a Vault availability issue
- **High Opaque secret count** with no external provider suggests credentials may be manually managed in-cluster
- **CyberArk in sidecar mode** means secrets injection is happening per-pod rather than via a centralized operator
- Compare across clusters to ensure all production clusters have the same secrets management stack
- Cross-reference with `export-secrets-cert-rotation.sh` for TLS certificate rotation health
- Cross-reference with `export-etcd-encryption-status.sh` to verify secrets are encrypted at rest

---

## `export-shared-responsibility-model.sh`

Exports namespace-level tenant boundary controls — project request template configuration, namespace ownership metadata, ResourceQuotas, LimitRanges, NetworkPolicies, and namespace-scoped RoleBindings. Focuses on tenant (non-system) namespaces to document the shared responsibility boundary between platform teams and application teams.

**`oc` commands used:**

```bash
oc get project.config.openshift.io/cluster -o json
oc get template <name> -n openshift-config -o json
oc get namespaces -o json
oc get resourcequotas -A -o json
oc get limitranges -A -o json
oc get networkpolicies -A -o json
oc get rolebindings -n <namespace> -o json
```

**Output file:** `shared-responsibility-model-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `cluster_name` | Cluster display name |
| `cluster_context` | `oc` context |
| `cluster_server` | API server URL |
| `record_type` | `project_template`, `namespace`, `resource_quota`, `limit_range`, `network_policy`, `rolebinding` |
| `namespace` | Namespace name (or `(cluster)` for project template) |
| `name` | Resource name |
| `detail_1` | Section-specific (see table below) |
| `detail_2` | Section-specific |
| `detail_3` | Section-specific |
| `detail_4` | Section-specific |

**`detail_1` / `detail_2` / `detail_3` / `detail_4` by record type:**

| Record Type | detail_1 | detail_2 | detail_3 | detail_4 |
|---|---|---|---|---|
| Project Template | `has_quota:<N>` | `has_limitrange:<N>` | `has_networkpolicy:<N>` | `object_kinds:<list>` |
| Namespace | `owner:<name>` | `team:<name>` | `environment:<env>;status:<phase>;created:<ts>` | `node_selector:<selector>` |
| ResourceQuota | `hard_cpu:<val>;hard_memory:<val>` | `hard_pods:<val>;hard_storage:<val>` | `used_cpu:<val>;used_memory:<val>;used_pods:<val>` | |
| LimitRange | `default_cpu:<val>;default_memory:<val>` | `default_request_cpu:<val>;default_request_memory:<val>` | `max_cpu:<val>;max_memory:<val>` | `types:<list>` |
| NetworkPolicy | `policy_types:<Ingress;Egress>` | `pod_selector:<labels>` | `ingress_rules:<N>;egress_rules:<N>` | `default_deny:<bool>` |
| RoleBinding | `role_ref:<kind>/<name>` | `subjects:<kind:name;...>` | `subject_count:<N>` | |

**Console warnings:**

| Warning | Meaning |
|---|---|
| CRITICAL: No project template + no quotas/limits/netpols | Tenant boundaries are completely unenforced |
| WARNING: No project request template configured | New projects get default settings only |
| WARNING: Project template has no ResourceQuota | New projects get no resource limits |
| WARNING: Project template has no NetworkPolicy | New projects get no network isolation |
| WARNING: N tenant namespaces have no owner or team label | Namespace ownership is not documented |
| WARNING: N tenant namespaces have no ResourceQuota | Resource consumption is unbounded |
| WARNING: N tenant namespaces have no LimitRange | Pods without limits get no defaults |
| WARNING: N tenant namespaces have no NetworkPolicy | Flat network, no tenant isolation |

**What auditors should look for:**

- **No project request template** is a significant finding — new projects get no default boundaries
- **Namespaces without ResourceQuotas** can consume unlimited CPU/memory/storage
- **Namespaces without LimitRanges** allow pods to run without resource requests/limits
- **Namespaces without NetworkPolicies** have unrestricted network access across the cluster
- **Missing owner/team labels** means no clear accountability for namespace resources
- **RoleBindings with broad roles** (admin, edit) granted to many subjects indicate loose RBAC delegation
- **Empty node-selector annotations** mean tenant workloads can schedule on any node including infra/master
- Compare coverage ratios across clusters — production should have 100% quota/limit/netpol coverage
- Cross-reference with `export-clusterrolebindings.sh` for cluster-wide vs. namespace-scoped access patterns
- Cross-reference with `export-platform-guardrails.sh` for cluster-level configuration guardrails

---

## export-monitoring-audit-logging.sh

Exports observability, audit logging, and centralized log retention — cluster monitoring operator health, cluster monitoring config, user workload monitoring, Datadog integration, cluster logging and log forwarding with output destination TLS verification, audit log forwarding validation, LokiStack log retention, alerting rules, and Alertmanager receivers.

### Commands Used

```bash
oc get clusteroperator monitoring -o json
oc get configmap cluster-monitoring-config -n openshift-monitoring -o json
oc get namespace openshift-user-workload-monitoring
oc get pods -n openshift-user-workload-monitoring --no-headers
oc get configmap user-workload-monitoring-config -n openshift-user-workload-monitoring -o json
oc get apiserver.config.openshift.io/cluster -o json
oc get crd datadogagents.datadoghq.com
oc get datadogagents.datadoghq.com -A -o json
oc get csv -n <datadog-ns> -o json
oc get daemonset -n <ns> -o json
oc get pods -n <datadog-ns> --no-headers
oc get clusteroperator cluster-logging -o json
oc get crd clusterloggings.logging.openshift.io
oc get clusterlogging instance -n openshift-logging -o json
oc get clusterlogforwarder instance -n openshift-logging -o json
oc get crd lokistacks.loki.grafana.com
oc get lokistacks -n openshift-logging -o json
oc get prometheusrules -A -o json
oc get secret alertmanager-main -n openshift-monitoring -o json
```

### Output File

`monitoring-audit-logging-<cluster>-<timestamp>.csv`

### Columns

| Column | Description |
|---|---|
| `cluster_name` | Name of the OpenShift cluster |
| `cluster_context` | Current kube context |
| `cluster_server` | API server URL |
| `record_type` | One of: `cluster_operator`, `monitoring_config`, `user_workload_monitoring`, `audit_policy`, `external_monitoring`, `cluster_logging`, `log_forwarder`, `log_forwarder_output`, `audit_forwarding`, `log_retention`, `lokistack`, `alerting_rules`, `alertmanager` |
| `component_name` | Component or product name (e.g., `monitoring`, `Datadog`, `ClusterLogForwarder`) |
| `status` | Health status or configuration state |
| `namespace` | Namespace where the component lives |
| `detail_1` | Component-specific detail (see below) |
| `detail_2` | Component-specific detail |
| `detail_3` | Component-specific detail |
| `detail_4` | Component-specific detail |

### Record Types and Details

| Record Type | detail_1 | detail_2 | detail_3 | detail_4 |
|---|---|---|---|---|
| `cluster_operator` | Operator version | Available status | Degraded status | Progressing status |
| `monitoring_config` | Retention period | Storage class | Storage size | UWM enabled via config |
| `user_workload_monitoring` | Pod count | Retention | Storage class | — |
| `audit_policy` | Audit profile level | Custom rules count | — | — |
| `external_monitoring` | Version; agent pod count | Log collection; APM | Process monitoring; cluster agent | — |
| `cluster_logging` | Operator version | Collection type | Log store type | Status |
| `log_forwarder` | Output destinations | Pipelines | Input types | — |
| `log_forwarder_output` | Destination URL (redacted) | TLS configured (boolean) | TLS scheme (boolean) | — |
| `audit_forwarding` | Audit in pipelines (boolean) | Audit destinations | — | — |
| `log_retention` | App retention | Infra retention | Audit retention | — |
| `lokistack` | Size; tenant mode | Storage type | Global retention (days) | Stream retention |
| `alerting_rules` | Critical; warning; info counts | Recording rules count | Rule object count | Namespace count |
| `alertmanager` | Receiver count | Receiver types | Route count | — |

### Console Warnings

| Warning | Meaning |
|---|---|
| WARNING: Monitoring operator is degraded | Prometheus/Alertmanager stack may be unhealthy |
| WARNING: No cluster-monitoring-config ConfigMap | Using all monitoring defaults — no persistent storage, default retention |
| WARNING: User workload monitoring is DISABLED | Tenant workloads cannot emit custom metrics |
| WARNING: Audit profile is 'Default' | API request bodies NOT logged — consider WriteRequestBodies for compliance |
| CRITICAL: No external monitoring, no cluster logging, no log forwarding | Usage is NOT being monitored externally |
| CRITICAL: Audit profile 'Default' with no external log aggregation | Unapproved usage cannot be detected |
| WARNING: No log retention policy configured in ClusterLogging | Using log store defaults — retention period unknown |
| ERROR: Audit logs are NOT included in any CLF pipeline | Audit events not forwarded to centralized logging |
| CRITICAL: CLF exists but audit logs are NOT forwarded | Audit events stay local and may be lost |

**What auditors should look for:**

- **Monitoring operator degraded** means Prometheus/Alertmanager may not be collecting or alerting properly
- **No cluster-monitoring-config** means default 15-day retention with no persistent storage — metrics lost on pod restart
- **User workload monitoring disabled** means teams cannot define custom ServiceMonitors or PrometheusRules
- **Audit profile 'Default'** only logs metadata, not request bodies — insufficient for forensics
- **Datadog not installed** (when expected) or **log collection disabled** means gaps in log aggregation
- **No ClusterLogForwarder** means audit/application/infrastructure logs are not forwarded to a SIEM
- **CLF output missing TLS** means log data in transit may not be encrypted — check `tls_configured` and `tls_scheme` columns
- **Audit logs not forwarded** (audit_forwarding record shows `false`) means API audit events stay local and may be lost on node rotation
- **No log retention policy** means ClusterLogging/Elasticsearch uses defaults — logs may be deleted before investigation windows close
- **LokiStack not installed** (when expected) or global retention not configured means no guaranteed log retention period
- **No alert rules** or **only default receivers** means the cluster cannot notify on anomalous usage
- Cross-reference alerting rules with Alertmanager receivers — rules without receivers fire silently
- Cross-reference with `export-apiserver-console-access.sh` which also reports the audit profile level

---

## `export-configuration-drift-status.sh`

Exports configuration drift signals across multiple detection sources: ArgoCD sync drift, Flux reconciliation status, Compliance Operator scan results, node version consistency, and operator version consistency.

### Commands Used

```bash
oc get crd applications.argoproj.io
oc get applications.argoproj.io -A -o json
oc get crd helmreleases.helm.toolkit.fluxcd.io
oc get crd kustomizations.kustomize.toolkit.fluxcd.io
oc get helmreleases.helm.toolkit.fluxcd.io -A -o json
oc get kustomizations.kustomize.toolkit.fluxcd.io -A -o json
oc get crd compliancescans.compliance.openshift.io
oc get compliancescans -A -o json
oc get compliancecheckresults -A -o json
oc get nodes -o json
oc get clusteroperators -o json
```

### Output File

`configuration-drift-status-<cluster>-<timestamp>.csv`

### Columns

| Column | Description |
|---|---|
| `cluster_name` | Name of the OpenShift cluster |
| `cluster_context` | Current kube context |
| `cluster_server` | API server URL |
| `record_type` | One of: `gitops_summary`, `gitops_drift`, `gitops_degraded`, `flux_summary`, `flux_drift`, `compliance_scan`, `compliance_results_summary`, `compliance_fail`, `node_consistency`, `node_version_drift`, `operator_consistency`, `operator_version_drift`, `operator_degraded` |
| `component_name` | Component or resource name (e.g., `ArgoCD`, app name, node name, operator name) |
| `status` | Sync status, health state, or version count |
| `namespace` | Namespace where the component lives |
| `detail_1` | Component-specific detail (see below) |
| `detail_2` | Component-specific detail |
| `detail_3` | Component-specific detail |
| `detail_4` | Component-specific detail |

### Record Types and Details

| Record Type | detail_1 | detail_2 | detail_3 | detail_4 |
|---|---|---|---|---|
| `gitops_summary` | apps:N;synced:N;out_of_sync:N;unknown:N | healthy:N;degraded:N | — | — |
| `gitops_drift` | repo URL | path | health status | sync policy |
| `gitops_degraded` | sync status | health message | — | — |
| `flux_summary` | ready:N;not_ready:N | — | — | — |
| `flux_drift` | type (HelmRelease/Kustomization) | chart or path | condition message | — |
| `compliance_scan` | phase | profile | content image | — |
| `compliance_results_summary` | pass:N;fail:N | manual:N;error:N | other:N | — |
| `compliance_fail` | severity | scan name | description (truncated) | — |
| `node_consistency` | versions or images list | node count | — | — |
| `node_version_drift` | kubelet version | majority version | OS image | node role |
| `operator_consistency` | versions list | majority version | operator count | — |
| `operator_version_drift` | version | majority version | degraded status | progressing status |
| `operator_degraded` | version | degraded message | — | — |

### Console Warnings

| Warning | Meaning |
|---|---|
| WARNING: N ArgoCD applications are OutOfSync | GitOps-managed resources have drifted from git |
| WARNING: N Flux resources are not reconciled | Flux HelmReleases or Kustomizations failed to apply |
| WARNING: N compliance checks FAILED | Drift from security compliance baseline detected |
| WARNING: N different kubelet versions detected | Nodes not at the same Kubernetes version |
| WARNING: N different OS images detected | Nodes at different RHCOS versions |
| WARNING: N different operator versions detected | Cluster upgrade may be in-progress or stalled |
| ERROR: N ClusterOperators are Degraded | Misconfigured components (K09) — operator health issue |
| CRITICAL: No GitOps and no Compliance Operator | No drift detection tooling installed |

**What auditors should look for:**

- **ArgoCD OutOfSync apps** indicate live cluster state has drifted from the declared git source of truth — investigate manual changes
- **ArgoCD apps with manual sync policy** cannot self-heal drift; prefer `automated` sync with `selfHeal: true`
- **Flux NotReady resources** mean desired state from Helm charts or kustomize overlays is not applied
- **Compliance FAIL results** represent specific CIS/NIST checks that the cluster does not pass — cross-reference with `export-governance-policy-ecosystem.sh`
- **Multiple kubelet versions** across nodes means an upgrade is incomplete or stalled — cross-reference with `export-patch-lifecycle.sh` MachineConfigPool status
- **Multiple operator versions** means a cluster upgrade has not fully rolled out — check for `Progressing` operators
- **Degraded operators** are a K09 misconfiguration signal — the operator cannot achieve desired state
- **No GitOps tooling and no Compliance Operator** means the cluster has no automated drift detection — manual configuration changes go undetected

---

## `export-vulnerability-runtime-detection.sh`

Exports vulnerability scanning and runtime threat detection posture — ACS/StackRox SecuredCluster scanner and collector configuration, Compliance Operator scan settings and bindings, image provenance controls (mirror sets, registry restrictions), and third-party security tool detection (Falco, NeuVector, Sysdig, CrowdStrike, Prisma Cloud, Aqua Security) with DaemonSet health.

### Commands Used

```bash
oc get crd securedclusters.platform.stackrox.io
oc get securedclusters.platform.stackrox.io -A -o json
oc get pods -n <acs-ns> --no-headers -l 'app in (scanner,scanner-v4)'
oc get crd scansettings.compliance.openshift.io
oc get scansettings.compliance.openshift.io -A -o json
oc get crd scansettingbindings.compliance.openshift.io
oc get scansettingbindings.compliance.openshift.io -A -o json
oc get crd imagedigestmirrorsets.config.openshift.io
oc get imagedigestmirrorsets.config.openshift.io -o json
oc get crd imagetagmirrorsets.config.openshift.io
oc get imagetagmirrorsets.config.openshift.io -o json
oc get crd imagecontentsourcepolicies.operator.openshift.io
oc get imagecontentsourcepolicies.operator.openshift.io -o json
oc get image.config.openshift.io cluster -o json
oc get crd falcos.falco.org
oc get ds -A -l 'app.kubernetes.io/name=falco' -o json
oc get crd neuvectors.neuvector.com
oc get deployment -A -l 'app=neuvector-controller-pod' -o json
oc get crd sysdigagents.sysdig.com
oc get ds -A -l 'app.kubernetes.io/name=sysdig-agent' -o json
oc get crd falconnodesensors.falcon.crowdstrike.com
oc get ds -A -l 'crowdstrike.com/provider=crowdstrike' -o json
oc get crd defenders.twistlock.com
oc get crd aquastarboards.aquasecurity.github.io
oc get ds -A -o json
```

### Output File

`vulnerability-runtime-detection-<cluster>-<timestamp>.csv`

### Columns

| Column | Description |
|---|---|
| `cluster_name` | Name of the OpenShift cluster |
| `cluster_context` | Current kube context |
| `cluster_server` | API server URL |
| `record_type` | One of: `acs_secured_cluster`, `acs_scanner`, `scan_setting`, `scan_setting_binding`, `image_digest_mirror`, `image_tag_mirror`, `image_content_source`, `image_config`, `runtime_falco`, `runtime_neuvector`, `runtime_sysdig`, `runtime_crowdstrike`, `runtime_prisma`, `runtime_aqua`, `security_daemonset`, `summary` |
| `component_name` | Tool or resource name |
| `status` | Installation state, health, or pod readiness |
| `namespace` | Namespace where the component lives |
| `detail_1` | Component-specific detail (see below) |
| `detail_2` | Component-specific detail |
| `detail_3` | Component-specific detail |
| `detail_4` | Component-specific detail |

### Record Types and Details

| Record Type | detail_1 | detail_2 | detail_3 | detail_4 |
|---|---|---|---|---|
| `acs_secured_cluster` | Scanner config (autoscale;replicas;db) | Admission control (creates;updates;events;bypass) | Collector config (collection;taintToleration) | — |
| `acs_scanner` | Running pod count | Total pod count | — | — |
| `scan_setting` | Roles; rotation; maxRetry | — | — | — |
| `scan_setting_binding` | ScanSetting name | Bound profiles | — | — |
| `image_digest_mirror` | Mirror sources | — | — | — |
| `image_tag_mirror` | Mirror sources | — | — | — |
| `image_content_source` | Mirror sources | Type (legacy_deprecated) | — | — |
| `image_config` | Allowed registries | Blocked registries | Additional trusted CA | Insecure registries |
| `runtime_falco` | CRD present (boolean) | — | — | — |
| `runtime_neuvector` | CRD present (boolean) | — | — | — |
| `runtime_sysdig` | CRD present (boolean) | — | — | — |
| `runtime_crowdstrike` | CRD present (boolean) | — | — | — |
| `runtime_prisma` | CRD present (boolean) | — | — | — |
| `runtime_aqua` | CRD present (boolean) | — | — | — |
| `security_daemonset` | Container images | — | — | — |
| `summary` | ACS presence | Compliance ScanSettings | Falco CRD | Further tool CRDs |

### Console Warnings

| Warning | Meaning |
|---|---|
| CRITICAL: No vulnerability scanning tool detected | Containers and pods are NOT being scanned for CVEs |
| CRITICAL: No runtime threat detection tool detected | Cluster has no runtime anomaly monitoring |
| WARNING: No image registry allow/block list configured | Images can be pulled from any registry |

**What auditors should look for:**

- **No ACS SecuredCluster** means the primary OpenShift vulnerability scanner is not deployed — check whether an alternative is present
- **ACS collector method** should be `CORE_BPF` or `EBPF` for kernel-level runtime monitoring; `NO_COLLECTION` disables runtime detection
- **ACS admission control** with `listenOnCreates: false` means vulnerable images can be deployed without admission checks
- **No Compliance Operator ScanSettings** means vulnerability/compliance scans are not scheduled — check `export-configuration-drift-status.sh` for scan results
- **ScanSettingBindings** bind security profiles to scan schedules — missing bindings mean profiles are defined but unused
- **Image registry restrictions** not configured (no allow/block list) means any registry can serve images to the cluster
- **ImageContentSourcePolicy** is deprecated in OCP 4.18 — migrate to `ImageDigestMirrorSet`
- **No runtime threat detection tool** means the cluster cannot detect anomalous process execution, file access, or network activity at runtime
- **Security DaemonSets in tenant namespaces** may indicate team-deployed security agents — verify they are authorized
- Cross-reference with `export-governance-policy-ecosystem.sh` for ACS/StackRox presence and image policy
- Cross-reference with `export-configuration-drift-status.sh` for Compliance Operator scan results

---

### export-network-security-mesh.sh

Exports network security posture and service mesh enforcement: cluster network configuration, IPsec/transit encryption, Multus NetworkAttachmentDefinitions (CNI plugin usage), egress firewalls, AdminNetworkPolicy / BaselineAdminNetworkPolicy (cluster-scoped network segmentation), default-deny posture for inter-project traffic, exposed services (NodePort/LoadBalancer), IngressControllers, Route TLS summary, Gateway API detection, and service mesh (OSSM/Istio) with mTLS and sidecar injection detection.

```bash
./scripts/export-network-security-mesh.sh
```

**OC commands:**

```bash
oc get network.config.openshift.io cluster -o json
oc get network.operator.openshift.io cluster -o json
oc get egressfirewalls.k8s.ovn.org -A -o json
oc get egressnetworkpolicies.network.openshift.io -A -o json
oc get adminnetworkpolicies.policy.networking.k8s.io -o json
oc get baselineadminnetworkpolicies.policy.networking.k8s.io -o json
oc get network-attachment-definitions.k8s.cni.cncf.io -A -o json
oc get services -A -o json
oc get ingresscontrollers -n openshift-ingress-operator -o json
oc get routes -A -o json
oc get gateways.gateway.networking.k8s.io -A -o json
oc get httproutes.gateway.networking.k8s.io -A -o json
oc get servicemeshcontrolplanes.maistra.io -A -o json
oc get servicemeshmemberrolls.maistra.io -A -o json
oc get peerauthentications.security.istio.io -A -o json
oc get destinationrules.networking.istio.io -A -o json
oc get namespaces -o json
oc get kialis.kiali.io -A -o json
oc get jaegers.jaegertracing.io -A -o json
```

**Output file:** `network-security-mesh-<cluster>-<timestamp>.csv`

| Column | Description |
|---|---|
| `record_type` | Row category (see Record Types below) |
| `component_name` | Resource name or identifier |
| `status` | Current state or condition summary |
| `namespace` | Kubernetes namespace (if applicable) |
| `detail_1` | Primary configuration details |
| `detail_2` | Secondary configuration details |
| `detail_3` | Additional metadata |
| `detail_4` | Reserved for extra context |

### Record Types and Details — Network Security & Mesh

| Record Type | detail_1 | detail_2 | detail_3 | detail_4 |
|---|---|---|---|---|
| `cluster_network` | Cluster CIDRs | Host prefixes | Service CIDRs | ExternalIP policy |
| `network_operator` | Default network type | Additional networks count | — | — |
| `network_encryption` | Geneve port | Routing via host | MTU | — |
| `network_attachment_definition` | CNI type and plugins | Resource name annotation | — | — |
| `cni_plugin_summary` | Additional networks count | NAD count | Multus CRD presence | — |
| `egress_firewall` | Rule count | Allow/deny counts | DNS rule count | — |
| `egress_network_policy` | Rule count | Allow/deny counts | Type (legacy_sdn) | — |
| `admin_network_policy` | Subject (namespace/pod selector) | Ingress/egress rule counts | Ingress actions | Egress actions |
| `baseline_admin_network_policy` | Subject (namespace/pod selector) | Ingress/egress rule counts | Ingress actions | Egress actions |
| `default_deny_posture` | BANP deny-all detected (true/false) | AdminNetworkPolicy count | BaselineANP count | — |
| `service_nodeport` | Ports (port:nodePort/proto) | Selector labels | External IPs | — |
| `service_loadbalancer` | Ports (port/proto) | Load balancer IP/hostname | External traffic policy | — |
| `exposed_services_summary` | Total exposed count | — | — | — |
| `ingress_controller` | Domain and publish strategy | TLS profile and min version | Replicas and route admission | Wildcard policy |
| `route_tls_summary` | Edge/passthrough/reencrypt counts | No-TLS count | Insecure allow/redirect/none | — |
| `route_no_tls` | Hostname | — | — | — |
| `route_insecure_allow` | Hostname | TLS termination type | — | — |
| `gateway` | Gateway class | Listener and TLS counts | — | — |
| `gateway_httproute_summary` | — | — | — | — |
| `service_mesh_control_plane` | Version | Data-plane and control-plane mTLS | Ready reason | — |
| `service_mesh_member_roll` | Spec members | Configured members | — | — |
| `peer_authentication_summary` | STRICT/PERMISSIVE/DISABLE counts | — | — | — |
| `peer_authentication` | — (non-STRICT individual entries) | — | — | — |
| `destination_rule_summary` | ISTIO_MUTUAL/MUTUAL counts | SIMPLE/DISABLE/unset counts | — | — |
| `sidecar_injection` | — | — | — | — |
| `mesh_observability` | CRD presence | — | — | — |
| `summary` | Network type | Egress firewall count | Exposed service count | Mesh installed |
| `transit_encryption_summary` | Routes no-TLS / insecure-allow counts | ANP / BANP counts | Mesh installed | Network type |

### Console Warnings — Network Security & Mesh

| Warning | Meaning |
|---|---|
| Routes have NO TLS configured | Unencrypted traffic — data in transit is not protected |
| Routes allow insecure (HTTP) traffic | HTTP is permitted alongside HTTPS — potential downgrade attack |
| No EgressFirewall or EgressNetworkPolicy found | Egress traffic is unrestricted — pods can reach any external endpoint |
| No service mesh (OSSM/Istio) detected | No mTLS enforcement between services — east-west traffic is unencrypted |
| No ExternalIP policy configured | External IPs may be assignable without restriction |
| IPsec is disabled | Pod-to-pod traffic is not encrypted at the network layer |
| No AdminNetworkPolicy or BaselineAdminNetworkPolicy found | No cluster-scoped network segmentation policies |
| No BaselineAdminNetworkPolicy with Deny action found | No cluster-wide default-deny posture for inter-project traffic (OCP.36) |

**What auditors should look for:**

- **Network type** should be `OVNKubernetes` on OCP 4.18 — `OpenShiftSDN` is deprecated
- **No egress firewalls** means pods can reach any external endpoint — check whether this is compensated by external firewalls
- **NodePort services** expose application ports on every node — verify each is intentional and authorized
- **LoadBalancer services** provision cloud load balancers — check for services in tenant namespaces that should use Routes instead
- **IngressController TLS profile** should be `Intermediate` or `Custom` with TLS 1.2+ — `Old` allows TLS 1.0/1.1
- **Routes with no TLS** serve plaintext HTTP — should be TLS-terminated at minimum (`edge`, `reencrypt`, or `passthrough`)
- **Routes allowing insecure traffic** (insecureEdgeTerminationPolicy=Allow) permit HTTP alongside HTTPS
- **Gateway API** presence indicates newer ingress model — check both OCP Routes and Gateway API for complete picture
- **No OSSM/Istio** means inter-service communication is not mTLS-protected — verify network policies provide equivalent segmentation
- **PeerAuthentication mode** should be `STRICT` for mTLS enforcement — `PERMISSIVE` accepts plaintext
- **DestinationRule TLS mode** `DISABLE` turns off mTLS for specific destinations — verify this is intentional
- **Sidecar injection** labels on namespaces indicate mesh enrollment — unlabeled namespaces are not mesh-protected
- Cross-reference with `export-shared-responsibility-model.sh` for per-namespace NetworkPolicy coverage
- Cross-reference with `export-platform-guardrails.sh` for external IP policy validation
- **IPsec mode** should be `Full` for pod-to-pod encryption — `Disabled` means traffic between nodes is unencrypted
- **AdminNetworkPolicy** provides cluster-scoped network segmentation that overrides namespace NetworkPolicies — verify priority ordering
- **BaselineAdminNetworkPolicy** is the lowest-priority fallback — use for cluster-wide default-deny or default-allow baselines
- **Default deny posture** (`default_deny_posture` record) — if `banpDenyAll` is `false` and no ANPs exist, inter-project traffic has no cluster-wide deny baseline; cross-reference per-namespace NetworkPolicy default-deny in `export-shared-responsibility-model.sh`
- Cross-reference with `export-shared-responsibility-model.sh` for per-namespace NetworkPolicy counts and default-deny status
- **Multus / NetworkAttachmentDefinitions** indicate secondary network interfaces — verify each NAD is authorized and its CNI type is appropriate
- **No NADs** with Multus present may indicate misconfiguration — additional networks configured in the operator should have corresponding NADs

---

### export-ingress-boundary-protection.sh

Exports external ingress/egress boundary protection and internal service exposure: WAF/API Gateway detection via IngressController and Route annotations, 3scale APIManager/APIcast instances, Gateway API resources, and internal service exposure audit including ExternalName services, services with externalIPs, and endpoints with external (non-pod) targets.

```bash
./scripts/export-ingress-boundary-protection.sh
```

**OC commands used:**

```bash
oc get ingresscontrollers -n openshift-ingress-operator -o json
oc get routes -A -o json
oc get crd apimanagers.apps.3scale.net
oc get apimanagers -A -o json
oc get crd apicasts.apps.3scale.net
oc get apicasts -A -o json
oc get crd gateways.gateway.networking.k8s.io
oc get gateways -A -o json
oc get services -A -o json
oc get endpoints -A -o json
```

**Output file:** `ingress-boundary-protection-<cluster>-<timestamp>.csv`

| Record Type | detail_1 | detail_2 | detail_3 | detail_4 |
|---|---|---|---|---|
| `ingress_waf_check` | WAF annotations found | Rate-limit annotations | Custom annotations | — |
| `route_waf_annotation` | WAF annotation keys | Rate-limit annotation keys | — | — |
| `route_ip_whitelist_summary` | Total routes | — | — | — |
| `threescale_api_manager` | Wildcard domain | APIcast staging/production replicas | Status conditions | — |
| `apicast_instance` | Replicas | Admin portal reference | — | — |
| `gateway_api_instance` | Gateway class | Listener count | — | — |
| `api_gateway_summary` | 3scale CRD presence | APIcast CRD presence | Gateway API CRD presence | Instance counts |
| `service_external_name` | Target external hostname | — | — | — |
| `service_external_ip` | Service type | External IPs | Ports | — |
| `endpoint_external_target` | External IP addresses | Address count | — | — |
| `service_type_summary` | ClusterIP/NodePort counts | LoadBalancer/ExternalName counts | ExternalIP service count | External endpoint count |
| `boundary_protection_summary` | Route WAF annotation count | IP whitelist route count | 3scale/APIcast CRD presence | Gateway API/APIManager counts |

### Console Warnings — Ingress Boundary Protection

| Warning | Meaning |
|---|---|
| No WAF annotations, API gateway, or 3scale detected | External traffic has no application-layer protection (OCP.35) |
| ExternalName service(s) found | DNS rebinding risk — verify each is authorized (OCP.37) |
| Services have externalIPs set | Bypasses normal ingress controls — verify each is authorized (OCP.37) |
| Endpoints have external (non-pod) targets | Traffic may leave the cluster without ingress controls (OCP.37) |

**What auditors should look for:**

- **No WAF/API gateway** means external HTTP traffic reaches applications without application-layer filtering (SQLi, XSS, etc.) — verify whether boundary protection is provided by external WAF appliances or CDN
- **IngressController WAF annotations** (e.g., ModSecurity, F5, Cloudflare, AWS WAF) indicate application-layer protection is configured at the ingress level
- **Route WAF annotations** indicate per-route WAF or rate-limiting configuration — check whether critical routes have protection
- **IP whitelist annotations** on routes restrict source IPs — verify these match expected client ranges
- **3scale APIManager** provides API management (rate limiting, key management, analytics) — verify production instances are deployed and healthy
- **ExternalName services** create DNS aliases to external endpoints — risk of DNS rebinding attacks; each should be authorized and documented
- **Services with externalIPs** bypass the normal ingress path (Routes/IngressControllers) — this is a high-risk pattern that should be explicitly approved
- **Endpoints with external targets** (no pod targetRef) indicate manually-managed backends pointing outside the cluster — verify these are intentional
- Cross-reference with `export-network-security-mesh.sh` for NodePort/LoadBalancer exposed services and IngressController TLS configuration
- Cross-reference with `export-platform-guardrails.sh` for ExternalIP policy configuration
- Cross-reference with `export-shared-responsibility-model.sh` for per-namespace NetworkPolicy coverage of internal services

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
| **Industry Framework Alignment** | `export-governance-policy-ecosystem.sh` (Compliance Operator profiles & scan status) |
| **OpenShift Usage Policies** | `export-platform-guardrails.sh`, `export-olm-governance.sh` |
| **Exception Management** | `export-scc-privileged.sh`, `export-cluster-admin-bindings.sh`, `export-policy-as-code.sh` |
| **Authorized Image Registry Policy** | `export-governance-policy-ecosystem.sh` (image policy section) |
| **Enterprise Secrets Integration** | `export-secrets-integration.sh` |
| **Shared Responsibility Model** | `export-shared-responsibility-model.sh` |
| **OpenShift Usage Monitoring** | `export-monitoring-audit-logging.sh` |
| **Centralized Logging, Auditing & Retention** | `export-monitoring-audit-logging.sh` |
| **Cluster Audit Logging** | `export-monitoring-audit-logging.sh`, `export-apiserver-console-access.sh` |
| **Configuration Drift Detection** | `export-configuration-drift-status.sh`, `export-patch-lifecycle.sh` |
| **Vulnerability Scanning** | `export-vulnerability-runtime-detection.sh`, `export-governance-policy-ecosystem.sh` |
| **Runtime Threat Detection** | `export-vulnerability-runtime-detection.sh` |
| **Network Port Restriction** | `export-network-security-mesh.sh`, `export-shared-responsibility-model.sh` |
| **Network Segmentation** | `export-network-security-mesh.sh`, `export-shared-responsibility-model.sh` |
| **CNI Plugin Usage** | `export-network-security-mesh.sh` |
| **Encryption in Transit** | `export-network-security-mesh.sh`, `export-apiserver-console-access.sh` |
| **Default Deny for Inter-Project Traffic** | `export-network-security-mesh.sh`, `export-shared-responsibility-model.sh` |
| **External Egress/Ingress Boundary Protection** | `export-ingress-boundary-protection.sh`, `export-network-security-mesh.sh` |
| **Internal Service Exposure Control** | `export-ingress-boundary-protection.sh`, `export-network-security-mesh.sh`, `export-shared-responsibility-model.sh` |
| **Service Mesh Enforcement** | `export-network-security-mesh.sh` |
