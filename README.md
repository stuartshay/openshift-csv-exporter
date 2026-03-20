# OpenShift CSV Exporter

A small collection of Bash scripts to export common OpenShift cluster information to timestamped CSV files.

## What it does

These scripts use `oc` and `jq` to collect cluster data and write CSV reports into the `output/` directory.

Each output file is named with a timestamp in this format:

`yyyy-mm-dd-hh-mm`

Example:

`output/clusteroperators-2026-03-12-09-15.csv`

## Included reports

- `clusterrolebindings` — all ClusterRoleBinding subjects
- `clusterrolebinding self-provisioners` — self-provisioner binding
- `cluster-admin-bindings` — subjects with cluster-admin access
- `clusterroles` — ClusterRole permission rules
- `clusterversion` — cluster version and update status
- `clusteroperators` — cluster operator health
- `oauth cluster` — OAuth configuration summary
- `oauth external auth` — external authentication enforcement
- `infrastructure cluster` — platform and topology
- `apiserver console access` — API server and console security config
- `scc privileged` — privileged SecurityContextConstraints
- `worker node auth` — worker node authentication and authorization enforcement
- `credential management` — cluster admin and infrastructure credential audit
- `platform guardrails` — platform distribution validation and misconfigured component detection
- `policy as code` — OPA Gatekeeper policy enforcement status and constraints
- `cicd pipeline enforcement` — detects in-cluster GitOps (ArgoCD, Flux), Tekton pipelines, and external CI/CD tool footprints

See [`scripts/README.md`](scripts/README.md) for full column details and usage.

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

## Requirements

- Bash (or Git Bash on Windows)
- `oc` CLI already authenticated to the target cluster
- `jq`

Check prerequisites:

```bash
oc whoami
jq --version
```

## Quick start

Run the setup script to install dev tools and set permissions:

```bash
./setup.sh
```

Run all reports:

```bash
./run-all.sh
```

Run a single report:

```bash
./scripts/export-clusteroperators.sh
```

## Output location

All CSV files are written to:

```bash
./output
```

The directory is created automatically if it does not exist.

## Notes

- Some commands require elevated cluster permissions.
- If one report fails while others succeed, that is usually an RBAC issue.
- For CSV export, `jq` is generally more reliable than trying to flatten YAML or `describe` text directly.

## Suggested repo layout

This package is already structured well for a starter GitHub repo:

```text
openshift-csv-exporter/
├── README.md
├── run-all.sh
├── scripts/
│   ├── common.sh
│   ├── export-clusteroperators.sh
│   ├── export-clusterrolebindings.sh
│   ├── export-clusterrolebinding-self-provisioners.sh
│   ├── export-clusterversion.sh
│   ├── export-infrastructure-cluster.sh
│   ├── export-oauth-cluster.sh
│   └── export-scc-privileged.sh
└── output/
```

## Next sensible improvements

A better long-term approach is usually one of these:

1. Keep separate scripts, but share common helper functions, which this package already does.
2. Add a single parameterized wrapper like `./run-report.sh clusteroperators`.
3. Add CI checks with `shellcheck`.
4. Add more exports for namespaces, pods, quotas, and deployments.

For a first GitHub repo, this package is a solid starting point.
