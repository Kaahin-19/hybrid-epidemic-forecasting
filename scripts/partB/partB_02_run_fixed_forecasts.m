%PARTB_02_RUN_FIXED_FORECASTS Run fixed Part A AR/ARX forecasts on SEIR truth.
%
%   Description:
%       Loads the selected practical Part A AR/ARX configurations, verifies
%       that they match the frozen Part B robustness design, and executes
%       expanding-window Rt forecasts against SEIR truth. Historical
%       exogenous covariates come from the SEIR S and I trajectories; future
%       covariates are projected by the simpler SIRS model inside fit_arimax.
%
%   Workflow:
%       1. Initialization and fixed configuration validation
%       2. Forecast loop over SEIR truth files and fixed AR/ARX models
%       3. Artifact and figure persistence
%
%   See also PARTB_CONFIG, FIT_ARIMA, FIT_ARIMAX.

% A. M. Kaahin 2026-05-18

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Fixed Forecast Execution ===\n');

cfg = partB_config();
dataDir = cfg.output.data_dir;
saveDir = cfg.output.forecast_dir;
figDir  = cfg.output.fig_dir;
wis_alphas = cfg.forecast.wis_alphas;

if ~exist(saveDir, 'dir'), mkdir(saveDir); end
if ~exist(figDir, 'dir'),  mkdir(figDir); end

fileList = dir(fullfile(dataDir, 'partB_01_truth_seir_*.mat'));
if isempty(fileList)
    error('FORECAST:NoData', ...
        'No SEIR truth files found. Run partB_01_generate_truth.m first.');
end

fixed_configs = local_load_fixed_partA_configs(cfg);

%% 2. Forecast Loop
for i = 1:length(fileList)
    filename = fileList(i).name;
    fullPath = fullfile(dataDir, filename);
    [~, name_core] = fileparts(filename);

    scenario_id = strrep(name_core, 'partB_01_truth_seir_', '');
    fprintf('  - Processing Scenario: %s...\n', scenario_id);

    loaded  = load(fullPath);
    Rt_true = loaded.Rt_true;
    tspan   = loaded.tspan;

    for c = 1:numel(fixed_configs)
        model_cfg = fixed_configs(c);
        fprintf('    * Fixed model %s | %s\n', model_cfg.model_type, model_cfg.exo_mode);

        results = local_run_scenario_forecasts(loaded, Rt_true, tspan, ...
            cfg, model_cfg, wis_alphas);

        summary_table = local_summary_table(model_cfg, numel(results));
        file_prefix = sprintf('partB_02_forecast_%s_%s_%s', ...
            scenario_id, model_cfg.model_type, model_cfg.exo_mode);

        csvName = fullfile(saveDir, [file_prefix, '_summary.csv']);
        writetable(summary_table, csvName);
        fprintf('Forecast summary saved to: %s\n', csvName);

        outName = fullfile(saveDir, [file_prefix, '.mat']);
        model_type = model_cfg.model_type;
        exo_mode = model_cfg.exo_mode;
        selected_model = model_cfg.selected_model;
        save(outName, 'results', 'cfg', 'model_type', 'exo_mode', 'selected_model');
        fprintf('Forecast artifact saved to: %s\n', outName);

        plot_name = sprintf('%s_%s_%s', scenario_id, ...
            model_cfg.model_type, model_cfg.exo_mode);
        plotPath = plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg);
        partBPlotPath = fullfile(figDir, ...
            sprintf('partB_02_forecast_plot_%s.png', plot_name));
        if exist(plotPath, 'file')
            movefile(plotPath, partBPlotPath, 'f');
            plotPath = partBPlotPath;
        end
        fprintf('Forecast visualization saved to: %s\n', plotPath);
    end
end

fprintf('=== Part B Fixed Forecast Execution Complete ===\n\n');

