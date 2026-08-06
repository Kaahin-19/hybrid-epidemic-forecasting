%PARTC_03_RUN_FORECASTS Generate held-out Part C Rt forecasts.
%
%   Description:
%       Generates held-out forecasts of the operational Swedish Rt estimate
%       for AR/None and ARX/I under Part A online fitting, Part C local online
%       fitting, and Part A fixed calibration fitting. All strategies share one
%       held-out origin grid, deterministic common random numbers, and the same
%       result contract. Fixed strategies preserve calibration-only coefficients
%       and residual pools while updating observed lag history and the current
%       reported-case SIRS proxy state at each origin.
%
%   Workflow:
%       1. Load and validate the prepared data and local-selection artifacts.
%       2. Construct one common held-out forecast-origin grid.
%       3. Fit the two fixed Part A models on the calibration block.
%       4. Generate and validate all six forecast combinations in memory.
%       5. Verify deterministic reproduction and common-random-number equality.
%       6. Commit the complete six-artifact set through validated temporary files.
%
%   See also PARTC_CONFIG, PARTC_01_PREPARE_DATA, ...
%            PARTC_02_SELECT_LOCAL_ORDERS, FORECAST_OPEN, FORECAST_CLOSED, ...
%            SIRS_INIT, SIRS_STEP.
%
% A. M. Kaahin 2026-08-06

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Held-Out Forecast Generation ===\n');

cfg = partC_config();
forecast_configurations = cfg.final_forecast.configurations;
strategies = cfg.final_forecast.strategies;

local_validate_forecast_configuration(forecast_configurations, strategies);

%% 2. Load and Validate Prepared Data
prepared = local_load_prepared_data(cfg);

fprintf('Prepared-data period: %s to %s\n', ...
    string(prepared.dates(1)), string(prepared.dates(end)));
fprintf('Calibration boundary: %s\n', ...
    string(cfg.validation.calibration_end_date));

%% 3. Build Common Held-Out Origins
[forecast_origin_indices, forecast_origin_dates] = ...
    local_build_forecast_origins(prepared, cfg);

fprintf('Held-out forecast origins: %d\n', ...
    numel(forecast_origin_indices));

%% 4. Load and Validate Selection Artifacts
num_configurations = numel(forecast_configurations);
selections = cell(num_configurations, 1);

for configuration_index = 1:num_configurations
    selections{configuration_index} = local_load_selection_artifact( ...
        forecast_configurations(configuration_index), cfg);
end

%% 5. Prepare the Reusable Closed-Loop SIRS Stepper
sirs_parameters = struct( ...
    "gamma", cfg.state_reconstruction.gamma, ...
    "xi", cfg.state_reconstruction.xi, ...
    "pop_size", cfg.state_reconstruction.effective_population, ...
    "min_susceptible", cfg.state_reconstruction.min_susceptible);
step_options = struct( ...
    "solver", "uds", ...
    "seed", cfg.final_forecast.base_seed);
base_stepper = sirs_init(sirs_parameters, step_options);

%% 6. Generate All Forecast Artifacts in Memory
num_strategies = numel(strategies);
artifacts = cell(num_configurations, num_strategies);
canonical_paths = strings(num_configurations, num_strategies);
fixed_fits = cell(num_configurations, 1);

for configuration_index = 1:num_configurations
    active_configuration = forecast_configurations(configuration_index);
    selection = selections{configuration_index};

    fprintf('\nModel: %s | Exogenous mode: %s\n', ...
        active_configuration.model_type, active_configuration.exo_mode);

    fixed_fits{configuration_index} = local_fit_fixed_model( ...
        active_configuration, selection.partA_selected_configuration, ...
        prepared, cfg);

    for strategy_index = 1:num_strategies
        active_strategy = strategies(strategy_index);
        [forecast_configuration, fixed_fit_info] = ...
            local_resolve_strategy(active_strategy, selection, ...
            fixed_fits{configuration_index});

        fprintf('Strategy: %s\n', active_strategy.identifier);
        fprintf('Forecast configuration: %s\n', ...
            mat2str(forecast_configuration));

        results = local_run_forecasts( ...
            active_configuration, active_strategy, ...
            forecast_configuration, fixed_fit_info, prepared, ...
            forecast_origin_indices, base_stepper, ...
            configuration_index, cfg);

        artifact = local_build_artifact( ...
            active_configuration, active_strategy, ...
            forecast_configuration, fixed_fit_info, selection, ...
            results, cfg);
        local_validate_artifact(artifact, prepared, ...
            forecast_origin_indices, forecast_origin_dates, cfg);

        artifacts{configuration_index, strategy_index} = artifact;
        canonical_paths(configuration_index, strategy_index) = ...
            local_canonical_path(active_configuration, ...
            active_strategy.identifier, cfg.output.forecast_dir);
    end
end

%% 7. Validate the Complete Forecast Stage
local_validate_artifact_set(artifacts, selections, prepared, ...
    forecast_origin_indices, forecast_origin_dates, cfg);
local_verify_representative_origins(artifacts, fixed_fits, prepared, ...
    forecast_origin_indices, base_stepper, cfg);

%% 8. Commit the Complete Artifact Set
local_commit_artifacts(artifacts, canonical_paths, cfg.output.forecast_dir);

for artifact_index = 1:numel(canonical_paths)
    fprintf('Saved artifact: %s\n', canonical_paths(artifact_index));
end

fprintf('\n=== Part C Held-Out Forecast Generation Complete ===\n\n');

%% 9. Local Functions
function local_validate_forecast_configuration(configurations, strategies)
%LOCAL_VALIDATE_FORECAST_CONFIGURATION Validate the supported final protocol.
valid_configurations = numel(configurations) == 2 && ...
    configurations(1).model_type == "AR" && ...
    configurations(1).exo_mode == "None" && ...
    configurations(2).model_type == "ARX" && ...
    configurations(2).exo_mode == "I";
expected_strategies = [ ...
    "partA_online_fit"
    "local_online_fit"
    "partA_fixed_fit"];
actual_strategies = [strategies.identifier].';

if ~valid_configurations
    error('PARTC_03:UnsupportedConfigurationList', ...
        'Final forecasts require exactly AR/None and ARX/I in that order.');
end

if ~isequal(actual_strategies, expected_strategies)
    error('PARTC_03:UnsupportedStrategyList', ...
        'Final forecasts require the three configured transfer strategies in their canonical order.');
end
end

function prepared = local_load_prepared_data(cfg)
%LOCAL_LOAD_PREPARED_DATA Load and validate the shared prepared artifact.
prepared_artifact_path = cfg.output.prepared_artifact_path;

