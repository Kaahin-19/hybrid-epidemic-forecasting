#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
MATLAB_BIN="${MATLAB_BIN:-/home/kaahin/MATLAB/R2025b/bin/matlab}"
LOG_ROOT="$REPO_ROOT/results/partA/logs"
RUN_ID=""
RUN_LOG_DIR=""
PIPELINE_LOG=""
MANIFEST_FILE=""

show_help() {
  cat <<'EOF'
Usage:
  ./run_partA_pipeline.sh [--models <ids>] [--exo <ids>] [--fresh] [--help]

Description:
  Runs the Part A pipeline in the following order:
    1. scripts/partA/partA_01_generate_synthetic_truth.m
    2. For each selected valid Model/Exo combination:
         - scripts/partA/partA_02_select_global_model_configurations.m
         - scripts/partA/partA_03_run_forecasts.m
    3. scripts/partA/partA_04_evaluate_models.m

  Each invocation creates a timestamped run folder under:
    results/partA/logs/<run_id>/
  containing a pipeline log, per-stage MATLAB logs, and a manifest file.

Model Type Options:
  1 = AR
  2 = ARX
  3 = N4SID
  4 = SSEST

Exogenous Mode Options:
  0 = None
  1 = S
  2 = I
  3 = Both

Selection Behavior:
  --models and --exo accept comma-separated numeric lists.
  The script forms the cross-product of the selected sets and runs only
  valid combinations.

  Valid combinations:
    AR    -> None only
    ARX   -> S, I, Both
    N4SID -> None, S, I, Both
    SSEST -> None, S, I, Both

Examples:
  ./run_partA_pipeline.sh
  ./run_partA_pipeline.sh --models 2 --exo 2
  ./run_partA_pipeline.sh --models 2,4 --exo 1,2,3
  ./run_partA_pipeline.sh --models 1,2 --exo 0,1,2 --fresh

Options:
  --models <ids>  Model type IDs to run. Default: all model types.
  --exo <ids>     Exogenous mode IDs to run. Default: all exogenous modes.
  --fresh         Clear data/partA and results/partA before execution.
  --help, -h      Show this help message.
EOF
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

warn() {
  printf 'Warning: %s\n' "$1" >&2
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

append_manifest() {
  local step_name="$1"
  local model_name="$2"
  local exo_name="$3"
  local status="$4"
  local log_path="$5"
  local details="${6:-}"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(timestamp_now)" \
    "$step_name" \
    "$model_name" \
    "$exo_name" \
    "$status" \
    "$log_path" \
    "$details" >> "$MANIFEST_FILE"
}

sanitize_name() {
  local value="$1"
  value="${value// /_}"
  value="${value//|/_}"
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
  printf 'Timestamp\tStep\tModel\tExo\tStatus\tLogFile\tDetails\n' > "$MANIFEST_FILE"
}

model_name_from_id() {
  case "$1" in
    1) printf 'AR' ;;
    2) printf 'ARX' ;;
    3) printf 'N4SID' ;;
    4) printf 'SSEST' ;;
    *) return 1 ;;
  esac
}

exo_name_from_id() {
  case "$1" in
    0) printf 'None' ;;
    1) printf 'S' ;;
    2) printf 'I' ;;
    3) printf 'Both' ;;
    *) return 1 ;;
  esac
}

combo_is_valid() {
  local model_name="$1"
  local exo_name="$2"

  case "$model_name" in
    AR) [[ "$exo_name" == "None" ]] ;;
    ARX) [[ "$exo_name" != "None" ]] ;;
    N4SID|SSEST) return 0 ;;
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

