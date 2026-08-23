%PARTC_03_RUN_FORECASTS Generate held-out real-data Rt forecasts.
%
%   Description:
%       Generates held-out forecasts of the operational Rt estimate for
%       AR/None and ARX/I under three transfer strategies: globally selected
%       online fitting, locally selected online fitting, and globally selected
%       fixed calibration fitting. All strategies use the same held-out
%       forecast origins and common random-number construction. Fixed strategies
%       retain coefficients and residuals fitted only on the calibration block
%       while updating the observed lag history and current SIRS proxy state at
%       each origin.
%
%   Workflow:
%       1. Initialize the held-out forecasting paths and configuration.
%       2. Load prepared data and construct the common forecast origins.
%       3. Load the Part C local-selection artifacts.
%       4. Prepare the reusable closed-loop SIRS stepper.
%       5. Fit fixed models and generate all model-strategy forecasts.
%       6. Check online-strategy equality for matching configurations.
%       7. Save one artifact per model-strategy combination.
%
%   See also PARTC_CONFIG, PARTC_01_PREPARE_DATA,
%            PARTC_02_SELECT_LOCAL_ORDERS, PARTC_04_EVALUATE_FORECASTS,
%            FORECAST_OPEN, FORECAST_CLOSED, SIRS_INIT, SIRS_STEP.
%
% A. M. Kaahin 2026-08-06
% Modified: 2026-08-23

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Held-Out Forecast Generation ===\n');

cfg = partC_config();
forecast_configurations = cfg.final_forecast.configurations;
strategies = cfg.final_forecast.strategies;

%% 2. Prepared Data
prepared = local_load_prepared_data(cfg);

fprintf('Prepared-data period: %s to %s\n', string(prepared.dates(1)), string(prepared.dates(end)));
fprintf('Calibration boundary: %s\n', string(cfg.validation.calibration_end_date));

forecast_origin_indices = local_build_forecast_origins(prepared, cfg);

fprintf('Held-out forecast origins: %d\n', numel(forecast_origin_indices));

%% 3. Local-Selection Artifacts
num_configurations = numel(forecast_configurations);
selections = cell(num_configurations, 1);

for configuration_index = 1:num_configurations
    selections{configuration_index} = local_load_selection_artifact(forecast_configurations(configuration_index));
end

%% 4. Closed-Loop SIRS Stepper
sirs_parameters = struct("gamma", cfg.state_reconstruction.gamma, "xi", cfg.state_reconstruction.xi, "pop_size", cfg.state_reconstruction.effective_population, "min_susceptible", cfg.state_reconstruction.min_susceptible);
step_options = struct("solver", "uds", "seed", cfg.final_forecast.base_seed);
base_stepper = sirs_init(sirs_parameters, step_options);

%% 5. Forecast Generation
num_strategies = numel(strategies);
artifacts = cell(num_configurations, num_strategies);

for configuration_index = 1:num_configurations
    active_configuration = forecast_configurations(configuration_index);
    selection = selections{configuration_index};

    fprintf('\nModel: %s | Exogenous mode: %s\n', active_configuration.model_type, active_configuration.exo_mode);

    fixed_fit = local_fit_fixed_model(active_configuration, selection.partA_selected_configuration, prepared);

    for strategy_index = 1:num_strategies
        active_strategy = strategies(strategy_index);

        [forecast_configuration, fixed_fit_info] = local_resolve_strategy(active_strategy, selection, fixed_fit);

        fprintf('Strategy: %s\n', active_strategy.identifier);
        fprintf('Forecast configuration: %s\n', mat2str(forecast_configuration));

        results = local_run_forecasts(active_configuration, active_strategy, forecast_configuration, fixed_fit_info, prepared, forecast_origin_indices, base_stepper, configuration_index, cfg);

        artifacts{configuration_index, strategy_index} = local_build_artifact(active_configuration, active_strategy, forecast_configuration, results, cfg.final_forecast.wis_alphas);
    end
end

%% 6. Cross-Strategy Check
for configuration_index = 1:num_configurations
    selection = selections{configuration_index};

    if isequal(selection.partA_selected_configuration, selection.selected_configuration)
        partA_online_results = artifacts{configuration_index, 1}.results;
        local_online_results = artifacts{configuration_index, 2}.results;

        if ~isequal(partA_online_results, local_online_results)
            error('PARTC_03:CommonRandomNumbersMismatch', 'Equal Part A and local configurations must produce identical online forecasts.');
        end
    end
