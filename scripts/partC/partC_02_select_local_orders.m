%PARTC_02_SELECT_LOCAL_ORDERS Select local AR/None and ARX/I configurations.
%
%   Description:
%       Starts from the AR/None and ARX/I configurations selected by Part A,
%       constructs configuration-specific local neighbourhoods, and compares
%       candidates on one shared chronological calibration block from the
%       prepared Swedish data. Feasible candidates complete every common
%       expanding-window origin; recognized forecast-domain failures mark the
%       active candidate infeasible without altering its forecasts or the
%       candidate grid. Selection uses calibration WIS under a one-standard-
%       error complexity rule. ARX/I uses the prepared infectious fraction and
%       the aligned reported-case SIRS proxy state. Held-out test observations
%       are not used.
%
%   Workflow:
%       1. Load the Part C local-selection configuration.
%       2. Load and validate the shared prepared-data artifact once.
%       3. Build one common set of calibration forecast origins.
%       4. Load each configuration's Part A baseline.
%       5. Construct and validate each local candidate grid.
%       6. Refit and score candidates, recording recognized infeasibility.
%       7. Apply the one-standard-error complexity rule.
%       8. Save one independent artifact for each configuration.
%
%   See also PARTC_CONFIG, PARTC_01_PREPARE_DATA, ...
%            PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS, FORECAST_OPEN, ...
%            FORECAST_CLOSED, SIRS_INIT, COMPUTE_WIS.
%
% A. M. Kaahin 2026-07-28
% Modified: 2026-08-06

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Local Configuration Selection ===\n');

cfg = partC_config();
configurations = cfg.local_selection.configurations;

valid_configuration_list = numel(configurations) == 2 && ...
    configurations(1).model_type == "AR" && ...
    configurations(1).exo_mode == "None" && ...
    configurations(2).model_type == "ARX" && ...
    configurations(2).exo_mode == "I";

if ~valid_configuration_list
    error('PARTC_02:UnsupportedConfigurationList', ...
        'Local selection requires exactly AR/None and ARX/I.');
end

%% 2. Load and Validate Shared Prepared Data
[calibration, preparation_snapshot] = local_load_calibration_data(cfg);

fprintf('Calibration period: %s to %s\n', ...
    string(calibration.dates(1)), string(calibration.dates(end)));

%% 3. Build Common Calibration Forecast Origins
[forecast_origin_indices, forecast_origin_dates] = ...
    local_build_forecast_origins(calibration.dates, cfg);

