function wis = compute_wis(truth_Rt, median_Rt, lower_Rt, upper_Rt, alphas)
%COMPUTE_WIS Compute pointwise weighted interval score values.
%
%   Syntax:
%       wis = compute_wis(truth_Rt, median_Rt, lower_Rt, upper_Rt, alphas)
%
%   Description:
%       Computes the pointwise weighted interval score for effective
%       reproduction-number forecasts using a predictive median and central
%       interval bounds. The formula matches the Part A model-selection
%       convention, with a median absolute-error term and alpha-weighted
%       interval scores.
%
%   Inputs:
%       truth_Rt  - Horizon-by-one vector of true Rt values.
%       median_Rt - Horizon-by-one vector of predictive medians.
%       lower_Rt  - Horizon-by-numAlphas lower interval matrix.
%       upper_Rt  - Horizon-by-numAlphas upper interval matrix.
%       alphas    - Row vector of interval miscoverage rates.
%
%   Outputs:
%       wis - Horizon-by-one vector of pointwise WIS values.
%
%   See also COMPUTE_RMSE, COMPUTE_COVERAGE.
%
% A. M. Kaahin 2026-06-01

    %% 1. Input Validation
    truth_Rt = double(truth_Rt(:));
    median_Rt = double(median_Rt(:));
    lower_Rt = double(lower_Rt);
    upper_Rt = double(upper_Rt);
    alphas = reshape(double(alphas), 1, []);

    local_validate_shapes(truth_Rt, median_Rt, lower_Rt, upper_Rt, alphas);

    %% 2. WIS Computation
    num_intervals = numel(alphas);
    wis = 0.5 * abs(truth_Rt - median_Rt);

    for j = 1:num_intervals
        alpha = alphas(j);
        interval_score = (upper_Rt(:, j) - lower_Rt(:, j)) ...
            + (2 / alpha) * max(lower_Rt(:, j) - truth_Rt, 0) ...
            + (2 / alpha) * max(truth_Rt - upper_Rt(:, j), 0);
        wis = wis + (alpha / 2) * interval_score;
    end

    wis = wis / (num_intervals + 0.5);
    wis(~isfinite(wis)) = inf;
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