%% 3. Local Functions
function fixed_configs = local_load_fixed_partA_configs(cfg)
%LOCAL_LOAD_FIXED_PARTA_CONFIGS Load and validate frozen Part A selections.
    fixed_configs = repmat(struct( ...
        'model_type', '', ...
        'exo_mode', '', ...
        'selected_model', [], ...
        'headers', {{}}), 1, 4);

    fixed_configs(1) = local_load_one_config(cfg, 'AR',  'None', 2, ...
        {'p'});
    fixed_configs(2) = local_load_one_config(cfg, 'ARX', 'S',    [7, 3, 3], ...
        {'na', 'nb', 'nk'});
    fixed_configs(3) = local_load_one_config(cfg, 'ARX', 'I',    [7, 2, 1], ...
        {'na', 'nb', 'nk'});
    fixed_configs(4) = local_load_one_config(cfg, 'ARX', 'Both', [7, 1, 3], ...
        {'na', 'nb', 'nk'});
end

function model_cfg = local_load_one_config(cfg, model_type, exo_mode, ...
    expected_model, headers)
%LOCAL_LOAD_ONE_CONFIG Load one Part A tuning artifact and verify its order.
    tuning_path = fullfile(cfg.output.partA_tuning_dir, ...
        sprintf('partA_02_global_hyperparameters_%s_%s.mat', model_type, exo_mode));

    if ~exist(tuning_path, 'file')
        error('FORECAST:MissingPartATuningArtifact', ...
            'Missing Part A tuning artifact: %s.', tuning_path);
    end

    tuning = load(tuning_path);
    required_fields = {'model_type', 'exo_mode', 'selected_model'};
    if ~all(isfield(tuning, required_fields))
        error('FORECAST:InvalidPartATuningArtifact', ...
            'Part A tuning artifact is missing required fields: %s.', tuning_path);
    end

    selected_model = reshape(double(tuning.selected_model), 1, []);
    expected_model = reshape(double(expected_model), 1, []);

    if ~strcmp(string(tuning.model_type), string(model_type)) || ...
            ~strcmp(string(tuning.exo_mode), string(exo_mode))
        error('FORECAST:PartATuningIdentityMismatch', ...
            'Part A tuning artifact identity mismatch: %s.', tuning_path);
    end

    if ~isequal(selected_model, expected_model)
        error('FORECAST:UnexpectedPartASelection', ...
            ['Part A selected_model mismatch for %s/%s. Expected %s, ' ...
            'found %s. Part B is fixed by design.'], ...
            model_type, exo_mode, mat2str(expected_model), mat2str(selected_model));
    end

    model_cfg = struct( ...
        'model_type', model_type, ...
        'exo_mode', exo_mode, ...
        'selected_model', selected_model, ...
        'headers', {headers});
end

function results = local_run_scenario_forecasts(loaded, Rt_true, tspan, ...
    cfg, model_cfg, wis_alphas)
