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
PIPELINE_STARTED_AT=""
PIPELINE_STARTED_EPOCH=""

show_help() {
  cat <<'EOF'
Usage:
  ./run_partA_pipeline.sh
  ./run_partA_pipeline.sh --models <ids> --exo <ids>
  ./run_partA_pipeline.sh --models <ids> --exo <ids> --fresh
  ./run_partA_pipeline.sh --models <ids> --exo <ids> --reuse-selection
  ./run_partA_pipeline.sh --help

Description:
  Runs the configuration-driven Part A synthetic forecasting pipeline:

    1. Generate (or reuse) the development, refinement, and assessment
       synthetic datasets.
    2. For each selected valid Model/Exo combination, select its
       hyperparameters: preliminary identification on the development
       data, cross-scenario validation on A1-A4, and final refinement.
    3. For each selected valid Model/Exo combination, run the independent
       assessment forecasts of the final configuration.
    4. Evaluate all accumulated compatible artifacts.
    5. Generate Part A thesis figures: comparative figures from all
       accumulated compatible results, and configuration-specific
       (representative forecast) figures for the selected combinations
       only. Configuration-specific figures of other combinations are
       kept as they are.

  Selection for every requested combination completes before any
  independent assessment starts. Artifacts of combinations from earlier
  runs are kept and evaluated together with the new ones when they were
  produced under the same configuration; incompatible artifacts stop the
  evaluation stage.

  When no candidate of a combination is feasible in preliminary
  identification or final refinement, its selection stage records a
  no-feasible-candidate outcome (shown as "no feasible candidate"), its
  dependent stages are not applicable (its assessment is shown as "not
  applicable"), and the pipeline continues with the remaining
  combinations. Evaluation and figures report the combination as having
  no feasible candidate. Any other MATLAB error stops the pipeline.

  Each invocation creates a timestamped run folder under:
    results/partA/logs/<run_id>/

  The folder contains the pipeline log, per-stage MATLAB logs, and a
  manifest file.

  The terminal shows one compact row per stage. Long-running stages update
  their progress in place while full MATLAB output remains in the stage logs.

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
  The script forms the cross-product of the selected sets and keeps only
  combinations supported by the current Part A pipeline.

  Current valid combinations:
    AR    -> None
    ARX   -> S, I, Both
    N4SID -> None, S, I, Both
    SSEST -> None, S, I, Both

Examples:
  ./run_partA_pipeline.sh
  ./run_partA_pipeline.sh --models 2 --exo 2
  ./run_partA_pipeline.sh --models 3,4 --exo 3
  ./run_partA_pipeline.sh --models 1,2,3,4 --exo 0,1,2,3
  ./run_partA_pipeline.sh --models 1,2,3,4 --exo 0,1,2,3 --fresh
  ./run_partA_pipeline.sh --models 3 --exo 0,2,3 --reuse-selection

Options:
  --models <ids>  Model type IDs to run. Default: all model type IDs.
  --exo <ids>     Exogenous mode IDs to run. Default: all exogenous mode IDs.
  --fresh         Delete data/partA and the generated Part A results
                  (model_selection, forecasts, evaluation, tables, figures)
                  before execution. Run logs are kept. With a subset of
                  combinations, only the selected combinations are rerun.
  --reuse-selection
                  Skip hyperparameter selection for selected combinations
                  that already have a recorded selection outcome (a final
                  configuration handover or a no-feasible-candidate record)
                  and run the later stages from it; combinations without one
                  are selected as usual. The assessment and evaluation stages
                  check that the reused artifacts are consistent and match
                  the current configuration. Cannot be combined with --fresh.
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
  printf 'Timestamp\tStep\tModel\tExo\tStatus\tLogFile\tDetails\n' > "$MANIFEST_FILE"
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

create_partA_directories() {
  mkdir -p \
    "$REPO_ROOT/data/partA" \
    "$REPO_ROOT/results/partA/model_selection" \
    "$REPO_ROOT/results/partA/forecasts" \
    "$REPO_ROOT/results/partA/evaluation" \
    "$REPO_ROOT/results/partA/tables" \
    "$REPO_ROOT/results/partA/figures" \
    "$REPO_ROOT/results/partA/logs"
}

# Deletes data/partA and the generated results/partA subdirectories below the
# resolved repository root, keeping results/partA/logs, and refuses symlinks
# and any target that resolves outside the repository.
remove_partA_contents() {
  local target
  local resolved

  [[ -n "$REPO_ROOT" && "$REPO_ROOT" != "/" && -f "$REPO_ROOT/startup.m" ]] || die "Refusing cleanup: unexpected repository root '$REPO_ROOT'."

  local targets=(
    "$REPO_ROOT/data/partA"
    "$REPO_ROOT/results/partA/model_selection"
    "$REPO_ROOT/results/partA/forecasts"
    "$REPO_ROOT/results/partA/evaluation"
    "$REPO_ROOT/results/partA/tables"
    "$REPO_ROOT/results/partA/figures")

  for target in "${targets[@]}"; do
    [[ -e "$target" || -L "$target" ]] || continue
    [[ ! -L "$target" ]] || die "Refusing cleanup: $target is a symbolic link."

    resolved="$(cd "$target" && pwd -P)"
    [[ "$resolved" == "$target" ]] || die "Refusing cleanup: $target resolves to $resolved."
  done

  printf 'Clearing generated Part A artifacts (data/partA, results/partA except logs)...\n'

  for target in "${targets[@]}"; do
    rm -rf -- "$target"
  done

  create_partA_directories
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
    AR)
      [[ "$exo_name" == "None" ]]
      ;;
    ARX)
      [[ "$exo_name" != "None" ]]
      ;;
    N4SID|SSEST)
      return 0
      ;;
    *)
      return 1
      ;;
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