if exist(prepared_artifact_path, 'file') ~= 2
    error('PARTC_03:MissingPreparedArtifact', ...
        'Missing prepared Part C artifact: %s. Run Part C Script 1 first.', ...
        prepared_artifact_path);
end

loaded = load(prepared_artifact_path);
required_fields = {
    'dates'
    'Rt_estimated'
    'Rt_valid_mask'
    'I_fraction_proxy'
    'S_proxy'
    'I_proxy'
    'R_proxy'
    'state_valid_mask'
    'preparation_snapshot'
    };

if ~all(isfield(loaded, required_fields))
    missing_fields = required_fields(~isfield(loaded, required_fields));
    error('PARTC_03:MissingPreparedFields', ...
        'Prepared Part C artifact is missing fields: %s.', ...
        strjoin(string(missing_fields), ', '));
end

dates = loaded.dates;
Rt_estimated = loaded.Rt_estimated;
Rt_valid_mask = loaded.Rt_valid_mask;
I_fraction_proxy = loaded.I_fraction_proxy;
S_proxy = loaded.S_proxy;
I_proxy = loaded.I_proxy;
R_proxy = loaded.R_proxy;
state_valid_mask = loaded.state_valid_mask;

if ~isdatetime(dates) || ~iscolumn(dates) || any(isnat(dates))
    error('PARTC_03:InvalidPreparedDates', ...
        'Prepared dates must be a valid datetime column vector.');
end

if numel(unique(dates)) ~= numel(dates) || ...
        any(diff(dates) ~= days(1))
    error('PARTC_03:InvalidPreparedDates', ...
        'Prepared dates must be unique, strictly increasing, and daily.');
end

if dates(1) ~= cfg.study.start_date || dates(end) ~= cfg.study.end_date
    error('PARTC_03:PreparedStudyPeriodMismatch', ...
        'Prepared dates must match the configured Part C study period exactly.');
end

numeric_signals = {
    Rt_estimated
    I_fraction_proxy
    S_proxy
    I_proxy
    R_proxy
    };
numeric_signal_names = [ ...
    "Rt_estimated"
    "I_fraction_proxy"
    "S_proxy"
    "I_proxy"
    "R_proxy"];

for signal_index = 1:numel(numeric_signals)
    signal = numeric_signals{signal_index};
    if ~isnumeric(signal) || ~isreal(signal) || ~iscolumn(signal)
        error('PARTC_03:InvalidPreparedSignal', ...
            '%s must be a real numeric column vector.', ...
            numeric_signal_names(signal_index));
    end
end

if ~islogical(Rt_valid_mask) || ~iscolumn(Rt_valid_mask) || ...
        ~islogical(state_valid_mask) || ~iscolumn(state_valid_mask)
    error('PARTC_03:InvalidPreparedMask', ...
        'Rt_valid_mask and state_valid_mask must be logical column vectors.');
end

signal_lengths = [ ...
    numel(Rt_estimated)
    numel(Rt_valid_mask)
    numel(I_fraction_proxy)
    numel(S_proxy)
    numel(I_proxy)
    numel(R_proxy)
    numel(state_valid_mask)];

if any(signal_lengths ~= numel(dates))
    error('PARTC_03:PreparedLengthMismatch', ...
        'All prepared signals and masks must match the dates vector length.');
end

expected_Rt_valid_mask = isfinite(Rt_estimated) & Rt_estimated > 0;
if ~isequal(Rt_valid_mask, expected_Rt_valid_mask)
    error('PARTC_03:EstimatedRtMaskMismatch', ...
        'Rt_valid_mask must equal isfinite(Rt_estimated) & Rt_estimated > 0.');
end

first_valid_index = find(Rt_valid_mask, 1);
expected_first_valid_index = ...
    cfg.renewal.serial_interval_max_lag_days + 1;
valid_Rt_block = ~isempty(first_valid_index) && ...
    first_valid_index == expected_first_valid_index && ...
    ~any(Rt_valid_mask(1:first_valid_index - 1)) && ...
    all(Rt_valid_mask(first_valid_index:end));

if ~valid_Rt_block
    error('PARTC_03:InvalidEstimatedRtBlock', ...
        'Rt_estimated must have one contiguous valid block beginning immediately after the renewal warm-up and continuing through study end.');
end

if any(~isfinite(I_fraction_proxy)) || ...
        any(I_fraction_proxy < 0 | I_fraction_proxy > 1)
    error('PARTC_03:InvalidInfectiousFractionProxy', ...
        'I_fraction_proxy must be finite and within [0, 1].');
end

if ~all(state_valid_mask)
    error('PARTC_03:InvalidStateMask', ...
        'Every prepared proxy-state row must satisfy state_valid_mask.');
end

proxy_states = [S_proxy, I_proxy, R_proxy];
if any(~isfinite(proxy_states), 'all')
    error('PARTC_03:InvalidProxyStates', ...
        'Every prepared proxy state must be finite.');
end

if any(S_proxy <= cfg.state_reconstruction.min_susceptible)
    error('PARTC_03:SusceptibleBelowThreshold', ...
        'Every susceptible proxy must exceed the configured threshold.');
end

if any(I_proxy < 0) || any(R_proxy < 0)
    error('PARTC_03:NegativeProxyState', ...
        'Infectious and recovered proxies must be nonnegative.');
end

state_sum_error = abs(sum(proxy_states, 2) - ...
    cfg.state_reconstruction.effective_population);
if any(state_sum_error > ...
        cfg.state_reconstruction.conservation_tolerance)
    error('PARTC_03:StateConservationFailure', ...
        'Prepared proxy states do not conserve the effective population.');
end

if ~isequaln(loaded.preparation_snapshot, cfg.snapshot.preparation)
    error('PARTC_03:PreparationSnapshotMismatch', ...
        'Prepared Part C artifact does not match the current preparation configuration.');
end

calibration_end_index = find( ...
    dates == cfg.validation.calibration_end_date, 1);
test_start_index = find(dates == cfg.validation.test_start_date, 1);

if isempty(calibration_end_index) || isempty(test_start_index)
    error('PARTC_03:MissingValidationBoundary', ...
        'Prepared dates must contain the configured calibration end and test start dates.');
end

prepared = struct( ...
    "dates", dates, ...
    "Rt_estimated", Rt_estimated, ...
    "Rt_valid_mask", Rt_valid_mask, ...
    "I_fraction_proxy", I_fraction_proxy, ...
    "S_proxy", S_proxy, ...
    "I_proxy", I_proxy, ...
    "R_proxy", R_proxy, ...
    "state_valid_mask", state_valid_mask, ...
    "first_valid_index", first_valid_index, ...
    "calibration_end_index", calibration_end_index, ...
    "test_start_index", test_start_index, ...
    "preparation_snapshot", loaded.preparation_snapshot, ...
    "artifact_path", prepared_artifact_path);