%% 4. Select Each Supported Configuration
for configuration_index = 1:numel(configurations)
    active_configuration = configurations(configuration_index);
    model_type = active_configuration.model_type;
    exo_mode = active_configuration.exo_mode;

    fprintf('\nModel: %s | Exogenous mode: %s\n', model_type, exo_mode);

    partA_selected_configuration = ...
        local_load_partA_baseline(active_configuration);
    candidate_configurations = local_construct_candidate_grid( ...
        partA_selected_configuration, active_configuration, ...
        cfg.local_selection.order_radius);
    candidate_complexity = sum(candidate_configurations, 2);

    local_validate_minimum_window(candidate_configurations, ...
        active_configuration, cfg.local_selection.min_window);

    base_stepper = [];
    if model_type == "ARX"
        sirs_parameters = struct( ...
            "gamma", cfg.state_reconstruction.gamma, ...
            "xi", cfg.state_reconstruction.xi, ...
            "pop_size", cfg.state_reconstruction.effective_population, ...
            "min_susceptible", ...
            cfg.state_reconstruction.min_susceptible);
        step_options = struct( ...
            "solver", "uds", ...
            "seed", cfg.local_selection.seed);
        base_stepper = sirs_init(sirs_parameters, step_options);
    end

    num_candidates = size(candidate_configurations, 1);
    num_origins = numel(forecast_origin_indices);
    candidate_origin_mean_wis = nan(num_candidates, num_origins);
    candidate_feasible_mask = false(num_candidates, 1);
    failure_record_template = struct( ...
        "candidate_index", NaN, ...
        "candidate_configuration", [], ...
        "forecast_origin_index", NaN, ...
        "forecast_origin_date", NaT, ...
        "error_identifier", "", ...
        "error_message", "");
    candidate_failure_records = repmat( ...
        failure_record_template, num_candidates, 1);
    num_failure_records = 0;

    for candidate_index = 1:num_candidates
        candidate_configuration = ...
            candidate_configurations(candidate_index, :);

        fprintf('Evaluating candidate %d/%d: %s\n', ...
            candidate_index, num_candidates, ...
            mat2str(candidate_configuration));

        [origin_mean_wis, candidate_feasible, failure_record] = ...
            local_evaluate_candidate(active_configuration, ...
            candidate_configuration, candidate_index, calibration, ...
            forecast_origin_indices, base_stepper, cfg);
        candidate_origin_mean_wis(candidate_index, :) = origin_mean_wis.';
        candidate_feasible_mask(candidate_index) = candidate_feasible;

        if ~isempty(failure_record)
            num_failure_records = num_failure_records + 1;
            candidate_failure_records(num_failure_records) = failure_record;
        end
    end

    candidate_failure_records = ...
        candidate_failure_records(1:num_failure_records);

    completed_origin_mask = all(isfinite(candidate_origin_mean_wis), 2);
    if ~isequal(candidate_feasible_mask, completed_origin_mask)
        error('PARTC_02:CandidateFeasibilityMismatch', ...
            'Candidate feasibility must match completion of every finite origin WIS.');
    end

    candidate_mean_wis = inf(num_candidates, 1);
    candidate_se_wis = inf(num_candidates, 1);
    candidate_mean_wis(candidate_feasible_mask) = mean( ...
        candidate_origin_mean_wis(candidate_feasible_mask, :), 2);
    candidate_se_wis(candidate_feasible_mask) = std( ...
        candidate_origin_mean_wis(candidate_feasible_mask, :), 0, 2) / ...
        sqrt(num_origins);

    if any(~isfinite(candidate_mean_wis(candidate_feasible_mask))) || ...
            any(~isfinite(candidate_se_wis(candidate_feasible_mask)))
        error('PARTC_02:InvalidCandidateScores', ...
            'Feasible candidate mean WIS and standard errors must be finite.');
    end

    selection_pool_mask = candidate_feasible_mask & ...
        isfinite(candidate_mean_wis);
    selection_pool_indices = find(selection_pool_mask);

    if isempty(selection_pool_indices)
        error('PARTC_02:NoFeasibleCandidate', ...
            'No feasible candidate completed all origins for %s/%s.', ...
            model_type, exo_mode);
    end

    [best_mean_wis, best_pool_position] = min( ...
        candidate_mean_wis(selection_pool_indices));
    numerically_best_index = ...
        selection_pool_indices(best_pool_position);
    numerically_best_configuration = ...
        candidate_configurations(numerically_best_index, :);
    selection_threshold = best_mean_wis + ...
        candidate_se_wis(numerically_best_index);
    eligible_indices = find(selection_pool_mask & ...
        candidate_mean_wis <= selection_threshold);

    eligible_ranking = [ ...
        candidate_complexity(eligible_indices), ...
        candidate_mean_wis(eligible_indices), ...
        eligible_indices];
    eligible_ranking = sortrows(eligible_ranking, [1, 2, 3]);
    selected_index = eligible_ranking(1, 3);
    selected_configuration = ...
        candidate_configurations(selected_index, :);
    selection_rule = cfg.local_selection.selection_rule;

    %% 5. Save Configuration Artifact
    artifact = struct();
    artifact.model_type = model_type;
    artifact.exo_mode = exo_mode;
    artifact.strategy = "local_order_online_fit";
    artifact.partA_selection_artifact_path = ...
        active_configuration.partA_selection_artifact_path;
    artifact.partA_selected_configuration = ...
        partA_selected_configuration;
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
    artifact.numerically_best_configuration = ...
        numerically_best_configuration;
    artifact.selection_threshold = selection_threshold;
    artifact.eligible_indices = eligible_indices;
    artifact.selected_index = selected_index;
    artifact.selected_configuration = selected_configuration;
    artifact.selection_rule = selection_rule;
    artifact.prepared_artifact_path = cfg.output.prepared_artifact_path;
    artifact.preparation_snapshot = preparation_snapshot;
    artifact.local_selection_snapshot = ...
        active_configuration.local_selection_snapshot;

    if exist(cfg.output.model_selection_dir, 'dir') ~= 7
        mkdir(cfg.output.model_selection_dir);
    end

    save(active_configuration.local_selection_artifact_path, ...
        '-struct', 'artifact');

    fprintf('Part A baseline: %s\n', ...
        mat2str(partA_selected_configuration));
    fprintf('Local candidate grid: %s\n', ...
        mat2str(candidate_configurations));
    fprintf('Feasible candidates: %d | Infeasible candidates: %d\n', ...
        nnz(candidate_feasible_mask), nnz(~candidate_feasible_mask));
    fprintf('Selected local configuration: %s\n', ...
        mat2str(selected_configuration));
    fprintf('Saved artifact: %s\n', ...
        active_configuration.local_selection_artifact_path);
