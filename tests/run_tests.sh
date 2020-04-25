#!/usr/bin/env bash

set -e

# check formatting
black . --check

# activate environment
conda activate gpl-covid

# make sure jupyter kernel exists
python -m ipykernel install --user --name gpl-covid

# run tests
pytest tests/tests.py