render_stage() {
  local stage_index="$1"
  local total_stages="$2"
  local label="$3"
  local progress="$4"
  local state="$5"

  printf '\r\033[2K[%d/%d] %-34s %-22s %s' \
    "$stage_index" \
    "$total_stages" \
    "$label" \
    "$progress" \
    "$state"
}

current_stage_progress() {
  local step_name="$1"
  local log_path="$2"
  local completed
  local line

  case "$step_name" in
    truth)
      if grep -Eq '^Datasets: reused' "$log_path" 2>/dev/null; then
        printf 'datasets reused'
        return 0
      fi

      line="$(grep -E '^Generating [0-9]+ trajectories' "$log_path" 2>/dev/null | tail -n 1 || true)"
      completed="$(grep -Ec '^  - Generating ' "$log_path" 2>/dev/null || true)"

      if [[ "$line" =~ Generating[[:space:]]+([0-9]+)[[:space:]]+trajectories ]]; then
        printf '%d/%s trajectories' "$completed" "${BASH_REMATCH[1]}"
      fi
      ;;

    model_selection)
      # Stage k of partA_02 announces its task count (first number on its
      # header line); candidates or trajectories completed since then are
      # counted from the worker output.
      awk '
        /^Stage [123]:/ {
          stage = substr($2, 1, 1); total = ""; done = 0
          for (i = 3; i <= NF; i++) if (total == "" && $i ~ /^[0-9]+$/) total = $i
        }
        /^Evaluated candidate / || /^Forecast trajectory / { done++ }
        END { if (stage != "") printf "stage %s/3 %d/%s", stage, done, total }
      ' "$log_path" 2>/dev/null || true
      ;;

    forecast)
      line="$(grep -E '^Processing trajectory [0-9]+/[0-9]+' "$log_path" 2>/dev/null | tail -n 1 || true)"

      if [[ "$line" =~ Processing[[:space:]]+trajectory[[:space:]]+([0-9]+)/([0-9]+) ]]; then
        printf '%s/%s trajectories' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      fi
      ;;
  esac
}

final_stage_progress() {
  local step_name="$1"
  local log_path="$2"

  case "$(stage_outcome "$step_name" "$log_path")" in
    no_feasible_candidate)
      printf 'no feasible candidate'
      ;;
    not_applicable)
      printf 'not applicable'
      ;;
    *)
      case "$step_name" in
        truth|model_selection|forecast)
          current_stage_progress "$step_name" "$log_path"
          ;;
      esac
      ;;
  esac
}

# Prints the manifest status of a completed stage: partA_02 records a
# selection without a feasible candidate, and partA_03 reports the
# assessment of such a selection as not applicable.
stage_outcome() {
  local step_name="$1"
  local log_path="$2"

  if [[ "$step_name" == "model_selection" ]] && grep -Eq '^Selection outcome: no feasible candidate' "$log_path" 2>/dev/null; then
    printf 'no_feasible_candidate'
  elif [[ "$step_name" == "forecast" ]] && grep -Eq '^Assessment not applicable' "$log_path" 2>/dev/null; then
    printf 'not_applicable'
  else
    printf 'completed'
  fi
}

