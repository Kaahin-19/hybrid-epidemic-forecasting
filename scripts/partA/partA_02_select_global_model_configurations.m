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
%   See also PARTA_CONFIG, GENERATE_CANDIDATE_GRID, EVALUATE_CANDIDATE,
%            AGGREGATE_CANDIDATE_SCORES, SELECT_BEST_CONFIGURATION.
%
% A. M. Kaahin 2026-05-31

%% 1. Initialization
clear; close all; clc;

fprintf('=== Global Model-Configuration Selection ===\n');

cfg = partA_config();
MODEL_TYPE = char(cfg.run.model_type);
EXO_MODE   = char(cfg.run.exo_mode);

EXO_MODE = local_validate_configuration(MODEL_TYPE, EXO_MODE);
fprintf('Configuration: Model = %s | Exogenous Mode = %s\n', MODEL_TYPE, EXO_MODE);

dataDir = cfg.output.data_dir;
selectionDir = cfg.output.model_selection_dir;
fileList = dir(fullfile(dataDir, '*.mat'));

if isempty(fileList)
    error('SELECT:NoData', ...
        'No synthetic truth files found. Run partA_01_generate_synthetic_truth.m first.');
end

if ~exist(selectionDir, 'dir')
    mkdir(selectionDir);
end

%% 2. Candidate and Scenario Setup
[candidate_grid, parameter_names] = generate_candidate_grid(cfg, MODEL_TYPE);
num_candidates = size(candidate_grid, 1);

fprintf('Stage: Preparing scenario-window inputs for %d scenarios\n', length(fileList));
scenario_data = local_prepare_scenario_data(fileList, dataDir, cfg, EXO_MODE);
scenario_ids = reshape(string({scenario_data.scenario_id}), 1, []);
window_counts = zeros(1, length(scenario_data));
for i = 1:length(scenario_data)
    window_counts(i) = numel(scenario_data(i).windows);
end

pool_cleanup = onCleanup(@local_shutdown_parallel_pool);
if isempty(gcp('nocreate'))
    parpool('Processes', 4);
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
selected_model = selected_configuration;
candidate_models = candidate_grid;
wis_alphas = cfg.forecast.wis_alphas;
aggregation_mode = 'equal_scenario_mean_wis';
failure_policy = 'inf_on_invalid';
cfg_snapshot = struct( ...
    'min_window', cfg.forecast.min_window, ...
    'step_size', cfg.forecast.step_size, ...
    'horizon', cfg.forecast.horizon, ...
    'wis_alphas', cfg.forecast.wis_alphas, ...
    'pop_size', cfg.sirs.pop_size, ...
    'gamma', cfg.sirs.gamma, ...
    'xi', cfg.sirs.xi, ...
    'sim_seed', cfg.sim.seed);

file_prefix = sprintf('partA_02_global_hyperparameters_%s_%s', MODEL_TYPE, EXO_MODE);
artifact_path = fullfile(selectionDir, [file_prefix, '.mat']);

save(artifact_path, ...
    'model_type', 'exo_mode', ...
    'candidate_grid', 'candidate_scores', ...
    'scenario_mean_wis', 'global_mean_wis', ...
    'selected_configuration', 'selected_index', ...
    'scenario_ids', 'window_counts', 'cfg_snapshot', ...
    'selected_model', 'candidate_models', 'parameter_names', ...
    'wis_alphas', 'aggregation_mode', 'failure_policy', 'best_global_wis');

fprintf('Selected global model configuration: %s\n', mat2str(selected_configuration));
fprintf('Global model-selection artifact saved to: %s\n', artifact_path);
fprintf('=== Global Model-Configuration Selection Complete ===\n\n');

%% 5. Local Functions
function valid_exo_mode = local_validate_configuration(model_type, exo_mode)
%LOCAL_VALIDATE_CONFIGURATION Resolve logical conflicts in run configuration.
    valid_exo_mode = exo_mode;
    if strcmp(model_type, 'AR') && ~strcmp(exo_mode, 'None')
        warning('CFG:ArExo', 'AR is strictly autoregressive. Forcing EXO_MODE to None.');
        valid_exo_mode = 'None';
    elseif strcmp(model_type, 'ARX') && strcmp(exo_mode, 'None')
        error('CFG:ArxExo', 'ARX requires exogenous covariates. Set EXO_MODE to S, I, or Both.');
    elseif ~any(strcmp(model_type, {'AR', 'ARX', 'N4SID', 'SSEST'}))
        error('CFG:UnknownModel', 'Unsupported MODEL_TYPE: %s', model_type);
    end