end

function [origin_indices, origin_dates] = ...
        local_build_forecast_origins(prepared, cfg)
%LOCAL_BUILD_FORECAST_ORIGINS Build the common held-out origin grid.
horizon = cfg.final_forecast.horizon;
step_size = cfg.final_forecast.step_size;
last_valid_origin_index = numel(prepared.dates) - horizon;
origin_indices = (prepared.calibration_end_index:step_size: ...
    last_valid_origin_index).';

if isempty(origin_indices)
    error('PARTC_03:NoHeldOutOrigins', ...
        'The prepared study period is too short for held-out forecasts.');
end

origin_dates = prepared.dates(origin_indices);
if origin_dates(1) ~= cfg.validation.calibration_end_date
    error('PARTC_03:InvalidFirstOrigin', ...
        'The first held-out forecast origin must be the calibration end date.');
end

for origin_position = 1:numel(origin_indices)
    target_indices = origin_indices(origin_position) + (1:horizon);
    target_dates = prepared.dates(target_indices);

    if target_dates(1) < cfg.validation.test_start_date || ...
            any(target_dates < cfg.validation.test_start_date) || ...
            target_dates(end) > cfg.study.end_date || ...
            target_indices(end) > numel(prepared.dates)
        error('PARTC_03:InvalidHeldOutTargets', ...
            'Forecast targets must remain inside the configured held-out study period.');
    end
end

if prepared.dates(origin_indices(1) + 1) ~= ...
        cfg.validation.test_start_date
    error('PARTC_03:InvalidFirstTarget', ...
        'The first held-out target must be the configured test start date.');
end
end

function selection = local_load_selection_artifact(configuration, cfg)
%LOCAL_LOAD_SELECTION_ARTIFACT Load one validated Script 2 artifact.
artifact_path = configuration.selection_artifact_path;

if exist(artifact_path, 'file') ~= 2
    error('PARTC_03:MissingSelectionArtifact', ...
        'Missing Script 2 artifact for %s/%s: %s. Run Part C Script 2 first.', ...
        configuration.model_type, configuration.exo_mode, artifact_path);
end

selection = load(artifact_path);
required_fields = {
    'model_type'
    'exo_mode'
    'strategy'
    'partA_selected_configuration'
    'candidate_configurations'
    'candidate_feasible_mask'
    'selected_index'
    'selected_configuration'
    'preparation_snapshot'
    'local_selection_snapshot'
    'prepared_artifact_path'
    };

if ~all(isfield(selection, required_fields))
    missing_fields = required_fields(~isfield(selection, required_fields));
    error('PARTC_03:MissingSelectionFields', ...
        'Script 2 artifact for %s/%s is missing fields: %s.', ...
        configuration.model_type, configuration.exo_mode, ...
        strjoin(string(missing_fields), ', '));
end

if selection.model_type ~= configuration.model_type || ...
        selection.exo_mode ~= configuration.exo_mode || ...
        selection.strategy ~= "local_order_online_fit"
    error('PARTC_03:SelectionMetadataMismatch', ...
        'Script 2 artifact metadata does not match %s/%s local selection.', ...
        configuration.model_type, configuration.exo_mode);
end

local_configuration_index = find( ...
    [cfg.local_selection.configurations.model_type] == ...
    configuration.model_type & ...
    [cfg.local_selection.configurations.exo_mode] == ...
    configuration.exo_mode, 1);

if isempty(local_configuration_index)
    error('PARTC_03:MissingLocalSelectionConfiguration', ...
        'No local-selection configuration exists for %s/%s.', ...
        configuration.model_type, configuration.exo_mode);
end

expected_local_snapshot = cfg.local_selection.configurations( ...
    local_configuration_index).local_selection_snapshot;

if ~isequaln(selection.preparation_snapshot, cfg.snapshot.preparation) || ...
        ~isequaln(selection.local_selection_snapshot, ...
        expected_local_snapshot)
    error('PARTC_03:SelectionSnapshotMismatch', ...
        'Script 2 artifact for %s/%s is incompatible with the current Part C snapshots.', ...
        configuration.model_type, configuration.exo_mode);
end

if ~isequal(selection.prepared_artifact_path, ...
        cfg.output.prepared_artifact_path)
    error('PARTC_03:PreparedArtifactPathMismatch', ...
        'Script 2 artifact for %s/%s references a different prepared artifact.', ...
        configuration.model_type, configuration.exo_mode);
end

candidate_configurations = selection.candidate_configurations;
candidate_feasible_mask = selection.candidate_feasible_mask;
selected_index = selection.selected_index;
num_candidates = size(candidate_configurations, 1);

if ~isnumeric(candidate_configurations) || ...
        ~isreal(candidate_configurations) || ...
        any(~isfinite(candidate_configurations), 'all') || ...
        any(candidate_configurations < 1, 'all') || ...
        any(mod(candidate_configurations, 1) ~= 0, 'all')
    error('PARTC_03:InvalidCandidateConfigurations', ...
        'Script 2 candidate configurations must contain positive integers.');
end

if ~islogical(candidate_feasible_mask) || ...
        ~iscolumn(candidate_feasible_mask) || ...
        numel(candidate_feasible_mask) ~= num_candidates
    error('PARTC_03:InvalidCandidateFeasibility', ...
        'Script 2 candidate_feasible_mask must align with candidate configurations.');
end

if ~isnumeric(selected_index) || ~isscalar(selected_index) || ...
        ~isfinite(selected_index) || mod(selected_index, 1) ~= 0 || ...
        selected_index < 1 || selected_index > num_candidates
    error('PARTC_03:InvalidSelectedIndex', ...
        'Script 2 selected_index is outside the candidate grid.');
end

local_validate_model_configuration( ...
    selection.partA_selected_configuration, configuration.model_type, ...
    'partA_selected_configuration');
local_validate_model_configuration( ...
    selection.selected_configuration, configuration.model_type, ...
    'selected_configuration');

expected_columns = 1;
if configuration.model_type == "ARX"
    expected_columns = 3;
end

if size(candidate_configurations, 2) ~= expected_columns || ...
        ~ismember(selection.selected_configuration, ...
        candidate_configurations, 'rows') || ...
        ~isequal(candidate_configurations(selected_index, :), ...
        selection.selected_configuration) || ...
        ~candidate_feasible_mask(selected_index)
    error('PARTC_03:InvalidSelectedCandidate', ...
        'The Script 2 selected configuration must be the feasible candidate at selected_index.');
end

selection.artifact_path = artifact_path;
end

