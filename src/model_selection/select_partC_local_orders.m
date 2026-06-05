function selection = select_partC_local_orders(cfg, processed, fixed_configs)
%SELECT_PARTC_LOCAL_ORDERS Select local Part C real-data orders.
%
%   Syntax:
%       selection = select_partC_local_orders(cfg, processed, fixed_configs)
%
%   Description:
%       Builds small local AR/None and ARX/I order grids centered on the
%       Part A-selected orders, scores those candidates on initial
%       calibration windows only, and selects the lowest mean calibration WIS
%       order for each Part C model case. Candidate forecasting uses the
%       shared expanding-window dispatcher, while WIS is computed with the
%       shared evaluation function.
%
%   Inputs:
%       cfg           - Part C configuration structure.
%       processed     - Loaded Part C processed real-data artifact.
%       fixed_configs - Fixed Part A-selected/fallback model configurations.
%
%   Outputs:
%       selection - Structure containing local grid scores, selected order
%                   table, and retuned model configurations.
%
%   See also BUILD_PARTC_LOCAL_ORDER_GRID, RUN_EXPANDING_WINDOW_FORECAST, ...
%            EVALUATE_FORECAST_WINDOW_METRICS.
%
% A. M. Kaahin 2026-06-03
% Modified: 2026-06-05

    %% 1. Strategy Setup
    strategy = local_strategy(cfg, "local_order_retuning");
    selected_configs = fixed_configs;
    score_blocks = cell(numel(fixed_configs), 1);
    selected_blocks = cell(numel(fixed_configs), 1);

    %% 2. Local Grid Scoring
    for c = 1:numel(fixed_configs)
        model_cfg = fixed_configs(c);
        scenario_entry = build_partC_forecast_entry(processed, cfg, ...
            model_cfg.exo_mode);
        calibration_end_idx = local_calibration_end_index(scenario_entry, ...
            cfg, strategy);
        calibration_entry = local_calibration_entry(scenario_entry, ...
            calibration_end_idx, cfg.local_order_grid.max_calibration_windows);

        candidate_orders = build_partC_local_order_grid( ...
            model_cfg.selected_configuration, model_cfg.model_type, ...
            cfg.local_order_grid);

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
            'candidate_count', size(candidate_orders, 1), ...
            'selection_interval_mode', local_selection_interval_mode(cfg));
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
        forecast_results = run_expanding_window_forecast(calibration_entry, ...
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

function forecast_options = local_forecast_options(cfg, exo_mode, scenario_entry)
%LOCAL_FORECAST_OPTIONS Build local-order selection forecast options.
    intervals_cfg = cfg.intervals;
    if isfield(cfg.local_order_grid, 'selection_intervals_enabled')
        intervals_cfg.enabled = logical(cfg.local_order_grid.selection_intervals_enabled);
    end

    forecast_options = struct( ...
        'horizon', cfg.forecast.horizon, ...
        'wis_alphas', cfg.forecast.wis_alphas, ...
        'sirs_cfg', cfg.sirs_projection, ...
        'exo_mode', char(exo_mode), ...
        'sim_seed', cfg.sim.seed, ...
        'num_exo', scenario_entry.num_exo, ...
        'intervals', intervals_cfg, ...
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

function strategy = local_strategy(cfg, strategy_id)
%LOCAL_STRATEGY Return one strategy from cfg.strategies.
    ids = string({cfg.strategies.strategy_id});
    idx = find(ids == string(strategy_id), 1);
    if isempty(idx)
        error('PARTC:MissingStrategy', ...
            'Missing Part C strategy definition: %s.', strategy_id);
    end
    strategy = cfg.strategies(idx);
end

function mode = local_selection_interval_mode(cfg)
%LOCAL_SELECTION_INTERVAL_MODE Describe local-order selection interval mode.
    if isfield(cfg.local_order_grid, 'selection_intervals_enabled') && ...
            ~cfg.local_order_grid.selection_intervals_enabled
        mode = "analytic_dispatcher_intervals";
    else
        mode = string(cfg.intervals.selection_method);
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