end

fprintf('\n=== Part C Local Configuration Selection Complete ===\n\n');

%% 6. Local Functions
function [calibration, preparation_snapshot] = ...
        local_load_calibration_data(cfg)
%LOCAL_LOAD_CALIBRATION_DATA Load and validate the shared calibration block.
prepared_artifact_path = cfg.output.prepared_artifact_path;

if exist(prepared_artifact_path, 'file') ~= 2
    error('PARTC_02:MissingPreparedArtifact', ...
        'Missing prepared Part C artifact: %s. Run Part C Script 1 first.', ...
        prepared_artifact_path);
end

prepared = load(prepared_artifact_path);
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

if ~all(isfield(prepared, required_fields))
    missing_fields = required_fields(~isfield(prepared, required_fields));
    error('PARTC_02:MissingPreparedFields', ...
        'Prepared Part C artifact is missing fields: %s.', ...
        strjoin(string(missing_fields), ', '));
end

dates = prepared.dates;
Rt_estimated = prepared.Rt_estimated;
Rt_valid_mask = prepared.Rt_valid_mask;
I_fraction_proxy = prepared.I_fraction_proxy;
S_proxy = prepared.S_proxy;
I_proxy = prepared.I_proxy;
R_proxy = prepared.R_proxy;
state_valid_mask = prepared.state_valid_mask;
preparation_snapshot = prepared.preparation_snapshot;

if ~isdatetime(dates) || ~iscolumn(dates) || any(isnat(dates))
    error('PARTC_02:InvalidPreparedDates', ...
        'Prepared dates must be a valid datetime column vector.');
end

if numel(unique(dates)) ~= numel(dates) || ...
        any(diff(dates) ~= days(1))
    error('PARTC_02:InvalidPreparedDates', ...
        'Prepared dates must be unique, strictly increasing, and daily.');
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
    "R_proxy"
    ];

for signal_index = 1:numel(numeric_signals)
    signal = numeric_signals{signal_index};
    if ~isnumeric(signal) || ~isreal(signal) || ~iscolumn(signal)
        error('PARTC_02:InvalidPreparedSignal', ...
            '%s must be a real numeric column vector.', ...
            numeric_signal_names(signal_index));
    end
end

if ~islogical(Rt_valid_mask) || ~iscolumn(Rt_valid_mask) || ...
        ~islogical(state_valid_mask) || ~iscolumn(state_valid_mask)
    error('PARTC_02:InvalidPreparedMask', ...
        'Rt_valid_mask and state_valid_mask must be logical column vectors.');
end

signal_lengths = [ ...
    numel(Rt_estimated)
    numel(Rt_valid_mask)
    numel(I_fraction_proxy)
    numel(S_proxy)
    numel(I_proxy)
    numel(R_proxy)
    numel(state_valid_mask)
    ];

