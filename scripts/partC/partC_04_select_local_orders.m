%PARTC_04_SELECT_LOCAL_ORDERS Select Part C local retuned orders.
%
%   Description:
%       Performs the canonical Part C local-order selection stage. The Part
%       A-selected AR/None and ARX/I orders are used as grid centers. Nearby
%       orders are scored only on initial calibration windows, and the
%       selected local orders are saved for the Part C strategy forecast
%       stage.
%
%   Workflow:
%       1. Load processed real-data artifact and Part A-selected orders.
%       2. Build local order grids centered on those orders.
%       3. Score candidates on calibration windows with shared forecast and
%          WIS helpers.
%       4. Save canonical local-order selection artifact and tables.
%
%   See also PARTC_CONFIG, BUILD_FORECAST_ENTRIES, ...
%            LOAD_PARTC_FIXED_CONFIGURATIONS, GENERATE_CANDIDATE_GRID, ...
%            PARTC_02_RUN_FORECASTS.
%
% A. M. Kaahin 2026-06-03
% Modified: 2026-06-11

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Local Order Selection ===\n');

cfg = partC_config();
processedPath = fullfile(cfg.output.data_processed_dir, ...
    'partC_01_real_data_processed.mat');
selectionPath = fullfile(cfg.output.evaluation_dir, ...
    'partC_local_order_selection.mat');

if exist(processedPath, 'file') ~= 2
    error('LOCALORDER:MissingProcessedData', ...
        ['Missing processed WHO-derived real-data artifact: %s\n' ...
        'Run scripts/partC/partC_01_prepare_real_data.m first.'], ...
        processedPath);
end

if ~exist(cfg.output.evaluation_dir, 'dir'), mkdir(cfg.output.evaluation_dir); end
if ~exist(cfg.output.table_dir, 'dir'), mkdir(cfg.output.table_dir); end

loaded = load(processedPath);
local_validate_processed_data(loaded, processedPath);
fixed_configs = load_partC_fixed_configurations(cfg);

fprintf('Calibration fraction: %.2f\n', ...
    local_strategy(cfg, "local_order_retuning").calibration_fraction);
fprintf('Maximum calibration windows scored per candidate: %d\n', ...
    cfg.local_order_grid.max_calibration_windows);

%% 2. Selection
selection = select_partC_local_orders(cfg, loaded, fixed_configs);

%% 3. Persistence
selection_artifact = string(selectionPath);
selected_local_configs = selection.selected_local_configs;
local_order_grid_scores = selection.local_order_grid_scores;
selected_local_orders = selection.selected_local_orders;
cfg_snapshot = selection.cfg_snapshot;

save(selectionPath, 'selection', 'selection_artifact', ...
    'selected_local_configs', 'local_order_grid_scores', ...
    'selected_local_orders', 'cfg_snapshot');

gridScoresPath = fullfile(cfg.output.table_dir, ...
    'partC_local_order_grid_scores.csv');
selectedOrdersPath = fullfile(cfg.output.table_dir, ...
    'partC_selected_local_orders.csv');

writetable(local_order_grid_scores, gridScoresPath);
writetable(selected_local_orders, selectedOrdersPath);

fprintf('Local order selection artifact saved to: %s\n', selectionPath);
fprintf('Local order grid scores saved to: %s\n', gridScoresPath);
fprintf('Selected local orders saved to: %s\n', selectedOrdersPath);
fprintf('=== Part C Local Order Selection Complete ===\n\n');

%% 4. Local Functions
function local_validate_processed_data(data, processedPath)
%LOCAL_VALIDATE_PROCESSED_DATA Verify processed Part C artifact fields.
    required_fields = {'date', 't', 'Rt_est', 'I_proxy', 'I_scaled', ...
        'daily_cases', 'renewal_lambda', 'metadata'};
    if ~all(isfield(data, required_fields))
        error('LOCALORDER:InvalidProcessedData', ...
            'Processed artifact is missing required fields: %s.', processedPath);
    end
end

