#!/usr/bin/env bash

set -e

# check formatting
black . --check

# run tests
bash run --nostata --nocensus --num-proj 2
pytest tests/post_run_tests.py