if any(signal_lengths ~= numel(dates))
    error('PARTC_02:PreparedLengthMismatch', ...
        'All prepared signals and masks must match the dates vector length.');
end

expected_valid_mask = isfinite(Rt_estimated) & Rt_estimated > 0;
if ~isequal(Rt_valid_mask, expected_valid_mask)
    error('PARTC_02:EstimatedRtMaskMismatch', ...
        'Rt_valid_mask must equal isfinite(Rt_estimated) & Rt_estimated > 0.');
end

if any(~isfinite(I_fraction_proxy)) || ...
        any(I_fraction_proxy < 0 | I_fraction_proxy > 1)
    error('PARTC_02:InvalidInfectiousFractionProxy', ...
        'I_fraction_proxy must be finite and within [0, 1].');
end

if ~isequaln(preparation_snapshot, cfg.snapshot.preparation)
    error('PARTC_02:PreparationSnapshotMismatch', ...
        'Prepared Part C artifact does not match the current preparation configuration.');
end

calibration_end_index = find( ...
    dates == cfg.validation.calibration_end_date, 1);
test_start_index = find(dates == cfg.validation.test_start_date, 1);

if isempty(calibration_end_index) || isempty(test_start_index)
    error('PARTC_02:MissingValidationBoundary', ...
        'Prepared dates must contain the configured calibration end and test start dates.');
end

first_valid_index = find( ...
    Rt_valid_mask & dates <= cfg.validation.calibration_end_date, 1);

if isempty(first_valid_index)
    error('PARTC_02:NoValidCalibrationRt', ...
        'No valid Rt_estimated observation exists in the calibration period.');
end

calibration_indices = first_valid_index:calibration_end_index;
invalid_calibration_index = find( ...
    ~Rt_valid_mask(calibration_indices), 1);

if ~isempty(invalid_calibration_index)
    prepared_index = calibration_indices(invalid_calibration_index);
    error('PARTC_02:InternalInvalidCalibrationRt', ...
        'Rt_estimated is invalid inside the calibration block on %s.', ...
        string(dates(prepared_index)));
end

if any(~state_valid_mask(calibration_indices))
    error('PARTC_02:InvalidCalibrationStateMask', ...
        'Every selected calibration state must satisfy state_valid_mask.');
end

selected_states = [ ...
    S_proxy(calibration_indices), ...
    I_proxy(calibration_indices), ...
    R_proxy(calibration_indices)];

if any(~isfinite(selected_states), 'all')
    error('PARTC_02:InvalidCalibrationStates', ...
        'Every selected calibration state must be finite.');
end


if any(selected_states(:, 1) <= ...
        cfg.state_reconstruction.min_susceptible)
    error('PARTC_02:SusceptibleBelowThreshold', ...
        'Every selected susceptible proxy must exceed the configured threshold.');
end


if any(selected_states(:, 2) < 0) || any(selected_states(:, 3) < 0)
    error('PARTC_02:NegativeCalibrationState', ...
        'Selected infectious and recovered proxies must be nonnegative.');
end

state_sum_error = abs(sum(selected_states, 2) - ...
    cfg.state_reconstruction.effective_population);
if any(state_sum_error > ...
        cfg.state_reconstruction.conservation_tolerance)
    error('PARTC_02:StateConservationFailure', ...
        'Selected proxy states do not conserve the effective population.');
end

calibration = struct();
calibration.dates = dates(calibration_indices);
calibration.Rt = Rt_estimated(calibration_indices);
calibration.I_fraction_proxy = I_fraction_proxy(calibration_indices);
calibration.S_proxy = S_proxy(calibration_indices);
calibration.I_proxy = I_proxy(calibration_indices);
calibration.R_proxy = R_proxy(calibration_indices);

if any(calibration.dates >= cfg.validation.test_start_date)
    error('PARTC_02:CalibrationLeakage', ...
        'The calibration series contains held-out test-period dates.');
end
end

function [forecast_origin_indices, forecast_origin_dates] = ...
        local_build_forecast_origins(calibration_dates, cfg)
