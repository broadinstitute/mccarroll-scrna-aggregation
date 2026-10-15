#!/usr/bin/env bash
# Runs ALL nf-tests (fixture tests, pre-flight tests and the live gs:// tests), with no options.
# The live tests compare with the baseline made by the prototype shell script, which is run separately first:
#   docs/specifications/scrna-aggregation_prototype.sh --manifest tests/live_data/manifest.yaml \
#       --analysis-id SMRI_V11.unfiltered --out-dir tests/live_data/baseline --image-tag jn_test
# See docs/testing.md. Needs GOOGLE_PROJECT_ID in the environment, for example: export GOOGLE_PROJECT_ID=bican-um1-mccarroll
# To run one file or one test, see "Running one file or one test" in docs/testing.md.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"

# fail before starting docker, with a clear message
[[ -n ${GOOGLE_PROJECT_ID:-} ]] || { echo "ERROR: export GOOGLE_PROJECT_ID first, for example: export GOOGLE_PROJECT_ID=bican-um1-mccarroll" >&2; exit 1; }
ADC=${HOME}/.config/gcloud/application_default_credentials.json
[[ -f $ADC ]] || { echo "ERROR: credentials not found: $ADC (run: gcloud auth application-default login)" >&2; exit 1; }
command -v nf-test >/dev/null || { echo "ERROR: nf-test not found on PATH" >&2; exit 1; }
[[ -d tests/live_data/baseline/artifacts ]] || { echo "ERROR: no baseline in tests/live_data/baseline: run the prototype shell script first (see docs/testing.md, Live tests)" >&2; exit 1; }

export SCRNA_LIVE_MANIFEST=$REPO/tests/live_data/manifest.yaml
export SCRNA_LIVE_BASELINE_ROOT=$REPO/tests/live_data/baseline
exec nf-test test
