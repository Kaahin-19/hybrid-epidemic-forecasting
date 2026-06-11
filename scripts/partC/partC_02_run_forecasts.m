%PARTC_02_RUN_FORECASTS Run Part C strategy forecasts on real data.
%
%   Description:
%       Loads the processed WHO-derived Swedish COVID Rt estimate and runs
%       the final Part C real-data transfer/adaptation study. The strategies
%       are fixed-parameter transfer, online parameter re-estimation, and
%       local order retuning. AR/None and ARX/I remain the only Part C model
%       cases.
%
%   Workflow:
%       1. Load processed real-data artifact and Part A-selected orders.
%       2. Load local order-retuning selections from Part C 04.
%       3. Run each strategy/model case on post-calibration forecast windows.
%       4. Save one canonical forecast artifact per strategy/model case.
%
%   See also PARTC_CONFIG, BUILD_FORECAST_ENTRIES, ...
%            RUN_EXPANDING_WINDOW_FORECAST, LOAD_PARTC_FIXED_CONFIGURATIONS.
%
% A. M. Kaahin 2026-05-18
% Modified: 2026-06-11

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Strategy Forecast Execution ===\n');

cfg = partC_config();
processedPath = fullfile(cfg.output.data_processed_dir, ...
    'partC_01_real_data_processed.mat');
forecastDir = cfg.output.forecast_dir;

if exist(processedPath, 'file') ~= 2
    error('FORECAST:MissingProcessedData', ...
        ['Missing processed WHO-derived real-data artifact: %s\n' ...
        'Run scripts/partC/partC_01_prepare_real_data.m first.'], ...
        processedPath);
end

if ~exist(forecastDir, 'dir'), mkdir(forecastDir); end
if ~exist(cfg.output.evaluation_dir, 'dir'), mkdir(cfg.output.evaluation_dir); end
if ~exist(cfg.output.table_dir, 'dir'), mkdir(cfg.output.table_dir); end

loaded = load(processedPath);
local_validate_processed_data(loaded, processedPath);

date = loaded.date(:);
fixed_configs = load_partC_fixed_configurations(cfg);
local_order_selection = local_load_local_order_selection(cfg);

fprintf('Experiment: %s\n', cfg.experiment_id);
fprintf('Loaded %d processed real-data observations.\n', numel(loaded.Rt_est));