end

%% 7. Persistence
if ~exist(cfg.output.forecast_dir, 'dir')
    mkdir(cfg.output.forecast_dir);
end

for configuration_index = 1:num_configurations
    active_configuration = forecast_configurations(configuration_index);

    for strategy_index = 1:num_strategies
        active_strategy = strategies(strategy_index);
        artifact = artifacts{configuration_index, strategy_index};
        artifact_path = local_canonical_path(active_configuration, active_strategy.identifier, cfg.output.forecast_dir);

        save(artifact_path, '-struct', 'artifact');

        fprintf('Saved artifact: %s\n', artifact_path);
    end
end

fprintf('\n=== Part C Held-Out Forecast Generation Complete ===\n\n');

%% 8. Local Functions
function prepared = local_load_prepared_data(cfg)
%LOCAL_LOAD_PREPARED_DATA Load the Script 1 prepared data.

artifact_path = cfg.output.prepared_artifact_path;

if ~isfile(artifact_path)
    error('PARTC_03:MissingPreparedArtifact', 'Missing prepared Part C artifact: %s. Run Part C Script 1 first.', artifact_path);
end

prepared = load(artifact_path, 'dates', 'Rt_estimated', 'Rt_valid_mask', 'I_fraction_proxy', 'S_proxy', 'I_proxy', 'R_proxy');

first_valid_index = find(prepared.Rt_valid_mask, 1);

if isempty(first_valid_index) || any(~prepared.Rt_valid_mask(first_valid_index:end))
    error('PARTC_03:InvalidEstimatedRtBlock', 'Rt_estimated must remain valid after the renewal warm-up.');
end

calibration_end_index = find(prepared.dates == cfg.validation.calibration_end_date, 1);

if isempty(calibration_end_index)
    error('PARTC_03:MissingCalibrationBoundary', 'Prepared data do not contain the configured calibration end date.');
end

prepared.first_valid_index = first_valid_index;
prepared.calibration_end_index = calibration_end_index;

end

function origin_indices = local_build_forecast_origins(prepared, cfg)
%LOCAL_BUILD_FORECAST_ORIGINS Build the common held-out forecast-origin grid.

horizon = cfg.final_forecast.horizon;
step_size = cfg.final_forecast.step_size;
last_origin_index = numel(prepared.dates) - horizon;

origin_indices = (prepared.calibration_end_index:step_size:last_origin_index).';

if isempty(origin_indices)
    error('PARTC_03:NoHeldOutOrigins', 'The prepared study period is too short for the configured held-out forecast protocol.');
end

end

function selection = local_load_selection_artifact(configuration)
%LOCAL_LOAD_SELECTION_ARTIFACT Load one Script 2 selection artifact.

artifact_path = configuration.selection_artifact_path;

if ~isfile(artifact_path)
    error('PARTC_03:MissingSelectionArtifact', 'Missing Script 2 artifact for %s/%s: %s. Run Part C Script 2 first.', configuration.model_type, configuration.exo_mode, artifact_path);
end

selection = load(artifact_path, 'partA_selected_configuration', 'selected_configuration');

end

function fixed_fit = local_fit_fixed_model(active_configuration, configuration, prepared)
%LOCAL_FIT_FIXED_MODEL Fit one globally selected configuration on calibration data only.

calibration_indices = prepared.first_valid_index:prepared.calibration_end_index;
calibration_Rt = prepared.Rt_estimated(calibration_indices);

switch active_configuration.model_type
    case "AR"
        fixed_fit = local_fit_fixed_ar(configuration, calibration_Rt);

    case "ARX"
        calibration_U = prepared.I_fraction_proxy(calibration_indices);
        fixed_fit = local_fit_fixed_arx(configuration, calibration_Rt, calibration_U);

    otherwise
        error('PARTC_03:UnsupportedConfiguration', 'Unsupported forecast model type: %s.', active_configuration.model_type);
end

end

function fit_info = local_fit_fixed_ar(configuration, calibration_Rt)
%LOCAL_FIT_FIXED_AR Fit a calibration-only AR model on log Rt.

