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
# 5. Verify Python 3.14+ and sqlite3 (for datastore)
# ---------------------------------------------------------------------------
echo ""
echo "--- Checking Python 3.14+ and sqlite3 (datastore) ---"

REQUIRED_PY_MAJOR=3
REQUIRED_PY_MINOR=14

# Check for python3.14 first, then fall back to python3
PY_CMD=""
for candidate in python3.14 python3; do
  if command -v "$candidate" >/dev/null 2>&1; then
    PY_CMD="$candidate"
    break
  fi
done

if [ -n "$PY_CMD" ]; then
  PY_VER=$("$PY_CMD" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
  PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
  PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
  if [ "$PY_MAJOR" -ge "$REQUIRED_PY_MAJOR" ] && [ "$PY_MINOR" -ge "$REQUIRED_PY_MINOR" ]; then
    echo "  [OK] Python $PY_VER ($PY_CMD)"
  else
    echo "  [WARN] Python $PY_VER found ($PY_CMD) but ${REQUIRED_PY_MAJOR}.${REQUIRED_PY_MINOR}+ required for datastore"
    echo "  Attempting to install python3.14..."
    PY_CMD=""  # trigger install below
  fi
else
  echo "  [MISSING] python3 not found"
fi

if [ -z "$PY_CMD" ]; then
  case "$OS" in
    macos)
      if command -v brew >/dev/null 2>&1; then
        echo "  Installing python@3.14 via Homebrew..."
        brew install python@3.14
      else
        echo "  ERROR: brew not found. Install Python 3.14+ manually: https://www.python.org/downloads/"
        MISSING=1
      fi
      ;;
    linux)
      if command -v apt-get >/dev/null 2>&1; then
        echo "  Installing python3.14 via deadsnakes PPA..."
        if command -v add-apt-repository >/dev/null 2>&1; then
          sudo add-apt-repository -y ppa:deadsnakes/ppa
          sudo apt-get update -qq
          sudo apt-get install -y -qq python3.14 python3.14-venv python3.14-dev
        else
          echo "  ERROR: add-apt-repository not found. Install software-properties-common first:"
          echo "         sudo apt-get install -y software-properties-common"
          MISSING=1
        fi
      elif command -v dnf >/dev/null 2>&1; then
        echo "  Installing python3.14 via dnf..."
        sudo dnf install -y python3.14 python3.14-pip python3.14-devel 2>/dev/null || {
          echo "  ERROR: python3.14 not available in default repos. Install manually:"
          echo "         https://www.python.org/downloads/"
          MISSING=1
        }
      else
        echo "  ERROR: Install Python 3.14+ manually: https://www.python.org/downloads/"
        MISSING=1
      fi
      ;;
    windows)
      echo "  ERROR: Install Python 3.14+ from https://www.python.org/downloads/"
      MISSING=1
      ;;
  esac

  # Verify install succeeded
  if command -v python3.14 >/dev/null 2>&1; then
    echo "  [OK] python3.14 installed: $(python3.14 --version)"
  fi
fi

check_command sqlite3 || {
  echo "       sqlite3 is used to inspect the datastore. Install via your package manager."
}

# ---------------------------------------------------------------------------
# 6. Make all scripts executable
# ---------------------------------------------------------------------------
echo ""
echo "--- Setting executable permissions ---"

chmod +x run-all.sh
chmod +x scripts/*.sh
echo "  [OK] All scripts set to executable"

# ---------------------------------------------------------------------------
# 7. Create output directory
# ---------------------------------------------------------------------------
mkdir -p output
echo "  [OK] output/ directory ready"

# ---------------------------------------------------------------------------
# 8. Create datastore virtualenv and install dependencies
# ---------------------------------------------------------------------------
echo ""
echo "--- Setting up datastore virtualenv ---"

# Resolve the best available Python for the datastore
DS_PYTHON=""
for candidate in python3.14 python3; do
  if command -v "$candidate" >/dev/null 2>&1; then
    DS_PYTHON="$candidate"
    break
  fi
done

if [ -n "$DS_PYTHON" ]; then
  DS_DIR="datastore"
  VENV_DIR="$DS_DIR/.venv"
  if [ -d "$VENV_DIR" ]; then
    echo "  [OK] $VENV_DIR already exists (using $($DS_PYTHON --version))"
  else
    echo "  Creating $VENV_DIR with $DS_PYTHON..."
    "$DS_PYTHON" -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install --upgrade pip -q
    "$VENV_DIR/bin/pip" install -r "$DS_DIR/requirements.txt" -q
    echo "  [OK] $VENV_DIR created ($($DS_PYTHON --version)) and dependencies installed"
  fi
else
  echo "  [SKIP] python3 not available — cannot create datastore virtualenv"
fi

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
echo "  cd datastore && make schema      Generate SQLite audit DB"
