function weights = serial_interval_weights(mean_days, sd_days, max_lag_days)
%SERIAL_INTERVAL_WEIGHTS Construct normalized discrete gamma lag weights.
%
%   Syntax:
%       weights = serial_interval_weights(mean_days, sd_days, max_lag_days)
%
%   Description:
%       Constructs serial-interval weights by matching a gamma distribution
%       to the supplied mean and standard deviation, integrating its
%       probability mass over daily lag bins 1 through max_lag_days, and
%       normalizing the truncated weights to sum to one.
%
%   Inputs:
%       mean_days     - Positive real finite gamma mean in days.
%       sd_days       - Positive real finite gamma standard deviation in days.
%       max_lag_days  - Positive integer maximum lag in days.
%
%   Outputs:
%       weights - max_lag_days-by-1 normalized nonnegative weight vector.
%
%   See also ESTIMATE_RT_RENEWAL, PARTC_CONFIG.
%
% A. M. Kaahin 2026-07-27

    %% 1. Input Validation
    if ~isnumeric(mean_days) || ~isreal(mean_days) || ~isscalar(mean_days) || ...
            ~isfinite(mean_days) || mean_days <= 0
        error('EPIDEMIC:InvalidSerialIntervalMean', ...
            'mean_days must be a real, finite, positive scalar.');
    end

    if ~isnumeric(sd_days) || ~isreal(sd_days) || ~isscalar(sd_days) || ...
            ~isfinite(sd_days) || sd_days <= 0
        error('EPIDEMIC:InvalidSerialIntervalSD', ...
            'sd_days must be a real, finite, positive scalar.');
    end

    if ~isnumeric(max_lag_days) || ~isreal(max_lag_days) || ...
            ~isscalar(max_lag_days) || ~isfinite(max_lag_days) || ...
            max_lag_days < 1 || mod(max_lag_days, 1) ~= 0
        error('EPIDEMIC:InvalidSerialIntervalLag', ...
            'max_lag_days must be a real, finite, positive integer scalar.');
    end

    %% 2. Gamma Discretization
    gamma_shape = (mean_days / sd_days)^2;
    gamma_scale = sd_days^2 / mean_days;
    lag_days = (1:max_lag_days)';

    upper_probability = gammainc(lag_days / gamma_scale, gamma_shape);
    lower_probability = gammainc((lag_days - 1) / gamma_scale, gamma_shape);
    weights = upper_probability - lower_probability;

    if any(~isfinite(weights)) || any(weights < 0) || sum(weights) <= 0
        error('EPIDEMIC:InvalidSerialIntervalWeights', ...
            'The configured gamma approximation produced invalid lag weights.');
    end

    weights = weights / sum(weights);
end
