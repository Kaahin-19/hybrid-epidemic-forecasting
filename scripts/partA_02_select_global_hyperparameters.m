%PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS Select a global hyperparameter configuration.
%
%   Description:
%       Evaluates candidate hyperparameter configurations for the active
%       model family and exogenous-input setting using the synthetic
%       ground truth data. Each candidate is scored across all scenarios
%       and expanding forecast windows using the Weighted Interval Score
%       (WIS), and the configuration with the lowest aggregated score is
%       saved for use by the forecast execution stage.
%
%   Workflow:
%       1. Load the active run configuration and synthetic truth datasets.
%       2. Construct the candidate hyperparameter grid.
%       3. Score every candidate across all scenarios and forecast windows.
%       4. Select the candidate with the minimum global mean WIS.
%       5. Persist machine-readable tuning artifacts for downstream use.
%
%   See also PARTA_CONFIG, GENDATA_SIRS, PARTA_01_GENERATE_TRUTH.

% A. M. Kaahin 2026-03-28
% Modified: 2026-03-29

%% 1. Initialization
clear; close all; clc;

fprintf('=== Global Hyperparameter Selection ===\n');

cfg = partA_config();
MODEL_TYPE = char(cfg.run.model_type);
EXO_MODE   = char(cfg.run.exo_mode);

EXO_MODE = validate_configuration(MODEL_TYPE, EXO_MODE);
fprintf('Configuration: Model = %s | Exogenous Mode = %s\n', MODEL_TYPE, EXO_MODE);

%% 2. Configuration and Grid Setup
dataDir   = cfg.output.data_dir;
tuningDir = cfg.output.tuning_dir;
fileList  = dir(fullfile(dataDir, '*.mat'));

if isempty(fileList)
    error('TUNE:NoData', 'No synthetic truth files found. Run partA_01_generate_truth.m first.');
end

if ~exist(tuningDir, 'dir')
    mkdir(tuningDir);
end

[candidate_models, parameter_names] = get_candidate_models(cfg, MODEL_TYPE);
num_models = size(candidate_models, 1);
horizon    = cfg.forecast.horizon;
wis_alphas = cfg.forecast.wis_alphas;
sirs_cfg   = cfg.sirs;
sim_seed   = cfg.sim.seed;

fprintf('Stage: Preparing scenario-window inputs for %d scenarios\n', length(fileList));

pool_cleanup = onCleanup(@local_shutdown_parallel_pool);

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

    scenario_id = string(strrep(name_core, 'partA_01_truth_', ''));
    scaled_S = loaded.S_true(:) / cfg.sirs.pop_size;
    scaled_I = loaded.I_true(:) / cfg.sirs.pop_size;

    switch EXO_MODE
        case 'None', U_true = [];
        case 'S',    U_true = scaled_S;
        case 'I',    U_true = scaled_I;
        case 'Both', U_true = [scaled_S, scaled_I];
    end

    T_end   = length(loaded.Rt_true);
    max_T   = T_end - horizon;
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
        'U_future', []), numel(windows), 1);

    for w = 1:numel(windows)
        T = windows(w);
        idx_T = find(precompute_data.tspan == T, 1);
        if isempty(idx_T)
            continue;
        end

        idx_end = idx_T + horizon;
        window_data(w).Rt_past = precompute_data.Rt_true(1:idx_T);
        window_data(w).truth_Rt = precompute_data.Rt_true(idx_T+1:idx_end);
        [window_data(w).U_past, window_data(w).U_future] = ...
            prepare_exogenous_inputs(precompute_data, idx_T, horizon, ...
            EXO_MODE, sirs_cfg, sim_seed);
    end

    scenario_data(i).scenario_id = scenario_id;
    scenario_data(i).num_exo = size(U_true, 2);
    scenario_data(i).windows = windows;
    scenario_data(i).window_data = window_data;

    fprintf('Progress: prepared scenario %d/%d (%s)\n', ...
        i, length(fileList), char(scenario_id));
end

scenario_ids  = reshape(string({scenario_data.scenario_id}), 1, []);
window_counts = zeros(1, length(scenario_data));
for i = 1:length(scenario_data)
    window_counts(i) = numel(scenario_data(i).windows);
end

if isempty(gcp('nocreate'))
    parpool;
end

%% 3. Candidate Evaluation
fprintf('Stage: Evaluating %d candidate configurations across %d scenarios\n', ...
    num_models, length(scenario_data));

report_interval = max(1, ceil(num_models / 20));
progress_queue = parallel.pool.DataQueue;
local_report_candidate_progress([], num_models, report_interval, true);
afterEach(progress_queue, @(~) local_report_candidate_progress([], num_models, report_interval));

scenario_mean_wis = inf(num_models, length(scenario_data));
global_mean_wis   = inf(num_models, 1);