function strategy = local_strategy(cfg, strategy_id)
%LOCAL_STRATEGY Return one Part C strategy definition.
    ids = string({cfg.strategies.strategy_id});
    idx = find(ids == string(strategy_id), 1);
    if isempty(idx)
        error('LOCALORDER:MissingStrategy', ...
            'Missing Part C strategy definition: %s.', strategy_id);
    end
    strategy = cfg.strategies(idx);
end

function selection = select_partC_local_orders(cfg, processed, fixed_configs)
%SELECT_PARTC_LOCAL_ORDERS Score local AR/ARX order grids on calibration windows.
    %% 1. Strategy Setup
    strategy = local_strategy(cfg, "local_order_retuning");
    selected_configs = fixed_configs;
    score_blocks = cell(numel(fixed_configs), 1);
    selected_blocks = cell(numel(fixed_configs), 1);

    %% 2. Local Grid Scoring
    for c = 1:numel(fixed_configs)
        model_cfg = fixed_configs(c);
        scenario_entry = build_forecast_entries(cfg, model_cfg.exo_mode, ...
            struct('mode', "partC", 'data', processed));
        calibration_end_idx = local_calibration_end_index(scenario_entry, ...
            cfg, strategy);
        calibration_entry = local_calibration_entry(scenario_entry, ...
            calibration_end_idx, cfg.local_order_grid.max_calibration_windows);

        candidate_orders = generate_candidate_grid(cfg, model_cfg.model_type, ...
            struct('mode', 'local', ...
            'center_order', model_cfg.selected_configuration));

        fprintf('  - Local order grid %s / %s: %d candidates, %d calibration windows\n', ...
            model_cfg.model_type, model_cfg.exo_mode, ...
            size(candidate_orders, 1), numel(calibration_entry.window_data));

        [score_blocks{c}, selected_order, selected_mean_wis] = ...
            local_score_candidates(cfg, strategy, model_cfg, ...
            calibration_entry, candidate_orders);

        selected_blocks{c} = score_blocks{c}(score_blocks{c}.Selected, :);
        selected_configs(c).partA_selected_configuration = ...
            model_cfg.selected_configuration;
        selected_configs(c).selected_order_for_strategy = selected_order;
        selected_configs(c).local_order_selection_metadata = struct( ...
            'strategy_id', string(strategy.strategy_id), ...
            'strategy_name', string(strategy.strategy_name), ...
            'partA_selected_order', model_cfg.selected_configuration, ...
            'selected_order', selected_order, ...
            'mean_calibration_wis', selected_mean_wis, ...
            'calibration_fraction', double(strategy.calibration_fraction), ...
            'calibration_end_idx', calibration_end_idx, ...
            'calibration_window_days', [calibration_entry.window_data.window_day], ...
            'calibration_windows', numel(calibration_entry.window_data), ...
            'candidate_count', size(candidate_orders, 1));
    end

    %% 3. Output Assembly
    selection = struct();
    selection.strategy_id = string(strategy.strategy_id);
    selection.strategy_name = string(strategy.strategy_name);
    selection.order_treatment = string(strategy.order_treatment);
    selection.parameter_treatment = string(strategy.parameter_treatment);
    selection.local_order_grid_scores = vertcat(score_blocks{:});
    selection.selected_local_orders = vertcat(selected_blocks{:});
    selection.selected_local_configs = selected_configs;
    selection.cfg_snapshot = local_cfg_snapshot(cfg, strategy);
end

function [candidate_scores, selected_order, selected_mean_wis] = ...
    local_score_candidates(cfg, strategy, model_cfg, calibration_entry, ...
    candidate_orders)
