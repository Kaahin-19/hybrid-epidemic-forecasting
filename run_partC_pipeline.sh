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
  ./run_partC_pipeline.sh [--fresh] [--help]

Description:
  Runs the final Part C Swedish COVID real-data transfer/adaptation study:
    1. scripts/partC/partC_01_prepare_real_data.m
    2. scripts/partC/partC_04_select_local_orders.m
    3. scripts/partC/partC_02_run_forecasts.m
    4. scripts/partC/partC_03_evaluate_models.m
    5. scripts/partC/partC_05_generate_figures.m

  The pipeline expects the downloaded WHO COVID-19 file:
    data/partC/raw/WHO-COVID-19-global-daily-data.csv

  Project dependencies under third_party are added to the MATLAB path before
  every Part C stage, after startup has initialized config/, scripts/, and src/.

Options:
  --fresh     Clear data/partC/processed and results/partC before execution.
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
  printf 'Timestamp\tStage\tStatus\tLogFile\tDetails\n' > "$MANIFEST_FILE"
}

append_manifest() {
  local stage_name="$1"
  local status="$2"
  local log_path="$3"
  local details="${4:-}"

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(timestamp_now)" \
    "$stage_name" \
    "$status" \
    "$log_path" \
    "$details" >> "$MANIFEST_FILE"
}

filter_matlab_output() {
  awk '
    /^(===|Stage:|Experiment:|Strategy:|Calibration fraction:)/ {
      print
      fflush()
      next
    }

    /^Loaded [0-9]+ processed real-data observations/ {
      print
      fflush()
      next
    }

    /^Prepared [0-9]+ WHO-derived real-data observations/ {
      print
      fflush()
      next
    }

    /saved to:/ {
      print
      fflush()
      next
    }

    /^Table saved to:/ {
      print
      fflush()
      next
    }

    /^Saved [0-9]+/ {
      print
      fflush()
      next
    }

    /^  - / {
      print
      fflush()
      next
    }

    /^=== MATLAB ERROR ===$/ {
      print
      fflush()
      next
    }

    /^Message:/ {
      print
      fflush()
      next
    }

    /^Stack trace \(most recent first\):$/ {
      print
      fflush()
      next
    }

    /^  \// {
      print
      fflush()
      next
    }
  '
}

run_matlab_code() {
  local description="$1"
  local stage_name="$2"
  local log_path="$3"
  local matlab_body="$4"

  local matlab_code
  local exit_code
  local start_epoch
  local elapsed_secs
  local matlab_pid
  local tail_pid

  matlab_code="warning('off', 'backtrace'); try; startup; addpath(genpath('${REPO_ROOT}/third_party')); ${matlab_body}; catch ME; fprintf(2, '=== MATLAB ERROR ===\\n'); fprintf(2, 'Message: %s\\n', ME.message); fprintf(2, 'Stack trace (most recent first):\\n'); for k = 1:numel(ME.stack); fprintf(2, '  %s:%d in %s\\n', ME.stack(k).file, ME.stack(k).line, ME.stack(k).name); end; rethrow(ME); end"

  log_status "Stage: Starting ${description}"
  append_manifest "$stage_name" "started" "$log_path" "$description"

  start_epoch=$(date +%s)
  : > "$log_path"

  set +e
  "$MATLAB_BIN" -batch "$matlab_code" > "$log_path" 2>&1 &
  matlab_pid=$!

  tail -n +1 -f --pid="$matlab_pid" "$log_path" | filter_matlab_output &
  tail_pid=$!

  wait "$matlab_pid"
  exit_code=$?
  wait "$tail_pid" || true
  set -e

  elapsed_secs=$(( $(date +%s) - start_epoch ))
  if [[ "$exit_code" -eq 0 ]]; then
    log_status "Stage: ${description} complete (${elapsed_secs}s)"
    append_manifest "$stage_name" "completed" "$log_path" "${elapsed_secs}s"
  else
    log_status "Stage: ${description} failed after ${elapsed_secs}s (exit ${exit_code}). Log: ${log_path}"
    append_manifest "$stage_name" "failed" "$log_path" "exit=${exit_code}; elapsed=${elapsed_secs}s"
    printf '\nLast log lines from %s:\n' "$log_path" >&2
    tail -n 30 "$log_path" >&2 || true
    return "$exit_code"
  fi
}

run_matlab_script() {
  local description="$1"
  local stage_name="$2"
  local script_path="$3"
  local log_path="$RUN_LOG_DIR/${stage_name}.log"
  local matlab_body

  matlab_body="fprintf('Stage: Starting ${description}\\n'); run('${script_path}'); fprintf('Stage: ${description} complete\\n');"
  run_matlab_code "$description" "$stage_name" "$log_path" "$matlab_body"
}

remove_partC_contents() {
  printf 'Clearing existing Part C processed data and result artifacts...\n'
  rm -rf "$REPO_ROOT/data/partC/processed" "$REPO_ROOT/results/partC"

  mkdir -p \
    "$REPO_ROOT/data/partC/raw" \
    "$REPO_ROOT/data/partC/processed" \
    "$REPO_ROOT/results/partC/forecasts" \
    "$REPO_ROOT/results/partC/evaluation" \
    "$REPO_ROOT/results/partC/tables" \
    "$REPO_ROOT/results/partC/figures" \
    "$REPO_ROOT/results/partC/refinement" \
    "$REPO_ROOT/results/partC/logs"
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
log_status "Running final Part C real-data transfer/adaptation pipeline"

run_matlab_script \
  "Preparing Part C real-data input" \
  "partC_01_prepare_real_data" \
  "scripts/partC/partC_01_prepare_real_data.m"

run_matlab_script \
  "Selecting local Part C orders" \
  "partC_04_select_local_orders" \
  "scripts/partC/partC_04_select_local_orders.m"

run_matlab_script \
  "Running Part C strategy forecasts" \
  "partC_02_run_forecasts" \
  "scripts/partC/partC_02_run_forecasts.m"

run_matlab_script \
  "Evaluating Part C strategy performance" \
  "partC_03_evaluate_models" \
  "scripts/partC/partC_03_evaluate_models.m"

run_matlab_script \
  "Generating Part C thesis figures" \
  "partC_05_generate_figures" \
  "scripts/partC/partC_05_generate_figures.m"

log_status "Part C pipeline completed successfully."
log_status "Run logs saved to: ${RUN_LOG_DIR}"
