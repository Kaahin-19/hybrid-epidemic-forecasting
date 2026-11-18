#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$SCRIPT_DIR"
MATLAB_BIN="${MATLAB_BIN:-/home/kaahin/MATLAB/R2025b/bin/matlab}"
LOG_ROOT="$REPO_ROOT/results/partB/logs"
SELECTION_ARTIFACT="$REPO_ROOT/results/partA/model_selection/partA_02_global_hyperparameters_ARX_I.mat"
STAGE_SCRIPTS=(
  "partB_01_prepare_datasets"
  "partB_02_run_forecasts"
  "partB_03_evaluate_forecasts"
  "partB_04_generate_figures"
)
RUN_ID=""
RUN_LOG_DIR=""
PIPELINE_LOG=""
MANIFEST_FILE=""
PIPELINE_STARTED_AT=""
PIPELINE_STARTED_EPOCH=""
PREFLIGHT_OUTPUT=""

show_help() {
  cat <<'EOF'
Usage:
  ./run_partB_pipeline.sh
  ./run_partB_pipeline.sh --fresh
  ./run_partB_pipeline.sh --help

Description:
  Runs the Part B infectious-population forecasting pipeline:
    1. scripts/partB/partB_01_prepare_datasets.m
         synthetic truth, daily I-entry observations, and causal SIRS-inversion
         estimates for five conditions (clean baseline, observation noise,
         process noise, structural mismatch, combined stress)
    2. scripts/partB/partB_02_run_forecasts.m
         persistence, oracle, and Part A-selected ARX/I Rt drivers propagated
         through the same SIRS model from the same estimated state
    3. scripts/partB/partB_03_evaluate_forecasts.m
         infectious-population MAE/RMSE, paired comparisons, degradation,
         and execution support
    4. scripts/partB/partB_04_generate_figures.m

  Before any artifact is touched, a MATLAB preflight validates the
  environment and configuration and prints the configuration identity.
  Git provenance is captured before --fresh cleanup. Each invocation then
  creates results/partB/logs/<run_id>/ containing run_metadata.txt,
  manifest.tsv, pipeline.log, and one MATLAB log per stage.

Options:
  --fresh     Delete all generated Part B artifacts (data/partB and
              results/partB, including earlier logs) before execution.
              Part A, Part C, source, and configuration files are never touched.
  --help, -h  Show this help message.

Without --fresh, Stage 1 rejects existing Part B artifacts that were not
produced under the current protocol, configuration, and source identity.
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

validate_repository() {
  local stage

  [[ -n "$REPO_ROOT" && "$REPO_ROOT" != "/" ]] || die "Unsafe repository root: '$REPO_ROOT'."
  [[ -f "$REPO_ROOT/startup.m" && -d "$REPO_ROOT/scripts" && -f "$REPO_ROOT/config/partB_config.m" ]] || die "Run this script from the repository root: $REPO_ROOT"

  for stage in "${STAGE_SCRIPTS[@]}"; do
    [[ -f "$REPO_ROOT/scripts/partB/${stage}.m" ]] || die "Missing Part B stage script: scripts/partB/${stage}.m"
  done

  [[ -n "$(ls -A "$REPO_ROOT/third_party/urdme" 2>/dev/null)" ]] || die "third_party/urdme is empty; initialise submodules (git submodule update --init)."
  [[ -f "$SELECTION_ARTIFACT" ]] || die "Missing Part A ARX/I selection artifact: ${SELECTION_ARTIFACT#"$REPO_ROOT"/}"
  [[ -x "$MATLAB_BIN" ]] || die "MATLAB binary not found or not executable: $MATLAB_BIN"
}

# Runs MATLAB once from a temporary directory: product list, path setup via the
# repository startup, configuration construction, dependency resolution, and the
# configuration identity. Any failure aborts before artifacts are touched.
run_matlab_preflight() {
  local preflight_dir
  local matlab_root_escaped
  local matlab_code
  local exit_code=0

  preflight_dir="$(mktemp -d)"
  matlab_root_escaped="${REPO_ROOT//\'/\'\'}"
  matlab_code="ver; fprintf('\n== PARTB_PREFLIGHT ==\n'); run('${matlab_root_escaped}/startup.m'); addpath(genpath('${matlab_root_escaped}/third_party')); cfg = partB_config(); required = {'urdme', 'forecast_closed', 'estimate_sirs_history_from_incidence', 'sirs_step', 'seirs_step', 'compute_point_error'}; for i = 1:numel(required), if isempty(which(required{i})), error('PARTB_PREFLIGHT:MissingDependency', 'Unresolved dependency: %s', required{i}); end, end; products = ver; names = string({products.Name}); if ~any(names == \"System Identification Toolbox\") || ~any(names == \"Statistics and Machine Learning Toolbox\"), error('PARTB_PREFLIGHT:MissingToolbox', 'System Identification and Statistics and Machine Learning toolboxes are required.'); end; fprintf('protocol_version: %s\nconfig_id: %s\nsource_id: %s\ngit_head: %s\ngit_source_dirty: %d\n', cfg.partB.protocol_version, cfg.partB.config_id, cfg.partB.provenance.source_id, cfg.partB.provenance.git_head, cfg.partB.provenance.git_source_dirty); fprintf('== PARTB_CONFIG_JSON ==\n%s\n', jsonencode(cfg.partB.snapshot, 'PrettyPrint', true));"

  PREFLIGHT_OUTPUT="$(cd "$preflight_dir" && "$MATLAB_BIN" -batch "$matlab_code" 2>&1)" || exit_code=$?
  rm -rf -- "$preflight_dir"

  if [[ "$exit_code" -ne 0 ]]; then
    printf '%s\n' "$PREFLIGHT_OUTPUT" | tail -n 30 >&2
    die "MATLAB preflight failed (exit ${exit_code}); no artifacts were changed."
  fi
}

# Prints Git provenance for the launch state. Called before --fresh so the
# tracked Part B artifacts it deletes do not appear as working-tree changes.
capture_git_provenance() {
  local git_status
  local source_changes

  if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'Git metadata unavailable: %s is not a readable Git work tree.\n' "$REPO_ROOT"
    return 0
  fi

  git_status="$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null || true)"
  source_changes="$(printf '%s\n' "$git_status" | grep -Ev '^.. (data|results)/|^$' || true)"

  printf 'Commit: %s\n' "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'unavailable')"
  printf 'Branch: %s\n' "$(git -C "$REPO_ROOT" symbolic-ref --short -q HEAD || printf 'detached HEAD')"

  if [[ -z "$git_status" ]]; then
    printf 'Working tree: clean\n'
  else
    printf 'Working tree: modified\n'
  fi

  if [[ -n "$source_changes" ]]; then
    printf 'WARNING: uncommitted changes outside data/ and results/; the run cannot be reconstructed exactly from the commit alone (see source_id).\n'
  fi

  printf '\nModified and untracked files (git status --porcelain):\n%s\n' "${git_status:-(none)}"
  printf '\nSubmodules (git submodule status; leading + = checkout differs from recorded commit, - = not initialised):\n%s\n' \
    "$(git -C "$REPO_ROOT" submodule status --recursive 2>/dev/null || printf 'unavailable')"
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

# Deletes exactly data/partB and results/partB below the resolved repository
# root, refusing symlinks and any target that resolves outside the repository.
remove_partB_contents() {
  local target
  local resolved

  [[ -n "$REPO_ROOT" && "$REPO_ROOT" != "/" && -f "$REPO_ROOT/startup.m" ]] || die "Refusing cleanup: unexpected repository root '$REPO_ROOT'."

  printf 'Clearing generated Part B artifacts (data/partB, results/partB)...\n'

  for target in "$REPO_ROOT/data/partB" "$REPO_ROOT/results/partB"; do
    case "$target" in
      "$REPO_ROOT/data/partB"|"$REPO_ROOT/results/partB") ;;
      *) die "Refusing cleanup of unexpected path: $target" ;;
    esac

    [[ -e "$target" || -L "$target" ]] || continue
    [[ ! -L "$target" ]] || die "Refusing cleanup: $target is a symbolic link."

    resolved="$(cd "$target" && pwd -P)"
    [[ "$resolved" == "$target" ]] || die "Refusing cleanup: $target resolves to $resolved."

    rm -rf -- "$target"
  done

  create_partB_directories
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

# Writes results/partB/logs/<run_id>/run_metadata.txt once per pipeline run.
write_run_metadata() {
  local git_provenance="$1"
  local metadata_file="$RUN_LOG_DIR/run_metadata.txt"
  local matlab_root
  local version_xml

  matlab_root="$(cd "$(dirname "$(readlink -f "$MATLAB_BIN")")/.." && pwd)"
  version_xml="$matlab_root/VersionInfo.xml"

  {
    printf '== Execution ==\n'
    printf 'Run ID: %s\n' "$RUN_ID"
    printf 'Started: %s\n' "$PIPELINE_STARTED_AT"
    printf 'Repository: %s\n' "$REPO_ROOT"
    printf 'Command: %s\n' "$(printf '%q ' "$0" "${args[@]}")"
    printf 'Fresh (--fresh): %s\n' "$([[ "$fresh_run" -eq 1 ]] && printf 'yes' || printf 'no')"
    printf 'Stages: %s\n' "${STAGE_SCRIPTS[*]}"
    printf 'Configuration file sha256: %s\n' "$(sha256sum "$REPO_ROOT/config/partB_config.m" | cut -d' ' -f1)"
    printf 'Outputs: data/partB, results/partB/{forecasts,evaluation,tables,figures}, results/partB/logs/%s\n' "$RUN_ID"

    printf '\n== Git provenance (captured before cleanup) ==\n%s\n' "$git_provenance"

    printf '\n== MATLAB environment ==\n'
    printf 'Executable: %s\n' "$MATLAB_BIN"
    printf 'MATLAB root: %s\n' "$matlab_root"
    if [[ -f "$version_xml" ]]; then
      printf 'VersionInfo.xml release: %s\n' "$(sed -n 's:.*<release>\(.*\)</release>.*:\1:p' "$version_xml")"
      printf 'VersionInfo.xml version: %s\n' "$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' "$version_xml")"
      printf 'VersionInfo.xml update: %s\n' "$(sed -n 's:.*<description>\(.*\)</description>.*:\1:p' "$version_xml")"
    else
      printf 'VersionInfo.xml: unavailable (%s not found)\n' "$version_xml"
    fi

    printf '\nInstalled products (MATLAB ver; license number omitted):\n'
    printf '%s\n' "$PREFLIGHT_OUTPUT" | sed '/== PARTB_PREFLIGHT ==/,$d' | grep -v 'License Number' || true

    printf '\n== Part B configuration identity (MATLAB preflight) ==\n'
    printf '%s\n' "$PREFLIGHT_OUTPUT" | sed -n '/== PARTB_PREFLIGHT ==/,$p' | sed '1d'
  } > "$metadata_file"
}

render_stage() {
  local stage_index="$1"
  local label="$2"
  local progress="$3"
  local state="$4"

  printf '\r\033[2K[%d/4] %-44s %-20s %s' "$stage_index" "$label" "$progress" "$state"
}

current_stage_progress() {
  local step_name="$1"
  local log_path="$2"
  local completed
  local line

  case "$step_name" in
    partB_01_prepare_datasets)
      completed="$(grep -Ec '^  - ' "$log_path" 2>/dev/null || true)"
      if (( completed > 0 )); then
        printf '%d datasets' "$completed"
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

run_matlab_script() {
  local stage_index="$1"
  local step_name="$2"
  local label="$3"
  local log_path="$RUN_LOG_DIR/${step_name}.log"
  local matlab_code
  local start_epoch
  local elapsed_secs
  local matlab_pid
  local exit_code
  local progress=""

  matlab_code="warning('off', 'backtrace'); addpath(genpath('third_party')); startup; ${step_name};"

  log_status "Starting [${stage_index}/4] ${label}"
  append_manifest "$step_name" "started" "$log_path" "$label"

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
    progress="$(current_stage_progress "$step_name" "$log_path")"
    render_stage "$stage_index" "$label" "$progress" "✓ $(format_duration "$elapsed_secs")"
    printf '\n'

    log_status "Completed [${stage_index}/4] ${label} in ${elapsed_secs}s"
    append_manifest "$step_name" "completed" "$log_path" "duration=${elapsed_secs}s"
  else
    render_stage "$stage_index" "$label" "$progress" "✗ failed"
    printf '\n'

    log_status "Failed [${stage_index}/4] ${label} after ${elapsed_secs}s (exit ${exit_code}). Log: ${log_path}"
    append_manifest "$step_name" "failed" "$log_path" "exit=${exit_code}; duration=${elapsed_secs}s"

    printf '\nPipeline failed at stage %d/4 (%s).\n' "$stage_index" "$step_name"
    printf 'Finished: %s\n' "$(timestamp_now)"
    printf 'Log: %s\n' "$log_path"
    printf '\nLast log lines:\n' >&2
    tail -n 30 "$log_path" >&2 || true

    return "$exit_code"
  fi
}

fresh_run=0
args=("$@")

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

validate_repository
cd "$REPO_ROOT"

printf 'Part B infectious-population forecasting pipeline\n'
printf 'Running MATLAB preflight...\n'
run_matlab_preflight

GIT_PROVENANCE="$(capture_git_provenance)"

if [[ "$fresh_run" -eq 1 ]]; then
  remove_partB_contents
else
  create_partB_directories
fi

initialize_run_logging

PIPELINE_STARTED_AT="$(timestamp_now)"
PIPELINE_STARTED_EPOCH="$(date +%s)"

log_status "Run ID: ${RUN_ID}"
log_status "Fresh: $([[ "$fresh_run" -eq 1 ]] && printf 'yes' || printf 'no')"
log_status "Pipeline started"

write_run_metadata "$GIT_PROVENANCE"

printf 'Run: %s\n' "$RUN_ID"
printf 'Started: %s\n' "$PIPELINE_STARTED_AT"
printf '%s\n' "$PREFLIGHT_OUTPUT" | grep -E '^(config_id|source_id):' || true
if printf '%s\n' "$GIT_PROVENANCE" | grep -q '^WARNING:'; then
  printf 'WARNING: uncommitted source changes; see run_metadata.txt.\n'
fi
printf 'Metadata: results/partB/logs/%s/run_metadata.txt\n\n' "$RUN_ID"

run_matlab_script 1 "partB_01_prepare_datasets" "Prepare synthetic datasets and estimates"
run_matlab_script 2 "partB_02_run_forecasts" "Generate infectious-population forecasts"
run_matlab_script 3 "partB_03_evaluate_forecasts" "Evaluate forecasting performance"
run_matlab_script 4 "partB_04_generate_figures" "Generate scientific figures"

PIPELINE_FINISHED_AT="$(timestamp_now)"
PIPELINE_ELAPSED_SECS=$(( $(date +%s) - PIPELINE_STARTED_EPOCH ))

log_status "Part B pipeline completed successfully in ${PIPELINE_ELAPSED_SECS}s"
log_status "Figures: $REPO_ROOT/results/partB/figures"
log_status "Run logs: ${RUN_LOG_DIR}"

printf '\nPipeline completed successfully.\n'
printf 'Finished: %s\n\n' "$PIPELINE_FINISHED_AT"
printf 'Tables:  results/partB/tables\n'
printf 'Figures: results/partB/figures\n'
printf 'Logs:    results/partB/logs/%s\n' "$RUN_ID"
