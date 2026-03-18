#!/usr/bin/env bash
set -euo pipefail

# setup.sh — Bootstrap development environment
# Works on Git Bash (Windows), macOS, and Linux

echo "=== OpenShift CSV Exporter — Development Setup ==="
echo ""

# ---------------------------------------------------------------------------
# Detect platform
# ---------------------------------------------------------------------------
OS="unknown"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
  Darwin*)               OS="macos"   ;;
  Linux*)                OS="linux"   ;;
esac
echo "Detected platform: $OS"

# ---------------------------------------------------------------------------
# Helper: check if a command exists
# ---------------------------------------------------------------------------
check_command() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "  [OK] $1 found: $(command -v "$1")"
    return 0
  else
    echo "  [MISSING] $1 not found"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 1. Verify required tools
# ---------------------------------------------------------------------------
echo ""
echo "--- Checking required tools ---"

MISSING=0

check_command bash || MISSING=1
check_command git  || MISSING=1
check_command jq   || { MISSING=1; echo "       Install: https://jqlang.github.io/jq/download/"; }
check_command oc   || { MISSING=1; echo "       Install: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/"; }

# ---------------------------------------------------------------------------
# 2. Install / verify shellcheck
# ---------------------------------------------------------------------------
echo ""
echo "--- Checking shellcheck ---"

if ! check_command shellcheck; then
  echo "  Attempting to install shellcheck..."
  case "$OS" in
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install shellcheck
      else
        echo "  ERROR: brew not found. Install Homebrew first: https://brew.sh"
        MISSING=1
      fi
      ;;
    linux)
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y -qq shellcheck
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y ShellCheck
      elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y ShellCheck
      else
        echo "  ERROR: Could not detect package manager. Install manually:"
        echo "         https://github.com/koalaman/shellcheck#installing"
        MISSING=1
      fi
      ;;
    windows)
      if command -v scoop >/dev/null 2>&1; then
        scoop install shellcheck
      elif command -v choco >/dev/null 2>&1; then
        choco install shellcheck -y
      else
        echo "  ERROR: Install via scoop or chocolatey:"
        echo "         scoop install shellcheck"
        echo "         choco install shellcheck"
        MISSING=1
      fi
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# 3. Install / verify pre-commit
# ---------------------------------------------------------------------------
echo ""
echo "--- Checking pre-commit ---"

if ! check_command pre-commit; then
  echo "  Attempting to install pre-commit..."
  if command -v pip3 >/dev/null 2>&1; then
    pip3 install pre-commit
  elif command -v pip >/dev/null 2>&1; then
    pip install pre-commit
  elif command -v brew >/dev/null 2>&1; then
    brew install pre-commit
  else
    echo "  ERROR: pip/pip3/brew not found. Install pre-commit manually:"
    echo "         https://pre-commit.com/#install"
    MISSING=1
  fi
fi

# ---------------------------------------------------------------------------
# 4. Install pre-commit hooks into this repo
# ---------------------------------------------------------------------------
echo ""
echo "--- Installing pre-commit hooks ---"

if command -v pre-commit >/dev/null 2>&1; then
  if [ -f ".pre-commit-config.yaml" ]; then
    pre-commit install
    echo "  [OK] Pre-commit hooks installed"
  else
    echo "  [SKIP] .pre-commit-config.yaml not found"
  fi
else
  echo "  [SKIP] pre-commit not available"
fi

# ---------------------------------------------------------------------------
# 5. Make all scripts executable
# ---------------------------------------------------------------------------
echo ""
echo "--- Setting executable permissions ---"

chmod +x run-all.sh
chmod +x scripts/*.sh
echo "  [OK] All scripts set to executable"

# ---------------------------------------------------------------------------
# 6. Create output directory
# ---------------------------------------------------------------------------
mkdir -p output
echo "  [OK] output/ directory ready"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if [ "$MISSING" -eq 0 ]; then
  echo "=== Setup complete. All tools available. ==="
else
  echo "=== Setup complete with warnings. Review [MISSING] items above. ==="
fi

echo ""
echo "Quick commands:"
echo "  ./run-all.sh                     Run all export reports"
echo "  ./scripts/export-<name>.sh       Run a single report"
echo "  shellcheck scripts/*.sh          Lint all scripts"
echo "  pre-commit run --all-files       Run all pre-commit checks"