%LOCAL_SCORE_CANDIDATES Evaluate each local order candidate.
    num_candidates = size(candidate_orders, 1);
    rows = cell(num_candidates, 1);
    mean_wis = inf(num_candidates, 1);
    calibration_windows = zeros(num_candidates, 1);
    forecast_options = local_forecast_options(cfg, model_cfg.exo_mode, ...
        calibration_entry);

    for i = 1:num_candidates
        candidate_order = candidate_orders(i, :);
        forecast_results = local_analytic_calibration_forecast(calibration_entry, ...
            model_cfg.model_type, candidate_order, forecast_options);
        [mean_wis(i), calibration_windows(i)] = ...
            local_mean_calibration_wis(forecast_results);

        rows{i} = table(string(strategy.strategy_id), ...
            string(strategy.strategy_name), string(model_cfg.model_type), ...
            string(model_cfg.exo_mode), ...
            string(mat2str(double(model_cfg.selected_configuration))), ...
            string(mat2str(double(candidate_order))), mean_wis(i), ...
            calibration_windows(i), false, ...
            'VariableNames', {'StrategyID', 'StrategyName', 'Model', ...
            'ExoMode', 'PartASelectedOrder', 'CandidateOrder', ...
            'MeanCalibrationWIS', 'CalibrationWindows', 'Selected'});
    end

    candidate_scores = vertcat(rows{:});
    [selected_mean_wis, selected_idx] = min(mean_wis);
    selected_order = candidate_orders(selected_idx, :);
    candidate_scores.Selected(selected_idx) = true;
end

function forecast_results = local_analytic_calibration_forecast(scenario_entry, ...
    model_type, candidate_order, forecast_options)
%LOCAL_ANALYTIC_CALIBRATION_FORECAST Score calibration windows analytically.
    model_type = string(model_type);
    params     = reshape(double(candidate_order), 1, []);
    horizon    = forecast_options.horizon;
    wis_alphas = forecast_options.wis_alphas;
    sirs_cfg   = forecast_options.sirs_cfg;
    exo_mode   = forecast_options.exo_mode;
    sim_seed   = forecast_options.sim_seed;
    num_exo    = scenario_entry.num_exo;

    window_data = scenario_entry.window_data;
    num_windows = numel(window_data);
    forecast_results = repmat(struct('Rt_true_future', [], 'Rt_pred', [], ...
        'lower_bounds', [], 'upper_bounds', [], 'interval_alphas', []), ...
        num_windows, 1);
    count = 0;

    for w = 1:num_windows
        window_entry = window_data(w);
        if ~window_entry.is_valid_window
            continue;
        end

        Rt_past    = window_entry.Rt_past;
        U_past     = window_entry.U_past;
        sirs_state = window_entry.sirs_state;

        switch model_type
            case "AR"
                ar_model = fit_ar_model(Rt_past, params(1));
                [Rt_pred, ~, out_alphas, Rt_lower, Rt_upper] = ...
                    forecast_ar_model(ar_model, horizon, wis_alphas);
            case "ARX"
                nb_vec = repmat(params(2), 1, num_exo);
                nk_vec = repmat(params(3), 1, num_exo);
                arx_model = fit_arx_model(Rt_past, U_past, params(1), nb_vec, nk_vec);
                [Rt_pred, ~, out_alphas, Rt_lower, Rt_upper] = ...
                    forecast_arx_closed_loop(arx_model, Rt_past, U_past, ...
                    sirs_state, sirs_cfg, exo_mode, horizon, wis_alphas, sim_seed);
            case "N4SID"
                [Rt_pred, ~, out_alphas, Rt_lower, Rt_upper] = ...
                    fit_n4sid_model(Rt_past, U_past, [], params(1), params(2), ...
                    horizon, wis_alphas, sirs_state, sirs_cfg, exo_mode, sim_seed);
            case "SSEST"
                [Rt_pred, ~, out_alphas, Rt_lower, Rt_upper] = ...
                    fit_ssest_model(Rt_past, U_past, [], params(1), params(2), ...
                    horizon, wis_alphas, sirs_state, sirs_cfg, exo_mode, sim_seed);
            otherwise
                error('LOCALORDER:UnknownModel', ...
                    'Unsupported MODEL_TYPE: %s', model_type);
        end

        count = count + 1;
        forecast_results(count).Rt_true_future  = window_entry.truth_Rt;
        forecast_results(count).Rt_pred         = Rt_pred(:);
        forecast_results(count).lower_bounds    = Rt_lower;
        forecast_results(count).upper_bounds    = Rt_upper;
        forecast_results(count).interval_alphas = reshape(double(out_alphas), 1, []);
    end

    forecast_results = forecast_results(1:count);
end