parfor idx = 1:num_models
    params = candidate_models(idx, :);
    scenario_scores = inf(1, length(scenario_data));

    for s = 1:length(scenario_data)
        data = scenario_data(s);
        window_wis = inf(numel(data.window_data), 1);

        for w = 1:numel(data.window_data)
            window_entry = data.window_data(w);
            if isempty(window_entry.Rt_past) || isempty(window_entry.truth_Rt)
                continue;
            end

            [Rt_pred, ~, out_alphas, Rt_lower, Rt_upper] = fit_candidate( ...
                MODEL_TYPE, params, window_entry.Rt_past, window_entry.U_past, ...
                window_entry.U_future, data.num_exo, ...
                horizon, wis_alphas);

            if ~is_valid_forecast(Rt_pred, out_alphas, Rt_lower, Rt_upper, ...
                    window_entry.truth_Rt)
                window_wis(w) = inf;
                continue;
            end

            pointwise_wis = compute_wis(window_entry.truth_Rt, Rt_pred, ...
                Rt_lower, Rt_upper, out_alphas);
            if any(~isfinite(pointwise_wis))
                window_wis(w) = inf;
            else
                window_wis(w) = mean(pointwise_wis);
            end
        end

        scenario_scores(s) = mean(window_wis);
    end

    scenario_mean_wis(idx, :) = scenario_scores;
    global_mean_wis(idx) = mean(scenario_scores);
    send(progress_queue, idx);
end

fprintf('Stage: Candidate evaluation complete\n');

[best_global_wis, best_idx] = min(global_mean_wis);
if ~isfinite(best_global_wis)
    error('TUNE:NoValidCandidate', ...
        'All candidate hyperparameter configurations produced invalid global WIS scores.');
end

selected_model = candidate_models(best_idx, :);

%% 4. Artifact Generation
[~, sort_idx] = sort(global_mean_wis, 'ascend');
sorted_candidates = candidate_models(sort_idx, :);
sorted_scenario_means = scenario_mean_wis(sort_idx, :);
sorted_global_means = global_mean_wis(sort_idx);
rankings = (1:num_models)';

scenario_columns = cellstr(compose('MeanWIS_%s', scenario_ids));
summary_headers = [parameter_names, scenario_columns, {'GlobalMeanWIS', 'Rank'}];
summary_matrix = [sorted_candidates, sorted_scenario_means, sorted_global_means, rankings];
summary_table = array2table(summary_matrix, 'VariableNames', summary_headers);

file_prefix = sprintf('partA_02_global_hyperparameters_%s_%s', MODEL_TYPE, EXO_MODE);
summary_path = fullfile(tuningDir, [file_prefix, '_summary.csv']);
writetable(summary_table, summary_path);

model_type = MODEL_TYPE;
exo_mode = EXO_MODE;
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

artifact_path = fullfile(tuningDir, [file_prefix, '.mat']);
save(artifact_path, ...
    'model_type', 'exo_mode', 'selected_model', 'candidate_models', ...
    'scenario_ids', 'scenario_mean_wis', 'global_mean_wis', ...
    'window_counts', 'aggregation_mode', 'failure_policy', ...
    'wis_alphas', 'cfg_snapshot');

fprintf('Selected global hyperparameters: %s\n', mat2str(selected_model));
fprintf('Global tuning summary saved to: %s\n', summary_path);
fprintf('Global tuning artifact saved to: %s\n', artifact_path);
fprintf('=== Global Hyperparameter Selection Complete ===\n\n');

%% 5. Local Functions
function valid_exo_mode = validate_configuration(model_type, exo_mode)
%VALIDATE_CONFIGURATION Resolve logical conflicts in configuration.
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

function [candidate_models, parameter_names] = get_candidate_models(cfg, model_type)
%GET_CANDIDATE_MODELS Construct the candidate hyperparameter grid.
    switch model_type
        case 'AR'
            candidate_models = (0:cfg.forecast.max_ar_order)';
            parameter_names  = {'p'};

        case 'ARX'
            [P, NB, NK] = ndgrid( ...
                0:cfg.forecast.max_ar_order, ...
                1:cfg.forecast.max_exo_order, ...
                1:cfg.forecast.max_exo_delay);
            candidate_models = [P(:), NB(:), NK(:)];
            parameter_names  = {'na', 'nb', 'nk'};

        case {'N4SID', 'SSEST'}
            [N_order, D_order] = ndgrid( ...
                1:cfg.forecast.max_state_order, ...
                cfg.forecast.state_diff_orders);
            candidate_models = [N_order(:), D_order(:)];
            parameter_names  = {'State_Order_n', 'Differencing_d'};

        otherwise
            error('CFG:UnknownModel', 'Unsupported MODEL_TYPE: %s', model_type);
    end
end

