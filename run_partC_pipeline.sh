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
  ./run_partC_pipeline.sh [--mode frozen|refined] [--models <ids>] [--fresh] [--help]

Description:
  Runs the compact Part C WHO COVID-19 proof-of-concept pipeline.

  Frozen mode is the default and preserves the primary transfer test:
    1. scripts/partC/partC_01_prepare_real_data.m
    2. scripts/partC/partC_02_run_forecasts.m
    3. scripts/partC/partC_03_evaluate_models.m
    4. scripts/partC/partC_05_generate_figures.m

  Refined mode runs the held-out local recalibration extension:
    1. scripts/partC/partC_01_prepare_real_data.m
    2. scripts/partC/partC_04_local_refinement.m

  The pipeline expects the downloaded WHO COVID-19 file:
    data/partC/raw/WHO-COVID-19-global-daily-data.csv

  Each invocation creates a timestamped run folder under:
    results/partC/logs/<run_id>/
  containing a pipeline log, per-stage MATLAB logs, and a manifest file.

Modes:
  --mode frozen   Run the existing frozen AR/None and ARX/I workflow. Default.
  --mode refined  Run preprocessing plus local refinement only.

Refinement Model Options:
  1 = AR
  2 = ARX

Examples:
  ./run_partC_pipeline.sh
  ./run_partC_pipeline.sh --mode frozen
  ./run_partC_pipeline.sh --mode refined
  ./run_partC_pipeline.sh --mode refined --models 1
  ./run_partC_pipeline.sh --mode refined --models 2
  ./run_partC_pipeline.sh --mode refined --models 1,2

Options:
  --models <ids>  Refinement model IDs to run. Default in refined mode: 1,2.
                  This option is rejected in frozen mode.
  --fresh         Clear data/partC/processed and results/partC before execution.
                  The raw WHO CSV files under data/partC/raw/ are preserved.
  --help, -h      Show this help message.
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

sanitize_name() {
  local value="$1"
  value="${value// /_}"
  value="${value//,/_}"
  value="${value//[^A-Za-z0-9._-]/_}"
  printf '%s' "$value"
}

initialize_run_logging() {
  RUN_ID="$(date '+%Y%m%d_%H%M%S')"
  RUN_LOG_DIR="$LOG_ROOT/$RUN_ID"
  PIPELINE_LOG="$RUN_LOG_DIR/pipeline.log"
  MANIFEST_FILE="$RUN_LOG_DIR/manifest.tsv"

  mkdir -p "$RUN_LOG_DIR"
  : > "$PIPELINE_LOG"
  printf 'Timestamp\tStage\tMode\tModel\tStatus\tLogFile\tDetails\n' > "$MANIFEST_FILE"
}

append_manifest() {
  local stage_name="$1"
  local mode_name="$2"
  local model_name="$3"
  local status="$4"
  local log_path="$5"
  local details="${6:-}"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(timestamp_now)" \
    "$stage_name" \
    "$mode_name" \
    "$model_name" \
    "$status" \
    "$log_path" \
    "$details" >> "$MANIFEST_FILE"
}

model_name_from_id() {
  case "$1" in
    1) printf 'AR' ;;
    2) printf 'ARX' ;;
    *) return 1 ;;
  esac
}

parse_numeric_list() {
  local raw_value="$1"
  local option_name="$2"
  local -n output_ref="$3"
  local normalized
  local token
  local -A seen=()

  normalized="${raw_value//[[:space:]]/}"
  [[ -n "$normalized" ]] || die "Missing value for ${option_name}."

  IFS=',' read -r -a tokens <<< "$normalized"
  for token in "${tokens[@]}"; do
    [[ -n "$token" ]] || continue
    [[ "$token" =~ ^[0-9]+$ ]] || die "Invalid ${option_name} entry '${token}'. Use numeric IDs."
    if [[ -z "${seen[$token]+x}" ]]; then
      output_ref+=("$token")
      seen["$token"]=1
    fi
  done

  [[ "${#output_ref[@]}" -gt 0 ]] || die "No valid numeric entries were provided for ${option_name}."
}

