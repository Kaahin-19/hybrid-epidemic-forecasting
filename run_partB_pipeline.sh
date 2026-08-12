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
PIPELINE_STARTED_AT=""
PIPELINE_STARTED_EPOCH=""

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

  The terminal shows one compact row per stage. Long-running stages update
  their progress in place while full MATLAB output remains in the stage logs.

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

  if [[ -n "${PIPELINE_LOG:-}" ]]; then
    printf '%s\n' "$line" >> "$PIPELINE_LOG"
  fi
}

format_duration() {
  local total_secs="$1"
  local hours=$(( total_secs / 3600 ))
  local minutes=$(( (total_secs % 3600) / 60 ))
  local seconds=$(( total_secs % 60 ))

  if (( hours > 0 )); then
    printf '%dh %02dm %02ds' "$hours" "$minutes" "$seconds"
  elif (( minutes > 0 )); then
    printf '%dm %02ds' "$minutes" "$seconds"
  else
    printf '%ds' "$seconds"
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

render_stage() {
  local stage_index="$1"
  local label="$2"
  local progress="$3"
  local state="$4"

  printf '\r\033[2K[%d/4] %-30s %-22s %s' "$stage_index" "$label" "$progress" "$state"
}

current_stage_progress() {
  local step_name="$1"
  local log_path="$2"
  local completed
  local line

  case "$step_name" in
    partB_01_generate_robustness_datasets)
      completed="$(grep -Ec '^  - ' "$log_path" 2>/dev/null || true)"
      if (( completed > 0 )); then
        printf '%d attempts' "$completed"
      fi
      ;;
    partB_02_run_forecasts)
      line="$(grep -E '^Dataset [0-9]+/[0-9]+' "$log_path" 2>/dev/null | tail -n 1 || true)"
      if [[ "$line" =~ ^Dataset[[:space:]]+([0-9]+)/([0-9]+) ]]; then
        printf '%s/%s datasets' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      fi
      ;;
  esac
}

final_stage_progress() {
  local step_name="$1"
  local log_path="$2"
  local completed
  local progress

  case "$step_name" in
    partB_01_generate_robustness_datasets)
      completed="$(grep -Ec '^  - ' "$log_path" 2>/dev/null || true)"
      if (( completed > 0 )); then
        printf '%d/%d attempts' "$completed" "$completed"
      fi
      ;;
    partB_02_run_forecasts)
      progress="$(current_stage_progress "$step_name" "$log_path")"
      printf '%s' "$progress"
      ;;
  esac
}

run_matlab_script() {
  local stage_index="$1"
  local step_name="$2"
  local label="$3"
  local description="$4"
  local script_name="$5"
  local log_path="$RUN_LOG_DIR/${step_name}.log"
  local matlab_code
  local start_epoch
  local elapsed_secs
  local matlab_pid
  local exit_code
  local progress

  matlab_code="warning('off', 'backtrace'); addpath(genpath('third_party')); startup; ${script_name};"

  log_status "Starting ${description}"
  append_manifest "$step_name" "started" "$log_path" "$description"

  : > "$log_path"
  start_epoch="$(date +%s)"
  render_stage "$stage_index" "$label" "" "running"

  "$MATLAB_BIN" -batch "$matlab_code" > "$log_path" 2>&1 &
  matlab_pid=$!

  while kill -0 "$matlab_pid" 2>/dev/null; do
    progress="$(current_stage_progress "$step_name" "$log_path")"
    render_stage "$stage_index" "$label" "$progress" "running"
    sleep 1
  done

  set +e
  wait "$matlab_pid"
  exit_code=$?
  set -e

  elapsed_secs=$(( $(date +%s) - start_epoch ))

  if [[ "$exit_code" -eq 0 ]]; then
    progress="$(final_stage_progress "$step_name" "$log_path")"
    render_stage "$stage_index" "$label" "$progress" "✓ $(format_duration "$elapsed_secs")"
    printf '\n'

    log_status "Completed ${description} in ${elapsed_secs}s"
    append_manifest "$step_name" "completed" "$log_path" "${elapsed_secs}s"
  else
    render_stage "$stage_index" "$label" "$progress" "✗ failed"
    printf '\n'

    log_status "Failed ${description} after ${elapsed_secs}s (exit ${exit_code}). Log: ${log_path}"
    append_manifest "$step_name" "failed" "$log_path" "exit=${exit_code}; elapsed=${elapsed_secs}s"

    printf '\nPipeline failed.\n'
    printf 'Finished: %s\n' "$(timestamp_now)"
    printf 'Log: %s\n' "$log_path"
    printf '\nLast log lines:\n' >&2
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

PIPELINE_STARTED_AT="$(timestamp_now)"
PIPELINE_STARTED_EPOCH="$(date +%s)"

log_status "Run ID: ${RUN_ID}"
log_status "Running Part B synthetic robustness pipeline"
log_status "Pipeline started"

printf 'Part B robustness pipeline\n'
printf 'Run: %s\n' "$RUN_ID"
printf 'Started: %s\n\n' "$PIPELINE_STARTED_AT"

run_matlab_script \
  1 \
  "partB_01_generate_robustness_datasets" \
  "Generate robustness datasets" \
  "Generating Part B robustness datasets" \
  "partB_01_generate_robustness_datasets"

run_matlab_script \
  2 \
  "partB_02_run_forecasts" \
  "Run forecasts" \
  "Running frozen Part A-selected configurations on Part B datasets" \
  "partB_02_run_forecasts"

run_matlab_script \
  3 \
  "partB_03_evaluate_forecasts" \
  "Evaluate forecasts" \
  "Evaluating Part B robustness forecasts against latent Rt truth and Part A baselines" \
  "partB_03_evaluate_forecasts"

run_matlab_script \
  4 \
  "partB_04_generate_figures" \
  "Generate thesis figures" \
  "Generating Part B robustness thesis figures" \
  "partB_04_generate_figures"

PIPELINE_FINISHED_AT="$(timestamp_now)"
PIPELINE_ELAPSED_SECS=$(( $(date +%s) - PIPELINE_STARTED_EPOCH ))

log_status "Part B robustness pipeline completed successfully in ${PIPELINE_ELAPSED_SECS}s"
log_status "Thesis-level figures generated under: $REPO_ROOT/results/partB/figures"
log_status "Run logs saved to: ${RUN_LOG_DIR}"

printf '\nPipeline completed successfully.\n'
printf 'Finished: %s\n\n' "$PIPELINE_FINISHED_AT"
printf 'Figures: results/partB/figures\n'
printf 'Logs:    results/partB/logs/%s\n' "$RUN_ID"