%% 2. Strategy Forecast Loop
for s = 1:numel(cfg.strategies)
    strategy = cfg.strategies(s);
    fprintf('Strategy: %s (%s)\n', ...
        strategy.strategy_name, strategy.strategy_id);

    for c = 1:numel(fixed_configs)
        base_cfg = fixed_configs(c);
        [selected_order_for_strategy, local_order_selection_metadata] = ...
            local_strategy_order(base_cfg, strategy, local_order_selection);

        fprintf('  - %s / %s using order %s\n', ...
            base_cfg.model_type, base_cfg.exo_mode, ...
            mat2str(selected_order_for_strategy));

        scenario_entry = build_forecast_entries(cfg, base_cfg.exo_mode, ...
            struct('mode', "partC", 'data', loaded));
        forecast_options = local_forecast_options(cfg, base_cfg.exo_mode, ...
            scenario_entry);
        calibration_end_idx = local_calibration_end_index(scenario_entry, ...
            cfg, strategy);

        if strategy.uses_fixed_calibration_parameters
            [forecast_results, parameter_fit_metadata] = ...
                run_partC_fixed_parameter_forecast(scenario_entry, ...
                base_cfg.model_type, selected_order_for_strategy, ...
                forecast_options, calibration_end_idx);
        else
            parameter_fit_metadata = struct();
            evaluation_entry = local_evaluation_entry(scenario_entry, ...
                calibration_end_idx);
            forecast_results = run_expanding_window_forecast( ...
                evaluation_entry, base_cfg.model_type, ...
                selected_order_for_strategy, forecast_options);
        end

        forecast_results = local_attach_forecast_dates(forecast_results, date);

        if isempty(forecast_results)
            warning('FORECAST:NoWindows', ...
                'No valid Part C forecast windows for %s / %s / %s.', ...
                strategy.strategy_id, base_cfg.model_type, base_cfg.exo_mode);
        end

        %% 3. Persist Forecast Artifact
        experiment_id = string(cfg.experiment_id);
        experiment_name = string(cfg.experiment_name);
        data_source = string(cfg.data_source);
        country_code = string(cfg.input.country_code);
        country_name = local_country_name(loaded, cfg);
        date_range = [date(1), date(end)];
        strategy_id = string(strategy.strategy_id);
        strategy_name = string(strategy.strategy_name);
        order_treatment = string(strategy.order_treatment);
        parameter_treatment = string(strategy.parameter_treatment);
        model_type = string(base_cfg.model_type);
        exo_mode = string(base_cfg.exo_mode);
        selected_configuration = base_cfg.selected_configuration;
        selected_configuration_source = string(base_cfg.selected_configuration_source);
        selected_configuration_artifact = string(base_cfg.selected_configuration_artifact);
        selection_metadata = base_cfg.selection_metadata;
        source_processed_artifact = string(processedPath);
        compatibility_metadata = scenario_entry.compatibility_metadata;
        cfg_snapshot = local_cfg_snapshot(cfg, strategy, forecast_options, ...
            base_cfg, selected_order_for_strategy, compatibility_metadata, ...
            calibration_end_idx);

        outName = sprintf('partC_forecast_%s_%s_%s.mat', ...
            char(strategy_id), char(model_type), char(exo_mode));
        outPath = fullfile(forecastDir, outName);

        save(outPath, ...
            'experiment_id', 'experiment_name', 'data_source', ...
            'country_code', 'country_name', 'date_range', ...
            'strategy_id', 'strategy_name', 'order_treatment', ...
            'parameter_treatment', 'model_type', 'exo_mode', ...
            'selected_configuration', 'selected_configuration_source', ...
            'selected_configuration_artifact', 'selection_metadata', ...
            'selected_order_for_strategy', ...
            'local_order_selection_metadata', 'parameter_fit_metadata', ...
            'forecast_results', 'source_processed_artifact', ...
            'compatibility_metadata', 'cfg_snapshot');

        fprintf('      Forecast artifact saved to: %s\n', outPath);
    end
end

fprintf('=== Part C Strategy Forecast Execution Complete ===\n\n');

%% 4. Local Functions
function local_validate_processed_data(data, processedPath)
%LOCAL_VALIDATE_PROCESSED_DATA Verify processed Part C artifact fields.
    required_fields = {'date', 't', 'Rt_est', 'I_proxy', 'I_scaled', ...
        'daily_cases', 'renewal_lambda', 'metadata'};
    if ~all(isfield(data, required_fields))
        error('FORECAST:InvalidProcessedData', ...
            'Processed artifact is missing required fields: %s.', processedPath);
    end

    n = numel(data.Rt_est(:));
    if n == 0 || numel(data.t(:)) ~= n || numel(data.I_proxy(:)) ~= n || ...
            numel(data.I_scaled(:)) ~= n || numel(data.date(:)) ~= n
        error('FORECAST:InvalidProcessedData', ...
            'Processed Part C vectors must be nonempty and have equal length.');
    end

    values = [double(data.t(:)); double(data.Rt_est(:)); ...
        double(data.I_proxy(:)); double(data.I_scaled(:)); ...
        double(data.daily_cases(:))];
    if any(~isfinite(values)) || any(double(data.Rt_est(:)) <= 0) || ...
            any(double(data.I_proxy(:)) < 0) || ...
            any(double(data.I_scaled(:)) < 0)
        error('FORECAST:InvalidProcessedData', ...
            ['Processed Part C data must have finite positive Rt_est and ' ...
            'finite nonnegative case proxy values.']);
    end
end

function selection = local_load_local_order_selection(cfg)
%LOCAL_LOAD_LOCAL_ORDER_SELECTION Load canonical Part C local-order selections.
    selection_path = fullfile(cfg.output.evaluation_dir, ...
        'partC_local_order_selection.mat');

    if exist(selection_path, 'file') ~= 2
        error('FORECAST:MissingLocalOrderSelection', ...
            ['Missing Part C local-order selection artifact: %s\n' ...
            'Run scripts/partC/partC_04_select_local_orders.m first.'], ...
            selection_path);
    end

    loaded_selection = load(selection_path);
    if isfield(loaded_selection, 'selection')
        selection = loaded_selection.selection;
    else
        selection = loaded_selection;
    end

    if ~isfield(selection, 'selected_local_configs')
        error('FORECAST:InvalidLocalOrderSelection', ...
            'Local-order selection artifact is missing selected_local_configs: %s.', ...
            selection_path);
    end