p = configuration(1);
y = log(calibration_Rt);

if std(y) < 1e-8
    error('FORECAST_OPEN:ConstantSeries', 'log(calibration_Rt) is effectively constant (std < 1e-8); cannot fit AR model.');
end

if numel(y) <= p + 1
    error('FORECAST_OPEN:InsufficientHistory', 'AR calibration history is too short for the selected order.');
end

sys = ar(iddata(y, [], 1), p, 'burg');
a_coefficients = sys.A(2:end);

num_observations = numel(y);
residuals = zeros(num_observations - p, 1);

for observation_index = (p + 1):num_observations
    prediction = -(a_coefficients * y(observation_index - 1:-1:observation_index - p));
    residuals(observation_index - p) = y(observation_index) - prediction;
end

if any(~isfinite(residuals))
    error('FORECAST_OPEN:InvalidResiduals', 'AR calibration produced non-finite residuals.');
end

fit_info = struct();
fit_info.configuration = configuration;
fit_info.A_coefficients = a_coefficients;
fit_info.centred_residuals = residuals - mean(residuals);

end

function fit_info = local_fit_fixed_arx(configuration, calibration_Rt, calibration_U)
%LOCAL_FIT_FIXED_ARX Fit a calibration-only ARX/I model on log Rt.

na = configuration(1);
nb = configuration(2);
nk = configuration(3);

y = log(calibration_Rt);
num_observations = numel(y);
max_lag = max(na, nk + nb - 1);

if std(y) < 1e-8
    error('FORECAST_CLOSED:ConstantSeries', 'log(calibration_Rt) is effectively constant (std < 1e-8); cannot fit ARX model.');
end

if num_observations - max_lag < 2
    error('FORECAST_CLOSED:InsufficientHistory', 'ARX calibration history is too short for the selected configuration.');
end

sys = arx(iddata(y, calibration_U, 1), [na, nb, nk]);
a_coefficients = sys.A(2:end);
b_coefficients = sys.B(nk + 1:nk + nb);

residuals = zeros(num_observations - max_lag, 1);

for observation_index = (max_lag + 1):num_observations
    prediction = local_arx_step(a_coefficients, b_coefficients, na, nb, nk, y(1:observation_index - 1), calibration_U(1:observation_index - 1));
    residuals(observation_index - max_lag) = y(observation_index) - prediction;
end

if any(~isfinite(residuals))
    error('FORECAST_CLOSED:InvalidResiduals', 'ARX calibration produced non-finite residuals.');
end

fit_info = struct();
fit_info.configuration = configuration;
fit_info.A_coefficients = a_coefficients;
fit_info.B_coefficients = b_coefficients;
fit_info.centred_residuals = residuals - mean(residuals);

end

function [configuration, fixed_fit_info] = local_resolve_strategy(strategy, selection, fixed_fit)
%LOCAL_RESOLVE_STRATEGY Resolve one transfer strategy.

switch strategy.configuration_source
    case "partA"
        configuration = selection.partA_selected_configuration;

    case "partC_local_selection"
        configuration = selection.selected_configuration;

    otherwise
        error('PARTC_03:UnsupportedConfigurationSource', 'Unsupported strategy configuration source: %s.', strategy.configuration_source);
end

switch strategy.parameter_update_mode
    case "online"
        fixed_fit_info = struct();

    case "fixed_calibration_fit"
        fixed_fit_info = fixed_fit;

    otherwise
        error('PARTC_03:UnsupportedParameterUpdateMode', 'Unsupported parameter update mode: %s.', strategy.parameter_update_mode);
end

end

function results = local_run_forecasts(active_configuration, strategy, forecast_configuration, fixed_fit_info, prepared, origin_indices, base_stepper, configuration_index, cfg)
%LOCAL_RUN_FORECASTS Generate one model-strategy forecast result array.

result_template = struct("origin_date", NaT, "target_dates", NaT(0, 1), "target_Rt_estimated", [], "forecast_median", [], "forecast_lower", [], "forecast_upper", []);
results = repmat(result_template, numel(origin_indices), 1);

