%PARTC_02_SELECT_LOCAL_ORDERS Select local AR/None and ARX/I configurations.
%
%   Description:
%       Starts from the AR/None and ARX/I configurations selected in Part A,
%       constructs a limited neighbourhood around each selected order, and
%       evaluates the candidates on one shared chronological calibration block
%       from the prepared real-data series. Candidates are refitted at every
%       calibration forecast origin and selected by calibration WIS using the
%       configured one-standard-error complexity rule. Recognized closed-loop
%       forecast-domain failures make the affected candidate infeasible.
%
%   Workflow:
%       1. Load the prepared Part C calibration data.
%       2. Build the common expanding-window calibration origins.
%       3. Load each Part A-selected baseline configuration.
%       4. Construct the limited local candidate neighbourhood.
%       5. Refit and score every candidate across all calibration origins.
%       6. Select the simplest configuration within one standard error.
%       7. Save one local-selection artifact per supported configuration.
%
%   See also PARTC_CONFIG, PARTC_01_PREPARE_DATA,
%            PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS, FORECAST_OPEN,
%            FORECAST_CLOSED, SIRS_INIT, COMPUTE_WIS.
%
% A. M. Kaahin 2026-07-28
% Modified: 2026-08-22

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Local Configuration Selection ===\n');

cfg = partC_config();
configurations = cfg.local_selection.configurations;

if ~exist(cfg.output.model_selection_dir, 'dir')
    mkdir(cfg.output.model_selection_dir);
end

%% 2. Calibration Data
[calibration, preparation_snapshot] = local_load_calibration_data(cfg);

fprintf('Calibration period: %s to %s\n', string(calibration.dates(1)), string(calibration.dates(end)));

[forecast_origin_indices, forecast_origin_dates] = local_build_forecast_origins(calibration.dates, cfg);

fprintf('Calibration forecast origins: %d\n', numel(forecast_origin_indices));