%LOCAL_BUILD_FORECAST_ORIGINS Build common expanding-window origins.
horizon = cfg.local_selection.horizon;
min_window = cfg.local_selection.min_window;
step_size = cfg.local_selection.step_size;
last_origin_index = numel(calibration_dates) - horizon;

forecast_origin_indices = (min_window:step_size:last_origin_index)';

if isempty(forecast_origin_indices)
    error('PARTC_02:NoCalibrationOrigins', ...
        'The valid calibration series is too short for the configured forecast protocol.');
end

forecast_origin_dates = calibration_dates(forecast_origin_indices);
target_end_indices = forecast_origin_indices + horizon;
target_end_dates = calibration_dates(target_end_indices);

if any(target_end_dates > cfg.validation.calibration_end_date) || ...
        any(target_end_dates >= cfg.validation.test_start_date)
    error('PARTC_02:CalibrationLeakage', ...
        'At least one calibration forecast target enters the held-out test period.');
end
end

function selected_configuration = ...
        local_load_partA_baseline(active_configuration)
%LOCAL_LOAD_PARTA_BASELINE Load and validate one Part A selected configuration.
artifact_path = active_configuration.partA_selection_artifact_path;

if exist(artifact_path, 'file') ~= 2
    error('PARTC_02:MissingPartABaseline', ...
        'Missing Part A %s/%s selection artifact: %s.', ...
        active_configuration.model_type, active_configuration.exo_mode, ...
        artifact_path);
end

selection = load(artifact_path);
required_fields = {'selected_configuration'; 'snapshot'};

if ~all(isfield(selection, required_fields))
    missing_fields = required_fields(~isfield(selection, required_fields));
    error('PARTC_02:MissingPartABaselineFields', ...
        'Part A selection artifact is missing fields: %s.', ...
        strjoin(string(missing_fields), ', '));
end


if ~isequaln(selection.snapshot, ...
        active_configuration.partA_selection_snapshot)
    error('PARTC_02:PartABaselineSnapshotMismatch', ...
        'Part A %s/%s artifact does not match its selection protocol.', ...
        active_configuration.model_type, active_configuration.exo_mode);
end


if isfield(selection, 'model_type') && ...
        ~isequal(selection.model_type, active_configuration.model_type)
    error('PARTC_02:ContradictoryPartAMetadata', ...
        'Part A selection artifact contains contradictory model_type metadata.');
end


if isfield(selection, 'exo_mode') && ...
        ~isequal(selection.exo_mode, active_configuration.exo_mode)
    error('PARTC_02:ContradictoryPartAMetadata', ...
        'Part A selection artifact contains contradictory exo_mode metadata.');
end

selected_configuration = selection.selected_configuration;

if ~isnumeric(selected_configuration) || ...
        ~isreal(selected_configuration) || ...
        any(~isfinite(selected_configuration)) || ...
        any(selected_configuration < 1) || ...
        any(mod(selected_configuration, 1) ~= 0)
    error('PARTC_02:InvalidPartASelectedConfiguration', ...
        'Part A selected_configuration must contain positive integers.');
end


if active_configuration.model_type == "AR"
    valid_dimensions = isscalar(selected_configuration);
else
    valid_dimensions = isequal(size(selected_configuration), [1, 3]);
end


if ~valid_dimensions
    error('PARTC_02:InvalidPartASelectedConfiguration', ...
        'Part A %s/%s selected_configuration has invalid dimensions.', ...
        active_configuration.model_type, active_configuration.exo_mode);
end
end

function candidate_configurations = local_construct_candidate_grid( ...
        partA_configuration, active_configuration, order_radius)
%LOCAL_CONSTRUCT_CANDIDATE_GRID Construct one deterministic local grid.
if ~isnumeric(order_radius) || ~isreal(order_radius) || ...
        ~isscalar(order_radius) || ~isfinite(order_radius) || ...
        order_radius < 0 || mod(order_radius, 1) ~= 0
    error('PARTC_02:InvalidOrderRadius', ...
        'The local order radius must be a finite nonnegative integer scalar.');
