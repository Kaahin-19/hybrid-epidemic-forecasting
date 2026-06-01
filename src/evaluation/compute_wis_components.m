function components = compute_wis_components(truth_Rt, median_Rt, lower_Rt, upper_Rt, alphas)
%COMPUTE_WIS_COMPONENTS Decompose raw-scale pointwise WIS values.
%
%   Syntax:
%       components = compute_wis_components(truth_Rt, median_Rt, lower_Rt, upper_Rt, alphas)
%
%   Description:
%       Computes raw-scale pointwise weighted interval score values and
%       decomposes them into median absolute-error, dispersion, lower-tail
%       miss, and upper-tail miss components. The total matches compute_wis.
%
%   Inputs:
%       truth_Rt  - Horizon-by-one vector of true Rt values.
%       median_Rt - Horizon-by-one vector of predictive medians.
%       lower_Rt  - Horizon-by-numAlphas lower interval matrix.
%       upper_Rt  - Horizon-by-numAlphas upper interval matrix.
%       alphas    - Row vector of interval miscoverage rates.
%
%   Outputs:
%       components - Structure with raw_scale_wis, median, dispersion,
%                    underprediction, overprediction, and per-alpha
%                    interval component matrices.
%
%   See also COMPUTE_WIS.
%
% A. M. Kaahin 2026-06-01

    %% 1. Input Validation
    truth_Rt = double(truth_Rt(:));
    median_Rt = double(median_Rt(:));
    lower_Rt = double(lower_Rt);
    upper_Rt = double(upper_Rt);
    alphas = reshape(double(alphas), 1, []);

    local_validate_shapes(truth_Rt, median_Rt, lower_Rt, upper_Rt, alphas);

    %% 2. Component Computation
    num_intervals = numel(alphas);
    denominator = num_intervals + 0.5;
    horizon = numel(truth_Rt);

    median_component = 0.5 * abs(truth_Rt - median_Rt) / denominator;
    sharpness_by_interval = nan(horizon, num_intervals);
    under_by_interval = nan(horizon, num_intervals);
    over_by_interval = nan(horizon, num_intervals);
    interval_score = nan(horizon, num_intervals);
    interval_component = nan(horizon, num_intervals);

    for j = 1:num_intervals
        alpha = alphas(j);
        width = upper_Rt(:, j) - lower_Rt(:, j);
        under_miss = max(lower_Rt(:, j) - truth_Rt, 0);
        over_miss = max(truth_Rt - upper_Rt(:, j), 0);

        interval_score(:, j) = width ...
            + (2 / alpha) * under_miss ...
            + (2 / alpha) * over_miss;
        sharpness_by_interval(:, j) = ((alpha / 2) * width) / denominator;
        under_by_interval(:, j) = under_miss / denominator;
        over_by_interval(:, j) = over_miss / denominator;
        interval_component(:, j) = ((alpha / 2) * interval_score(:, j)) / denominator;
    end

    dispersion_component = sum(sharpness_by_interval, 2);
    under_component = sum(under_by_interval, 2);
    over_component = sum(over_by_interval, 2);
    raw_scale_wis = median_component + dispersion_component + ...
        under_component + over_component;

    raw_scale_wis(~isfinite(raw_scale_wis)) = inf;

    %% 3. Output Assembly
    components = struct();
    components.raw_scale_wis = raw_scale_wis;
    components.median = median_component;
    components.dispersion = dispersion_component;
    components.underprediction = under_component;
    components.overprediction = over_component;
    components.interval_score = interval_score;
    components.interval_component = interval_component;
    components.sharpness_by_interval = sharpness_by_interval;
    components.underprediction_by_interval = under_by_interval;
    components.overprediction_by_interval = over_by_interval;
end

function local_validate_shapes(truth_Rt, median_Rt, lower_Rt, upper_Rt, alphas)
%LOCAL_VALIDATE_SHAPES Validate metric input dimensions.
    horizon = numel(truth_Rt);
    if horizon == 0 || numel(median_Rt) ~= horizon || isempty(alphas) || ...
            size(lower_Rt, 1) ~= horizon || size(upper_Rt, 1) ~= horizon || ...
            size(lower_Rt, 2) ~= numel(alphas) || ...
            size(upper_Rt, 2) ~= numel(alphas)
        error('EVALUATION:InvalidForecastShape', ...
            'Forecast vectors and interval matrices have incompatible dimensions.');
    end

    if any(alphas <= 0 | alphas >= 1)
        error('EVALUATION:InvalidAlpha', ...
            'Interval alphas must satisfy 0 < alpha < 1.');
    end
end
