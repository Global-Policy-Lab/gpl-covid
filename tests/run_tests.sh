#!/usr/bin/env bash

set -e

# check formatting
black . --check

# make sure jupyter kernel exists
python -m ipykernel install --user --name gpl-covid

# run tests
pytest tests/tests.py