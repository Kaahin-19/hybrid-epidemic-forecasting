%PARTA_03_RUN_FORECASTS Run final Part A forecasts.
%
%   Description:
%       Generates final expanding-window Rt forecasts for each synthetic
%       scenario using the selected model configuration. Exports one forecast
%       artifact per scenario containing the forecast median, prediction
%       intervals, forecast horizon times, and matching truth windows.
%
%   Workflow:
%       1. Load the selected model configuration.
%       2. Build forecast windows for each synthetic scenario.
%       3. Run final forecasts with the selected configuration.
%       4. Save one forecast artifact per scenario.
%
%   See also PARTA_CONFIG, PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS, ...
%            FORECAST_OPEN, FORECAST_CLOSED, INTERVAL_BOUNDS.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-06-28

%% 1. Initialization
clear; close all; clc;

fprintf('=== Final Part A Forecast Generation ===\n');

cfg        = partA_config();
model_type = cfg.run.model_type;
exo_mode   = cfg.run.exo_mode;

fprintf('Configuration: Model = %s | Exogenous Mode = %s\n', model_type, exo_mode);

forecast_dir = cfg.output.forecast_dir;
if ~exist(forecast_dir, 'dir')
    mkdir(forecast_dir);
end

%% 2. Load Selected Configuration
selection = local_load_selection(cfg, model_type, exo_mode);

selected_configuration = selection.selected_configuration;
forecast_snapshot      = cfg.snapshot.forecast;

fprintf('Using selected configuration: %s\n', mat2str(selected_configuration));

%% 3. Scenario Preparation
data_dir  = cfg.output.data_dir;
file_list = dir(fullfile(data_dir, 'partA_01_truth_*.mat'));
[~, order] = sort({file_list.name});
file_list = file_list(order);

if isempty(file_list)
    error('PARTA_03:NoData', ...
        'No synthetic truth files found in %s. Run partA_01 first.', data_dir);
end

horizon    = cfg.forecast.horizon;
pop_size   = cfg.sirs.pop_size;
base_seed  = cfg.run.seed;
num_draws  = cfg.intervals.num_draws;
wis_alphas = cfg.forecast.wis_alphas;
vary       = cfg.intervals.include_epidemic_seed_variation;

if exo_mode == "None"
    base_stepper = [];
else
    base_stepper = sirs_init(cfg.sirs, ...
        struct('solver', 'uds', 'compile', false, 'seed', base_seed));
end

%% 4. Scenario Forecast Loop
for i = 1:numel(file_list)
    loaded = load(fullfile(data_dir, file_list(i).name));

    scenario_id = string(loaded.scenario_id);
    Rt_true     = loaded.Rt_true;
    S_true      = loaded.S_true;
    I_true      = loaded.I_true;
    tspan       = loaded.tspan;

    fprintf('Processing scenario %d/%d (%s)\n', i, numel(file_list), scenario_id);

    switch exo_mode
        case "None"
            U_true = [];
        case "S"
            U_true = S_true / pop_size;
        case "I"
            U_true = I_true / pop_size;
        case "Both"
            U_true = [S_true / pop_size, I_true / pop_size];
        otherwise
            error('PARTA_03:UnknownExoMode', 'Unsupported exo_mode: %s', exo_mode);
    end

    win_endpoints = cfg.forecast.min_window : cfg.forecast.step_size : (numel(Rt_true) - horizon);

    [~, window_data] = local_build_windows(Rt_true, U_true, S_true, I_true, ...
        tspan, win_endpoints, horizon, pop_size, ~isempty(U_true));

    if isempty(window_data)
        error('PARTA_03:NoForecastWindows', ...
            ['Scenario %s has no forecast windows; check min_window, ' ...
            'step_size, horizon, and truth length.'], scenario_id);
    end

    results = local_run_scenario_forecasts( ...
        model_type, exo_mode, selected_configuration, window_data, ...
        base_stepper, base_seed, num_draws, horizon, wis_alphas, vary, i);

    artifact = struct( ...
        'scenario_id', scenario_id, ...
        'model_type', model_type, ...
        'exo_mode', exo_mode, ...
        'selected_configuration', selected_configuration, ...
        'snapshot', forecast_snapshot, ...
        'wis_alphas', wis_alphas, ...
        'tspan', tspan, ...
        'Rt_true', Rt_true, ...
        'results', results);

    file_prefix = sprintf('partA_03_forecast_%s_%s_%s', ...
        scenario_id, model_type, exo_mode);
    artifact_path = fullfile(forecast_dir, [file_prefix, '.mat']);

    save(artifact_path, '-struct', 'artifact');
    fprintf('Forecast artifact saved to: %s\n', artifact_path);