function [U_past, U_future] = prepare_exogenous_inputs(data, idx_T, horizon, exo_mode, sirs_cfg, sim_seed)
%PREPARE_EXOGENOUS_INPUTS Build historical and projected exogenous inputs.
    if isempty(data.U_true)
        U_past = [];
        U_future = [];
        return;
    end

    U_past = data.U_true(1:idx_T, :);

    current_Rt = data.Rt_true(idx_T);
    current_I  = data.I_true(idx_T);
    current_S  = data.S_true(idx_T);
    current_R  = sirs_cfg.pop_size - current_S - current_I;

    future_tspan = 0:horizon;
    flat_beta    = repmat(current_Rt * sirs_cfg.gamma, 1, length(future_tspan));

    uds_params = sirs_cfg;
    uds_params.beta    = flat_beta;
    uds_params.I0      = current_I;
    uds_params.R0_init = current_R;
    uds_params.solver  = 'uds';
    uds_params.compile = 0;

    uds_mod = genData_SIRS(future_tspan, uds_params, sim_seed);

    S_future_raw = uds_mod.U(1, 2:end)';
    I_future_raw = uds_mod.U(2, 2:end)';

    scaled_S_fut = S_future_raw / sirs_cfg.pop_size;
    scaled_I_fut = I_future_raw / sirs_cfg.pop_size;

    switch exo_mode
        case 'S',    U_future = scaled_S_fut;
        case 'I',    U_future = scaled_I_fut;
        case 'Both', U_future = [scaled_S_fut, scaled_I_fut];
        otherwise,   U_future = [];
    end
end

function [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = fit_candidate( ...
    model_type, params, Rt_past, U_past, U_future, num_exo, horizon, wis_alphas)
%FIT_CANDIDATE Fit and forecast one candidate hyperparameter configuration.
    Rt_pred = [];
    aicc = [];
    out_alphas = [];
    Rt_lower = [];
    Rt_upper = [];

    switch model_type
        case 'AR'
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                fit_arima(Rt_past, params(1), 0, 0, horizon, wis_alphas);

        case 'ARX'
            nb_vec = repmat(params(2), 1, num_exo);
            nk_vec = repmat(params(3), 1, num_exo);
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                fit_arimax(Rt_past, U_past, U_future, params(1), 0, 0, ...
                nb_vec, nk_vec, horizon, wis_alphas);

        case 'N4SID'
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                fit_n4sid(Rt_past, U_past, U_future, params(1), params(2), ...
                horizon, wis_alphas);

        case 'SSEST'
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                fit_ssest(Rt_past, U_past, U_future, params(1), params(2), ...
                horizon, wis_alphas);
    end
end

function is_valid = is_valid_forecast(Rt_pred, out_alphas, Rt_lower, Rt_upper, truth_Rt)
%IS_VALID_FORECAST Verify forecast output dimensions and finiteness.
    out_alphas = reshape(double(out_alphas), 1, []);
    Rt_pred = double(Rt_pred(:));
    Rt_lower = double(Rt_lower);
    Rt_upper = double(Rt_upper);
    truth_Rt = double(truth_Rt(:));

    is_valid = ...
        ~isempty(out_alphas) && ...
        numel(Rt_pred) == numel(truth_Rt) && ...
        size(Rt_lower, 1) == numel(truth_Rt) && ...
        size(Rt_upper, 1) == numel(truth_Rt) && ...
        size(Rt_lower, 2) == numel(out_alphas) && ...
        size(Rt_upper, 2) == numel(out_alphas) && ...
        all(isfinite(Rt_pred)) && ...
        all(isfinite(Rt_lower(:))) && ...
        all(isfinite(Rt_upper(:))) && ...
        all(Rt_lower(:) <= Rt_upper(:));
end

function wis = compute_wis(truth_Rt, median_Rt, lower_Rt, upper_Rt, alphas)
%COMPUTE_WIS Compute pointwise weighted interval score values.
    truth_Rt = double(truth_Rt(:));
    median_Rt = double(median_Rt(:));
    lower_Rt = double(lower_Rt);
    upper_Rt = double(upper_Rt);
    alphas = reshape(double(alphas), 1, []);

    num_intervals = numel(alphas);
    wis = 0.5 * abs(truth_Rt - median_Rt);

    for j = 1:num_intervals
        alpha = alphas(j);
        interval_score = (upper_Rt(:, j) - lower_Rt(:, j)) ...
            + (2 / alpha) * max(lower_Rt(:, j) - truth_Rt, 0) ...
            + (2 / alpha) * max(truth_Rt - upper_Rt(:, j), 0);
        wis = wis + (alpha / 2) * interval_score;
    end

    wis = wis / (num_intervals + 0.5);
end

function local_report_candidate_progress(~, total_models, report_interval, reset_flag)
%LOCAL_REPORT_CANDIDATE_PROGRESS Emit coarse candidate-evaluation progress updates.
    persistent completed_count progress_tic

    if nargin >= 4 && reset_flag
        completed_count = 0;
        progress_tic = tic;
        fprintf('Progress: candidates 0/%d completed (0.0%%)\n', total_models);
        return;
    end

    if isempty(completed_count)
        completed_count = 0;
        progress_tic = tic;
    end

    completed_count = completed_count + 1;

    if completed_count == 1 || ...
            mod(completed_count, report_interval) == 0 || ...
            completed_count == total_models
        elapsed = toc(progress_tic);
        fprintf('Progress: candidates %d/%d completed (%.1f%%, %.1fs elapsed)\n', ...
            completed_count, total_models, ...
            100 * completed_count / total_models, elapsed);
    end
end

function local_shutdown_parallel_pool()
%LOCAL_SHUTDOWN_PARALLEL_POOL Close the local parallel pool before MATLAB exits.
    pool = gcp('nocreate');
    if ~isempty(pool)
        delete(pool);
    end
end