end


switch active_configuration.model_type
    case "AR"
        candidate_configurations = ((partA_configuration - order_radius): ...
            (partA_configuration + order_radius))';
        candidate_configurations = ...
            candidate_configurations(candidate_configurations >= 1);
    case "ARX"
        na_values = (partA_configuration(1) - order_radius): ...
            (partA_configuration(1) + order_radius);
        nb_values = (partA_configuration(2) - order_radius): ...
            (partA_configuration(2) + order_radius);
        nk_values = (partA_configuration(3) - order_radius): ...
            (partA_configuration(3) + order_radius);
        [na_grid, nb_grid, nk_grid] = ndgrid( ...
            na_values, nb_values, nk_values);
        candidate_configurations = [ ...
            na_grid(:), nb_grid(:), nk_grid(:)];
        candidate_configurations = candidate_configurations( ...
            all(candidate_configurations >= 1, 2), :);
    otherwise
        error('PARTC_02:UnsupportedConfiguration', ...
            'Unsupported local-selection model type: %s.', ...
            active_configuration.model_type);
end

candidate_configurations = unique(candidate_configurations, 'rows');
candidate_configurations = sortrows(candidate_configurations);

valid_grid = ~isempty(candidate_configurations) && ...
    all(isfinite(candidate_configurations), 'all') && ...
    all(candidate_configurations >= 1, 'all') && ...
    all(mod(candidate_configurations, 1) == 0, 'all') && ...
    ismember(partA_configuration, candidate_configurations, 'rows');

if ~valid_grid
    error('PARTC_02:InvalidCandidateGrid', ...
        'The local candidate grid must be sorted, unique, positive, integer-valued, and contain the Part A configuration.');
end
end

function local_validate_minimum_window( ...
        candidate_configurations, active_configuration, min_window)
%LOCAL_VALIDATE_MINIMUM_WINDOW Require enough fitting and residual observations.
switch active_configuration.model_type
    case "AR"
        sufficient_history = min_window > ...
            candidate_configurations(:, 1) + 1;
    case "ARX"
        max_lag = max(candidate_configurations(:, 1), ...
            candidate_configurations(:, 3) + ...
            candidate_configurations(:, 2) - 1);
        sufficient_history = min_window - max_lag >= 2;
end


if any(~sufficient_history)
    error('PARTC_02:InsufficientMinimumWindow', ...
        'The configured minimum window is too short for at least one %s/%s candidate.', ...
        active_configuration.model_type, active_configuration.exo_mode);
end
end

function [origin_mean_wis, candidate_feasible, failure_record] = ...
        local_evaluate_candidate( ...
        active_configuration, candidate_configuration, candidate_index, ...
        calibration, forecast_origin_indices, base_stepper, cfg)
%LOCAL_EVALUATE_CANDIDATE Refit and score one configuration at every origin.
num_origins = numel(forecast_origin_indices);
origin_mean_wis = nan(num_origins, 1);
candidate_feasible = false;
failure_record = struct( ...
    "candidate_index", {}, ...
    "candidate_configuration", {}, ...
    "forecast_origin_index", {}, ...
    "forecast_origin_date", {}, ...
    "error_identifier", {}, ...
    "error_message", {});
horizon = cfg.local_selection.horizon;
wis_alphas = cfg.local_selection.wis_alphas;

