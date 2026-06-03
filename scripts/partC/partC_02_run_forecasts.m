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
%       2. Load or produce local order-retuning selections.
%       3. Run each strategy/model case on post-calibration forecast windows.
%       4. Save one canonical forecast artifact per strategy/model case.
%
%   See also PARTC_CONFIG, BUILD_PARTC_FORECAST_ENTRY, ...
%            RUN_EXPANDING_WINDOW_FORECAST, RUN_PARTC_FIXED_PARAMETER_FORECAST.
%
% A. M. Kaahin 2026-05-18
% Modified: 2026-06-03

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
local_require_forecast_dependencies();

date = loaded.date(:);
fixed_configs = load_partC_fixed_configurations(cfg);
local_order_selection = local_load_or_select_local_orders(cfg, loaded, ...
    fixed_configs);

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

        scenario_entry = build_partC_forecast_entry(loaded, cfg, ...
            base_cfg.exo_mode);
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

function local_require_forecast_dependencies()
%LOCAL_REQUIRE_FORECAST_DEPENDENCIES Check user-provided MATLAB dependencies.
    required = ["iddata", "ar", "arx", "rparse", "urdme"];
    missing = strings(0, 1);

    for i = 1:numel(required)
        if local_dependency_missing(required(i))
            missing(end + 1, 1) = required(i); %#ok<AGROW>
        end
    end

    if ~isempty(missing)
        error('FORECAST:MissingExternalDependency', ...
            ['Missing required MATLAB/URDME dependency function(s): %s.\n' ...
            'Part C does not add third_party paths automatically; add your ' ...
            'local URDME/StenLib/System Identification paths before running.'], ...
            char(strjoin(missing, ', ')));
    end
end

function tf = local_dependency_missing(function_name)
%LOCAL_DEPENDENCY_MISSING Return true when MATLAB cannot resolve a dependency.
    name = char(function_name);
    tf = exist(name, 'file') == 0 && exist(name, 'class') == 0 && ...
        exist(name, 'builtin') == 0;
end

function selection = local_load_or_select_local_orders(cfg, processed, fixed_configs)
%LOCAL_LOAD_OR_SELECT_LOCAL_ORDERS Load or create canonical local selections.
    selection_path = fullfile(cfg.output.evaluation_dir, ...
        'partC_local_order_selection.mat');

    if exist(selection_path, 'file') == 2
        loaded_selection = load(selection_path);
        if isfield(loaded_selection, 'selection')
            selection = loaded_selection.selection;
        else
            selection = loaded_selection;
        end
        if local_selection_has_dependency_preflight(selection)
            return;
        end
        warning('FORECAST:StaleLocalOrderSelection', ...
            ['Existing local order selection artifact lacks dependency ' ...
            'preflight metadata; recomputing it.']);
    end

    fprintf('Selecting local orders now.\n');
    selection = select_partC_local_orders(cfg, processed, fixed_configs);
    local_write_local_order_selection_outputs(cfg, selection, selection_path);
end

function local_write_local_order_selection_outputs(cfg, selection, selection_path)
%LOCAL_WRITE_LOCAL_ORDER_SELECTION_OUTPUTS Persist local order selection.
    selection_artifact = string(selection_path);
    selection.cfg_snapshot.dependency_preflight_completed = true;
    selected_local_configs = selection.selected_local_configs;
    local_order_grid_scores = selection.local_order_grid_scores;
    selected_local_orders = selection.selected_local_orders;
    cfg_snapshot = selection.cfg_snapshot;
    save(selection_path, 'selection', 'selection_artifact', ...
        'selected_local_configs', 'local_order_grid_scores', ...
        'selected_local_orders', 'cfg_snapshot');

    writetable(local_order_grid_scores, fullfile(cfg.output.table_dir, ...
        'partC_local_order_grid_scores.csv'));
    writetable(selected_local_orders, fullfile(cfg.output.table_dir, ...
        'partC_selected_local_orders.csv'));
end

function tf = local_selection_has_dependency_preflight(selection)
%LOCAL_SELECTION_HAS_DEPENDENCY_PREFLIGHT Check valid selection provenance.
    tf = isfield(selection, 'cfg_snapshot') && ...
        isfield(selection.cfg_snapshot, 'dependency_preflight_completed') && ...
        logical(selection.cfg_snapshot.dependency_preflight_completed);
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