# Succeeds when a combination has a recorded selection outcome: a final
# configuration handover or a no-feasible-candidate record.
selection_outcome_recorded() {
  local suffix="$1_$2"
  local selection_dir="$REPO_ROOT/results/partA/model_selection"

  [[ -f "$selection_dir/partA_02_global_hyperparameters_${suffix}.mat" || -f "$selection_dir/partA_02_no_feasible_candidate_${suffix}.mat" ]]
}

run_matlab_code() {
  local stage_index="$1"
  local total_stages="$2"
  local step_name="$3"
  local label="$4"
  local description="$5"
  local model_name="$6"
  local exo_name="$7"
  local log_path="$8"
  local matlab_body="$9"

  local matlab_code
  local start_epoch
  local elapsed_secs
  local matlab_pid
  local exit_code
  local progress=""

  matlab_code="warning('off', 'backtrace'); run('startup.m'); addpath(genpath('third_party')); ${matlab_body}"

  log_status "Starting ${description}"
  append_manifest "$step_name" "$model_name" "$exo_name" "started" "$log_path" "$description"

  : > "$log_path"
  start_epoch="$(date +%s)"

  render_stage "$stage_index" "$total_stages" "$label" "" "running"

  "$MATLAB_BIN" -batch "$matlab_code" > "$log_path" 2>&1 &
  matlab_pid=$!

  while kill -0 "$matlab_pid" 2>/dev/null; do
    progress="$(current_stage_progress "$step_name" "$log_path")"
    render_stage "$stage_index" "$total_stages" "$label" "$progress" "running"
    sleep 1
  done

  set +e
  wait "$matlab_pid"
  exit_code=$?
  set -e

  elapsed_secs=$(( $(date +%s) - start_epoch ))

  if [[ "$exit_code" -eq 0 ]]; then
    progress="$(final_stage_progress "$step_name" "$log_path")"
    render_stage "$stage_index" "$total_stages" "$label" "$progress" "✓ $(format_duration "$elapsed_secs")"
    printf '\n'

    log_status "Completed ${description} in ${elapsed_secs}s ($(stage_outcome "$step_name" "$log_path"))"
    append_manifest "$step_name" "$model_name" "$exo_name" "$(stage_outcome "$step_name" "$log_path")" "$log_path" "${elapsed_secs}s"
  else
    render_stage "$stage_index" "$total_stages" "$label" "$progress" "✗ failed"
    printf '\n'

    log_status "Failed ${description} after ${elapsed_secs}s (exit ${exit_code}). Log: ${log_path}"
    append_manifest "$step_name" "$model_name" "$exo_name" "failed" "$log_path" "exit=${exit_code}; elapsed=${elapsed_secs}s"

    printf '\nPipeline failed.\n'
    printf 'Finished: %s\n' "$(timestamp_now)"
    printf 'Log: %s\n' "$log_path"
    printf '\nLast log lines:\n' >&2
    tail -n 30 "$log_path" >&2 || true

    return "$exit_code"
  fi
}

run_matlab_script() {
  local stage_index="$1"
  local total_stages="$2"
  local step_name="$3"
  local label="$4"
  local description="$5"
  local log_path="$6"
  local script_path="$7"

  run_matlab_code \
    "$stage_index" \
    "$total_stages" \
    "$step_name" \
    "$label" \
    "$description" \
    "-" \
    "-" \
    "$log_path" \
    "run('${script_path}');"
}

# Prints Git provenance for the launch state. Called before --fresh so the
# tracked Part A artifacts it deletes do not appear as working-tree changes.
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
    printf 'WARNING: uncommitted changes outside data/ and results/; the run cannot be reconstructed exactly from the commit alone.\n'
  fi

  printf '\nModified and untracked files (git status --porcelain):\n%s\n' "${git_status:-(none)}"
  printf '\nSubmodules (git submodule status; leading + = checkout differs from recorded commit, - = not initialised):\n%s\n' \
    "$(git -C "$REPO_ROOT" submodule status --recursive 2>/dev/null || printf 'unavailable')"
}

