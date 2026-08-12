#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
MATLAB_BIN="${MATLAB_BIN:-/home/kaahin/MATLAB/R2025b/bin/matlab}"
LOG_ROOT="$REPO_ROOT/results/partB/logs"
RUN_ID=""
RUN_LOG_DIR=""
PIPELINE_LOG=""
MANIFEST_FILE=""

show_help() {
  cat <<'EOF'
Usage:
  ./run_partB_pipeline.sh
  ./run_partB_pipeline.sh --fresh
  ./run_partB_pipeline.sh --help

Description:
  Runs the configuration-driven Part B synthetic robustness pipeline:
    1. scripts/partB/partB_01_generate_robustness_datasets.m
    2. scripts/partB/partB_02_run_forecasts.m
    3. scripts/partB/partB_03_evaluate_forecasts.m
    4. scripts/partB/partB_04_generate_figures.m

  The stages generate robustness datasets, run the frozen Part A-selected
  configurations, evaluate forecasts against latent Rt truth and matched
  Part A baselines, and generate the Part B robustness figures.

  Each invocation creates a timestamped run folder under:
    results/partB/logs/<run_id>/
  containing a pipeline log, per-stage MATLAB logs, and a manifest file.

Options:
  --fresh     Clear generated Part B data/results before execution.
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

create_partB_directories() {
  mkdir -p \
    "$REPO_ROOT/data/partB" \
    "$REPO_ROOT/results/partB/forecasts" \
    "$REPO_ROOT/results/partB/evaluation" \
    "$REPO_ROOT/results/partB/tables" \
    "$REPO_ROOT/results/partB/figures" \
    "$REPO_ROOT/results/partB/logs"
}

remove_partB_contents() {
  printf 'Clearing generated Part B robustness-ladder artifacts...\n'
  rm -rf \
    "$REPO_ROOT/data/partB" \
    "$REPO_ROOT/results/partB"

  create_partB_directories
}

run_matlab_script() {
  local step_name="$1"
  local description="$2"
  local script_name="$3"
  local log_path="$RUN_LOG_DIR/${step_name}.log"
  local matlab_code
  local start_epoch
  local elapsed_secs

  matlab_code="warning('off', 'backtrace'); addpath(genpath('third_party')); startup; ${script_name};"

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
  remove_partB_contents
else
  create_partB_directories
fi

initialize_run_logging

log_status "Run ID: ${RUN_ID}"
log_status "Running Part B synthetic robustness pipeline"

run_matlab_script \
  "partB_01_generate_robustness_datasets" \
  "Generating Part B robustness datasets" \
  "partB_01_generate_robustness_datasets"

run_matlab_script \
  "partB_02_run_forecasts" \
  "Running frozen Part A-selected configurations on Part B datasets" \
  "partB_02_run_forecasts"

run_matlab_script \
  "partB_03_evaluate_forecasts" \
  "Evaluating Part B robustness forecasts against latent Rt truth and Part A baselines" \
  "partB_03_evaluate_forecasts"

run_matlab_script \
  "partB_04_generate_figures" \
  "Generating Part B robustness thesis figures" \
  "partB_04_generate_figures"

log_status "Part B robustness pipeline completed successfully."
log_status "Thesis-level figures generated under: $REPO_ROOT/results/partB/figures"
log_status "Run logs saved to: ${RUN_LOG_DIR}"