function local_validate_model_configuration(configuration, model_type, field_name)
%LOCAL_VALIDATE_MODEL_CONFIGURATION Validate one AR or ARX order vector.
valid_values = isnumeric(configuration) && isreal(configuration) && ...
    all(isfinite(configuration)) && all(configuration >= 1) && ...
    all(mod(configuration, 1) == 0);

if model_type == "AR"
    valid_dimensions = isscalar(configuration);
else
    valid_dimensions = isequal(size(configuration), [1, 3]);
end

if ~valid_values || ~valid_dimensions
    error('PARTC_03:InvalidModelConfiguration', ...
        '%s has an invalid %s configuration contract.', ...
        field_name, model_type);
end
end

function fixed_fit_info = local_fit_fixed_model( ...
        active_configuration, configuration, prepared, cfg)
%LOCAL_FIT_FIXED_MODEL Fit one Part A configuration on calibration data.
calibration_indices = prepared.first_valid_index: ...
    prepared.calibration_end_index;
calibration_Rt = prepared.Rt_estimated(calibration_indices);
calibration_dates = prepared.dates(calibration_indices);

switch active_configuration.model_type
    case "AR"
        fixed_fit_info = local_fit_fixed_ar( ...
            configuration, calibration_Rt, calibration_dates);
    case "ARX"
        calibration_U = ...
            prepared.I_fraction_proxy(calibration_indices);
        fixed_fit_info = local_fit_fixed_arx( ...
            configuration, calibration_Rt, calibration_U, ...
            calibration_dates);
end

if fixed_fit_info.calibration_end_date ~= ...
        cfg.validation.calibration_end_date
    error('PARTC_03:FixedFitCalibrationLeakage', ...
        'Fixed model fitting must end at the calibration boundary.');
end
end

function fit_info = local_fit_fixed_ar(configuration, calibration_Rt, dates)
%LOCAL_FIT_FIXED_AR Fit a calibration-only AR model on log Rt.
p = configuration(1);
y = log(calibration_Rt);

if std(y) < 1e-8
    error('FORECAST_OPEN:ConstantSeries', ...
        'log(calibration_Rt) is effectively constant (std < 1e-8); cannot fit AR model.');
end

if numel(y) <= p + 1
    error('FORECAST_OPEN:InsufficientHistory', ...
        'AR calibration history is too short for the selected order.');
end

sys = ar(iddata(y, [], 1), p, 'burg');
aicc = sys.Report.Fit.AICc;
a_coefficients = sys.A(2:end);

num_observations = numel(y);
residuals = zeros(num_observations - p, 1);
for observation_index = (p + 1):num_observations
    prediction = -(a_coefficients * ...
        y(observation_index - 1:-1:observation_index - p));
    residuals(observation_index - p) = ...
        y(observation_index) - prediction;
end
residuals = residuals(isfinite(residuals));

if numel(residuals) < 2
    error('FORECAST_OPEN:InsufficientResiduals', ...
        'Fewer than two finite AR calibration residuals are available.');
end

centred_residuals = residuals - mean(residuals);
fit_info = struct( ...
    "configuration", configuration, ...
    "A_coefficients", a_coefficients, ...
    "B_coefficients", [], ...
    "max_lag", p, ...
    "centred_calibration_residuals", centred_residuals, ...
    "residual_count", numel(centred_residuals), ...
    "calibration_AICc", aicc, ...
    "calibration_start_date", dates(1), ...
    "calibration_end_date", dates(end));
end

function fit_info = local_fit_fixed_arx( ...
        configuration, calibration_Rt, calibration_U, dates)
%LOCAL_FIT_FIXED_ARX Fit a calibration-only ARX/I model on log Rt.
na = configuration(1);
nb = configuration(2);
nk = configuration(3);
y = log(calibration_Rt);
num_observations = numel(y);
max_lag = max(na, nk + nb - 1);

if std(y) < 1e-8
    error('FORECAST_CLOSED:ConstantSeries', ...
        'log(calibration_Rt) is effectively constant (std < 1e-8); cannot fit ARX model.');
end

if num_observations - max_lag < 2
    error('FORECAST_CLOSED:InsufficientHistory', ...
        'ARX calibration history is too short for the selected configuration.');
end

sys = arx(iddata(y, calibration_U, 1), [na, nb, nk]);
aicc = sys.Report.Fit.AICc;
a_coefficients = sys.A(2:end);
b_coefficients = local_extract_active_b(sys.B, nb, nk);

residuals = zeros(num_observations - max_lag, 1);
for observation_index = (max_lag + 1):num_observations
    prediction = local_arx_step(a_coefficients, b_coefficients, ...
        na, nb, nk, y(1:observation_index - 1), ...
        calibration_U(1:observation_index - 1));
    residuals(observation_index - max_lag) = ...
        y(observation_index) - prediction;
end
residuals = residuals(isfinite(residuals));

if numel(residuals) < 2
    error('FORECAST_CLOSED:InsufficientResiduals', ...
        'Fewer than two finite ARX calibration residuals are available.');
end

centred_residuals = residuals - mean(residuals);
fit_info = struct( ...
    "configuration", configuration, ...
    "A_coefficients", a_coefficients, ...
    "B_coefficients", b_coefficients, ...
    "max_lag", max_lag, ...
    "centred_calibration_residuals", centred_residuals, ...
    "residual_count", numel(centred_residuals), ...
    "calibration_AICc", aicc, ...
    "calibration_start_date", dates(1), ...
    "calibration_end_date", dates(end));
end

function b_coefficients = local_extract_active_b(B_property, nb, nk)
%LOCAL_EXTRACT_ACTIVE_B Extract the active single-input ARX coefficients.
if iscell(B_property)
    b_coefficients = B_property{1}(nk + 1:nk + nb);
else
    b_coefficients = B_property(nk + 1:nk + nb);
end
end

function [configuration, fixed_fit_info] = ...
        local_resolve_strategy(strategy, selection, fixed_fit)
%LOCAL_RESOLVE_STRATEGY Resolve configuration and fixed-fit metadata.
switch strategy.identifier
    case "partA_online_fit"
        configuration = selection.partA_selected_configuration;
        fixed_fit_info = struct();
    case "local_online_fit"
        configuration = selection.selected_configuration;
        fixed_fit_info = struct();
    case "partA_fixed_fit"
        configuration = selection.partA_selected_configuration;
        fixed_fit_info = fixed_fit;
end
end

function results = local_run_forecasts( ...
        active_configuration, strategy, forecast_configuration, ...
        fixed_fit_info, prepared, origin_indices, base_stepper, ...
        configuration_index, cfg)