end

function [selected_order, local_metadata] = local_strategy_order( ...
    base_cfg, strategy, local_order_selection)
%LOCAL_STRATEGY_ORDER Resolve the order used by one strategy/model case.
    selected_order = base_cfg.selected_configuration;
    local_metadata = struct();

    if ~strategy.uses_local_order_grid
        return;
    end

    local_configs = local_order_selection.selected_local_configs;
    for i = 1:numel(local_configs)
        if string(local_configs(i).model_type) == string(base_cfg.model_type) && ...
                string(local_configs(i).exo_mode) == string(base_cfg.exo_mode)
            selected_order = local_configs(i).selected_order_for_strategy;
            local_metadata = local_configs(i).local_order_selection_metadata;
            return;
        end
    end

    error('FORECAST:MissingLocalOrderSelection', ...
        'Missing local order selection for %s / %s.', ...
        base_cfg.model_type, base_cfg.exo_mode);
end

function forecast_options = local_forecast_options(cfg, exo_mode, scenario_entry)
%LOCAL_FORECAST_OPTIONS Build reusable forecast options for Part C.
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

function evaluation_entry = local_evaluation_entry(scenario_entry, calibration_end_idx)
%LOCAL_EVALUATION_ENTRY Keep post-calibration forecast windows only.
    window_data = scenario_entry.window_data;
    keep_idx = false(numel(window_data), 1);
    for i = 1:numel(window_data)
        keep_idx(i) = window_data(i).is_valid_window && ...
            window_data(i).window_day_idx >= calibration_end_idx;
    end

    if ~any(keep_idx)
        error('FORECAST:NoEvaluationWindows', ...
            'No post-calibration Part C forecast windows are available.');
    end

    evaluation_entry = scenario_entry;
    evaluation_entry.window_data = window_data(keep_idx);
    evaluation_entry.windows = [evaluation_entry.window_data.window_day]';
end

function calibration_end_idx = local_calibration_end_index(scenario_entry, cfg, strategy)
%LOCAL_CALIBRATION_END_INDEX Convert strategy calibration fraction to index.
    n = numel(scenario_entry.Rt_true);
    calibration_fraction = double(strategy.calibration_fraction);
    calibration_end_idx = floor(n * calibration_fraction);
    min_idx = cfg.forecast.min_window + cfg.forecast.horizon + 1;
    max_idx = n - cfg.forecast.horizon;
    calibration_end_idx = min(max(calibration_end_idx, min_idx), max_idx);

    if calibration_end_idx <= min_idx || calibration_end_idx >= n
        error('FORECAST:InvalidCalibrationSplit', ...
            'Part C calibration split leaves no usable evaluation span.');
    end
end

function forecast_results = local_attach_forecast_dates(forecast_results, date)
%LOCAL_ATTACH_FORECAST_DATES Add noncanonical date metadata for evaluation.
    for k = 1:numel(forecast_results)
        origin_idx = double(forecast_results(k).window_day_idx);
        horizon_idx = double(forecast_results(k).horizon_indices(:));

        if isfinite(origin_idx) && origin_idx >= 1 && origin_idx <= numel(date)
            forecast_results(k).forecast_origin_date = date(origin_idx);
        else
            forecast_results(k).forecast_origin_date = NaT;
        end

        valid_horizon = horizon_idx >= 1 & horizon_idx <= numel(date);
        if all(valid_horizon)
            forecast_results(k).t_future_date = date(horizon_idx);
        else
            forecast_results(k).t_future_date = NaT(numel(horizon_idx), 1);
        end
    end
end

function country_name = local_country_name(loaded, cfg)
%LOCAL_COUNTRY_NAME Resolve country name from artifact metadata or config.
    country_name = string(cfg.input.country_name);
    if isfield(loaded, 'metadata') && isfield(loaded.metadata, 'country_name')
        country_name = string(loaded.metadata.country_name);
    end