collect_option_value() {
  local -n args_ref="$1"
  local start_index="$2"
  local collected=""
  local next_arg
  local idx="$start_index"

  while [[ "$idx" -lt "${#args_ref[@]}" ]]; do
    next_arg="${args_ref[$idx]}"
    [[ "$next_arg" == --* ]] && break
    collected+="$next_arg"
    idx=$((idx + 1))
  done

  printf '%s\n%s\n' "$collected" "$idx"
}

join_csv() {
  local IFS=,
  printf '%s' "$*"
}

filter_matlab_output() {
  awk '
    /^(===|Stage:|Progress:|Configuration:|Selected local orders:|Calibration windows:|Holdout windows:)/ {
      print
      fflush()
      next
    }

    /saved to:/ {
      print
      fflush()
      next
    }

    /^Reading WHO daily CSV:/ {
      print
      fflush()
      next
    }

    /^Prepared [0-9]+ WHO-derived real-data observations/ {
      print
      fflush()
      next
    }

    /^Loaded [0-9]+ processed real-data observations/ {
      print
      fflush()
      next
    }

    /^Scanning forecast directory:/ {
      print
      fflush()
      next
    }

    /^Aggregated WIS scores for / {
      print
      fflush()
      next
    }

    /^Evaluated [0-9]+ forecast windows/ {
      print
      fflush()
      next
    }

    /^Saved [0-9]+ table files/ {
      print
      fflush()
      next
    }

    /^Saved [0-9]+ figure file/ {
      print
      fflush()
      next
    }

    /^Thesis-level Part C figures are under:/ {
      print
      fflush()
      next
    }

    /^  - Fixed model / {
      print
      fflush()
      next
    }

    /^  - (AR|ARX)\// {
      print
      fflush()
      next
    }

    /visualization skipped:/ {
      print
      fflush()
      next
    }

    /^Warning:/ {
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
  local mode_name="$3"
  local model_name="$4"
  local log_path="$5"
  local matlab_body="$6"

  local matlab_code
  local exit_code
  local start_epoch
  local elapsed_secs
  local matlab_pid
  local tail_pid

  matlab_code="warning('off', 'backtrace'); try; addpath(genpath(fullfile(pwd, 'third_party'))); startup; ${matlab_body}; catch ME; fprintf(2, '=== MATLAB ERROR ===\\n'); fprintf(2, 'Message: %s\\n', ME.message); fprintf(2, 'Stack trace (most recent first):\\n'); for k = 1:numel(ME.stack); fprintf(2, '  %s:%d in %s\\n', ME.stack(k).file, ME.stack(k).line, ME.stack(k).name); end; rethrow(ME); end"

  log_status "Stage: Starting ${description}"
  append_manifest "$stage_name" "$mode_name" "$model_name" "started" "$log_path" "$description"

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

  if [[ "$exit_code" -eq 0 ]]; then
    elapsed_secs=$(( $(date +%s) - start_epoch ))
    log_status "Stage: ${description} complete (${elapsed_secs}s)"
    append_manifest "$stage_name" "$mode_name" "$model_name" "completed" "$log_path" "${elapsed_secs}s"
  else
    elapsed_secs=$(( $(date +%s) - start_epoch ))
    log_status "Stage: ${description} failed after ${elapsed_secs}s (exit ${exit_code}). Log: ${log_path}"
    append_manifest "$stage_name" "$mode_name" "$model_name" "failed" "$log_path" "exit=${exit_code}; elapsed=${elapsed_secs}s"
    printf '\nLast log lines from %s:\n' "$log_path" >&2
    tail -n 30 "$log_path" >&2 || true
    return "$exit_code"
  fi
}

