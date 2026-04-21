.PHONY: help venv schema seed load all reset-db clean

# Prefer python3.14, fall back to python3
PYTHON ?= $(shell command -v python3.14 2>/dev/null || echo python3)
VENV_DIR := .venv
DB_FILE  := ocp_audit.db

# CSV source directory passed to load_csv.py (OCP_DATA_DIR).
#   data    = bundled mock CSVs in this repo (flat layout)
#   ../data = real per-environment exports one level up (nested layout)
# Toggle by commenting out one of the two lines below (or override on the
# command line:  make load OCP_DATA_DIR=/some/other/path).
OCP_DATA_DIR ?= data
# OCP_DATA_DIR ?= ../data
export OCP_DATA_DIR

# CSV data directory layout passed to load_csv.py:
#   nested = recurse into per-environment / per-cluster sub-folders
#            e.g. data/DEV-DNA/aws-useast1-datalake-dev-1/*.csv
#   flat   = legacy layout where every CSV sits directly in data/
# Toggle by commenting out one of the two lines below (or override on the
# command line:  make load OCP_DATA_LAYOUT=flat).
OCP_DATA_LAYOUT ?= nested
# OCP_DATA_LAYOUT ?= flat
export OCP_DATA_LAYOUT

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

$(VENV_DIR)/bin/activate: requirements.txt
	$(PYTHON) -m venv $(VENV_DIR)
	$(VENV_DIR)/bin/pip install --upgrade pip -q
	$(VENV_DIR)/bin/pip install -r requirements.txt -q
	@touch $(VENV_DIR)/bin/activate

venv: $(VENV_DIR)/bin/activate ## Create virtualenv and install dependencies

all: seed ## Run full pipeline: schema → load → seed

schema: venv ## Generate the SQLite database schema
	$(VENV_DIR)/bin/python generate_schema.py

seed: load ## Seed clusters table from input/clusters_env.csv
	$(VENV_DIR)/bin/python seed_clusters.py

load: schema ## Load CSV data from data/ into the database
	$(VENV_DIR)/bin/python load_csv.py

reset-db: ## Delete the SQLite database
	rm -f $(DB_FILE)
	@echo "Removed $(DB_FILE)"

clean: ## Remove database and virtualenv
	rm -f $(DB_FILE)
	rm -rf $(VENV_DIR)
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	@echo "Cleaned $(DB_FILE), $(VENV_DIR)/, and __pycache__"