for origin_position = 1:num_origins
    origin_index = forecast_origin_indices(origin_position);
    origin_date = calibration.dates(origin_index);
    training_Rt = calibration.Rt(1:origin_index);
    target_Rt = calibration.Rt(origin_index + (1:horizon));
    resample_seed = cfg.local_selection.seed + ...
        100000 * candidate_index + origin_index;

    try
        switch active_configuration.model_type
            case "AR"
                ensemble_paths = forecast_open( ...
                    "AR", candidate_configuration, training_Rt, ...
                    cfg.local_selection.num_draws, horizon, resample_seed);
            case "ARX"
                training_U = ...
                    calibration.I_fraction_proxy(1:origin_index);
                origin_state = [ ...
                    calibration.S_proxy(origin_index), ...
                    calibration.I_proxy(origin_index), ...
                    calibration.R_proxy(origin_index)];
                epidemic_seed = cfg.local_selection.seed + 1000000 + ...
                    100000 * candidate_index + origin_index;
                ensemble_paths = forecast_closed( ...
                    "ARX", candidate_configuration, training_Rt, ...
                    training_U, origin_state, 1, ...
                    cfg.local_selection.num_draws, horizon, "I", ...
                    base_stepper, resample_seed, epidemic_seed, ...
                    cfg.local_selection.include_epidemic_seed_variation);
        end

        forecast_median = median(ensemble_paths, 2);
        forecast_lower = quantile( ...
            ensemble_paths, wis_alphas.' / 2, 2);
        forecast_upper = quantile( ...
            ensemble_paths, 1 - wis_alphas.' / 2, 2);

        valid_forecast = size(ensemble_paths, 1) == horizon && ...
            size(ensemble_paths, 2) == cfg.local_selection.num_draws && ...
            numel(forecast_median) == horizon && ...
            all(isfinite(forecast_median)) && ...
            all(forecast_median > 0) && ...
            all(isfinite(forecast_lower), 'all') && ...
            all(isfinite(forecast_upper), 'all') && ...
            all(forecast_lower <= forecast_upper, 'all');

        if ~valid_forecast
            error('PARTC_02:InvalidCandidateForecast', ...
                'Forecast ensemble or prediction intervals are invalid.');
        end

        horizon_wis = compute_wis(target_Rt, forecast_median, ...
            forecast_lower, forecast_upper, wis_alphas);

        if numel(horizon_wis) ~= horizon || ...
                any(~isfinite(horizon_wis))
            error('PARTC_02:InvalidCandidateWIS', ...
                'Candidate forecast produced invalid horizon-level WIS.');
        end

        origin_mean_wis(origin_position) = mean(horizon_wis);
    catch underlying_error
        [recognized_failure, matched_error] = ...
            local_find_candidate_infeasibility(underlying_error);

        if recognized_failure
            failure_record = struct( ...
                "candidate_index", candidate_index, ...
                "candidate_configuration", candidate_configuration, ...
                "forecast_origin_index", origin_index, ...
                "forecast_origin_date", origin_date, ...
                "error_identifier", string(matched_error.identifier), ...
                "error_message", string(matched_error.message));
            fprintf(['Infeasible %s/%s candidate %s at %s: ' ...
                '%s\n'], ...
                active_configuration.model_type, ...
                active_configuration.exo_mode, ...
                mat2str(candidate_configuration), string(origin_date), ...
                matched_error.identifier);
            return;
        end

        contextual_error = MException( ...
            'PARTC_02:CandidateEvaluationFailed', ...
            ['Candidate configuration %s failed at forecast origin %d ' ...
            '(%s). Underlying error: %s'], ...
            mat2str(candidate_configuration), origin_index, ...
            string(origin_date), underlying_error.message);
        contextual_error = addCause(contextual_error, underlying_error);
        throw(contextual_error);
    end
end

candidate_feasible = all(isfinite(origin_mean_wis));
end

function [recognized_failure, matched_error] = ...
        local_find_candidate_infeasibility(current_error)
%LOCAL_FIND_CANDIDATE_INFEASIBILITY Find a recognized error in a cause chain.
recognized_identifiers = [ ...
    "FORECAST_CLOSED:InvalidForecastDraw"
    "EPIDEMIC:SusceptibleBelowThreshold"
    ];

recognized_failure = any( ...
    string(current_error.identifier) == recognized_identifiers);
matched_error = current_error;

if recognized_failure
    return;
end

for cause_index = 1:numel(current_error.cause)
    [recognized_failure, matched_error] = ...
        local_find_candidate_infeasibility( ...
        current_error.cause{cause_index});

    if recognized_failure
        return;
    end
end
end
