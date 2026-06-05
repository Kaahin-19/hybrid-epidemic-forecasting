function metrics = evaluate_forecast_window_metrics( ...
    truth_Rt, pred_Rt, lower_Rt, upper_Rt, alphas)
%EVALUATE_FORECAST_WINDOW_METRICS Compute forecast-window evaluation metrics.
%
%   Syntax:
%       metrics = evaluate_forecast_window_metrics( ...
%           truth_Rt, pred_Rt, lower_Rt, upper_Rt, alphas)
%
%   Description:
%       Computes the shared Rt forecast metrics used by the Part A, Part B,
%       and Part C evaluation scripts for one forecast window. The function
%       preserves the existing invalid-window convention: malformed forecasts
%       receive infinite pointwise/window WIS, infinite RMSE/MAE, and NaN
%       interval/calibration summaries.
%
%   Inputs:
%       truth_Rt - Horizon-by-one vector of true Rt values.
%       pred_Rt  - Horizon-by-one vector of median forecast Rt values.
%       lower_Rt - Horizon-by-numAlphas lower interval matrix.
%       upper_Rt - Horizon-by-numAlphas upper interval matrix.
%       alphas   - Vector of interval miscoverage rates.
%
%   Outputs:
%       metrics - Structure containing validity, WIS, RMSE, MAE, coverage,
%                 calibration, interval-width, and WIS-component metrics.
%
%   See also COMPUTE_WIS_COMPONENTS.
%
% A. M. Kaahin 2026-06-05

    %% 1. Input Normalization
    truth_Rt = double(truth_Rt(:));
    pred_Rt = double(pred_Rt(:));
    lower_Rt = double(lower_Rt);
    upper_Rt = double(upper_Rt);
    alphas = reshape(double(alphas), 1, []);

    horizon = numel(truth_Rt);
    is_valid = local_is_valid_forecast(truth_Rt, pred_Rt, lower_Rt, upper_Rt, alphas);

    %% 2. Metric Computation
    if is_valid
        wis_components = compute_wis_components(truth_Rt, pred_Rt, ...
            lower_Rt, upper_Rt, alphas);
        pointwise_wis = wis_components.raw_scale_wis;
        window_rmse = local_compute_rmse(truth_Rt, pred_Rt);
        window_mae = local_compute_mae(truth_Rt, pred_Rt);
        coverage = local_compute_coverage(truth_Rt, lower_Rt, upper_Rt);
        interval_width = local_compute_interval_width(lower_Rt, upper_Rt);
        nominal_coverage = local_nominal_coverage_matrix(horizon, alphas);
        calibration_error = coverage - nominal_coverage;
        window_wis = mean(pointwise_wis);
    else
        pointwise_wis = inf(max(horizon, 0), 1);
        wis_components = local_nan_wis_components(max(horizon, 0), numel(alphas));
        window_rmse = inf;
        window_mae = inf;
        coverage = nan(max(horizon, 0), numel(alphas));
        interval_width = nan(max(horizon, 0), numel(alphas));
        calibration_error = nan(max(horizon, 0), numel(alphas));
        window_wis = inf;
    end

    %% 3. Summary Assembly
    metrics = struct();
    metrics.is_valid = is_valid;
    metrics.horizon = horizon;
    metrics.pointwise_wis = pointwise_wis;
    metrics.wis_components = wis_components;
    metrics.window_wis = window_wis;
    metrics.window_rmse = window_rmse;
    metrics.window_mae = window_mae;
    metrics.coverage = coverage;
    metrics.interval_width = interval_width;
    metrics.calibration_error = calibration_error;

    metrics.mean_wis_median_component = local_mean_finite(wis_components.median);
    metrics.mean_wis_dispersion_component = local_mean_finite( ...
        wis_components.dispersion);
    metrics.mean_wis_under_component = local_mean_finite( ...
        wis_components.underprediction);
    metrics.mean_wis_over_component = local_mean_finite( ...
        wis_components.overprediction);
    metrics.mean_coverage = local_mean_finite(coverage(:));
    metrics.mean_calibration_bias = local_mean_finite(calibration_error(:));
    metrics.mean_absolute_calibration_error = local_mean_finite( ...
        abs(calibration_error(:)));
    metrics.mean_interval_width = local_mean_finite(interval_width(:));

    metrics.coverage_mean = local_row_mean_finite(coverage);
    metrics.calibration_bias_mean = local_row_mean_finite(calibration_error);
    metrics.absolute_calibration_mean = local_row_mean_finite(abs(calibration_error));
    metrics.width_mean = local_row_mean_finite(interval_width);
end

function is_valid = local_is_valid_forecast(truth_Rt, pred_Rt, lower_Rt, upper_Rt, alphas)
%LOCAL_IS_VALID_FORECAST Verify forecast metric input shape and values.
    is_valid = ...
        ~isempty(truth_Rt) && ~isempty(alphas) && ...
        numel(pred_Rt) == numel(truth_Rt) && ...
        size(lower_Rt, 1) == numel(truth_Rt) && ...
        size(upper_Rt, 1) == numel(truth_Rt) && ...
        size(lower_Rt, 2) == numel(alphas) && ...
        size(upper_Rt, 2) == numel(alphas) && ...
        all(isfinite(truth_Rt(:))) && all(isfinite(pred_Rt(:))) && ...
        all(pred_Rt(:) > 0) && all(isfinite(lower_Rt(:))) && ...
        all(isfinite(upper_Rt(:))) && all(lower_Rt(:) > 0) && ...
        all(upper_Rt(:) > 0) && all(lower_Rt(:) <= upper_Rt(:));