run_matlab_code() {
  local description="$1"
  local step_name="$2"
  local model_name="$3"
  local exo_name="$4"
  local log_path="$5"
  local matlab_body="$6"

  local matlab_code
  local exit_code
  local start_epoch
  local elapsed_secs
  local matlab_pid
  local tail_pid

  matlab_code="warning('off', 'backtrace'); run('startup.m'); addpath(genpath('third_party')); ${matlab_body}"

  log_status "Starting ${description}"
  append_manifest "$step_name" "$model_name" "$exo_name" "started" "$log_path" "$description"

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
    log_status "Completed ${description} in ${elapsed_secs}s"
    append_manifest "$step_name" "$model_name" "$exo_name" "completed" "$log_path" "${elapsed_secs}s"
  else
    elapsed_secs=$(( $(date +%s) - start_epoch ))
    log_status "Failed ${description} after ${elapsed_secs}s (exit ${exit_code}). Log: ${log_path}"
    append_manifest "$step_name" "$model_name" "$exo_name" "failed" "$log_path" "exit=${exit_code}; elapsed=${elapsed_secs}s"
    printf '\nLast log lines from %s:\n' "$log_path" >&2
    tail -n 20 "$log_path" >&2 || true
    return "$exit_code"
  fi
}

filter_matlab_output() {
  awk '
    /^(===|Stage:|Progress:|Configuration:|Selected global hyperparameters:)/ {
      print
      fflush()
      next
    }

    /saved to:/ {
      print
      fflush()
      next
    }

    /Saving trajectories to:/ {
      print
      fflush()
      next
    }

    /^  - Processing Scenario:/ {
      print
      fflush()
      next
    }

    /^Starting parallel pool/ {
      print
      fflush()
      next
    }

    /^Connected to parallel pool/ {
      print
      fflush()
      next
    }

    /^Parallel pool using/ {
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

run_matlab_scripts() {
  local description="$1"
  local step_name="$2"
  local model_name="$3"
  local exo_name="$4"
  local log_path="$5"
  shift 5

  local matlab_body=""
  local script_path

  for script_path in "$@"; do
    matlab_body+=" run('${script_path}');"
  done

  run_matlab_code "$description" "$step_name" "$model_name" "$exo_name" "$log_path" "$matlab_body"
}

remove_partA_contents() {
  printf 'Clearing existing Part A data and result artifacts...\n'
  rm -rf "$REPO_ROOT/data/partA" "$REPO_ROOT/results/partA"

  mkdir -p \
    "$REPO_ROOT/data/partA" \
    "$REPO_ROOT/results/partA/model_selection" \
    "$REPO_ROOT/results/partA/forecasts" \
    "$REPO_ROOT/results/partA/evaluation" \
    "$REPO_ROOT/results/partA/figures" \
    "$REPO_ROOT/results/partA/tables" \
    "$REPO_ROOT/results/partA/logs"
}

if [[ ! -f "$REPO_ROOT/startup.m" ]] || [[ ! -d "$REPO_ROOT/scripts" ]]; then
  die "Run this script from the repository root: $REPO_ROOT"
fi

[[ -x "$MATLAB_BIN" ]] || die "MATLAB binary not found or not executable: $MATLAB_BIN"

models_spec=""
exo_spec=""
fresh_run=0

args=("$@")
idx=0
while [[ "$idx" -lt "${#args[@]}" ]]; do
  arg="${args[$idx]}"

  case "$arg" in
    --models|--exo)
      option_name="$arg"
      idx=$((idx + 1))
      [[ "$idx" -lt "${#args[@]}" ]] || die "Missing value for ${option_name}."
      mapfile -t option_result < <(collect_option_value args "$idx")
      option_value="${option_result[0]}"
      idx="${option_result[1]}"

      if [[ "$option_name" == "--models" ]]; then
        [[ -z "$models_spec" ]] || die "The --models option was provided more than once."
        models_spec="$option_value"
      else
        [[ -z "$exo_spec" ]] || die "The --exo option was provided more than once."
        exo_spec="$option_value"
      fi
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

declare -a selected_model_ids=()
declare -a selected_exo_ids=()

if [[ -n "$models_spec" ]]; then
  parse_numeric_list "$models_spec" "--models" selected_model_ids
else
  selected_model_ids=(1 2 3 4)
fi

if [[ -n "$exo_spec" ]]; then
  parse_numeric_list "$exo_spec" "--exo" selected_exo_ids
else
  selected_exo_ids=(0 1 2 3)
fi

declare -a combo_models=()
declare -a combo_exos=()
declare -a skipped_combos=()

for model_id in "${selected_model_ids[@]}"; do
  model_name="$(model_name_from_id "$model_id" 2>/dev/null || true)"
  [[ -n "$model_name" ]] || die "Unsupported model ID: ${model_id}."

  for exo_id in "${selected_exo_ids[@]}"; do
    exo_name="$(exo_name_from_id "$exo_id" 2>/dev/null || true)"
    [[ -n "$exo_name" ]] || die "Unsupported exogenous mode ID: ${exo_id}."

    if combo_is_valid "$model_name" "$exo_name"; then
      combo_models+=("$model_name")
      combo_exos+=("$exo_name")
    else
      skipped_combos+=("${model_name} + ${exo_name}")
    fi
  done
done

[[ "${#combo_models[@]}" -gt 0 ]] || die "No valid Model/Exo combinations remain after filtering."

cd "$REPO_ROOT"

if [[ "$fresh_run" -eq 1 ]]; then
  remove_partA_contents
fi

initialize_run_logging

log_status "Run ID: ${RUN_ID}"
log_status "Selected combinations to run:"
for idx in "${!combo_models[@]}"; do
  log_status "  - ${combo_models[$idx]} | ${combo_exos[$idx]}"
done

if [[ "${#skipped_combos[@]}" -gt 0 ]]; then
  for skipped in "${skipped_combos[@]}"; do
    warn "Skipping invalid combination: ${skipped}"
    append_manifest "selection" "-" "-" "skipped" "-" "$skipped"
  done
fi

run_matlab_scripts "Generating synthetic ground truth" \
  "truth" "-" "-" "$RUN_LOG_DIR/partA_01_generate_synthetic_truth.log" \
  "scripts/partA/partA_01_generate_synthetic_truth.m"

for idx in "${!combo_models[@]}"; do
  model_name="${combo_models[$idx]}"
  exo_name="${combo_exos[$idx]}"
  safe_model="$(sanitize_name "$model_name")"
  safe_exo="$(sanitize_name "$exo_name")"

  PARTA_MODEL_TYPE="$model_name" \
  PARTA_EXO_MODE="$exo_name" \
  run_matlab_code \
    "Selecting model configuration for ${model_name} | ${exo_name}" \
    "model_selection" "$model_name" "$exo_name" \
    "$RUN_LOG_DIR/${safe_model}_${safe_exo}_model_selection.log" \
    "fprintf('Stage: Starting model-configuration selection\\n'); run('scripts/partA/partA_02_select_global_model_configurations.m'); fprintf('Stage: Model-configuration selection complete\\n');"

  PARTA_MODEL_TYPE="$model_name" \
  PARTA_EXO_MODE="$exo_name" \
  run_matlab_code \
    "Running forecasts for ${model_name} | ${exo_name}" \
    "forecast" "$model_name" "$exo_name" \
    "$RUN_LOG_DIR/${safe_model}_${safe_exo}_forecast.log" \
    "fprintf('Stage: Starting forecast execution\\n'); run('scripts/partA/partA_03_run_forecasts.m'); fprintf('Stage: Forecast execution complete\\n');"
done

run_matlab_scripts "Evaluating accumulated forecast artifacts" \
  "evaluation" "-" "-" "$RUN_LOG_DIR/partA_04_evaluate_models.log" \
  "scripts/partA/partA_04_evaluate_models.m"

log_status "Part A pipeline completed successfully."
log_status "Run logs saved to: ${RUN_LOG_DIR}"