function forecast_options = local_forecast_options(cfg, exo_mode, scenario_entry)
%LOCAL_FORECAST_OPTIONS Build local-order selection forecast options.
    forecast_options = struct( ...
        'horizon', cfg.forecast.horizon, ...
        'wis_alphas', cfg.forecast.wis_alphas, ...
        'sirs_cfg', cfg.sirs_projection, ...
        'exo_mode', char(exo_mode), ...
        'sim_seed', cfg.sim.seed, ...
        'num_exo', scenario_entry.num_exo, ...
        'intervals', cfg.intervals, ...
        'scenario_id', scenario_entry.scenario_id);
end

function [mean_wis, calibration_windows] = local_mean_calibration_wis(forecast_results)
%LOCAL_MEAN_CALIBRATION_WIS Compute mean WIS over calibration forecasts.
    calibration_windows = numel(forecast_results);
    window_wis = inf(calibration_windows, 1);

    for k = 1:calibration_windows
        truth_Rt = double(forecast_results(k).Rt_true_future(:));
        pred_Rt = double(forecast_results(k).Rt_pred(:));
        lower_Rt = double(forecast_results(k).lower_bounds);
        upper_Rt = double(forecast_results(k).upper_bounds);
        alphas = reshape(double(forecast_results(k).interval_alphas), 1, []);

        metrics = evaluate_forecast_window_metrics(truth_Rt, pred_Rt, ...
            lower_Rt, upper_Rt, alphas);
        window_wis(k) = metrics.window_wis;
    end

    finite_wis = window_wis(isfinite(window_wis));
    if isempty(finite_wis)
        mean_wis = inf;
    else
        mean_wis = mean(finite_wis);
    end
end

function calibration_entry = local_calibration_entry(scenario_entry, ...
    calibration_end_idx, max_calibration_windows)
%LOCAL_CALIBRATION_ENTRY Keep calibration windows inside the calibration span.
    window_data = scenario_entry.window_data;
    keep_idx = false(numel(window_data), 1);
    for i = 1:numel(window_data)
        keep_idx(i) = window_data(i).is_valid_window && ...
            ~isempty(window_data(i).horizon_indices) && ...
            max(window_data(i).horizon_indices) <= calibration_end_idx;
    end

    selected_idx = find(keep_idx);
    max_calibration_windows = round(double(max_calibration_windows));
    if max_calibration_windows > 0 && numel(selected_idx) > max_calibration_windows
        pick_pos = unique(round(linspace(1, numel(selected_idx), ...
            max_calibration_windows)), 'stable');
        selected_idx = selected_idx(pick_pos);
    end

    if isempty(selected_idx)
        error('PARTC:NoCalibrationWindows', ...
            'No Part C calibration windows are available for local order selection.');
    end

    calibration_entry = scenario_entry;
    calibration_entry.window_data = window_data(selected_idx);
    calibration_entry.windows = [calibration_entry.window_data.window_day]';
end

function calibration_end_idx = local_calibration_end_index(scenario_entry, cfg, strategy)
%LOCAL_CALIBRATION_END_INDEX Convert calibration fraction to data index.
    n = numel(scenario_entry.Rt_true);
    calibration_fraction = double(strategy.calibration_fraction);
    calibration_end_idx = floor(n * calibration_fraction);
    min_idx = cfg.forecast.min_window + cfg.forecast.horizon + 1;
    max_idx = n - cfg.forecast.horizon;
    calibration_end_idx = min(max(calibration_end_idx, min_idx), max_idx);

    if calibration_end_idx <= min_idx || calibration_end_idx >= n
        error('PARTC:InvalidCalibrationSplit', ...
            'Part C calibration split leaves no usable calibration/evaluation span.');
    end
end

function cfg_snapshot = local_cfg_snapshot(cfg, strategy)
%LOCAL_CFG_SNAPSHOT Store local-order selection settings.
    cfg_snapshot = struct();
    cfg_snapshot.experiment_id = cfg.experiment_id;
    cfg_snapshot.experiment_name = cfg.experiment_name;
    cfg_snapshot.strategy = strategy;
    cfg_snapshot.fixed_forecast_cases = cfg.fixed_forecast_cases;
    cfg_snapshot.local_order_grid = cfg.local_order_grid;
    cfg_snapshot.forecast = cfg.forecast;
    cfg_snapshot.intervals = cfg.intervals;
end