end

function cfg_snapshot = local_cfg_snapshot(cfg, strategy, forecast_options, ...
    model_cfg, selected_order_for_strategy, compatibility_metadata, ...
    calibration_end_idx)
%LOCAL_CFG_SNAPSHOT Store relevant strategy-forecast configuration.
    cfg_snapshot = struct();
    cfg_snapshot.experiment_id = cfg.experiment_id;
    cfg_snapshot.experiment_name = cfg.experiment_name;
    cfg_snapshot.data_source = cfg.data_source;
    cfg_snapshot.strategy = strategy;
    cfg_snapshot.forecast = cfg.forecast;
    cfg_snapshot.intervals = forecast_options.intervals;
    cfg_snapshot.sirs_projection = cfg.sirs_projection;
    cfg_snapshot.compatibility_metadata = compatibility_metadata;
    cfg_snapshot.fixed_forecast_cases = cfg.fixed_forecast_cases;
    cfg_snapshot.local_order_grid = cfg.local_order_grid;
    cfg_snapshot.model_type = model_cfg.model_type;
    cfg_snapshot.exo_mode = model_cfg.exo_mode;
    cfg_snapshot.selected_configuration_source = ...
        model_cfg.selected_configuration_source;
    cfg_snapshot.selected_order_for_strategy = selected_order_for_strategy;
    cfg_snapshot.calibration_end_idx = calibration_end_idx;
    cfg_snapshot.sim_seed = cfg.sim.seed;
end

function [forecast_results, fit_metadata] = run_partC_fixed_parameter_forecast( ...
    scenario_entry, model_type, selected_order, forecast_options, calibration_end_idx)
%RUN_PARTC_FIXED_PARAMETER_FORECAST Fit once on calibration, reuse params across origins.
    %% One-Time Calibration Fit
    model_type = char(string(model_type));
    selected_order = reshape(double(selected_order), 1, []);
    calibration_end_idx = round(double(calibration_end_idx));
    calibration_Rt = scenario_entry.Rt_model_input(1:calibration_end_idx);

    switch model_type
        case 'AR'
            fitted_model = fit_ar_model(calibration_Rt, selected_order(1));
        case 'ARX'
            calibration_U = scenario_entry.U_true(1:calibration_end_idx, :);
            nb_vec = repmat(selected_order(2), 1, scenario_entry.num_exo);
            nk_vec = repmat(selected_order(3), 1, scenario_entry.num_exo);
            fitted_model = fit_arx_model(calibration_Rt, calibration_U, ...
                selected_order(1), nb_vec, nk_vec);
        otherwise
            error('PARTC:UnsupportedFixedParameterModel', ...
                'Fixed-parameter Part C forecasts support only AR and ARX.');
    end

    fit_metadata = local_fit_metadata(fitted_model, model_type, ...
        selected_order, calibration_end_idx, numel(calibration_Rt));

    %% Evaluation Forecast Loop
    window_data = scenario_entry.window_data;
    forecast_results = repmat(local_empty_result(), numel(window_data), 1);
    count = 0;

    for w = 1:numel(window_data)
        window_entry = window_data(w);
        if ~window_entry.is_valid_window || ...
                window_entry.window_day_idx < calibration_end_idx
            continue;
        end

        forecast = local_forecast_fixed_window(fitted_model, model_type, ...
            window_entry, forecast_options);
        is_valid = is_valid_forecast(forecast.Rt_pred, ...
            forecast.interval_alphas, forecast.lower_bounds, ...
            forecast.upper_bounds, window_entry.truth_Rt);

        count = count + 1;
        forecast_results(count).forecast_origin  = window_entry.window_day;
        forecast_results(count).window_day_idx   = window_entry.window_day_idx;
        forecast_results(count).horizon_indices  = window_entry.horizon_indices;
        forecast_results(count).t_future         = window_entry.t_future;
        forecast_results(count).Rt_true_future   = window_entry.truth_Rt;
        forecast_results(count).Rt_pred          = forecast.Rt_pred;
        forecast_results(count).lower_bounds     = forecast.lower_bounds;
        forecast_results(count).upper_bounds     = forecast.upper_bounds;
        forecast_results(count).interval_alphas  = forecast.interval_alphas;
        forecast_results(count).aicc             = forecast.aicc;
        forecast_results(count).interval_method  = forecast.interval_method;
        forecast_results(count).interval_num_draws = forecast.interval_num_draws;
        forecast_results(count).interval_seed    = forecast.interval_seed;
        forecast_results(count).interval_status  = forecast.interval_status;
        forecast_results(count).is_valid         = is_valid;
        forecast_results(count).status           = local_status_label(is_valid);
    end

    forecast_results = forecast_results(1:count);
    fit_metadata.evaluation_windows = count;