%LOCAL_RUN_FORECASTS Generate one model-strategy result array.
result_template = struct( ...
    "origin_index", [], ...
    "origin_date", NaT, ...
    "target_indices", [], ...
    "target_dates", NaT(0, 1), ...
    "target_Rt_estimated", [], ...
    "forecast_median", [], ...
    "forecast_lower", [], ...
    "forecast_upper", [], ...
    "fit_AICc", [], ...
    "resample_seed", [], ...
    "epidemic_seed", []);
results = repmat(result_template, numel(origin_indices), 1);

for origin_position = 1:numel(origin_indices)
    origin_index = origin_indices(origin_position);
    origin_date = prepared.dates(origin_index);

    try
        results(origin_position) = local_generate_origin_result( ...
            active_configuration, strategy, forecast_configuration, ...
            fixed_fit_info, prepared, origin_index, origin_position, ...
            base_stepper, configuration_index, cfg);
    catch underlying_error
        contextual_error = MException( ...
            'PARTC_03:ForecastCombinationFailed', ...
            ['Model %s, exogenous mode %s, strategy %s, configuration %s ' ...
            'failed at origin index %d (%s). Underlying error %s: %s'], ...
            active_configuration.model_type, ...
            active_configuration.exo_mode, strategy.identifier, ...
            mat2str(forecast_configuration), origin_index, ...
            string(origin_date), underlying_error.identifier, ...
            underlying_error.message);
        contextual_error = addCause(contextual_error, underlying_error);
        throw(contextual_error);
    end

    if mod(origin_position, 5) == 0 || ...
            origin_position == numel(origin_indices)
        fprintf('Completed origins: %d/%d\n', ...
            origin_position, numel(origin_indices));
    end
end
end

function result = local_generate_origin_result( ...
        active_configuration, strategy, forecast_configuration, ...
        fixed_fit_info, prepared, origin_index, origin_position, ...
        base_stepper, configuration_index, cfg)
%LOCAL_GENERATE_ORIGIN_RESULT Generate and summarize one forecast origin.
horizon = cfg.final_forecast.horizon;
num_draws = cfg.final_forecast.num_draws;
wis_alphas = cfg.final_forecast.wis_alphas;
history_indices = prepared.first_valid_index:origin_index;
Rt_past = prepared.Rt_estimated(history_indices);
target_indices = (origin_index + (1:horizon)).';
target_dates = prepared.dates(target_indices);
resample_seed = cfg.final_forecast.base_seed + ...
    100000 * configuration_index + origin_position;
epidemic_seed = [];

if active_configuration.model_type == "AR"
    if strategy.parameter_update_mode == "online"
        [ensemble_paths, fit_info] = forecast_open( ...
            "AR", forecast_configuration, Rt_past, ...
            num_draws, horizon, resample_seed);
        fit_AICc = fit_info.AICc;
    else
        ensemble_paths = local_forecast_fixed_ar( ...
            fixed_fit_info, Rt_past, num_draws, horizon, resample_seed);
        fit_AICc = fixed_fit_info.calibration_AICc;
    end
else
    U_past = prepared.I_fraction_proxy(history_indices);
    sirs_state = [ ...
        prepared.S_proxy(origin_index), ...
        prepared.I_proxy(origin_index), ...
        prepared.R_proxy(origin_index)];
    epidemic_seed = resample_seed + 1000000;

    if strategy.parameter_update_mode == "online"
        [ensemble_paths, fit_info] = forecast_closed( ...
            "ARX", forecast_configuration, Rt_past, U_past, ...
            sirs_state, 1, num_draws, horizon, "I", base_stepper, ...
            resample_seed, epidemic_seed, ...
            cfg.final_forecast.include_epidemic_seed_variation);
        fit_AICc = fit_info.AICc;
    else
        ensemble_paths = local_forecast_fixed_arx( ...
            fixed_fit_info, Rt_past, U_past, sirs_state, ...
            num_draws, horizon, base_stepper, resample_seed, ...
            epidemic_seed, ...
            cfg.final_forecast.include_epidemic_seed_variation);
        fit_AICc = fixed_fit_info.calibration_AICc;
    end
end

