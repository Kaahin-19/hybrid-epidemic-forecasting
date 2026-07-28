%PARTC_02_SELECT_LOCAL_ORDERS Select a limited AR order refinement on Swedish Rt.
%
%   Description:
%       Starts from the AR/None order selected by Part A, constructs only the
%       configured local order neighbourhood, and compares those candidates
%       on the chronological calibration portion of the incidence-derived
%       Swedish Rt_estimated series. Each candidate is refitted at every
%       expanding-window forecast origin and selected by calibration WIS under
%       a one-standard-error simplicity rule. Held-out test observations are
%       not used. ARX refinement is excluded because the prepared real-data
%       artifact contains no SIRS-compatible mechanistic state estimates.
%
%   Workflow:
%       1. Load the Part C local-selection configuration.
%       2. Load and validate the prepared incidence-derived Rt series.
%       3. Load and validate the Part A AR/None baseline order.
%       4. Construct the configured local AR-order neighbourhood.
%       5. Build common expanding-window calibration forecast origins.
%       6. Refit and score every candidate at every calibration origin.
%       7. Apply the one-standard-error simplicity rule.
%       8. Save one canonical local-selection artifact.
%
%   See also PARTC_CONFIG, PARTC_01_PREPARE_DATA, ...
%            PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS, FORECAST_OPEN, ...
%            COMPUTE_WIS.
%
% A. M. Kaahin 2026-07-28

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Local Order Selection ===\n');

cfg = partC_config();
model_type = cfg.local_selection.model_type;
exo_mode = cfg.local_selection.exo_mode;

if model_type ~= "AR" || exo_mode ~= "None"
    error('PARTC_02:UnsupportedModelScope', ...
        'Part C local selection currently supports only AR with exogenous mode None.');
end

fprintf('Model: %s | Exogenous mode: %s\n', model_type, exo_mode);

%% 2. Load and Validate Prepared Data
[calibration_dates, calibration_Rt, preparation_snapshot] = ...
    local_load_calibration_data(cfg);

fprintf('Calibration period: %s to %s\n', ...
    string(calibration_dates(1)), string(calibration_dates(end)));

%% 3. Load Part A Baseline Order
[partA_selected_configuration, partA_selected_order] = ...
    local_load_partA_baseline(cfg);

partA_selection_artifact_path = ...
    cfg.local_selection.partA_selection_artifact_path;

fprintf('Part A baseline order: %d\n', partA_selected_order);

%% 4. Construct Local Candidate Grid
order_radius = cfg.local_selection.order_radius;

if ~isnumeric(order_radius) || ~isreal(order_radius) || ...
        ~isscalar(order_radius) || ~isfinite(order_radius) || ...
        order_radius < 0 || mod(order_radius, 1) ~= 0
    error('PARTC_02:InvalidOrderRadius', ...
        'The local AR-order radius must be a finite nonnegative integer scalar.');
end

candidate_orders = ((partA_selected_order - order_radius): ...
    (partA_selected_order + order_radius))';
candidate_orders = candidate_orders(candidate_orders >= 1);
candidate_configurations = candidate_orders;

if isempty(candidate_orders) || ...
        any(diff(candidate_orders) <= 0) || ...
        any(candidate_orders < 1) || ...
        any(mod(candidate_orders, 1) ~= 0) || ...
        ~any(candidate_orders == partA_selected_order)
    error('PARTC_02:InvalidCandidateGrid', ...
        'The local AR candidate grid must be sorted, unique, positive, integer-valued, and contain the Part A order.');
end

if cfg.local_selection.min_window <= max(candidate_orders) + 1
    error('PARTC_02:InsufficientMinimumWindow', ...
        'The configured minimum window is too short for local AR order %d.', ...
        max(candidate_orders));
end