%% 3. Local Configuration Selection
for configuration_index = 1:numel(configurations)
    active_configuration = configurations(configuration_index);
    model_type = active_configuration.model_type;
    exo_mode = active_configuration.exo_mode;

    fprintf('\nModel: %s | Exogenous mode: %s\n', model_type, exo_mode);

    partA_selected_configuration = local_load_partA_baseline(active_configuration);
    candidate_configurations = local_construct_candidate_grid(partA_selected_configuration, model_type, cfg.local_selection.order_radius);
    candidate_complexity = sum(candidate_configurations, 2);

    local_validate_minimum_window(candidate_configurations, model_type, cfg.local_selection.min_window);

    base_stepper = [];

    if model_type == "ARX"
        sirs_parameters = struct("gamma", cfg.state_reconstruction.gamma, "xi", cfg.state_reconstruction.xi, "pop_size", cfg.state_reconstruction.effective_population, "min_susceptible", cfg.state_reconstruction.min_susceptible);
        step_options = struct("solver", "uds", "seed", cfg.local_selection.seed);
        base_stepper = sirs_init(sirs_parameters, step_options);
    end

    num_candidates = size(candidate_configurations, 1);
    num_origins = numel(forecast_origin_indices);

    candidate_origin_mean_wis = nan(num_candidates, num_origins);
    candidate_feasible_mask = false(num_candidates, 1);

    failure_record_template = struct("candidate_index", NaN, "candidate_configuration", [], "forecast_origin_index", NaN, "forecast_origin_date", NaT, "error_identifier", "", "error_message", "");
    candidate_failure_records = repmat(failure_record_template, num_candidates, 1);
    num_failure_records = 0;

    for candidate_index = 1:num_candidates
        candidate_configuration = candidate_configurations(candidate_index, :);

        fprintf('Evaluating candidate %d/%d: %s\n', candidate_index, num_candidates, mat2str(candidate_configuration));

        [origin_mean_wis, failure_record] = local_evaluate_candidate(active_configuration, candidate_configuration, candidate_index, calibration, forecast_origin_indices, base_stepper, cfg);

        candidate_origin_mean_wis(candidate_index, :) = origin_mean_wis.';

        if isempty(failure_record)
            candidate_feasible_mask(candidate_index) = true;
        else
            num_failure_records = num_failure_records + 1;
            candidate_failure_records(num_failure_records) = failure_record;
        end
    end

    candidate_failure_records = candidate_failure_records(1:num_failure_records);

    %% 4. One-Standard-Error Selection
    feasible_indices = find(candidate_feasible_mask);

    if isempty(feasible_indices)
        error('PARTC_02:NoFeasibleCandidate', 'No feasible candidate completed all origins for %s/%s.', model_type, exo_mode);
    end

    candidate_mean_wis = inf(num_candidates, 1);
    candidate_se_wis = inf(num_candidates, 1);

    candidate_mean_wis(feasible_indices) = mean(candidate_origin_mean_wis(feasible_indices, :), 2);
    candidate_se_wis(feasible_indices) = std(candidate_origin_mean_wis(feasible_indices, :), 0, 2) / sqrt(num_origins);

    [best_mean_wis, best_position] = min(candidate_mean_wis(feasible_indices));

    numerically_best_index = feasible_indices(best_position);
    numerically_best_configuration = candidate_configurations(numerically_best_index, :);
    selection_threshold = best_mean_wis + candidate_se_wis(numerically_best_index);
    eligible_indices = find(candidate_feasible_mask & candidate_mean_wis <= selection_threshold);

    eligible_ranking = [
        candidate_complexity(eligible_indices), candidate_mean_wis(eligible_indices), eligible_indices
        ];

    eligible_ranking = sortrows(eligible_ranking, [1, 2, 3]);

    selected_index = eligible_ranking(1, 3);
    selected_configuration = candidate_configurations(selected_index, :);

    %% 5. Persistence
    artifact = struct();

    artifact.model_type = model_type;
    artifact.exo_mode = exo_mode;
    artifact.strategy = "local_order_online_fit";
    artifact.partA_selection_artifact_path = active_configuration.partA_selection_artifact_path;
    artifact.partA_selected_configuration = partA_selected_configuration;
    artifact.candidate_configurations = candidate_configurations;
    artifact.candidate_complexity = candidate_complexity;
    artifact.candidate_feasible_mask = candidate_feasible_mask;
    artifact.candidate_failure_records = candidate_failure_records;
    artifact.calibration_dates = calibration.dates;
    artifact.calibration_end_date = cfg.validation.calibration_end_date;
    artifact.test_start_date = cfg.validation.test_start_date;
    artifact.forecast_origin_indices = forecast_origin_indices;
    artifact.forecast_origin_dates = forecast_origin_dates;
    artifact.candidate_origin_mean_wis = candidate_origin_mean_wis;
    artifact.candidate_mean_wis = candidate_mean_wis;
    artifact.candidate_se_wis = candidate_se_wis;
    artifact.numerically_best_index = numerically_best_index;
    artifact.numerically_best_configuration = numerically_best_configuration;
    artifact.selection_threshold = selection_threshold;
    artifact.eligible_indices = eligible_indices;
    artifact.selected_index = selected_index;
    artifact.selected_configuration = selected_configuration;
    artifact.selection_rule = cfg.local_selection.selection_rule;
    artifact.prepared_artifact_path = cfg.output.prepared_artifact_path;
    artifact.preparation_snapshot = preparation_snapshot;
    artifact.local_selection_snapshot = active_configuration.local_selection_snapshot;

    save(active_configuration.local_selection_artifact_path, '-struct', 'artifact');

    fprintf('Part A baseline: %s\n', mat2str(partA_selected_configuration));
    fprintf('Local candidate grid: %s\n', mat2str(candidate_configurations));
    fprintf('Feasible candidates: %d | Infeasible candidates: %d\n', nnz(candidate_feasible_mask), nnz(~candidate_feasible_mask));
    fprintf('Selected local configuration: %s\n', mat2str(selected_configuration));
    fprintf('Saved artifact: %s\n', active_configuration.local_selection_artifact_path);
end

fprintf('\n=== Part C Local Configuration Selection Complete ===\n\n');

%% 6. Local Functions
function [calibration, preparation_snapshot] = local_load_calibration_data(cfg)
%LOCAL_LOAD_CALIBRATION_DATA Load the prepared chronological calibration block.

prepared_artifact_path = cfg.output.prepared_artifact_path;

if ~isfile(prepared_artifact_path)
    error('PARTC_02:MissingPreparedArtifact', 'Missing prepared Part C artifact: %s. Run Part C Script 1 first.', prepared_artifact_path);
end

prepared = load(prepared_artifact_path);