# Writes results/partA/logs/<run_id>/run_metadata.txt once per pipeline run.
write_run_metadata() {
  local git_provenance="$1"
  local metadata_file="$RUN_LOG_DIR/run_metadata.txt"
  local matlab_root
  local version_xml
  local ver_output
  local ver_exit=0
  local i

  matlab_root="$(cd "$(dirname "$(readlink -f "$MATLAB_BIN")")/.." && pwd)"
  version_xml="$matlab_root/VersionInfo.xml"

  # Run `ver` outside the repository so MATLAB does not auto-run startup.m.
  ver_output="$(cd "$RUN_LOG_DIR" && "$MATLAB_BIN" -batch "ver" 2>&1)" || ver_exit=$?

  {
    printf '== Execution ==\n'
    printf 'Run ID: %s\n' "$RUN_ID"
    printf 'Started: %s\n' "$PIPELINE_STARTED_AT"
    printf 'Repository: %s\n' "$REPO_ROOT"
    printf 'Command: %s\n' "$(printf '%q ' "$0" "${args[@]}")"
    printf 'Fresh (--fresh): %s\n' "$([[ "$fresh_run" -eq 1 ]] && printf 'yes' || printf 'no')"
    printf 'Reuse recorded selections (--reuse-selection): %s\n' "$([[ "$reuse_selection" -eq 1 ]] && printf 'yes' || printf 'no')"
    printf 'Selected model/exo combinations (%d):\n' "${#combo_models[@]}"
    for i in "${!combo_models[@]}"; do
      printf '  %s | %s\n' "${combo_models[$i]}" "${combo_exos[$i]}"
    done
    printf 'Skipped invalid combinations (%d):\n' "${#skipped_combos[@]}"
    for i in "${!skipped_combos[@]}"; do
      printf '  %s\n' "${skipped_combos[$i]}"
    done

    printf '\n== Git provenance ==\n%s\n' "$git_provenance"

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

    if [[ "$ver_exit" -eq 0 ]]; then
      printf '\nInstalled products (MATLAB ver; license number omitted):\n'
      printf '%s\n' "$ver_output" | grep -v 'License Number' || true
    else
      printf '\nMATLAB ver unavailable (exit %d).\n' "$ver_exit"
    fi
  } > "$metadata_file"
}

models_spec=""
exo_spec=""
fresh_run=0
reuse_selection=0

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

    --reuse-selection)
      reuse_selection=1
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

[[ "$fresh_run" -eq 0 || "$reuse_selection" -eq 0 ]] || die "--reuse-selection cannot be combined with --fresh."

if [[ ! -f "$REPO_ROOT/startup.m" ]] || [[ ! -d "$REPO_ROOT/scripts" ]]; then
  die "Run this script from the repository root: $REPO_ROOT"
fi

[[ -x "$MATLAB_BIN" ]] || die "MATLAB binary not found or not executable: $MATLAB_BIN"

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

GIT_PROVENANCE="$(capture_git_provenance)"

cd "$REPO_ROOT"

if [[ "$fresh_run" -eq 1 ]]; then
  remove_partA_contents
else
  create_partA_directories
fi

initialize_run_logging

PIPELINE_STARTED_AT="$(timestamp_now)"
PIPELINE_STARTED_EPOCH="$(date +%s)"

for skipped in "${skipped_combos[@]}"; do
  append_manifest "selection" "-" "-" "skipped" "-" "$skipped"
done

