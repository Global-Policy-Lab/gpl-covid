#!/usr/bin/env bash

set -e

# check formatting
black . --check

# run tests
pytest tests/tests.py
bash run --nostata --nocensus --num-proj 2