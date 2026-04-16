# Multi-Cluster Export Guide

Run security audit exports across multiple OpenShift clusters in a single command.

## Overview

| Script | Purpose |
|---|---|
| `setup-contexts.sh` | Register and manage kubeconfig contexts with isolated credentials |
| `run-multi-cluster.sh` | Execute export scripts against all (or selected) authenticated clusters |

## Quick Start

```bash
# 1. Start with a clean kubeconfig (backs up existing)
./setup-contexts.sh reset

# 2. Add your clusters interactively
./setup-contexts.sh login

# 3. Verify all clusters are authenticated
./setup-contexts.sh test

# 4. Run all exports across every cluster
./run-multi-cluster.sh
```

## Context Setup (`setup-contexts.sh`)

### Why not just `oc login`?

When you `oc login` to multiple clusters with the same username, the second login **overwrites the token** from the first — leaving only the last cluster authenticated. `setup-contexts.sh` solves this by creating isolated credential entries per cluster so tokens never conflict.

### Commands

#### `login` — Interactive mode

Walks you through adding clusters one at a time. You provide the context name, server URL, and token for each cluster. Type `done` when finished.

```bash
./setup-contexts.sh login
```

```text
--- Cluster 1 ---
Context name (or 'done'): aws-useast1-apps-dev-1
Server URL: https://api.aws-useast1-apps-dev-1.ocpdev.us-east-1.example.com:6443
Token: sha256~abc...

✓ Context 'aws-useast1-apps-dev-1' added successfully
✓ Authenticated as: sshay

--- Cluster 2 ---
Context name (or 'done'): aws-useast1-apps-dev-2
Server URL: https://api.aws-useast1-apps-dev-2.ocpdev.us-east-1.example.com:6443
Token: sha256~xyz...

✓ Context 'aws-useast1-apps-dev-2' added successfully
✓ Authenticated as: sshay

--- Cluster 3 ---
Context name (or 'done'): done

✓ Added 2 cluster(s)
Ready to run: ./run-multi-cluster.sh
```

#### `add` — Non-interactive (single cluster)

```bash
./setup-contexts.sh add <context-name> <server-url> <token>
```

```bash
./setup-contexts.sh add ocp-prod https://api.prod.example.com:6443 sha256~token...
```

#### `list` — Show all contexts

```bash
./setup-contexts.sh list
```

#### `test` — Verify authentication

```bash
# Test all contexts
./setup-contexts.sh test

# Test a specific context
./setup-contexts.sh test aws-useast1-apps-dev-1
```

#### `remove` — Delete a context

Removes the context and its associated cluster/credential entries.

```bash
./setup-contexts.sh remove aws-useast1-apps-dev-1
```

#### `reset` — Wipe kubeconfig and start fresh

Creates a timestamped backup of `~/.kube/config` before removing it.

```bash
./setup-contexts.sh reset
```

## Running Exports (`run-multi-cluster.sh`)

### Usage

```bash
# Run ALL export scripts on every context
./run-multi-cluster.sh

# Run a single export script on every context
./run-multi-cluster.sh scripts/export-cluster-overview.sh

# Limit to specific contexts (comma-separated)
CONTEXTS="aws-useast1-apps-dev-1,aws-useast1-apps-dev-2" ./run-multi-cluster.sh
```

### What it does

For each context in the kubeconfig:

1. Switches to the context (`oc config use-context`)
2. Verifies the token is still valid (`oc whoami`)
3. Creates a per-cluster output subfolder
4. Runs the target script(s)
5. Reports pass/fail/skipped per cluster
6. Restores the original context when done

Clusters with expired tokens are skipped (not failed) so the remaining clusters still run.

### Output Structure

CSV files are organized by run date and cluster name:

```text
output/
└── 2026-04-15-15-05/              # date-stamped run folder
    ├── aws-useast1-apps-dev-1/    # cluster 1 outputs
    │   ├── cluster-overview-aws-useast1-apps-dev-1-2026-04-15-15-05.csv
    │   ├── clusterrolebindings-aws-useast1-apps-dev-1-2026-04-15-15-05.csv
    │   └── ...
    └── aws-useast1-apps-dev-2/    # cluster 2 outputs
        ├── cluster-overview-aws-useast1-apps-dev-2-2026-04-15-15-05.csv
        ├── clusterrolebindings-aws-useast1-apps-dev-2-2026-04-15-15-05.csv
        └── ...
```

### Console Output

The script prints color-coded progress for each cluster:

- **Yellow** — switching to a new context
- **Green** — cluster completed successfully
- **Red** — cluster failed or was skipped (expired token)
- **Summary** — total pass/fail/skipped count and wall-clock time

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `CONTEXTS` | *(all contexts)* | Comma-separated list of context names to process |
| `OUTPUT_DIR` | `./output` | Base directory for CSV output |

## Refreshing Expired Tokens

Tokens expire periodically. To refresh a single cluster's token without affecting others:

```bash
./setup-contexts.sh add aws-useast1-apps-dev-1 https://api.dev1.example.com:6443 sha256~new-token...
```

This overwrites the existing credential entry for that context — no need to remove it first.

To check which tokens are still valid:

```bash
./setup-contexts.sh test
```

## Platform Support

Both scripts work on:

- Git Bash (Windows)
- macOS (zsh/bash)
- Linux (bash)