end

function scenario_data = local_prepare_scenario_data(fileList, dataDir, cfg, exo_mode)
%LOCAL_PREPARE_SCENARIO_DATA Load truth artifacts and precompute window inputs.
    horizon = cfg.forecast.horizon;
    sirs_cfg = cfg.sirs;

    scenario_data = repmat(struct( ...
        'scenario_id', "", ...
        'num_exo', 0, ...
        'windows', [], ...
        'window_data', []), length(fileList), 1);

    for i = 1:length(fileList)
        filename = fileList(i).name;
        fullPath = fullfile(dataDir, filename);
        [~, name_core] = fileparts(filename);

        loaded = load(fullPath);
        local_validate_truth_artifact(loaded, fullPath);

        scenario_id = string(strrep(name_core, 'partA_01_truth_', ''));
        scaled_S = loaded.S_true(:) / cfg.sirs.pop_size;
        scaled_I = loaded.I_true(:) / cfg.sirs.pop_size;

        switch exo_mode
            case 'None', U_true = [];
            case 'S',    U_true = scaled_S;
            case 'I',    U_true = scaled_I;
            case 'Both', U_true = [scaled_S, scaled_I];
        end

        T_end = length(loaded.Rt_true);
        max_T = T_end - horizon;
        windows = cfg.forecast.min_window : cfg.forecast.step_size : max_T;

        precompute_data = struct( ...
            'Rt_true', loaded.Rt_true(:), ...
            'tspan', loaded.tspan(:), ...
            'S_true', loaded.S_true(:), ...
            'I_true', loaded.I_true(:), ...
            'U_true', U_true);

        window_data = repmat(struct( ...
            'Rt_past', [], ...
            'truth_Rt', [], ...
            'U_past', [], ...
            'sirs_state', []), numel(windows), 1);

        for w = 1:numel(windows)
            T = windows(w);
            idx_T = find(precompute_data.tspan == T, 1);
            if isempty(idx_T)
                continue;
            end

            idx_end = idx_T + horizon;
            window_data(w).Rt_past = precompute_data.Rt_true(1:idx_T);
            window_data(w).truth_Rt = precompute_data.Rt_true(idx_T+1:idx_end);
            [window_data(w).U_past, window_data(w).sirs_state] = ...
                local_prepare_exogenous_inputs(precompute_data, idx_T, sirs_cfg);
        end

        scenario_data(i).scenario_id = scenario_id;
        scenario_data(i).num_exo = size(U_true, 2);
        scenario_data(i).windows = windows;
        scenario_data(i).window_data = window_data;

        fprintf('Progress: prepared scenario %d/%d (%s)\n', ...
            i, length(fileList), char(scenario_id));
    end
end

function local_validate_truth_artifact(loaded, artifact_path)
%LOCAL_VALIDATE_TRUTH_ARTIFACT Verify required truth fields are present.
    required_fields = {'Rt_true', 'S_true', 'I_true', 'tspan'};
    if ~all(isfield(loaded, required_fields))
        error('SELECT:InvalidTruthArtifact', ...
            'Synthetic truth artifact is missing required fields: %s.', artifact_path);
    end
end

function [U_past, sirs_state] = local_prepare_exogenous_inputs(data, idx_T, sirs_cfg)
%LOCAL_PREPARE_EXOGENOUS_INPUTS Build historical covariates and current state.
    if isempty(data.U_true)
        U_past = [];
        sirs_state = [];
        return;
    end

    U_past = data.U_true(1:idx_T, :);

    current_I = data.I_true(idx_T);
    current_S = data.S_true(idx_T);
    current_R = sirs_cfg.pop_size - current_S - current_I;
    sirs_state = [current_S, current_I, current_R];
end

function local_shutdown_parallel_pool()
%LOCAL_SHUTDOWN_PARALLEL_POOL Close the local parallel pool before MATLAB exits.
    pool = gcp('nocreate');
    if ~isempty(pool)
        delete(pool);
    end
end