run_matlab_script() {
  local description="$1"
  local stage_name="$2"
  local mode_name="$3"
  local model_name="$4"
  local script_path="$5"
  local log_path="$RUN_LOG_DIR/${stage_name}.log"
  local matlab_body

  matlab_body="fprintf('Stage: Starting ${description}\\n'); run('${script_path}'); fprintf('Stage: ${description} complete\\n');"
  run_matlab_code "$description" "$stage_name" "$mode_name" "$model_name" "$log_path" "$matlab_body"
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

mode_name="frozen"
models_spec=""
fresh_run=0
mode_seen=0

args=("$@")
idx=0
while [[ "$idx" -lt "${#args[@]}" ]]; do
  arg="${args[$idx]}"

  case "$arg" in
    --mode)
      [[ "$mode_seen" -eq 0 ]] || die "The --mode option was provided more than once."
      mode_seen=1
      idx=$((idx + 1))
      [[ "$idx" -lt "${#args[@]}" ]] || die "Missing value for --mode."
      [[ "${args[$idx]}" != --* ]] || die "Missing value for --mode."
      mode_name="${args[$idx]}"
      ;;
    --models)
      [[ -z "$models_spec" ]] || die "The --models option was provided more than once."
      idx=$((idx + 1))
      [[ "$idx" -lt "${#args[@]}" ]] || die "Missing value for --models."
      mapfile -t option_result < <(collect_option_value args "$idx")
      models_spec="${option_result[0]}"
      idx="${option_result[1]}"
      continue
      ;;
    --fresh)
      fresh_run=1
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      die "Unknown argument: ${arg}. Use --help for usage."
      ;;
  esac

  idx=$((idx + 1))
done

case "$mode_name" in
  frozen|refined) ;;
  *) die "Unsupported --mode value: ${mode_name}. Use frozen or refined." ;;
esac

if [[ "$mode_name" == "frozen" && -n "$models_spec" ]]; then
  die "The --models option applies only with --mode refined."
fi

declare -a selected_model_ids=()
declare -a selected_model_names=()

if [[ "$mode_name" == "refined" ]]; then
  if [[ -n "$models_spec" ]]; then
    parse_numeric_list "$models_spec" "--models" selected_model_ids
  else
    selected_model_ids=(1 2)
  fi

  for model_id in "${selected_model_ids[@]}"; do
    model_name="$(model_name_from_id "$model_id" 2>/dev/null || true)"
    [[ -n "$model_name" ]] || die "Unsupported refinement model ID: ${model_id}."
    selected_model_names+=("$model_name")
  done
fi

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
log_status "Mode: ${mode_name}"

if [[ "$mode_name" == "frozen" ]]; then
  append_manifest "selection" "$mode_name" "AR,ARX" "selected" "-" "frozen Part C workflow"
  log_status "Running frozen Part C real-data proof-of-concept pipeline"

  run_matlab_script \
    "Preparing Part C real-data input" \
    "partC_01_prepare_real_data" \
    "$mode_name" "-" \
    "scripts/partC/partC_01_prepare_real_data.m"

  run_matlab_script \
    "Running fixed AR/None and ARX/I forecasts" \
    "partC_02_run_forecasts" \
    "$mode_name" "AR,ARX" \
    "scripts/partC/partC_02_run_forecasts.m"

  run_matlab_script \
    "Evaluating Part C Rt WIS performance" \
    "partC_03_evaluate_models" \
    "$mode_name" "AR,ARX" \
    "scripts/partC/partC_03_evaluate_models.m"

  run_matlab_script \
    "Generating Part C thesis figures" \
    "partC_05_generate_figures" \
    "$mode_name" "AR,ARX" \
    "scripts/partC/partC_05_generate_figures.m"
else
  refinement_models="$(join_csv "${selected_model_names[@]}")"
  safe_models="$(sanitize_name "$refinement_models")"

  append_manifest "selection" "$mode_name" "$refinement_models" "selected" "-" "local refinement models"
  log_status "Running refined Part C held-out local recalibration extension"
  log_status "Selected refinement models: ${refinement_models}"

  run_matlab_script \
    "Preparing Part C real-data input" \
    "partC_01_prepare_real_data" \
    "$mode_name" "-" \
    "scripts/partC/partC_01_prepare_real_data.m"

  PARTC_REFINEMENT_MODELS="$refinement_models" \
  run_matlab_code \
    "Running local refinement for ${refinement_models}" \
    "partC_04_local_refinement" \
    "$mode_name" "$refinement_models" \
    "$RUN_LOG_DIR/${safe_models}_partC_04_local_refinement.log" \
    "fprintf('Stage: Starting local refinement\\n'); run('scripts/partC/partC_04_local_refinement.m'); fprintf('Stage: Local refinement complete\\n');"
fi

log_status "Part C pipeline completed successfully."
log_status "Run logs saved to: ${RUN_LOG_DIR}"