if ~isequaln(prepared.preparation_snapshot, cfg.snapshot.preparation)
    error('PARTC_02:PreparationSnapshotMismatch', 'Prepared Part C artifact does not match the current preparation configuration.');
end

dates = prepared.dates;
Rt_estimated = prepared.Rt_estimated;
Rt_valid_mask = prepared.Rt_valid_mask;

calibration_end_index = find(dates == cfg.validation.calibration_end_date, 1);
test_start_index = find(dates == cfg.validation.test_start_date, 1);

if isempty(calibration_end_index) || isempty(test_start_index)
    error('PARTC_02:MissingValidationBoundary', 'Prepared data do not contain the configured calibration/test boundary.');
end

first_valid_index = find(Rt_valid_mask & dates <= cfg.validation.calibration_end_date, 1);

if isempty(first_valid_index)
    error('PARTC_02:NoValidCalibrationRt', 'No valid Rt estimate exists in the calibration period.');
end

calibration_indices = first_valid_index:calibration_end_index;

if any(~Rt_valid_mask(calibration_indices))
    invalid_index = calibration_indices(find(~Rt_valid_mask(calibration_indices), 1));
    error('PARTC_02:InvalidCalibrationRt', 'Rt_estimated is invalid inside the calibration block on %s.', string(dates(invalid_index)));
end

if any(~prepared.state_valid_mask(calibration_indices))
    error('PARTC_02:InvalidCalibrationState', 'The calibration block contains an invalid SIRS proxy state.');
end

calibration = struct();
calibration.dates = dates(calibration_indices);
calibration.Rt = Rt_estimated(calibration_indices);
calibration.I_fraction_proxy = prepared.I_fraction_proxy(calibration_indices);
calibration.S_proxy = prepared.S_proxy(calibration_indices);
calibration.I_proxy = prepared.I_proxy(calibration_indices);
calibration.R_proxy = prepared.R_proxy(calibration_indices);

preparation_snapshot = prepared.preparation_snapshot;

end

function [forecast_origin_indices, forecast_origin_dates] = local_build_forecast_origins(calibration_dates, cfg)
%LOCAL_BUILD_FORECAST_ORIGINS Build common expanding-window calibration origins.

horizon = cfg.local_selection.horizon;
min_window = cfg.local_selection.min_window;
step_size = cfg.local_selection.step_size;
last_origin_index = numel(calibration_dates) - horizon;

forecast_origin_indices = (min_window:step_size:last_origin_index)';

if isempty(forecast_origin_indices)
    error('PARTC_02:NoCalibrationOrigins', 'The calibration series is too short for the configured forecast protocol.');
end

forecast_origin_dates = calibration_dates(forecast_origin_indices);

end

function selected_configuration = local_load_partA_baseline(active_configuration)
%LOCAL_LOAD_PARTA_BASELINE Load the compatible Part A selected configuration.

artifact_path = active_configuration.partA_selection_artifact_path;

if ~isfile(artifact_path)
    error('PARTC_02:MissingPartABaseline', 'Missing Part A %s/%s selection artifact: %s.', active_configuration.model_type, active_configuration.exo_mode, artifact_path);
end

selection = load(artifact_path);

if ~isequaln(selection.snapshot, active_configuration.partA_selection_snapshot)
    error('PARTC_02:PartABaselineSnapshotMismatch', 'Part A %s/%s artifact does not match the current selection configuration.', active_configuration.model_type, active_configuration.exo_mode);
end

selected_configuration = selection.selected_configuration;

end

function candidate_configurations = local_construct_candidate_grid(partA_configuration, model_type, order_radius)
%LOCAL_CONSTRUCT_CANDIDATE_GRID Construct the limited neighbourhood around Part A.

switch model_type
    case "AR"
        candidate_configurations = ((partA_configuration - order_radius):(partA_configuration + order_radius))';
        candidate_configurations = candidate_configurations(candidate_configurations >= 1);

    case "ARX"
        na_values = (partA_configuration(1) - order_radius):(partA_configuration(1) + order_radius);
        nb_values = (partA_configuration(2) - order_radius):(partA_configuration(2) + order_radius);
        nk_values = (partA_configuration(3) - order_radius):(partA_configuration(3) + order_radius);

        [na_grid, nb_grid, nk_grid] = ndgrid(na_values, nb_values, nk_values);

        candidate_configurations = [na_grid(:), nb_grid(:), nk_grid(:)];
        candidate_configurations = candidate_configurations(all(candidate_configurations >= 1, 2), :);

    otherwise
        error('PARTC_02:UnsupportedConfiguration', 'Unsupported local-selection model type: %s.', model_type);