end

fprintf('=== Final Part A Forecast Generation Complete ===\n\n');

%% 5. Local Functions

function selection = local_load_selection(cfg, model_type, exo_mode)
%LOCAL_LOAD_SELECTION Load the Script 2 selected configuration artifact.
file_prefix = sprintf('partA_02_global_hyperparameters_%s_%s', model_type, exo_mode);
artifact_path = fullfile(cfg.output.model_selection_dir, [file_prefix, '.mat']);

if ~exist(artifact_path, 'file')
    error('PARTA_03:MissingSelectionArtifact', ...
        'Missing model-selection artifact: %s. Run partA_02 first.', artifact_path);
end

selection = load(artifact_path);

if ~isequaln(selection.snapshot, cfg.snapshot.selection)
    error('PARTA_03:SelectionConfigMismatch', ...
        'Script 2 model-selection artifact does not match the current Part A selection protocol.');
end
end

function [windows, window_data] = local_build_windows(Rt, U_true, S_true, I_true, ...
    tspan, win_endpoints, horizon, pop_size, has_exo)
%LOCAL_BUILD_WINDOWS Build expanding-window forecast entries for one scenario.
template = struct('window_day', [], 'window_day_idx', [], 'time_horizon', [], ...
    'Rt_past', [], 'U_past', [], 'sirs_state', [], 'truth_Rt', []);
built = repmat(template, numel(win_endpoints), 1);
keep  = false(numel(win_endpoints), 1);

for k = 1:numel(win_endpoints)
    idx_T = find(tspan == win_endpoints(k), 1);
    if isempty(idx_T) || idx_T + horizon > numel(Rt)
        continue;
    end

    built(k).window_day     = win_endpoints(k);
    built(k).window_day_idx = idx_T;
    built(k).time_horizon   = tspan(idx_T + 1 : idx_T + horizon);
    built(k).Rt_past        = Rt(1:idx_T);

    if has_exo
        R_at_T = pop_size - S_true(idx_T) - I_true(idx_T);
        built(k).U_past     = U_true(1:idx_T, :);
        built(k).sirs_state = [S_true(idx_T), I_true(idx_T), R_at_T];
    end

    built(k).truth_Rt = Rt(idx_T + 1 : idx_T + horizon);
    keep(k) = true;
end

windows     = win_endpoints(keep);
window_data = built(keep);
end

function results = local_run_scenario_forecasts( ...
    model_type, exo_mode, params, window_data, ...
    base_stepper, base_seed, num_draws, horizon, wis_alphas, vary, scenario_index)
%LOCAL_RUN_SCENARIO_FORECASTS Run selected-model forecasts for one scenario.
template = struct( ...
    'window_day', [], ...
    'window_day_idx', [], ...
    'time_horizon', [], ...
    'truth_Rt_window', [], ...
    'forecast_median', [], ...
    'forecast_lower', [], ...
    'forecast_upper', []);
results = repmat(template, numel(window_data), 1);

for w = 1:numel(window_data)
    win = window_data(w);

    window_seed = base_seed + 10000 * scenario_index + w;
    r_seed      = window_seed;

    if isempty(win.U_past)
        [~, ensemble_paths] = forecast_open(model_type, params, ...
            win.Rt_past, num_draws, horizon, r_seed);
    else
        e_seed = window_seed + 1000000;
        [~, ensemble_paths] = forecast_closed(model_type, params, ...
            win.Rt_past, win.U_past, win.sirs_state, size(win.U_past, 2), ...
            num_draws, horizon, exo_mode, base_stepper, r_seed, e_seed, vary);
    end

    [lower, upper, Rt_pred] = interval_bounds(ensemble_paths, wis_alphas);

    valid = numel(Rt_pred) == horizon && all(isfinite(Rt_pred)) ...
        && all(Rt_pred > 0) && all(isfinite(lower(:))) ...
        && all(isfinite(upper(:))) && all(lower(:) <= upper(:));

    if ~valid
        error('PARTA_03:UnscoreableWindow', ...
            'Forecast window produced invalid intervals.');
    end

    results(w).window_day      = win.window_day;
    results(w).window_day_idx  = win.window_day_idx;
    results(w).time_horizon    = win.time_horizon;
    results(w).truth_Rt_window = win.truth_Rt;
    results(w).forecast_median = Rt_pred;
    results(w).forecast_lower  = lower;
    results(w).forecast_upper  = upper;
end
end