for origin_position = 1:numel(origin_indices)
    origin_index = origin_indices(origin_position);

    results(origin_position) = local_generate_origin_result(active_configuration, strategy, forecast_configuration, fixed_fit_info, prepared, origin_index, origin_position, base_stepper, configuration_index, cfg);

    if mod(origin_position, 5) == 0 || origin_position == numel(origin_indices)
        fprintf('Completed origins: %d/%d\n', origin_position, numel(origin_indices));
    end
end

end

function result = local_generate_origin_result(active_configuration, strategy, forecast_configuration, fixed_fit_info, prepared, origin_index, origin_position, base_stepper, configuration_index, cfg)
%LOCAL_GENERATE_ORIGIN_RESULT Generate and summarize one held-out forecast origin.

horizon = cfg.final_forecast.horizon;
num_draws = cfg.final_forecast.num_draws;
wis_alphas = cfg.final_forecast.wis_alphas;

history_indices = prepared.first_valid_index:origin_index;
Rt_past = prepared.Rt_estimated(history_indices);

target_indices = origin_index + (1:horizon);
target_dates = prepared.dates(target_indices);
target_Rt_estimated = prepared.Rt_estimated(target_indices);

resample_seed = cfg.final_forecast.base_seed + 100000 * configuration_index + origin_position;

switch active_configuration.model_type
    case "AR"
        if strategy.parameter_update_mode == "online"
            ensemble_paths = forecast_open("AR", forecast_configuration, Rt_past, num_draws, horizon, resample_seed);
        else
            ensemble_paths = local_forecast_fixed_ar(fixed_fit_info, Rt_past, num_draws, horizon, resample_seed);
        end

    case "ARX"
        U_past = prepared.I_fraction_proxy(history_indices);
        sirs_state = [prepared.S_proxy(origin_index), prepared.I_proxy(origin_index), prepared.R_proxy(origin_index)];
        epidemic_seed = resample_seed + 1000000;

        if strategy.parameter_update_mode == "online"
            ensemble_paths = forecast_closed("ARX", forecast_configuration, Rt_past, U_past, sirs_state, 1, num_draws, horizon, "I", base_stepper, resample_seed, epidemic_seed, cfg.final_forecast.include_epidemic_seed_variation);
        else
            ensemble_paths = local_forecast_fixed_arx(fixed_fit_info, Rt_past, U_past, sirs_state, num_draws, horizon, base_stepper, resample_seed, epidemic_seed, cfg.final_forecast.include_epidemic_seed_variation);
        end

    otherwise
        error('PARTC_03:UnsupportedConfiguration', 'Unsupported forecast model type: %s.', active_configuration.model_type);
end

