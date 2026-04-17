.PHONY: help venv schema seed load all reset-db clean

# Prefer python3.14, fall back to python3
PYTHON ?= $(shell command -v python3.14 2>/dev/null || echo python3)
VENV_DIR := .venv
DB_FILE  := ocp_audit.db

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
