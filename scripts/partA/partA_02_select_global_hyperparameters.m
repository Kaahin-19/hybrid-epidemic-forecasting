%PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS Select global Part A model hyperparameters.
%
%   Description:
%       Evaluates the active model family and exogenous-input setting across
%       all Part A synthetic truth scenarios, using the established
%       expanding-window WIS protocol. The raw best candidate is the one with
%       the lowest cross-scenario global mean WIS; the final selected
%       configuration is the simplest candidate whose global mean WIS lies
%       within one empirical standard error of that raw best (one-SE parsimony
%       rule). WIS remains the selection metric; AICc stays diagnostic only.
%
%   Workflow:
%       1. Load configuration and synthetic truth artifacts.
%       2. Generate the candidate grid for the active model family.
%       3. Evaluate and aggregate candidate WIS scores.
%       4. Save one MATLAB model-selection artifact.
%
%   See also PARTA_CONFIG, BUILD_FORECAST_ENTRIES, GENERATE_CANDIDATE_GRID,
%            EVALUATE_CANDIDATE, AGGREGATE_CANDIDATE_SCORES.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-12

%% 1. Initialization
clear; close all; clc;

fprintf('=== Global Model-Configuration Selection ===\n');

cfg = partA_config();
model_type = cfg.run.model_type;
exo_mode   = cfg.run.exo_mode;

fprintf('Configuration: Model = %s | Exogenous Mode = %s\n', model_type, exo_mode);

selectionDir = cfg.output.model_selection_dir;
if ~exist(selectionDir, 'dir')
    mkdir(selectionDir);
end

%% 2. Candidate and Scenario Setup
candidate_grid = generate_candidate_grid(cfg, model_type);
num_candidates = size(candidate_grid, 1);

scenario_data = build_forecast_entries(cfg, exo_mode);
scenario_ids = [scenario_data.scenario_id];
window_counts = arrayfun(@(s) numel(s.windows), scenario_data(:)');

if isempty(gcp('nocreate'))
    parpool('Processes', cfg.run.num_workers);
    pool_cleanup = onCleanup(@local_shutdown_parallel_pool);
end

%% 3. Candidate Evaluation
fprintf('Stage: Evaluating %d candidate configurations across %d scenarios\n', ...
    num_candidates, length(scenario_data));

evaluation_options = struct( ...
    'model_type', model_type, ...
    'exo_mode', exo_mode, ...
    'sirs_cfg', cfg.sirs, ...
    'sim_seed', cfg.sim.seed, ...
    'horizon', cfg.forecast.horizon, ...
    'wis_alphas', cfg.forecast.wis_alphas, ...
    'intervals', cfg.intervals);

[candidate_scores, global_mean_wis, candidate_aicc, global_mean_aicc] = ...
    aggregate_candidate_scores(candidate_grid, scenario_data, evaluation_options);

fprintf('Stage: Candidate evaluation complete\n');
clear pool_cleanup

[best_global_wis, raw_best_index] = min(global_mean_wis);

if ~isfinite(best_global_wis)
    error('MODEL_SELECTION:NoValidCandidate', ...
        'All candidate model configurations produced invalid global WIS scores.');
end

one_se_threshold = best_global_wis + local_one_se(candidate_scores(raw_best_index, :));
candidate_complexity = local_candidate_complexity(model_type, candidate_grid, ...
    scenario_data(1).num_exo);
eligible = isfinite(global_mean_wis) & (global_mean_wis <= one_se_threshold);
eligible(raw_best_index) = true;
selected_index = local_select_simplest(candidate_complexity, global_mean_wis, eligible);

selected_configuration = candidate_grid(selected_index, :);

%% 4. Artifact Generation
wis_alphas = cfg.forecast.wis_alphas;
aggregation_mode = "equal_scenario_mean_wis";
failure_policy = "inf_on_invalid";
cfg_snapshot = cfg.run_snapshot;

candidate_diagnostics = struct( ...
    'description', "Fitted-model AICc complexity diagnostic; not a selection criterion.", ...
    'scenario_ids', scenario_ids, ...
    'candidate_aicc', candidate_aicc, ...
    'global_mean_aicc', global_mean_aicc, ...
    'selected_global_mean_aicc', global_mean_aicc(selected_index), ...
    'aicc_source', "sys.Report.Fit.AICc per fit, averaged over finite expanding windows then over scenarios", ...
    'interpretation', "Compare AICc within a model family/likelihood; cross-family AICc differences are weak evidence.");

file_prefix = sprintf('partA_02_global_hyperparameters_%s_%s', model_type, exo_mode);
artifact_path = fullfile(selectionDir, [file_prefix, '.mat']);

save(artifact_path, ...
    'model_type', 'exo_mode', ...
    'candidate_grid', 'candidate_scores', 'global_mean_wis', ...
    'selected_configuration', 'selected_index', ...
    'scenario_ids', 'window_counts', 'cfg_snapshot', ...
    'wis_alphas', 'aggregation_mode', 'failure_policy', 'best_global_wis', ...
    'candidate_diagnostics');

fprintf('Selected global model configuration: %s\n', mat2str(selected_configuration));
fprintf('Global model-selection artifact saved to: %s\n', artifact_path);
fprintf('=== Global Model-Configuration Selection Complete ===\n\n');

%% 5. Local Functions
function local_shutdown_parallel_pool()
%LOCAL_SHUTDOWN_PARALLEL_POOL Close the local parallel pool before MATLAB exits.
pool = gcp('nocreate');
if ~isempty(pool)
    delete(pool);
end
end

function one_se = local_one_se(scenario_scores)
%LOCAL_ONE_SE Empirical standard error of the equal-scenario mean WIS.
scenario_scores = scenario_scores(isfinite(scenario_scores));
n = numel(scenario_scores);
if n < 2
    one_se = 0;
else
    one_se = std(scenario_scores, 0) / sqrt(n);
end
if ~isscalar(one_se) || ~isfinite(one_se) || one_se < 0
    one_se = 0;
end
end

function complexity = local_candidate_complexity(model_type, candidate_grid, num_exo)
%LOCAL_CANDIDATE_COMPLEXITY Estimated free-parameter count per candidate.
model_type = string(model_type);
n = size(candidate_grid, 1);
complexity = nan(n, 1);
for i = 1:n
    row = candidate_grid(i, :);
    switch model_type
        case "AR"
            complexity(i) = row(1);
        case "ARX"
            complexity(i) = row(1) + num_exo * row(2) + row(3);
        case {"N4SID", "SSEST"}
            complexity(i) = row(1) + row(2);
        otherwise
            complexity(i) = sum(row);
    end
end
end

function idx = local_select_simplest(candidate_complexity, global_mean_wis, eligible)
%LOCAL_SELECT_SIMPLEST Simplest eligible candidate; ties broken by WIS then index.
candidate_indices = find(eligible);
keys = [candidate_complexity(candidate_indices), ...
    global_mean_wis(candidate_indices), candidate_indices];
keys = sortrows(keys, [1 2 3]);
idx = keys(1, 3);
end