end

function nominal_coverage = local_nominal_coverage_matrix(horizon, alphas)
%LOCAL_NOMINAL_COVERAGE_MATRIX Expand nominal coverage by horizon.
    nominal_coverage = repmat(1 - reshape(double(alphas), 1, []), horizon, 1);
end

function components = local_nan_wis_components(horizon, num_alphas)
%LOCAL_NAN_WIS_COMPONENTS Create placeholder WIS component arrays.
    components = struct();
    components.raw_scale_wis = inf(horizon, 1);
    components.median = nan(horizon, 1);
    components.dispersion = nan(horizon, 1);
    components.underprediction = nan(horizon, 1);
    components.overprediction = nan(horizon, 1);
    components.interval_score = nan(horizon, num_alphas);
    components.interval_component = nan(horizon, num_alphas);
    components.sharpness_by_interval = nan(horizon, num_alphas);
    components.underprediction_by_interval = nan(horizon, num_alphas);
    components.overprediction_by_interval = nan(horizon, num_alphas);
end

function values = local_row_mean_finite(matrix_values)
%LOCAL_ROW_MEAN_FINITE Compute finite row means without toolboxes.
    values = nan(size(matrix_values, 1), 1);
    for i = 1:size(matrix_values, 1)
        values(i) = local_mean_finite(matrix_values(i, :));
    end
end

function value = local_mean_finite(values)
%LOCAL_MEAN_FINITE Mean over finite numeric values only.
    values = double(values(:));
    values = values(isfinite(values));
    if isempty(values)
        value = nan;
    else
        value = mean(values);
    end
end

function rmse = local_compute_rmse(truth_Rt, pred_Rt)
%LOCAL_COMPUTE_RMSE Root mean squared error over finite paired values.
    truth_Rt = double(truth_Rt(:));
    pred_Rt = double(pred_Rt(:));

    if numel(truth_Rt) ~= numel(pred_Rt)
        error('EVALUATION:InvalidForecastShape', ...
            'truth_Rt and pred_Rt must have the same number of elements.');
    end

    finite_idx = isfinite(truth_Rt) & isfinite(pred_Rt);
    if ~any(finite_idx)
        rmse = inf;
        return;
    end

    residuals = pred_Rt(finite_idx) - truth_Rt(finite_idx);
    rmse = sqrt(mean(residuals .^ 2));
end

function mae = local_compute_mae(truth_Rt, pred_Rt)
%LOCAL_COMPUTE_MAE Mean absolute error over finite paired values.
    truth_Rt = double(truth_Rt(:));
    pred_Rt = double(pred_Rt(:));

    if numel(truth_Rt) ~= numel(pred_Rt)
        error('EVALUATION:InvalidForecastShape', ...
            'Truth and prediction vectors must have the same length.');
    end

    valid_idx = isfinite(truth_Rt) & isfinite(pred_Rt);
    if ~any(valid_idx)
        mae = inf;
        return;
    end

    mae = mean(abs(pred_Rt(valid_idx) - truth_Rt(valid_idx)));
end

function coverage = local_compute_coverage(truth_Rt, lower_Rt, upper_Rt)
%LOCAL_COMPUTE_COVERAGE Pointwise interval coverage indicators (0/1/NaN).
    truth_Rt = double(truth_Rt(:));
    lower_Rt = double(lower_Rt);
    upper_Rt = double(upper_Rt);

    if isempty(truth_Rt) || size(lower_Rt, 1) ~= numel(truth_Rt) || ...
            size(upper_Rt, 1) ~= numel(truth_Rt) || ...
            size(lower_Rt, 2) ~= size(upper_Rt, 2)
        error('EVALUATION:InvalidForecastShape', ...
            'truth_Rt and interval matrices have incompatible dimensions.');
    end

    truth_matrix = repmat(truth_Rt, 1, size(lower_Rt, 2));
    valid_idx = isfinite(truth_matrix) & isfinite(lower_Rt) & ...
        isfinite(upper_Rt) & lower_Rt <= upper_Rt;

    coverage = nan(size(lower_Rt));
    coverage(valid_idx) = double(truth_matrix(valid_idx) >= lower_Rt(valid_idx) & ...
        truth_matrix(valid_idx) <= upper_Rt(valid_idx));
end

function interval_width = local_compute_interval_width(lower_Rt, upper_Rt)
%LOCAL_COMPUTE_INTERVAL_WIDTH Interval widths with NaN for malformed bounds.
    lower_Rt = double(lower_Rt);
    upper_Rt = double(upper_Rt);

    if ~isequal(size(lower_Rt), size(upper_Rt))
        error('EVALUATION:InvalidForecastShape', ...
            'lower_Rt and upper_Rt must have identical dimensions.');
    end

    interval_width = upper_Rt - lower_Rt;
    invalid_idx = ~isfinite(lower_Rt) | ~isfinite(upper_Rt) | ...
        lower_Rt > upper_Rt;
    interval_width(invalid_idx) = nan;
end
