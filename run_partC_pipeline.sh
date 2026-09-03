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
PIPELINE_STARTED_AT=""
PIPELINE_STARTED_EPOCH=""

show_help() {
  cat <<'EOF'
Usage:
  ./run_partC_pipeline.sh
  ./run_partC_pipeline.sh --fresh
  ./run_partC_pipeline.sh --help

Description:
  Runs the configuration-driven Part C real-data transfer/adaptation pipeline:

    1. scripts/partC/partC_01_prepare_data.m
    2. scripts/partC/partC_02_select_local_orders.m
    3. scripts/partC/partC_03_run_forecasts.m
    4. scripts/partC/partC_04_evaluate_forecasts.m
    5. scripts/partC/partC_05_generate_figures.m

  The pipeline prepares the Swedish WHO COVID-19 incidence series, estimates
  Rt and reconstructs SIRS state proxies, performs limited local model-order
  selection, runs held-out transfer/adaptation forecasts, evaluates them, and
  generates the Part C thesis figures.

  The pipeline expects:
    data/partC/raw/WHO-COVID-19-global-daily-data.csv

  Each invocation creates a timestamped run folder under:
    results/partC/logs/<run_id>/

  The folder contains the pipeline log, per-stage MATLAB logs, and a
  manifest file.

  The terminal shows one compact row per stage. Long-running stages update
  their progress in place while full MATLAB output remains in the stage logs.

Options:
  --fresh     Clear generated Part C prepared data/results before execution.
              Raw WHO CSV files under data/partC/raw/ are preserved.
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

create_partC_directories() {
  mkdir -p \
    "$REPO_ROOT/data/partC/raw" \
    "$REPO_ROOT/data/partC/prepared" \
    "$REPO_ROOT/results/partC/model_selection" \
    "$REPO_ROOT/results/partC/forecasts" \
    "$REPO_ROOT/results/partC/evaluation" \
    "$REPO_ROOT/results/partC/tables" \
    "$REPO_ROOT/results/partC/figures" \
    "$REPO_ROOT/results/partC/logs"
}

remove_partC_contents() {
  printf 'Clearing generated Part C prepared data and result artifacts...\n'

  rm -rf \
    "$REPO_ROOT/data/partC/prepared" \
    "$REPO_ROOT/results/partC"

  create_partC_directories
}

render_stage() {
  local stage_index="$1"
  local label="$2"
  local progress="$3"
  local state="$4"

  printf '\r\033[2K[%d/5] %-30s %-22s %s' \
    "$stage_index" \
    "$label" \
    "$progress" \
    "$state"
}

current_stage_progress() {
  local step_name="$1"
  local log_path="$2"
  local line

  case "$step_name" in
    partC_02_select_local_orders)
      line="$(grep -E '^Evaluating candidate [0-9]+/[0-9]+' "$log_path" 2>/dev/null | tail -n 1 || true)"

      if [[ "$line" =~ Evaluating[[:space:]]+candidate[[:space:]]+([0-9]+)/([0-9]+) ]]; then
        printf '%s/%s candidates' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      fi
      ;;

    partC_03_run_forecasts)
      line="$(grep -E '^Completed origins: [0-9]+/[0-9]+' "$log_path" 2>/dev/null | tail -n 1 || true)"

      if [[ "$line" =~ Completed[[:space:]]+origins:[[:space:]]+([0-9]+)/([0-9]+) ]]; then
        printf '%s/%s origins' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      fi
      ;;
  esac
}

final_stage_progress() {
  local step_name="$1"
  local log_path="$2"
  local progress

  progress="$(current_stage_progress "$step_name" "$log_path")"
  printf '%s' "$progress"
}

run_matlab_script() {
  local stage_index="$1"
  local step_name="$2"
  local label="$3"
  local description="$4"
  local script_path="$5"
  local log_path="$RUN_LOG_DIR/${step_name}.log"

  local matlab_code
  local start_epoch
  local elapsed_secs
  local matlab_pid
  local exit_code
  local progress=""

  matlab_code="warning('off', 'backtrace'); try; startup; addpath(genpath('${REPO_ROOT}/third_party')); run('${script_path}'); catch ME; fprintf(2, '=== MATLAB ERROR ===\\n'); fprintf(2, 'Message: %s\\n', ME.message); fprintf(2, 'Stack trace (most recent first):\\n'); for k = 1:numel(ME.stack); fprintf(2, '  %s:%d in %s\\n', ME.stack(k).file, ME.stack(k).line, ME.stack(k).name); end; rethrow(ME); end"

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
  remove_partC_contents
else
  create_partC_directories
fi

initialize_run_logging

PIPELINE_STARTED_AT="$(timestamp_now)"
PIPELINE_STARTED_EPOCH="$(date +%s)"

log_status "Run ID: ${RUN_ID}"
log_status "Running Part C real-data transfer/adaptation pipeline"
log_status "Pipeline started"

printf 'Part C real-data transfer/adaptation pipeline\n'
printf 'Run: %s\n' "$RUN_ID"
printf 'Started: %s\n\n' "$PIPELINE_STARTED_AT"

run_matlab_script \
  1 \
  "partC_01_prepare_data" \
  "Prepare real-data input" \
  "Preparing Part C real-data input" \
  "scripts/partC/partC_01_prepare_data.m"

run_matlab_script \
  2 \
  "partC_02_select_local_orders" \
  "Select local orders" \
  "Selecting local Part C model orders" \
  "scripts/partC/partC_02_select_local_orders.m"

run_matlab_script \
  3 \
  "partC_03_run_forecasts" \
  "Run forecasts" \
  "Running Part C transfer/adaptation forecasts" \
  "scripts/partC/partC_03_run_forecasts.m"

run_matlab_script \
  4 \
  "partC_04_evaluate_forecasts" \
  "Evaluate forecasts" \
  "Evaluating Part C held-out forecast performance" \
  "scripts/partC/partC_04_evaluate_forecasts.m"

run_matlab_script \
  5 \
  "partC_05_generate_figures" \
  "Generate thesis figures" \
  "Generating Part C thesis figures" \
  "scripts/partC/partC_05_generate_figures.m"

PIPELINE_FINISHED_AT="$(timestamp_now)"
PIPELINE_ELAPSED_SECS=$(( $(date +%s) - PIPELINE_STARTED_EPOCH ))

log_status "Part C real-data transfer/adaptation pipeline completed successfully in ${PIPELINE_ELAPSED_SECS}s"
log_status "Thesis-level figures generated under: $REPO_ROOT/results/partC/figures"
log_status "Run logs saved to: ${RUN_LOG_DIR}"

printf '\nPipeline completed successfully.\n'
printf 'Finished: %s\n\n' "$PIPELINE_FINISHED_AT"
printf 'Figures: results/partC/figures\n'
printf 'Logs:    results/partC/logs/%s\n' "$RUN_ID"