forecast_median = median(ensemble_paths, 2);
forecast_lower = quantile(ensemble_paths, wis_alphas.' / 2, 2);
forecast_upper = quantile(ensemble_paths, 1 - wis_alphas.' / 2, 2);

result = struct("origin_date", prepared.dates(origin_index), "target_dates", target_dates, "target_Rt_estimated", target_Rt_estimated, "forecast_median", forecast_median, "forecast_lower", forecast_lower, "forecast_upper", forecast_upper);

end

function ensemble = local_forecast_fixed_ar(fit_info, Rt_past, num_draws, horizon, resample_seed)
%LOCAL_FORECAST_FIXED_AR Forecast with fixed AR coefficients and residuals.

p = fit_info.configuration(1);
y = log(Rt_past);

innovations = local_resample_centred(fit_info.centred_residuals, horizon, num_draws, resample_seed);

seed_values = y(end - p + 1:end);
rolling_y = [repmat(seed_values, 1, num_draws); zeros(horizon, num_draws)];
ensemble = zeros(horizon, num_draws);

for horizon_index = 1:horizon
    recent = rolling_y(horizon_index:horizon_index + p - 1, :);
    prediction = -(fit_info.A_coefficients * flipud(recent));
    y_next = prediction + innovations(horizon_index, :);
    Rt_next = exp(y_next);

    if ~all(isfinite(Rt_next) & Rt_next > 0)
        error('FORECAST_OPEN:InvalidForecastDraw', 'Fixed AR bootstrap draw produced a non-finite or non-positive Rt.');
    end

    ensemble(horizon_index, :) = Rt_next;
    rolling_y(p + horizon_index, :) = y_next;
end

end

function ensemble = local_forecast_fixed_arx(fit_info, Rt_past, U_past, sirs_state, num_draws, horizon, base_stepper, resample_seed, epidemic_seed, vary_epidemic_seed)
%LOCAL_FORECAST_FIXED_ARX Forecast with fixed ARX coefficients and residuals.

configuration = fit_info.configuration;
na = configuration(1);
nb = configuration(2);
nk = configuration(3);

y = log(Rt_past);
num_observations = numel(y);

innovations = local_resample_centred(fit_info.centred_residuals, horizon, num_draws, resample_seed);

pop_size = base_stepper.model_params.pop_size;
min_susceptible = base_stepper.model_params.min_susceptible;

rolling_y = [y; zeros(horizon, 1)];
rolling_U = [U_past; zeros(horizon, 1)];
ensemble = zeros(horizon, num_draws);

for draw_index = 1:num_draws
    draw_seed = local_draw_seed(epidemic_seed, draw_index, horizon, vary_epidemic_seed);

    stepper = base_stepper;
    stepper.seed = draw_seed;
    stepper.call_count = 0;

    state = sirs_state;
    Rt_driver = Rt_past(end);
    draw_y = rolling_y;
    draw_U = rolling_U;

    for horizon_index = 1:horizon
        prediction = local_arx_step(fit_info.A_coefficients, fit_info.B_coefficients, na, nb, nk, draw_y(1:num_observations + horizon_index - 1), draw_U(1:num_observations + horizon_index - 1));
        y_next = prediction + innovations(horizon_index, draw_index);
        Rt_next = exp(y_next);

        if ~isfinite(Rt_next) || Rt_next <= 0
            error('FORECAST_CLOSED:InvalidForecastDraw', 'Fixed ARX bootstrap draw produced a non-finite or non-positive Rt.');
        end

        [state, stepper] = sirs_step(stepper, state, Rt_driver);

        if state(1) <= min_susceptible
            error('EPIDEMIC:SusceptibleBelowThreshold', 'Forecasted SIRS state crossed the susceptible-domain threshold.');
        end

        ensemble(horizon_index, draw_index) = Rt_next;
        draw_y(num_observations + horizon_index) = y_next;
        draw_U(num_observations + horizon_index) = state(2) / pop_size;
        Rt_driver = Rt_next;
    end
end

end

function prediction = local_arx_step(a_coefficients, b_coefficients, na, nb, nk, log_history, U_history)
%LOCAL_ARX_STEP Compute one ARX/I prediction from aligned histories.

num_observations = numel(log_history);
prediction = 0;

for lag = 1:na
    prediction = prediction - a_coefficients(lag) * log_history(num_observations + 1 - lag);
end

for coefficient_index = 1:nb
    input_lag = nk + coefficient_index - 1;
    prediction = prediction + b_coefficients(coefficient_index) * U_history(num_observations + 1 - input_lag);
end

end

function innovations = local_resample_centred(centred_residuals, horizon, num_draws, resample_seed)
%LOCAL_RESAMPLE_CENTRED Resample a fixed centred residual pool.

caller_state = rng;
cleanup = onCleanup(@() rng(caller_state));

rng(resample_seed, 'twister');

residual_indices = randi(numel(centred_residuals), horizon, num_draws);
innovations = centred_residuals(residual_indices);

clear cleanup;

end

function seed = local_draw_seed(base_seed, draw_index, horizon, vary)
%LOCAL_DRAW_SEED Derive the per-draw epidemic seed.

seed = base_seed;

if vary
    seed = base_seed + (draw_index - 1) * (horizon + 1);
end

end

function artifact = local_build_artifact(active_configuration, strategy, forecast_configuration, results, wis_alphas)
%LOCAL_BUILD_ARTIFACT Assemble one final forecast artifact.

artifact = struct();
artifact.model_type = active_configuration.model_type;
artifact.exo_mode = active_configuration.exo_mode;
artifact.strategy = strategy.identifier;
artifact.forecast_configuration = forecast_configuration;
artifact.wis_alphas = wis_alphas;
artifact.results = results;

end

function artifact_path = local_canonical_path(active_configuration, strategy, forecast_dir)
%LOCAL_CANONICAL_PATH Construct one Script 3 artifact path.

filename = sprintf('partC_03_forecast_%s_%s_%s.mat', active_configuration.model_type, active_configuration.exo_mode, strategy);
artifact_path = fullfile(forecast_dir, filename);

end