end

candidate_configurations = sortrows(candidate_configurations);

end

function local_validate_minimum_window(candidate_configurations, model_type, min_window)
%LOCAL_VALIDATE_MINIMUM_WINDOW Require sufficient fitting history.

switch model_type
    case "AR"
        sufficient_history = min_window > candidate_configurations(:, 1) + 1;

    case "ARX"
        max_lag = max(candidate_configurations(:, 1), candidate_configurations(:, 3) + candidate_configurations(:, 2) - 1);
        sufficient_history = min_window - max_lag >= 2;

    otherwise
        error('PARTC_02:UnsupportedConfiguration', 'Unsupported local-selection model type: %s.', model_type);
end

if any(~sufficient_history)
    error('PARTC_02:InsufficientMinimumWindow', 'The configured minimum window is too short for at least one %s candidate.', model_type);
end

end

function [origin_mean_wis, failure_record] = local_evaluate_candidate(active_configuration, candidate_configuration, candidate_index, calibration, forecast_origin_indices, base_stepper, cfg)
%LOCAL_EVALUATE_CANDIDATE Refit and score one candidate at every origin.

num_origins = numel(forecast_origin_indices);
horizon = cfg.local_selection.horizon;
wis_alphas = cfg.local_selection.wis_alphas;

origin_mean_wis = nan(num_origins, 1);

failure_record = struct("candidate_index", {}, "candidate_configuration", {}, "forecast_origin_index", {}, "forecast_origin_date", {}, "error_identifier", {}, "error_message", {});

recognized_failures = [
    "FORECAST_CLOSED:InvalidForecastDraw"
    "EPIDEMIC:SusceptibleBelowThreshold"
    ];

for origin_position = 1:num_origins
    origin_index = forecast_origin_indices(origin_position);
    origin_date = calibration.dates(origin_index);

    training_Rt = calibration.Rt(1:origin_index);
    target_Rt = calibration.Rt(origin_index + (1:horizon));

    resample_seed = cfg.local_selection.seed + 100000 * candidate_index + origin_index;

    try
        switch active_configuration.model_type
            case "AR"
                ensemble_paths = forecast_open("AR", candidate_configuration, training_Rt, cfg.local_selection.num_draws, horizon, resample_seed);

            case "ARX"
                training_U = calibration.I_fraction_proxy(1:origin_index);
                origin_state = [calibration.S_proxy(origin_index), calibration.I_proxy(origin_index), calibration.R_proxy(origin_index)];
                epidemic_seed = cfg.local_selection.seed + 1000000 + 100000 * candidate_index + origin_index;

                ensemble_paths = forecast_closed("ARX", candidate_configuration, training_Rt, training_U, origin_state, 1, cfg.local_selection.num_draws, horizon, "I", base_stepper, resample_seed, epidemic_seed, cfg.local_selection.include_epidemic_seed_variation);

            otherwise
                error('PARTC_02:UnsupportedConfiguration', 'Unsupported local-selection model type: %s.', active_configuration.model_type);
        end

        forecast_median = median(ensemble_paths, 2);
        forecast_lower = quantile(ensemble_paths, wis_alphas.' / 2, 2);
        forecast_upper = quantile(ensemble_paths, 1 - wis_alphas.' / 2, 2);

        horizon_wis = compute_wis(target_Rt, forecast_median, forecast_lower, forecast_upper, wis_alphas);

        if numel(horizon_wis) ~= horizon || any(~isfinite(horizon_wis))
            error('PARTC_02:InvalidCandidateWIS', 'Candidate forecast produced invalid horizon-level WIS.');
        end

        origin_mean_wis(origin_position) = mean(horizon_wis);

    catch ME
        if any(string(ME.identifier) == recognized_failures)
            failure_record = struct("candidate_index", candidate_index, "candidate_configuration", candidate_configuration, "forecast_origin_index", origin_index, "forecast_origin_date", origin_date, "error_identifier", string(ME.identifier), "error_message", string(ME.message));

            fprintf('Infeasible %s/%s candidate %s at %s: %s\n', active_configuration.model_type, active_configuration.exo_mode, mat2str(candidate_configuration), string(origin_date), ME.identifier);

            return;
        end

        rethrow(ME);
    end
end

end