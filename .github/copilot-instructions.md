# Copilot Instructions for openshift-csv-exporter

## Project Overview

This project contains Bash scripts that export OpenShift cluster configuration to timestamped CSV files for security auditing. Each script lives in `scripts/`, sources `scripts/common.sh`, and writes output to `output/`.

## Documentation Rules

**When adding, removing, or modifying any export script in `scripts/`**, you MUST update both README files to stay in sync:

### 1. `scripts/README.md` (comprehensive reference)

- Add or update the script's section with:
  - Description of what it exports
  - The `oc` command(s) used
  - Output filename pattern
  - Full table of CSV columns with descriptions
- Update the **Audit Coverage Matrix** table at the bottom if the script maps to a new or existing audit area

### 2. `README.md` (root — quick-start guide)

- Update the **Included reports** list to reflect all current scripts
- Update the **Audit Coverage Matrix** table to stay in sync with `scripts/README.md`

### 3. `run-all.sh`

- Add or remove the script entry so it runs as part of the full export

## Script Conventions

- Every script begins with a header comment block immediately after the shebang:

  ```bash
  #!/usr/bin/env bash
  # Description: <one-line summary of what the script exports>
  # Audit Area:  <matching audit area from the Audit Coverage Matrix>
  ```

- Every script starts with `set -euo pipefail`
- Every script sources `common.sh` via:

  ```bash
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/common.sh"
  ```

- Every script validates required variables:

  ```bash
  : "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
  : "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
  : "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
  : "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
  : "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
  : "${TIMESTAMP:?TIMESTAMP is not set}"
  ```

- Output filenames follow the pattern: `<report-name>-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv`
- Every CSV starts with `cluster_name,cluster_context,cluster_server` as the first three columns
- Use `jq -r` with `--arg` for cluster variables; never interpolate shell variables inside jq expressions
- Use `// ""` for optional fields to avoid null in CSV output
- Multi-valued fields use `;` as the delimiter within a CSV cell
- Print `echo "Created: $OUTPUT_FILE"` at the end of each script

## jq Compatibility (jq 1.6 / Git Bash)

Scripts must run on **jq 1.6 under Git Bash on Windows** where many date/time builtins are missing.

- **Do NOT use** `now`, `fromdateiso8601`, `todateiso8601`, `strptime`, `mktime`, `strftime`, or `gmtime` inside jq expressions — these are not available on all jq 1.6 builds
- **Do** perform date/time calculations in shell using `date -d` and pass results into jq via `--arg`
- When computing values that require date math (e.g., age in days), iterate items with `jq -c` in a `while read` loop, compute in shell, then pass back via `--arg`

Example pattern for age calculation:

```bash
NOW_EPOCH=$(date +%s)
oc get secrets -n "$NS" -o json | jq -c '.items[]' | while IFS= read -r item; do
  CREATED=$(echo "$item" | jq -r '.metadata.creationTimestamp // ""')
  AGE_DAYS=""
  if [ -n "$CREATED" ]; then
    CREATED_EPOCH=$(date -d "$CREATED" +%s 2>/dev/null || echo "")
    if [ -n "$CREATED_EPOCH" ]; then
      AGE_DAYS=$(( (NOW_EPOCH - CREATED_EPOCH) / 86400 ))
    fi
  fi
  echo "$item" | jq -r --arg age_days "$AGE_DAYS" '...'
done
```

## Shell Style

- Use `#!/usr/bin/env bash` shebang
- Add `# shellcheck source=./common.sh` before the source line
- Quote all variable expansions
- Use `$(command)` not backticks
- Scripts must be executable (`chmod +x`)
