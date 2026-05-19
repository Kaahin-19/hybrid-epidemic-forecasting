#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
MATLAB_BIN="${MATLAB_BIN:-/home/kaahin/MATLAB/R2025b/bin/matlab}"
LOG_ROOT="$REPO_ROOT/results/partC/logs"
RUN_ID=""
RUN_LOG_DIR=""
PIPELINE_LOG=""
MANIFEST_FILE=""

show_help() {
  cat <<'EOF'
Usage:
  ./run_partC_pipeline.sh
  ./run_partC_pipeline.sh --fresh
  ./run_partC_pipeline.sh --help

Description:
  Runs the compact Part C WHO COVID-19 proof-of-concept pipeline:
    1. scripts/partC/partC_01_prepare_real_data.m
    2. scripts/partC/partC_02_run_forecasts.m
    3. scripts/partC/partC_03_evaluate_models.m

  The pipeline expects the downloaded WHO COVID-19 files:
    data/partC/raw/WHO-COVID-19-global-daily-data.csv

  The daily WHO file is the primary input. The preparation stage derives
  Rt_est and I_proxy from reported case counts for the configured country.

  Each invocation creates a timestamped run folder under:
    results/partC/logs/<run_id>/
  containing a pipeline log, per-stage MATLAB logs, and a manifest file.

Options:
  --fresh     Clear data/partC/processed and results/partC before execution.
              The raw WHO CSV files under data/partC/raw/ are preserved.
  --help, -h  Show this help message.
EOF
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

timestamp_now() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_status() {
  local message="$1"
  local line="[$(timestamp_now)] $message"

  printf '%s\n' "$line"
  if [[ -n "${PIPELINE_LOG:-}" ]]; then
    printf '%s\n' "$line" >> "$PIPELINE_LOG"
  fi
}

initialize_run_logging() {
  RUN_ID="$(date '+%Y%m%d_%H%M%S')"
  RUN_LOG_DIR="$LOG_ROOT/$RUN_ID"
  PIPELINE_LOG="$RUN_LOG_DIR/pipeline.log"
  MANIFEST_FILE="$RUN_LOG_DIR/manifest.tsv"

  mkdir -p "$RUN_LOG_DIR"
  : > "$PIPELINE_LOG"
  printf 'Timestamp\tStep\tStatus\tLogFile\tDetails\n' > "$MANIFEST_FILE"
}

append_manifest() {
  local step_name="$1"
  local status="$2"
  local log_path="$3"
  local details="${4:-}"

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(timestamp_now)" \
    "$step_name" \
    "$status" \
    "$log_path" \
    "$details" >> "$MANIFEST_FILE"
}

remove_partC_contents() {
  printf 'Clearing existing Part C processed data and result artifacts...\n'
  rm -rf "$REPO_ROOT/data/partC/processed" "$REPO_ROOT/results/partC"

  mkdir -p \
    "$REPO_ROOT/data/partC/raw" \
    "$REPO_ROOT/data/partC/processed" \
    "$REPO_ROOT/results/partC/forecasts" \
    "$REPO_ROOT/results/partC/scores" \
    "$REPO_ROOT/results/partC/figures" \
    "$REPO_ROOT/results/partC/logs"
}

run_matlab_script() {
  local step_name="$1"
  local description="$2"
  local script_path="$3"
  local log_path="$RUN_LOG_DIR/${step_name}.log"
  local matlab_code
  local start_epoch
  local elapsed_secs

  matlab_code="warning('off', 'backtrace'); run('startup.m'); addpath(genpath('third_party')); run('${script_path}');"

  log_status "Starting ${description}"
  append_manifest "$step_name" "started" "$log_path" "$description"

  start_epoch="$(date +%s)"
  if "$MATLAB_BIN" -batch "$matlab_code" > "$log_path" 2>&1; then
    elapsed_secs=$(( $(date +%s) - start_epoch ))
    log_status "Completed ${description} in ${elapsed_secs}s"
    append_manifest "$step_name" "completed" "$log_path" "${elapsed_secs}s"
  else
    local exit_code="$?"
    elapsed_secs=$(( $(date +%s) - start_epoch ))
    log_status "Failed ${description} after ${elapsed_secs}s (exit ${exit_code}). Log: ${log_path}"
    append_manifest "$step_name" "failed" "$log_path" "exit=${exit_code}; elapsed=${elapsed_secs}s"
    printf '\nLast log lines from %s:\n' "$log_path" >&2
    tail -n 30 "$log_path" >&2 || true
    return "$exit_code"
  fi
}

fresh_run=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --fresh)
      fresh_run=1
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      die "Unknown argument: $1. Use --help for usage."
      ;;
  esac
  shift
done

if [[ ! -f "$REPO_ROOT/startup.m" ]] || [[ ! -d "$REPO_ROOT/scripts" ]]; then
  die "Run this script from the repository root: $REPO_ROOT"
fi

[[ -x "$MATLAB_BIN" ]] || die "MATLAB binary not found or not executable: $MATLAB_BIN"

cd "$REPO_ROOT"

if [[ "$fresh_run" -eq 1 ]]; then
  remove_partC_contents
fi

initialize_run_logging

log_status "Run ID: ${RUN_ID}"
log_status "Running compact Part C real-data proof-of-concept pipeline"

run_matlab_script \
  "partC_01_prepare_real_data" \
  "Preparing Part C real-data input" \
  "scripts/partC/partC_01_prepare_real_data.m"

run_matlab_script \
  "partC_02_run_forecasts" \
  "Running fixed AR/None and ARX/I forecasts" \
  "scripts/partC/partC_02_run_forecasts.m"

run_matlab_script \
  "partC_03_evaluate_models" \
  "Evaluating Part C Rt WIS performance" \
  "scripts/partC/partC_03_evaluate_models.m"

log_status "Part C pipeline completed successfully."
log_status "Run logs saved to: ${RUN_LOG_DIR}"
