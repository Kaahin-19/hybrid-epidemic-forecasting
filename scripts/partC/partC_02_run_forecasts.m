%PARTC_02_RUN_FORECASTS Run fixed shared-dispatcher forecasts on real data.
%
%   Description:
%       Loads the processed WHO-derived Swedish COVID Rt estimate and runs the
%       frozen Part C AR/None and ARX/I comparison through the shared Part
%       A/B expanding-window forecast dispatcher. Rt_est is used as both the
%       model input and evaluation target. I_scaled is used as the ARX/I
%       covariate. A normalized SIRS state proxy is constructed only for
%       closed-loop ARX compatibility and is not interpreted as observed
%       Swedish susceptible-state data.
%
%   Workflow:
%       1. Load processed real-data artifact and fixed Part A configurations.
%       2. Build Part C forecast entries compatible with shared window data.
%       3. Run canonical expanding-window forecasts for AR/None and ARX/I.
%       4. Save canonical Part C forecast artifacts under results/partC.
%
%   See also PARTC_CONFIG, PREPARE_WINDOW_DATA, RUN_EXPANDING_WINDOW_FORECAST.
%
% A. M. Kaahin 2026-05-18
% Modified: 2026-06-03

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Fixed Forecast Execution ===\n');

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

loaded = load(processedPath);
local_validate_processed_data(loaded, processedPath);
local_require_forecast_dependencies(cfg);

date = loaded.date(:);
Rt_model_input = double(loaded.Rt_est(:));

fixed_configs = local_load_fixed_partA_configs(cfg);

fprintf('Experiment: %s\n', cfg.experiment_id);
fprintf('Loaded %d processed real-data observations.\n', numel(Rt_model_input));

%% 2. Forecast Loop
for c = 1:numel(fixed_configs)
    model_cfg = fixed_configs(c);
    fprintf('  - Fixed model %s / %s using %s configuration %s\n', ...
        model_cfg.model_type, model_cfg.exo_mode, ...
        model_cfg.selected_configuration_source, ...
        mat2str(model_cfg.selected_configuration));

    scenario_entry = local_build_partC_forecast_entry(loaded, cfg, ...
        model_cfg.exo_mode);
    forecast_options = local_forecast_options(cfg, model_cfg.exo_mode, ...
        scenario_entry);

    forecast_results = run_expanding_window_forecast(scenario_entry, ...
        model_cfg.model_type, model_cfg.selected_configuration, ...
        forecast_options);
    forecast_results = local_attach_forecast_dates(forecast_results, date);

    if isempty(forecast_results)
        warning('FORECAST:NoWindows', ...
            'No valid Part C forecast windows for %s / %s.', ...
            model_cfg.model_type, model_cfg.exo_mode);
    end

    %% 3. Persist Forecast Artifact
    experiment_id = string(cfg.experiment_id);
    experiment_name = string(cfg.experiment_name);
    data_source = string(cfg.data_source);
    country_code = string(cfg.input.country_code);
    country_name = local_country_name(loaded, cfg);
    date_range = [date(1), date(end)];
    model_type = string(model_cfg.model_type);
    exo_mode = string(model_cfg.exo_mode);
    selected_configuration = model_cfg.selected_configuration;
    selected_configuration_source = string(model_cfg.selected_configuration_source);
    selected_configuration_artifact = string(model_cfg.selected_configuration_artifact);
    selection_metadata = model_cfg.selection_metadata;
    source_processed_artifact = string(processedPath);
    compatibility_metadata = scenario_entry.compatibility_metadata;
    cfg_snapshot = local_cfg_snapshot(cfg, forecast_options, model_cfg, ...
        compatibility_metadata);

    outName = sprintf('partC_forecast_real_%s_%s.mat', ...
        char(model_type), char(exo_mode));
    outPath = fullfile(forecastDir, outName);

    save(outPath, ...
        'experiment_id', 'experiment_name', 'data_source', ...
        'country_code', 'country_name', 'date_range', 'model_type', ...
        'exo_mode', 'selected_configuration', ...
        'selected_configuration_source', ...
        'selected_configuration_artifact', 'selection_metadata', ...
        'forecast_results', 'source_processed_artifact', ...
        'compatibility_metadata', 'cfg_snapshot');

    fprintf('      Forecast artifact saved to: %s\n', outPath);
end

fprintf('=== Part C Fixed Forecast Execution Complete ===\n\n');

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

function local_require_forecast_dependencies(cfg)
%LOCAL_REQUIRE_FORECAST_DEPENDENCIES Check user-provided MATLAB dependencies.
    required = ["iddata", "ar", "arx"];
    if isfield(cfg, 'intervals') && cfg.intervals.enabled
        required = [required, "rparse", "urdme"];
    end

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

