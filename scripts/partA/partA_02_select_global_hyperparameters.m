%PARTA_02_SELECT_GLOBAL_MODEL_CONFIGURATIONS Select global Part A model configurations.
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
% Modified: 2026-06-04

%% 1. Initialization
clear; close all; clc;

fprintf('=== Global Model-Configuration Selection ===\n');

cfg = partA_config();
MODEL_TYPE = char(cfg.run.model_type);
EXO_MODE   = char(cfg.run.exo_mode);

fprintf('Configuration: Model = %s | Exogenous Mode = %s\n', MODEL_TYPE, EXO_MODE);

selectionDir = cfg.output.model_selection_dir;
if ~exist(selectionDir, 'dir')
    mkdir(selectionDir);
end

%% 2. Candidate and Scenario Setup
candidate_grid = generate_candidate_grid(cfg, MODEL_TYPE);
num_candidates = size(candidate_grid, 1);

scenario_data = build_forecasting_dataset(cfg, EXO_MODE);
scenario_ids = reshape(string({scenario_data.scenario_id}), 1, []);
window_counts = arrayfun(@(s) numel(s.windows), scenario_data(:)');

pool_cleanup = onCleanup(@local_shutdown_parallel_pool);
if isempty(gcp('nocreate'))
    parpool('Processes', cfg.run.num_workers);
end

%% 3. Candidate Evaluation
fprintf('Stage: Evaluating %d candidate configurations across %d scenarios\n', ...
    num_candidates, length(scenario_data));

evaluation_options = struct( ...
    'model_type', MODEL_TYPE, ...
    'exo_mode', EXO_MODE, ...
    'sirs_cfg', cfg.sirs, ...
    'sim_seed', cfg.sim.seed, ...
    'horizon', cfg.forecast.horizon, ...
    'wis_alphas', cfg.forecast.wis_alphas, ...
    'intervals', cfg.intervals);

[candidate_scores, scenario_mean_wis, global_mean_wis] = ...
    aggregate_candidate_scores(candidate_grid, scenario_data, evaluation_options);

fprintf('Stage: Candidate evaluation complete\n');

[selected_configuration, selected_index, best_global_wis] = ...
    select_best_configuration(candidate_grid, global_mean_wis);

%% 4. Artifact Generation
model_type = MODEL_TYPE;
exo_mode = EXO_MODE;
wis_alphas = cfg.forecast.wis_alphas;
aggregation_mode = 'equal_scenario_mean_wis';
failure_policy = 'inf_on_invalid';
cfg_snapshot = cfg.run_snapshot;

file_prefix = sprintf('partA_02_global_hyperparameters_%s_%s', MODEL_TYPE, EXO_MODE);
artifact_path = fullfile(selectionDir, [file_prefix, '.mat']);

save(artifact_path, ...
    'model_type', 'exo_mode', ...
    'candidate_grid', 'candidate_scores', ...
    'scenario_mean_wis', 'global_mean_wis', ...
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