fprintf('Local candidate orders: %s\n', mat2str(candidate_orders.'));

%% 5. Build Calibration Forecast Origins
horizon = cfg.local_selection.horizon;
min_window = cfg.local_selection.min_window;
step_size = cfg.local_selection.step_size;
last_origin_index = numel(calibration_Rt) - horizon;

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

%% 6. Evaluate Local Candidates
num_candidates = numel(candidate_orders);
num_origins = numel(forecast_origin_indices);
candidate_origin_mean_wis = nan(num_candidates, num_origins);

for candidate_index = 1:num_candidates
    candidate_order = candidate_orders(candidate_index);

    fprintf('Evaluating candidate %d/%d: AR(%d)\n', ...
        candidate_index, num_candidates, candidate_order);

    candidate_origin_mean_wis(candidate_index, :) = ...
        local_evaluate_candidate(candidate_order, candidate_index, ...
        calibration_dates, calibration_Rt, forecast_origin_indices, cfg).';
end

candidate_mean_wis = mean(candidate_origin_mean_wis, 2);
candidate_se_wis = std(candidate_origin_mean_wis, 0, 2) / sqrt(num_origins);

if any(~isfinite(candidate_mean_wis)) || any(~isfinite(candidate_se_wis))
    error('PARTC_02:InvalidCandidateScores', ...
        'Local candidate mean WIS and standard errors must be finite.');
end

%% 7. Apply Selection Rule
[best_mean_wis, numerically_best_index] = min(candidate_mean_wis);
numerically_best_order = candidate_orders(numerically_best_index);
selection_threshold = best_mean_wis + ...
    candidate_se_wis(numerically_best_index);
eligible_indices = find(candidate_mean_wis <= selection_threshold);

[~, simplest_eligible_position] = min(candidate_orders(eligible_indices));
selected_index = eligible_indices(simplest_eligible_position);
selected_order = candidate_orders(selected_index);
selected_configuration = candidate_configurations(selected_index, :);
selection_rule = cfg.local_selection.selection_rule;

fprintf('Selected local order: %d\n', selected_order);

%% 8. Save Local-Selection Artifact
prepared_artifact_path = cfg.output.prepared_artifact_path;
local_selection_snapshot = cfg.snapshot.local_selection;
strategy = "local_order_online_fit";

if exist(cfg.output.model_selection_dir, 'dir') ~= 7
    mkdir(cfg.output.model_selection_dir);
end

artifact = struct();
artifact.model_type = model_type;
artifact.exo_mode = exo_mode;
artifact.strategy = strategy;
artifact.partA_selection_artifact_path = partA_selection_artifact_path;
artifact.partA_selected_configuration = partA_selected_configuration;
artifact.partA_selected_order = partA_selected_order;
artifact.candidate_orders = candidate_orders;
artifact.candidate_configurations = candidate_configurations;
artifact.calibration_dates = calibration_dates;
artifact.calibration_end_date = cfg.validation.calibration_end_date;
artifact.test_start_date = cfg.validation.test_start_date;
artifact.forecast_origin_indices = forecast_origin_indices;
artifact.forecast_origin_dates = forecast_origin_dates;
artifact.candidate_origin_mean_wis = candidate_origin_mean_wis;
artifact.candidate_mean_wis = candidate_mean_wis;
artifact.candidate_se_wis = candidate_se_wis;
artifact.numerically_best_index = numerically_best_index;
artifact.numerically_best_order = numerically_best_order;
artifact.selection_threshold = selection_threshold;
artifact.eligible_indices = eligible_indices;
artifact.selected_index = selected_index;
artifact.selected_order = selected_order;
artifact.selected_configuration = selected_configuration;
artifact.selection_rule = selection_rule;
artifact.prepared_artifact_path = prepared_artifact_path;
artifact.preparation_snapshot = preparation_snapshot;
artifact.local_selection_snapshot = local_selection_snapshot;

save(cfg.output.local_selection_artifact_path, '-struct', 'artifact');

fprintf('Selection artifact saved to: %s\n', ...
    cfg.output.local_selection_artifact_path);
fprintf('=== Part C Local Order Selection Complete ===\n\n');

%% 9. Local Functions
function [calibration_dates, calibration_Rt, preparation_snapshot] = ...
        local_load_calibration_data(cfg)
%LOCAL_LOAD_CALIBRATION_DATA Load and validate the contiguous calibration Rt block.
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

if ~isnumeric(Rt_estimated) || ~isreal(Rt_estimated) || ...
        ~iscolumn(Rt_estimated)
    error('PARTC_02:InvalidEstimatedRt', ...
        'Rt_estimated must be a real numeric column vector.');
end

if ~islogical(Rt_valid_mask) || ~iscolumn(Rt_valid_mask)
    error('PARTC_02:InvalidEstimatedRtMask', ...
        'Rt_valid_mask must be a logical column vector.');
end

if numel(Rt_estimated) ~= numel(dates) || ...
        numel(Rt_valid_mask) ~= numel(dates)
    error('PARTC_02:PreparedLengthMismatch', ...
        'Prepared dates, Rt_estimated, and Rt_valid_mask must have equal lengths.');
end

expected_valid_mask = isfinite(Rt_estimated) & Rt_estimated > 0;
if ~isequal(Rt_valid_mask, expected_valid_mask)
    error('PARTC_02:EstimatedRtMaskMismatch', ...
        'Rt_valid_mask must equal isfinite(Rt_estimated) & Rt_estimated > 0.');
end

if any(~isfinite(Rt_estimated(Rt_valid_mask))) || ...
        any(Rt_estimated(Rt_valid_mask) <= 0)
    error('PARTC_02:InvalidEstimatedRt', ...
        'Every Rt_estimated entry marked valid must be finite and strictly positive.');
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

calibration_dates = dates(calibration_indices);
calibration_Rt = Rt_estimated(calibration_indices);

if any(calibration_dates >= cfg.validation.test_start_date)
    error('PARTC_02:CalibrationLeakage', ...
        'The calibration series contains held-out test-period dates.');
end
end

function [selected_configuration, selected_order] = ...
        local_load_partA_baseline(cfg)
%LOCAL_LOAD_PARTA_BASELINE Load and validate the canonical Part A AR/None order.
artifact_path = cfg.local_selection.partA_selection_artifact_path;

if exist(artifact_path, 'file') ~= 2
    error('PARTC_02:MissingPartABaseline', ...
        'Missing Part A AR/None selection artifact: %s. Run Part A Script 2 for AR/None first.', ...
        artifact_path);
end

selection = load(artifact_path);
required_fields = {'selected_configuration'; 'snapshot'};

if ~all(isfield(selection, required_fields))
    missing_fields = required_fields(~isfield(selection, required_fields));
    error('PARTC_02:MissingPartABaselineFields', ...
        'Part A AR/None selection artifact is missing fields: %s.', ...
        strjoin(string(missing_fields), ', '));
end

if ~isequaln(selection.snapshot, ...
        cfg.local_selection.partA_selection_snapshot)
    error('PARTC_02:PartABaselineSnapshotMismatch', ...
        'Part A AR/None selection artifact does not match the current Part A selection protocol.');
end

if isfield(selection, 'model_type') && ...
        ~isequal(selection.model_type, cfg.local_selection.model_type)
    error('PARTC_02:ContradictoryPartAMetadata', ...
        'Part A selection artifact contains contradictory model_type metadata.');
end

if isfield(selection, 'exo_mode') && ...
        ~isequal(selection.exo_mode, cfg.local_selection.exo_mode)
    error('PARTC_02:ContradictoryPartAMetadata', ...
        'Part A selection artifact contains contradictory exo_mode metadata.');
end

selected_configuration = selection.selected_configuration;

if ~isnumeric(selected_configuration) || ...
        ~isreal(selected_configuration) || ...
        numel(selected_configuration) ~= 1 || ...
        ~isfinite(selected_configuration) || ...
        selected_configuration < 1 || ...
        mod(selected_configuration, 1) ~= 0
    error('PARTC_02:InvalidPartASelectedOrder', ...
        'Part A selected_configuration must contain one positive integer AR order.');
end

selected_order = selected_configuration;
end

function origin_mean_wis = local_evaluate_candidate( ...
        candidate_order, candidate_index, calibration_dates, ...
        calibration_Rt, forecast_origin_indices, cfg)
%LOCAL_EVALUATE_CANDIDATE Refit and score one AR order at every origin.
num_origins = numel(forecast_origin_indices);
origin_mean_wis = nan(num_origins, 1);
horizon = cfg.local_selection.horizon;
wis_alphas = cfg.local_selection.wis_alphas;

for origin_position = 1:num_origins
    origin_index = forecast_origin_indices(origin_position);
    origin_date = calibration_dates(origin_index);
    training_Rt = calibration_Rt(1:origin_index);
    target_Rt = calibration_Rt(origin_index + (1:horizon));
    resample_seed = cfg.local_selection.seed + ...
        100000 * candidate_index + origin_index;

    try
        ensemble_paths = forecast_open("AR", candidate_order, ...
            training_Rt, cfg.local_selection.num_draws, horizon, ...
            resample_seed);

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
            all(isfinite(forecast_lower(:))) && ...
            all(isfinite(forecast_upper(:))) && ...
            all(forecast_lower(:) <= forecast_upper(:));

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
        contextual_error = MException( ...
            'PARTC_02:CandidateEvaluationFailed', ...
            ['Candidate order %d failed at forecast origin %d ' ...
            '(%s). Underlying error: %s'], ...
            candidate_order, origin_index, string(origin_date), ...
            underlying_error.message);
        contextual_error = addCause(contextual_error, underlying_error);
        throw(contextual_error);
    end
end
end