function fixed_configs = local_load_fixed_partA_configs(cfg)
%LOCAL_LOAD_FIXED_PARTA_CONFIGS Load or fall back to frozen Part A selections.
    cases = cfg.fixed_forecast_cases;
    fixed_configs = repmat(local_empty_fixed_config(), 1, numel(cases));
    for i = 1:numel(cases)
        fixed_configs(i) = local_load_one_fixed_config(cases(i));
    end
end

function model_cfg = local_load_one_fixed_config(fixed_case)
%LOCAL_LOAD_ONE_FIXED_CONFIG Load one Part A selection artifact or fallback.
    model_type = string(fixed_case.model_type);
    exo_mode = string(fixed_case.exo_mode);
    artifact_path = string(fixed_case.selected_configuration_artifact);

    if strlength(artifact_path) > 0 && exist(artifact_path, 'file') == 2
        selection = load(artifact_path);
        local_validate_selection_artifact(selection, artifact_path, ...
            model_type, exo_mode);
        selected_configuration = reshape(double(selection.selected_configuration), 1, []);
        source = "partA_model_selection";
        selection_artifact = artifact_path;
        fallback_used = false;
        selection_metadata = local_selection_metadata(selection);
    else
        selected_configuration = reshape(double(fixed_case.fallback_configuration), 1, []);
        source = "partC_config_fallback";
        selection_artifact = "";
        fallback_used = true;
        selection_metadata = struct('selected_index', nan, ...
            'best_global_wis', nan);
        warning('FORECAST:PartASelectionFallback', ...
            ['Missing Part A selection artifact for %s / %s: %s. ', ...
            'Using documented Part C fallback %s.'], ...
            model_type, exo_mode, artifact_path, mat2str(selected_configuration));
    end

    local_validate_configuration_shape(model_type, selected_configuration);
    selection_metadata.fallback_used = fallback_used;

    model_cfg = local_empty_fixed_config();
    model_cfg.model_type = model_type;
    model_cfg.exo_mode = exo_mode;
    model_cfg.selected_configuration = selected_configuration;
    model_cfg.selected_configuration_source = source;
    model_cfg.selected_configuration_artifact = selection_artifact;
    model_cfg.selection_metadata = selection_metadata;
end

function local_validate_selection_artifact(selection, artifact_path, model_type, exo_mode)
%LOCAL_VALIDATE_SELECTION_ARTIFACT Validate a Part A selection artifact.
    required_fields = {'model_type', 'exo_mode', 'selected_configuration'};
    if ~all(isfield(selection, required_fields))
        error('FORECAST:InvalidSelectionArtifact', ...
            'Selection artifact is missing required fields: %s.', artifact_path);
    end

    if string(selection.model_type) ~= model_type || string(selection.exo_mode) ~= exo_mode
        error('FORECAST:SelectionIdentityMismatch', ...
            'Selection artifact identity mismatch: %s.', artifact_path);
    end
end

function local_validate_configuration_shape(model_type, selected_configuration)
%LOCAL_VALIDATE_CONFIGURATION_SHAPE Check expected parameter counts.
    switch char(model_type)
        case 'AR'
            expected_count = 1;
        case 'ARX'
            expected_count = 3;
        otherwise
            error('FORECAST:UnsupportedModel', ...
                'Part C frozen workflow supports only AR and ARX.');
    end

    if numel(selected_configuration) ~= expected_count
        error('FORECAST:InvalidSelectedConfiguration', ...
            'Selected configuration for %s has invalid size: %s.', ...
            model_type, mat2str(selected_configuration));
    end
end

function metadata = local_selection_metadata(selection)
%LOCAL_SELECTION_METADATA Capture optional Part A selection metadata.
    metadata = struct();
    metadata.selected_index = local_numeric_field(selection, 'selected_index');
    metadata.best_global_wis = local_numeric_field(selection, 'best_global_wis');
    if isnan(metadata.best_global_wis) && isfield(selection, 'global_mean_wis') && ...
            isfield(selection, 'selected_index') && ...
            selection.selected_index >= 1 && ...
            selection.selected_index <= numel(selection.global_mean_wis)
        metadata.best_global_wis = double(selection.global_mean_wis(selection.selected_index));
    end
end

function value = local_numeric_field(s, field_name)
%LOCAL_NUMERIC_FIELD Read a scalar numeric field or NaN.
    value = nan;
    if isfield(s, field_name) && ~isempty(s.(field_name)) && isnumeric(s.(field_name))
        raw = double(s.(field_name));
        if isscalar(raw)
            value = raw;
        end
    end
end

function model_cfg = local_empty_fixed_config()
%LOCAL_EMPTY_FIXED_CONFIG Build a fixed configuration placeholder.
    model_cfg = struct( ...
        'model_type', "", ...
        'exo_mode', "", ...
        'selected_configuration', [], ...
        'selected_configuration_source', "", ...
        'selected_configuration_artifact', "", ...
        'selection_metadata', struct());
end

