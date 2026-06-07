%PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS Select global Part A model hyperparameters.
%
%   Description:
%       Evaluates the active model family and exogenous-input setting across
%       all Part A synthetic truth scenarios, using the established
%       expanding-window WIS protocol. The selected configuration is the
%       candidate with the lowest cross-scenario global mean WIS.
%
%   Workflow:
%       1. Load configuration and synthetic truth artifacts.
%       2. Generate the candidate grid for the active model family.
%       3. Evaluate and aggregate candidate WIS scores.
%       4. Save one MATLAB model-selection artifact.
%
%   See also PARTA_CONFIG, BUILD_FORECASTING_DATASET, GENERATE_CANDIDATE_GRID,
%            EVALUATE_CANDIDATE, AGGREGATE_CANDIDATE_SCORES, SELECT_BEST_CONFIGURATION.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-05

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

scenario_data = build_forecasting_dataset(cfg, exo_mode);
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

[candidate_scores, global_mean_wis] = ...
    aggregate_candidate_scores(candidate_grid, scenario_data, evaluation_options);

fprintf('Stage: Candidate evaluation complete\n');
clear pool_cleanup

[best_global_wis, selected_index] = min(global_mean_wis);

if ~isfinite(best_global_wis)
    error('MODEL_SELECTION:NoValidCandidate', ...
        'All candidate model configurations produced invalid global WIS scores.');
end

selected_configuration = candidate_grid(selected_index, :);

%% 4. Artifact Generation
wis_alphas = cfg.forecast.wis_alphas;
aggregation_mode = "equal_scenario_mean_wis";
failure_policy = "inf_on_invalid";
cfg_snapshot = cfg.run_snapshot;

file_prefix = sprintf('partA_02_global_hyperparameters_%s_%s', model_type, exo_mode);
artifact_path = fullfile(selectionDir, [file_prefix, '.mat']);

save(artifact_path, ...
    'model_type', 'exo_mode', ...
    'candidate_grid', 'candidate_scores', 'global_mean_wis', ...
    'selected_configuration', 'selected_index', ...
    'scenario_ids', 'window_counts', 'cfg_snapshot', ...
    'wis_alphas', 'aggregation_mode', 'failure_policy', 'best_global_wis');

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