end

function forecast = local_forecast_fixed_window(fitted_model, model_type, ...
    window_entry, forecast_options)
%LOCAL_FORECAST_FIXED_WINDOW Forecast one window without refitting.
    switch model_type
        case 'AR'
            [Rt_pred, aicc, out_alphas, lower_bounds, upper_bounds, status] = ...
                local_forecast_fixed_ar(fitted_model, window_entry.Rt_past, ...
                forecast_options.horizon, forecast_options.wis_alphas);
            interval_method = "fixed_parameter_log_normal";

        case 'ARX'
            [Rt_pred, aicc, out_alphas, lower_bounds, upper_bounds] = ...
                forecast_arx_closed_loop(fitted_model, window_entry.Rt_past, ...
                window_entry.U_past, window_entry.sirs_state, ...
                forecast_options.sirs_cfg, forecast_options.exo_mode, ...
                forecast_options.horizon, forecast_options.wis_alphas, ...
                forecast_options.sim_seed);
            status = "fixed_parameter_log_normal";
            interval_method = "fixed_parameter_closed_loop_log_normal";

        otherwise
            error('PARTC:UnsupportedFixedParameterModel', ...
                'Fixed-parameter Part C forecasts support only AR and ARX.');
    end

    forecast = struct( ...
        'Rt_pred', Rt_pred(:), ...
        'aicc', aicc, ...
        'interval_alphas', reshape(double(out_alphas), 1, []), ...
        'lower_bounds', lower_bounds, ...
        'upper_bounds', upper_bounds, ...
        'interval_method', interval_method, ...
        'interval_num_draws', 0, ...
        'interval_seed', double(forecast_options.sim_seed), ...
        'interval_status', string(status));
end

function result = local_empty_result()
%LOCAL_EMPTY_RESULT Preallocate a single forecast-result entry.
    result = struct( ...
        'forecast_origin', [], ...
        'window_day_idx', [], ...
        'horizon_indices', [], ...
        't_future', [], ...
        'Rt_true_future', [], ...
        'Rt_pred', [], ...
        'lower_bounds', [], ...
        'upper_bounds', [], ...
        'interval_alphas', [], ...
        'aicc', [], ...
        'interval_method', "", ...
        'interval_num_draws', 0, ...
        'interval_seed', 0, ...
        'interval_status', "", ...
        'is_valid', false, ...
        'status', "");
end

function [Rt_pred, aicc, interval_alphas, lower_bounds, upper_bounds, status] = ...
    local_forecast_fixed_ar(model, Rt_hist, horizon, interval_alphas)