TOTAL_STAGES=$((3 + 2 * ${#combo_models[@]}))

log_status "Run ID: ${RUN_ID}"
log_status "Running Part A synthetic forecasting pipeline"
log_status "Pipeline started"

printf 'Part A synthetic forecasting pipeline\n'
printf 'Run: %s\n' "$RUN_ID"
printf 'Started: %s\n' "$PIPELINE_STARTED_AT"
printf 'Configurations: %d\n' "${#combo_models[@]}"

if [[ "${#skipped_combos[@]}" -gt 0 ]]; then
  printf 'Skipped invalid combinations: %d\n' "${#skipped_combos[@]}"
fi

printf 'Metadata: results/partA/logs/%s/run_metadata.txt\n' "$RUN_ID"
write_run_metadata "$GIT_PROVENANCE"

printf '\n'

stage_index=1

run_matlab_script \
  "$stage_index" \
  "$TOTAL_STAGES" \
  "truth" \
  "Generate synthetic datasets" \
  "Generating or reusing Part A synthetic datasets" \
  "$RUN_LOG_DIR/partA_01_generate_truth.log" \
  "scripts/partA/partA_01_generate_truth.m"

stage_index=$((stage_index + 1))

declare -a no_feasible_combos=()

for idx in "${!combo_models[@]}"; do
  model_name="${combo_models[$idx]}"
  exo_name="${combo_exos[$idx]}"
  safe_model="$(sanitize_name "$model_name")"
  safe_exo="$(sanitize_name "$exo_name")"

  if [[ "$reuse_selection" -eq 1 ]] && selection_outcome_recorded "$model_name" "$exo_name"; then
    if [[ -f "$REPO_ROOT/results/partA/model_selection/partA_02_no_feasible_candidate_${model_name}_${exo_name}.mat" ]]; then
      selection_state="reused: no feasible candidate"
      no_feasible_combos+=("${model_name} | ${exo_name}")
    else
      selection_state="reused"
    fi

    render_stage "$stage_index" "$TOTAL_STAGES" "Select ${model_name} | ${exo_name}" "" "$selection_state"
    printf '\n'

    log_status "Reusing the recorded selection outcome of ${model_name} | ${exo_name} (${selection_state})"
    append_manifest "model_selection" "$model_name" "$exo_name" "reused" "-" "$selection_state"

    stage_index=$((stage_index + 1))
    continue
  fi

  selection_log="$RUN_LOG_DIR/${safe_model}_${safe_exo}_model_selection.log"

  PARTA_MODEL_TYPE="$model_name" \
  PARTA_EXO_MODE="$exo_name" \
  run_matlab_code \
    "$stage_index" \
    "$TOTAL_STAGES" \
    "model_selection" \
    "Select ${model_name} | ${exo_name}" \
    "Selecting hyperparameters for ${model_name} | ${exo_name}" \
    "$model_name" \
    "$exo_name" \
    "$selection_log" \
    "run('scripts/partA/partA_02_select_hyperparameters.m');"

  if [[ "$(stage_outcome "model_selection" "$selection_log")" == "no_feasible_candidate" ]]; then
    no_feasible_combos+=("${model_name} | ${exo_name}")
  fi

  stage_index=$((stage_index + 1))
done

for idx in "${!combo_models[@]}"; do
  model_name="${combo_models[$idx]}"
  exo_name="${combo_exos[$idx]}"
  safe_model="$(sanitize_name "$model_name")"
  safe_exo="$(sanitize_name "$exo_name")"

  PARTA_MODEL_TYPE="$model_name" \
  PARTA_EXO_MODE="$exo_name" \
  run_matlab_code \
    "$stage_index" \
    "$TOTAL_STAGES" \
    "forecast" \
    "Assess ${model_name} | ${exo_name}" \
    "Running independent assessment forecasts for ${model_name} | ${exo_name}" \
    "$model_name" \
    "$exo_name" \
    "$RUN_LOG_DIR/${safe_model}_${safe_exo}_assessment.log" \
    "run('scripts/partA/partA_03_run_forecasts.m');"

  stage_index=$((stage_index + 1))
done

run_matlab_script \
  "$stage_index" \
  "$TOTAL_STAGES" \
  "evaluation" \
  "Evaluate artifacts" \
  "Evaluating accumulated Part A selection and forecast artifacts" \
  "$RUN_LOG_DIR/partA_04_evaluate_forecasts.log" \
  "scripts/partA/partA_04_evaluate_forecasts.m"

stage_index=$((stage_index + 1))

# The selected combinations set the scope of the configuration-specific
# figures (cfg.figures in partA_config.m).
figure_configurations=""
for idx in "${!combo_models[@]}"; do
  figure_configurations+="${figure_configurations:+,}${combo_models[$idx]}/${combo_exos[$idx]}"
done

PARTA_FIGURE_SCOPE="selected" \
PARTA_FIGURE_CONFIGURATIONS="$figure_configurations" \
run_matlab_script \
  "$stage_index" \
  "$TOTAL_STAGES" \
  "figures" \
  "Generate thesis figures" \
  "Generating Part A thesis figures" \
  "$RUN_LOG_DIR/partA_05_generate_figures.log" \
  "scripts/partA/partA_05_generate_figures.m"

PIPELINE_FINISHED_AT="$(timestamp_now)"
PIPELINE_ELAPSED_SECS=$(( $(date +%s) - PIPELINE_STARTED_EPOCH ))

log_status "Part A synthetic forecasting pipeline completed successfully in ${PIPELINE_ELAPSED_SECS}s"
log_status "Thesis-level figures generated under: $REPO_ROOT/results/partA/figures"
log_status "Run logs saved to: ${RUN_LOG_DIR}"

printf '\nPipeline completed successfully.\n'
printf 'Finished: %s\n' "$PIPELINE_FINISHED_AT"

if [[ "${#no_feasible_combos[@]}" -gt 0 ]]; then
  printf 'No feasible candidate (dependent stages not applicable): %s\n' "$(IFS=','; printf '%s' "${no_feasible_combos[*]}" | sed 's/,/, /g')"
  log_status "No feasible candidate: ${no_feasible_combos[*]}"
fi

printf '\n'
printf 'Figures: results/partA/figures\n'
printf 'Logs:    results/partA/logs/%s\n' "$RUN_ID"