%LOCAL_RUN_SCENARIO_FORECASTS Run all expanding windows for one configuration.
    T_end   = length(Rt_true);
    max_T   = T_end - cfg.forecast.horizon;
    windows = cfg.forecast.min_window : cfg.forecast.step_size : max_T;
    num_windows = numel(windows);

    results = repmat(struct( ...
        'window_day', [], ...
        'window_day_idx', [], ...
        'forecast_median', [], ...
        'forecast_interval_alphas', [], ...
        'forecast_lower', [], ...
        'forecast_upper', [], ...
        'best_model', [], ...
        'aic_landscape', [], ...
        'truth_Rt_window', [], ...
        'truth_S_window', [], ...
        'truth_E_window', [], ...
        'truth_I_window', [], ...
        'truth_R_window', [], ...
        'time_horizon', []), num_windows, 1);
    count = 1;

    for T = windows
        idx_T = find(tspan == T, 1);
        if isempty(idx_T), continue; end

        horizon = cfg.forecast.horizon;
        idx_end = idx_T + horizon;

        Rt_past = Rt_true(1:idx_T);
        [U_past, sirs_state, num_exo] = local_prepare_exogenous_inputs( ...
            loaded, idx_T, cfg, model_cfg.exo_mode);

        [best_Rt_pred, aicc, best_wis_alpha, best_Rt_lower, best_Rt_upper] = ...
            local_fit_fixed_model(model_cfg, Rt_past, U_past, sirs_state, ...
            cfg, num_exo, horizon, wis_alphas);

        results(count).window_day      = T;
        results(count).window_day_idx  = idx_T;
        results(count).forecast_median = best_Rt_pred;
        results(count).forecast_interval_alphas = best_wis_alpha;
        results(count).forecast_lower  = best_Rt_lower;
        results(count).forecast_upper  = best_Rt_upper;
        results(count).best_model      = model_cfg.selected_model;
        results(count).aic_landscape   = [model_cfg.selected_model, aicc];
        results(count).truth_Rt_window = Rt_true(idx_T+1 : idx_end);
        results(count).truth_S_window  = loaded.S_true(idx_T+1 : idx_end);
        results(count).truth_E_window  = loaded.E_true(idx_T+1 : idx_end);
        results(count).truth_I_window  = loaded.I_true(idx_T+1 : idx_end);
        results(count).truth_R_window  = loaded.R_true(idx_T+1 : idx_end);
        results(count).time_horizon    = tspan(idx_T+1 : idx_end);

        count = count + 1;
    end

    results = results(1:count-1);
end

function [U_past, sirs_state, num_exo] = local_prepare_exogenous_inputs( ...
    data, idx_T, cfg, exo_mode)
%LOCAL_PREPARE_EXOGENOUS_INPUTS Build SEIR-history covariates and SIRS state.
    scaled_S = data.S_true(:) / cfg.seir.pop_size;
    scaled_I = data.I_true(:) / cfg.seir.pop_size;

    switch char(string(exo_mode))
        case 'None'
            U_true = [];
        case 'S'
            U_true = scaled_S;
        case 'I'
            U_true = scaled_I;
        case 'Both'
            U_true = [scaled_S, scaled_I];
        otherwise
            error('CFG:InvalidExoMode', 'Unsupported exogenous mode: %s.', exo_mode);
    end

    num_exo = size(U_true, 2);

    if isempty(U_true)
        U_past = [];
        sirs_state = [];
        return;
    end

    U_past = U_true(1:idx_T, :);

    current_S = data.S_true(idx_T);
    current_I = data.I_true(idx_T);
    current_R = cfg.sirs_projection.pop_size - current_S - current_I;

    if current_R < 0
        error('FORECAST:InvalidSirsProjectionState', ...
            'SIRS projection state has negative R remainder.');
    end

    sirs_state = [current_S, current_I, current_R];
end

function [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
    local_fit_fixed_model(model_cfg, Rt_past, U_past, sirs_state, cfg, ...
    num_exo, horizon, wis_alphas)
%LOCAL_FIT_FIXED_MODEL Dispatch AR/ARX fixed-order model fits.
    switch model_cfg.model_type
        case 'AR'
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                fit_arima(Rt_past, model_cfg.selected_model(1), 0, 0, ...
                horizon, wis_alphas);

        case 'ARX'
            nb_vec = repmat(model_cfg.selected_model(2), 1, num_exo);
            nk_vec = repmat(model_cfg.selected_model(3), 1, num_exo);
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                fit_arimax(Rt_past, U_past, [], model_cfg.selected_model(1), ...
                0, 0, nb_vec, nk_vec, horizon, wis_alphas, ...
                sirs_state, cfg.sirs_projection, model_cfg.exo_mode, cfg.sim.seed);

        otherwise
            error('CFG:UnknownModel', ...
                'Part B fixed forecasts support only AR and ARX.');
    end
end

function summary_table = local_summary_table(model_cfg, num_windows)
%LOCAL_SUMMARY_TABLE Build one-row fixed configuration summary.
    values = [model_cfg.selected_model, num_windows];
    summary_table = array2table(values, ...
        'VariableNames', [model_cfg.headers, {'Times_Selected'}]);
end
