#!/usr/bin/env bash

set -e

# run tests
pytest tests/tests.py
bash run --nostata --nocensus