function scenario_entry = local_build_partC_forecast_entry(loaded, cfg, exo_mode)
%LOCAL_BUILD_PARTC_FORECAST_ENTRY Build generic forecast input for real data.
    horizon = cfg.forecast.horizon;
    Rt_model_input = double(loaded.Rt_est(:));
    Rt_evaluation_target = Rt_model_input;
    tspan = double(loaded.t(:));
    I_scaled = double(loaded.I_scaled(:));

    [S_model_input, I_model_input, U_true, compatibility_metadata] = ...
        local_compatibility_state(I_scaled, cfg, exo_mode);

    scenario_inputs = struct( ...
        'Rt_true', Rt_model_input, ...
        'tspan', tspan, ...
        'S_true', S_model_input, ...
        'I_true', I_model_input, ...
        'U_true', U_true);

    max_window_day = tspan(end) - horizon;
    windows = cfg.forecast.min_window : cfg.forecast.step_size : max_window_day;

    if isempty(windows)
        window_data = struct([]);
    else
        window_data = repmat(prepare_window_data(scenario_inputs, windows(1), ...
            horizon, cfg.sirs_projection), numel(windows), 1);
        for w = 1:numel(windows)
            window_data(w) = prepare_window_data(scenario_inputs, windows(w), ...
                horizon, cfg.sirs_projection);
            if window_data(w).is_valid_window
                idx = window_data(w).horizon_indices;
                if max(idx) <= numel(Rt_evaluation_target)
                    window_data(w).truth_Rt = Rt_evaluation_target(idx);
                else
                    window_data(w).is_valid_window = false;
                end
            end
        end
    end

    scenario_entry = struct();
    scenario_entry.scenario_id = "real";
    scenario_entry.scenario_name = "WHO-derived Sweden Rt estimate";
    scenario_entry.num_exo = size(U_true, 2);
    scenario_entry.windows = windows(:);
    scenario_entry.window_data = window_data;
    scenario_entry.Rt_true = Rt_evaluation_target;
    scenario_entry.tspan = tspan;
    scenario_entry.compatibility_metadata = compatibility_metadata;
end

function [S_model_input, I_model_input, U_true, metadata] = ...
    local_compatibility_state(I_scaled, cfg, exo_mode)
%LOCAL_COMPATIBILITY_STATE Build the explicit Part C ARX state proxy.
    I_scaled = double(I_scaled(:));
    pop_size = double(cfg.sirs_projection.pop_size);
    max_fraction = 1 - (1 / pop_size);
    I_fraction = min(max(I_scaled, 0), max_fraction);
    I_model_input = I_fraction * pop_size;
    S_model_input = pop_size - I_model_input;
    S_model_input = max(S_model_input, 1);
    total_si = S_model_input + I_model_input;
    S_model_input = S_model_input .* (pop_size ./ total_si);
    I_model_input = I_model_input .* (pop_size ./ total_si);

    switch char(exo_mode)
        case 'None'
            U_true = [];
        case 'I'
            U_true = I_scaled;
        otherwise
            error('FORECAST:UnsupportedExoMode', ...
                'Part C frozen workflow supports only None and I exogenous modes.');
    end

    metadata = struct();
    metadata.Rt_model_input = "Rt_est";
    metadata.Rt_evaluation_target = "Rt_est";
    metadata.I_model_input = "I_scaled mapped to a normalized compatibility state";
    metadata.S_model_input = ...
        "Neutral complement to I_scaled for closed-loop ARX compatibility only";
    metadata.U_true = "I_scaled for ARX/I; empty for AR/None";
    metadata.pop_size = pop_size;
    metadata.max_state_fraction = max_fraction;
    metadata.biological_interpretation = ...
        "The Part C S/I state is not an observed Swedish susceptible trajectory.";
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

function cfg_snapshot = local_cfg_snapshot(cfg, forecast_options, model_cfg, ...
    compatibility_metadata)
%LOCAL_CFG_SNAPSHOT Store relevant fixed-forecast configuration.
    cfg_snapshot = struct();
    cfg_snapshot.experiment_id = cfg.experiment_id;
    cfg_snapshot.experiment_name = cfg.experiment_name;
    cfg_snapshot.data_source = cfg.data_source;
    cfg_snapshot.forecast = cfg.forecast;
    cfg_snapshot.intervals = forecast_options.intervals;
    cfg_snapshot.sirs_projection = cfg.sirs_projection;
    cfg_snapshot.compatibility_metadata = compatibility_metadata;
    cfg_snapshot.fixed_forecast_cases = cfg.fixed_forecast_cases;
    cfg_snapshot.model_type = model_cfg.model_type;
    cfg_snapshot.exo_mode = model_cfg.exo_mode;
    cfg_snapshot.selected_configuration_source = ...
        model_cfg.selected_configuration_source;
    cfg_snapshot.sim_seed = cfg.sim.seed;
end