%LOCAL_FORECAST_FIXED_AR Recursive AR forecast using fixed coefficients.
    horizon = round(double(horizon));
    interval_alphas = reshape(double(interval_alphas), 1, []);
    Rt_hist = double(Rt_hist(:));
    aicc = model.aicc;

    if ~isfield(model, 'is_persistence') || model.is_persistence || ...
            ~isfield(model, 'coefficients') || ...
            isempty(model.coefficients.a_values)
        [Rt_pred, lower_bounds, upper_bounds] = ...
            local_persistence_forecast(Rt_hist(end), horizon, interval_alphas);
        status = "persistence_fallback";
        return;
    end

    try
        a_values = reshape(double(model.coefficients.a_values), [], 1);
        rolling_log_Rt = log(max(Rt_hist, eps));
        pred_log_Rt = zeros(horizon, 1);

        for h = 1:horizon
            next_log_Rt = 0;
            for lag = 1:numel(a_values)
                next_log_Rt = next_log_Rt - ...
                    a_values(lag) * rolling_log_Rt(end + 1 - lag);
            end
            pred_log_Rt(h) = next_log_Rt;
            rolling_log_Rt = [rolling_log_Rt; next_log_Rt]; %#ok<AGROW>
        end

        residual_std = local_residual_std(model);
        pred_sd = sqrt((1:horizon)') * residual_std;
        [Rt_pred, lower_bounds, upper_bounds] = local_log_normal_output( ...
            pred_log_Rt, pred_sd, interval_alphas);
        local_validate_forecast_output(Rt_pred, lower_bounds, upper_bounds);
        status = "fixed_parameter_log_normal";
    catch
        [Rt_pred, lower_bounds, upper_bounds] = ...
            local_persistence_forecast(Rt_hist(end), horizon, interval_alphas);
        aicc = inf;
        status = "persistence_fallback";
    end
end

function scale = local_residual_std(model)
%LOCAL_RESIDUAL_STD Return fixed log-scale innovation scale.
    scale = 0;
    if isfield(model, 'residual_std') && ~isempty(model.residual_std)
        scale = double(model.residual_std);
    end
    if ~isscalar(scale) || ~isfinite(scale) || scale < 0
        scale = 0;
    end
end

function [Rt_curve, lower_bounds, upper_bounds] = ...
    local_log_normal_output(pred_log_Rt, pred_sd, interval_alphas)
%LOCAL_LOG_NORMAL_OUTPUT Convert log-scale medians and SDs to Rt intervals.
    z_scores = sqrt(2) * erfinv(1 - interval_alphas);
    horizon = numel(pred_log_Rt);
    num_alphas = numel(interval_alphas);

    Rt_curve = exp(pred_log_Rt(:));
    lower_bounds = zeros(horizon, num_alphas);
    upper_bounds = zeros(horizon, num_alphas);
    for j = 1:num_alphas
        lower_bounds(:, j) = exp(pred_log_Rt - z_scores(j) * pred_sd);
        upper_bounds(:, j) = exp(pred_log_Rt + z_scores(j) * pred_sd);
    end
end

function [Rt_curve, lower_bounds, upper_bounds] = ...
    local_persistence_forecast(last_value, horizon, interval_alphas)
%LOCAL_PERSISTENCE_FORECAST Return a deterministic persistence forecast.
    Rt_curve = repmat(double(last_value), horizon, 1);
    lower_bounds = repmat(Rt_curve, 1, numel(interval_alphas));
    upper_bounds = repmat(Rt_curve, 1, numel(interval_alphas));
end

function local_validate_forecast_output(Rt_curve, lower_bounds, upper_bounds)
%LOCAL_VALIDATE_FORECAST_OUTPUT Ensure forecasts and intervals are valid.
    if any(~isfinite(Rt_curve(:))) || any(Rt_curve(:) <= 0) || ...
            any(~isfinite(lower_bounds(:))) || any(lower_bounds(:) <= 0) || ...
            any(~isfinite(upper_bounds(:))) || any(upper_bounds(:) <= 0) || ...
            any(lower_bounds(:) > upper_bounds(:))
        error('PARTC:InvalidFixedParameterForecast', ...
            'Fixed-parameter forecast values and bounds must be finite, positive, and ordered.');
    end
end

function label = local_status_label(is_valid)
%LOCAL_STATUS_LABEL Map a validity flag to a status string.
    if is_valid
        label = "ok";
    else
        label = "invalid";
    end
end

function metadata = local_fit_metadata(model, model_type, selected_order, ...
    calibration_end_idx, calibration_observations)
%LOCAL_FIT_METADATA Summarize the one-time fixed-parameter fit.
    metadata = struct();
    metadata.model_type = string(model_type);
    metadata.selected_order = selected_order;
    metadata.calibration_end_idx = calibration_end_idx;
    metadata.calibration_observations = calibration_observations;
    metadata.aicc = model.aicc;
    metadata.residual_std = local_residual_std(model);
    metadata.is_persistence = false;
    if isfield(model, 'is_persistence')
        metadata.is_persistence = logical(model.is_persistence);
    end
    metadata.parameter_treatment = "fit_once_on_initial_real_data_calibration_segment";
end