forecast_median = median(ensemble_paths, 2);
forecast_lower = quantile( ...
    ensemble_paths, wis_alphas.' / 2, 2);
forecast_upper = quantile( ...
    ensemble_paths, 1 - wis_alphas.' / 2, 2);
target_Rt_estimated = prepared.Rt_estimated(target_indices);

local_validate_forecast_summary(ensemble_paths, forecast_median, ...
    forecast_lower, forecast_upper, cfg);

result = struct( ...
    "origin_index", origin_index, ...
    "origin_date", prepared.dates(origin_index), ...
    "target_indices", target_indices, ...
    "target_dates", target_dates, ...
    "target_Rt_estimated", target_Rt_estimated, ...
    "forecast_median", forecast_median, ...
    "forecast_lower", forecast_lower, ...
    "forecast_upper", forecast_upper, ...
    "fit_AICc", fit_AICc, ...
    "resample_seed", resample_seed, ...
    "epidemic_seed", epidemic_seed);
end

function ensemble = local_forecast_fixed_ar( ...
        fit_info, Rt_past, num_draws, horizon, resample_seed)
%LOCAL_FORECAST_FIXED_AR Forecast with fixed AR coefficients and residuals.
p = fit_info.configuration(1);
y = log(Rt_past);
innovations = local_resample_centred( ...
    fit_info.centred_calibration_residuals, horizon, num_draws, ...
    resample_seed);

seed_values = y(end - p + 1:end);
rolling_y = [repmat(seed_values, 1, num_draws); ...
    zeros(horizon, num_draws)];
ensemble = zeros(horizon, num_draws);

for horizon_index = 1:horizon
    recent = rolling_y(horizon_index:horizon_index + p - 1, :);
    prediction = -(fit_info.A_coefficients * flipud(recent));
    y_next = prediction + innovations(horizon_index, :);
    Rt_next = exp(y_next);

    if ~all(isfinite(Rt_next) & Rt_next > 0)
        error('FORECAST_OPEN:InvalidForecastDraw', ...
            'Fixed AR bootstrap draw produced a non-finite or non-positive Rt.');
    end

    ensemble(horizon_index, :) = Rt_next;
    rolling_y(p + horizon_index, :) = y_next;
end
end

function ensemble = local_forecast_fixed_arx( ...
        fit_info, Rt_past, U_past, sirs_state, num_draws, horizon, ...
        base_stepper, resample_seed, epidemic_seed, vary_epidemic_seed)
%LOCAL_FORECAST_FIXED_ARX Forecast with fixed ARX coefficients and residuals.
configuration = fit_info.configuration;
na = configuration(1);
nb = configuration(2);
nk = configuration(3);
y = log(Rt_past);
num_observations = numel(y);
innovations = local_resample_centred( ...
    fit_info.centred_calibration_residuals, horizon, num_draws, ...
    resample_seed);
pop_size = base_stepper.model_params.pop_size;
min_susceptible = base_stepper.model_params.min_susceptible;

rolling_y = [y; zeros(horizon, 1)];
rolling_U = [U_past; zeros(horizon, 1)];
ensemble = zeros(horizon, num_draws);

for draw_index = 1:num_draws
    draw_seed = local_draw_seed( ...
        epidemic_seed, draw_index, horizon, vary_epidemic_seed);
    stepper = base_stepper;
    stepper.seed = draw_seed;
    stepper.call_count = 0;
    state = sirs_state;
    draw_y = rolling_y;
    draw_U = rolling_U;

    for horizon_index = 1:horizon
        prediction = local_arx_step( ...
            fit_info.A_coefficients, fit_info.B_coefficients, ...
            na, nb, nk, draw_y(1:num_observations + horizon_index - 1), ...
            draw_U(1:num_observations + horizon_index - 1));
        y_next = prediction + innovations(horizon_index, draw_index);
        Rt_next = exp(y_next);

        if ~isfinite(Rt_next) || Rt_next <= 0
            error('FORECAST_CLOSED:InvalidForecastDraw', ...
                'Fixed ARX bootstrap draw produced a non-finite or non-positive Rt.');
        end

        [state, stepper] = sirs_step(stepper, state, Rt_next);
        if state(1) <= min_susceptible
            error('EPIDEMIC:SusceptibleBelowThreshold', ...
                'Forecasted SIRS state crossed the susceptible-domain threshold.');
        end

        ensemble(horizon_index, draw_index) = Rt_next;
        draw_y(num_observations + horizon_index) = y_next;
        draw_U(num_observations + horizon_index) = state(2) / pop_size;
    end
end
end

function prediction = local_arx_step( ...
        a_coefficients, b_coefficients, na, nb, nk, log_history, U_history)
%LOCAL_ARX_STEP Compute one ARX/I prediction from aligned histories.
num_observations = numel(log_history);
prediction = 0;

for lag = 1:na
    prediction = prediction - a_coefficients(lag) * ...
        log_history(num_observations + 1 - lag);
end

for coefficient_index = 1:nb
    input_lag = nk + coefficient_index - 1;
    prediction = prediction + b_coefficients(coefficient_index) * ...
        U_history(num_observations + 1 - input_lag);
end
end

function innovations = local_resample_centred( ...
        centred_residuals, horizon, num_draws, resample_seed)
%LOCAL_RESAMPLE_CENTRED Resample a fixed centred pool with isolated RNG state.
caller_state = rng;
cleanup = onCleanup(@() rng(caller_state));
rng(resample_seed, 'twister');
residual_indices = randi( ...
    numel(centred_residuals), horizon, num_draws);
innovations = centred_residuals(residual_indices);
clear cleanup;
end

function seed = local_draw_seed(base_seed, draw_index, horizon, vary)
%LOCAL_DRAW_SEED Derive the shared per-draw epidemic seed.
seed = base_seed;
if vary
    seed = base_seed + (draw_index - 1) * (horizon + 1);
end
end

function local_validate_forecast_summary( ...
        ensemble, forecast_median, forecast_lower, forecast_upper, cfg)
%LOCAL_VALIDATE_FORECAST_SUMMARY Validate one forecast ensemble and summary.
horizon = cfg.final_forecast.horizon;
num_draws = cfg.final_forecast.num_draws;
num_alphas = numel(cfg.final_forecast.wis_alphas);

valid = isequal(size(ensemble), [horizon, num_draws]) && ...
    all(isfinite(ensemble), 'all') && all(ensemble > 0, 'all') && ...
    isequal(size(forecast_median), [horizon, 1]) && ...
    all(isfinite(forecast_median)) && all(forecast_median > 0) && ...
    isequal(size(forecast_lower), [horizon, num_alphas]) && ...
    isequal(size(forecast_upper), [horizon, num_alphas]) && ...
    all(isfinite(forecast_lower), 'all') && ...
    all(isfinite(forecast_upper), 'all') && ...
    all(forecast_lower <= forecast_upper, 'all');

if ~valid
    error('PARTC_03:InvalidForecastSummary', ...
        'Forecast ensemble or prediction-interval summary is invalid.');
end
end

function artifact = local_build_artifact( ...
        active_configuration, strategy, forecast_configuration, ...
        fixed_fit_info, selection, results, cfg)
%LOCAL_BUILD_ARTIFACT Assemble one final forecast artifact.
artifact = struct( ...
    "model_type", active_configuration.model_type, ...
    "exo_mode", active_configuration.exo_mode, ...
    "strategy", strategy.identifier, ...
    "strategy_description", strategy.description, ...
    "configuration_source", strategy.configuration_source, ...
    "parameter_update_mode", strategy.parameter_update_mode, ...
    "forecast_configuration", forecast_configuration, ...
    "partA_selected_configuration", ...
    selection.partA_selected_configuration, ...
    "local_selected_configuration", selection.selected_configuration, ...
    "selection_artifact_path", selection.artifact_path, ...
    "prepared_artifact_path", cfg.output.prepared_artifact_path, ...
    "calibration_end_date", cfg.validation.calibration_end_date, ...
    "test_start_date", cfg.validation.test_start_date, ...
    "study_end_date", cfg.study.end_date, ...
    "wis_alphas", cfg.final_forecast.wis_alphas, ...
    "results", results, ...
    "fixed_fit_info", fixed_fit_info, ...
    "preparation_snapshot", selection.preparation_snapshot, ...
    "local_selection_snapshot", selection.local_selection_snapshot, ...
    "forecast_snapshot", cfg.snapshot.forecast);
end

function local_validate_artifact(artifact, prepared, ...
        origin_indices, origin_dates, cfg)
%LOCAL_VALIDATE_ARTIFACT Validate one complete in-memory artifact.
required_artifact_fields = {
    'model_type'
    'exo_mode'
    'strategy'
    'strategy_description'
    'configuration_source'
    'parameter_update_mode'
    'forecast_configuration'
    'partA_selected_configuration'
    'local_selected_configuration'
    'selection_artifact_path'
    'prepared_artifact_path'
    'calibration_end_date'
    'test_start_date'
    'study_end_date'
    'wis_alphas'
    'results'
    'fixed_fit_info'
    'preparation_snapshot'
    'local_selection_snapshot'
    'forecast_snapshot'
    };
required_result_fields = {
    'origin_index'
    'origin_date'
    'target_indices'
    'target_dates'
    'target_Rt_estimated'
    'forecast_median'
    'forecast_lower'
    'forecast_upper'
    'fit_AICc'
    'resample_seed'
    'epidemic_seed'
    };

if ~all(isfield(artifact, required_artifact_fields))
    error('PARTC_03:MissingArtifactFields', ...
        'A final forecast artifact is missing required fields.');
end

if numel(artifact.results) ~= numel(origin_indices) || ...
        ~all(isfield(artifact.results, required_result_fields))
    error('PARTC_03:InvalidResultContract', ...
        'Final forecast results do not satisfy the common field contract.');
end

if ~isequaln(artifact.preparation_snapshot, cfg.snapshot.preparation) || ...
        ~isequaln(artifact.forecast_snapshot, cfg.snapshot.forecast) || ...
        ~isequal(artifact.prepared_artifact_path, prepared.artifact_path) || ...
        ~isequal(artifact.wis_alphas, cfg.final_forecast.wis_alphas)
    error('PARTC_03:ArtifactSnapshotMismatch', ...
        'A final forecast artifact is incompatible with the active Part C protocol.');
end

for origin_position = 1:numel(origin_indices)
    result = artifact.results(origin_position);
    expected_target_indices = ...
        (origin_indices(origin_position) + ...
        (1:cfg.final_forecast.horizon)).';

    valid_result = result.origin_index == origin_indices(origin_position) && ...
        result.origin_date == origin_dates(origin_position) && ...
        isequal(result.target_indices, expected_target_indices) && ...
        isequal(result.target_dates, ...
        prepared.dates(expected_target_indices)) && ...
        isequaln(result.target_Rt_estimated, ...
        prepared.Rt_estimated(expected_target_indices)) && ...
        isequal(size(result.forecast_median), ...
        [cfg.final_forecast.horizon, 1]) && ...
        isequal(size(result.forecast_lower), ...
        [cfg.final_forecast.horizon, ...
        numel(cfg.final_forecast.wis_alphas)]) && ...
        isequal(size(result.forecast_upper), ...
        [cfg.final_forecast.horizon, ...
        numel(cfg.final_forecast.wis_alphas)]) && ...
        all(isfinite(result.forecast_median)) && ...
        all(result.forecast_median > 0) && ...
        all(isfinite(result.forecast_lower), 'all') && ...
        all(isfinite(result.forecast_upper), 'all') && ...
        all(result.forecast_lower <= result.forecast_upper, 'all') && ...
        isnumeric(result.fit_AICc) && isscalar(result.fit_AICc) && ...
        isnumeric(result.resample_seed) && ...
        isscalar(result.resample_seed);

    if artifact.model_type == "AR"
        valid_result = valid_result && isempty(result.epidemic_seed);
    else
        valid_result = valid_result && ...
            isnumeric(result.epidemic_seed) && ...
            isscalar(result.epidemic_seed);
    end

    if ~valid_result
        error('PARTC_03:InvalidArtifactResult', ...
            'A final forecast result is invalid at origin position %d.', ...
            origin_position);
    end
end
end

function local_validate_artifact_set(artifacts, selections, prepared, ...
        origin_indices, origin_dates, cfg)
%LOCAL_VALIDATE_ARTIFACT_SET Validate cross-artifact scientific contracts.
if ~isequal(size(artifacts), [2, 3]) || ...
        any(cellfun(@isempty, artifacts), 'all')
    error('PARTC_03:IncompleteArtifactSet', ...
        'The final forecast stage must produce exactly six artifacts.');
end

for configuration_index = 1:size(artifacts, 1)
    selection = selections{configuration_index};
    partA_online = artifacts{configuration_index, 1};
    local_online = artifacts{configuration_index, 2};
    partA_fixed = artifacts{configuration_index, 3};

    if ~isequal(partA_online.forecast_configuration, ...
            selection.partA_selected_configuration) || ...
            ~isequal(local_online.forecast_configuration, ...
            selection.selected_configuration) || ...
            ~isequal(partA_fixed.forecast_configuration, ...
            selection.partA_selected_configuration)
        error('PARTC_03:StrategyConfigurationMismatch', ...
            'A strategy does not use its required selected configuration.');
    end

    if ~isempty(fieldnames(partA_online.fixed_fit_info)) || ...
            ~isempty(fieldnames(local_online.fixed_fit_info))
        error('PARTC_03:UnexpectedOnlineFixedFit', ...
            'Online forecast artifacts must contain an empty scalar fixed_fit_info structure.');
    end

    local_validate_fixed_fit_info(partA_fixed.fixed_fit_info, ...
        prepared, selection.partA_selected_configuration, cfg);

    if isequal(selection.partA_selected_configuration, ...
            selection.selected_configuration) && ...
            ~isequaln(partA_online.results, local_online.results)
        error('PARTC_03:CommonRandomNumbersMismatch', ...
            'Equal Part A and local configurations must produce identical online forecasts.');
    end

    for strategy_index = 1:size(artifacts, 2)
        artifact = artifacts{configuration_index, strategy_index};
        local_validate_artifact(artifact, prepared, origin_indices, ...
            origin_dates, cfg);

        actual_resample_seeds = [artifact.results.resample_seed].';
        expected_resample_seeds = cfg.final_forecast.base_seed + ...
            100000 * configuration_index + ...
            (1:numel(origin_indices)).';
        if ~isequal(actual_resample_seeds, expected_resample_seeds)
            error('PARTC_03:InvalidResampleSeeds', ...
                'Residual-resampling seeds must depend only on model pair and origin position.');
        end

        if artifact.model_type == "ARX"
            actual_epidemic_seeds = [artifact.results.epidemic_seed].';
            if ~isequal(actual_epidemic_seeds, ...
                    expected_resample_seeds + 1000000)
                error('PARTC_03:InvalidEpidemicSeeds', ...
                    'ARX epidemic seeds must be derived from the corresponding residual-resampling seeds.');
            end
        end
    end
end

if origin_dates(1) ~= cfg.validation.calibration_end_date || ...
        artifacts{1, 1}.results(1).target_dates(1) ~= ...
        cfg.validation.test_start_date
    error('PARTC_03:InvalidHeldOutBoundary', ...
        'The common held-out grid has an invalid first origin or target.');
end

all_target_dates = vertcat(artifacts{1, 1}.results.target_dates);
if any(all_target_dates < cfg.validation.test_start_date) || ...
        any(all_target_dates > cfg.study.end_date)
    error('PARTC_03:TargetDateLeakage', ...
        'At least one forecast target falls outside the held-out study period.');
end
end

function local_validate_fixed_fit_info( ...
        fit_info, prepared, expected_configuration, cfg)
%LOCAL_VALIDATE_FIXED_FIT_INFO Validate calibration-only numeric metadata.
required_fields = {
    'configuration'
    'A_coefficients'
    'B_coefficients'
    'max_lag'
    'centred_calibration_residuals'
    'residual_count'
    'calibration_AICc'
    'calibration_start_date'
    'calibration_end_date'
    };

valid = all(isfield(fit_info, required_fields)) && ...
    isequal(fit_info.configuration, expected_configuration) && ...
    isnumeric(fit_info.A_coefficients) && ...
    all(isfinite(fit_info.A_coefficients)) && ...
    isnumeric(fit_info.B_coefficients) && ...
    all(isfinite(fit_info.B_coefficients)) && ...
    isnumeric(fit_info.centred_calibration_residuals) && ...
    iscolumn(fit_info.centred_calibration_residuals) && ...
    all(isfinite(fit_info.centred_calibration_residuals)) && ...
    fit_info.residual_count == ...
    numel(fit_info.centred_calibration_residuals) && ...
    fit_info.residual_count >= 2 && ...
    fit_info.calibration_start_date == ...
    prepared.dates(prepared.first_valid_index) && ...
    fit_info.calibration_end_date == ...
    cfg.validation.calibration_end_date;

if ~valid
    error('PARTC_03:InvalidFixedFitMetadata', ...
        'Fixed-fit metadata must contain one valid calibration-only numeric fit.');
end
end

function local_verify_representative_origins( ...
        artifacts, fixed_fits, prepared, origin_indices, base_stepper, cfg)
%LOCAL_VERIFY_REPRESENTATIVE_ORIGINS Reproduce one origin per combination.
forecast_configurations = cfg.final_forecast.configurations;
strategies = cfg.final_forecast.strategies;

for configuration_index = 1:size(artifacts, 1)
    active_configuration = forecast_configurations(configuration_index);

    for strategy_index = 1:size(artifacts, 2)
        strategy = strategies(strategy_index);
        artifact = artifacts{configuration_index, strategy_index};
        fixed_fit_info = struct();
        if strategy.parameter_update_mode == "fixed_calibration_fit"
            fixed_fit_info = fixed_fits{configuration_index};
        end

        reproduced = local_generate_origin_result( ...
            active_configuration, strategy, ...
            artifact.forecast_configuration, fixed_fit_info, prepared, ...
            origin_indices(1), 1, base_stepper, configuration_index, cfg);

        if ~isequaln(reproduced, artifact.results(1))
            error('PARTC_03:DeterministicReproductionFailure', ...
                'Representative origin reproduction failed for %s/%s/%s.', ...
                active_configuration.model_type, ...
                active_configuration.exo_mode, strategy.identifier);
        end
    end
end
end

function artifact_path = local_canonical_path( ...
        active_configuration, strategy, forecast_dir)
%LOCAL_CANONICAL_PATH Construct one canonical Script 3 artifact path.
filename = sprintf('partC_03_forecast_%s_%s_%s.mat', ...
    active_configuration.model_type, ...
    active_configuration.exo_mode, strategy);
artifact_path = fullfile(forecast_dir, filename);
end

function local_commit_artifacts(artifacts, canonical_paths, forecast_dir)
%LOCAL_COMMIT_ARTIFACTS Commit all six outputs with rollback on failure.
if exist(forecast_dir, 'dir') ~= 7
    mkdir(forecast_dir);
end

num_artifacts = numel(artifacts);
temporary_paths = strings(num_artifacts, 1);
backup_paths = strings(num_artifacts, 1);
had_canonical = false(num_artifacts, 1);
promoted = false(num_artifacts, 1);
cleanup = onCleanup(@() local_cleanup_transaction( ...
    temporary_paths, backup_paths));

for artifact_index = 1:num_artifacts
    temporary_paths(artifact_index) = string(tempname(forecast_dir)) + ".mat";
    artifact = artifacts{artifact_index};
    save(temporary_paths(artifact_index), '-struct', 'artifact');
    reloaded = load(temporary_paths(artifact_index));

    if ~isequaln(reloaded, artifact)
        error('PARTC_03:TemporaryArtifactMismatch', ...
            'A temporary forecast artifact failed round-trip validation.');
    end
end

try
    for artifact_index = 1:num_artifacts
        canonical_path = canonical_paths(artifact_index);
        if exist(canonical_path, 'file') == 2
            had_canonical(artifact_index) = true;
            backup_paths(artifact_index) = ...
                string(tempname(forecast_dir)) + ".mat";
            [moved, message] = movefile( ...
                canonical_path, backup_paths(artifact_index));
            if ~moved
                error('PARTC_03:ArtifactBackupFailed', ...
                    'Could not back up %s: %s', canonical_path, message);
            end
        end
    end

    for artifact_index = 1:num_artifacts
        [moved, message] = movefile(temporary_paths(artifact_index), ...
            canonical_paths(artifact_index));
        if ~moved
            error('PARTC_03:ArtifactPromotionFailed', ...
                'Could not promote %s: %s', ...
                canonical_paths(artifact_index), message);
        end
        promoted(artifact_index) = true;
        temporary_paths(artifact_index) = "";
    end
catch commit_error
    for artifact_index = 1:num_artifacts
        if promoted(artifact_index) && ...
                exist(canonical_paths(artifact_index), 'file') == 2
            delete(canonical_paths(artifact_index));
        end
    end

    for artifact_index = 1:num_artifacts
        if had_canonical(artifact_index) && ...
                exist(backup_paths(artifact_index), 'file') == 2
            movefile(backup_paths(artifact_index), ...
                canonical_paths(artifact_index));
            backup_paths(artifact_index) = "";
        end
    end
    rethrow(commit_error);
end

for artifact_index = 1:num_artifacts
    if had_canonical(artifact_index) && ...
            exist(backup_paths(artifact_index), 'file') == 2
        delete(backup_paths(artifact_index));
        backup_paths(artifact_index) = "";
    end
end

if nnz(arrayfun(@(artifact_path) ...
        exist(artifact_path, 'file') == 2, canonical_paths)) ~= 6
    error('PARTC_03:IncompleteCanonicalArtifactSet', ...
        'The canonical Script 3 artifact set is incomplete after promotion.');
end

clear cleanup;
end

function local_cleanup_transaction(temporary_paths, backup_paths)
%LOCAL_CLEANUP_TRANSACTION Remove abandoned transaction files.
transaction_paths = [temporary_paths; backup_paths];
for path_index = 1:numel(transaction_paths)
    if strlength(transaction_paths(path_index)) > 0 && ...
            exist(transaction_paths(path_index), 'file') == 2
        delete(transaction_paths(path_index));
    end
end
end
