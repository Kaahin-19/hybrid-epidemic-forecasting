function weights = serial_interval_weights(mean_days, sd_days, max_lag)
%SERIAL_INTERVAL_WEIGHTS Discretized, normalized gamma serial-interval weights.
%
%   Syntax:
%       weights = serial_interval_weights(mean_days, sd_days, max_lag)
%
%   Description:
%       Builds a fixed, assumption-driven serial/generation-interval weight
%       vector by evaluating a gamma density at integer day lags 1..max_lag
%       and normalizing the result to sum to one. The weights are used by the
%       renewal Rt estimator shared across the Part B observation-noise channel
%       and the Part C real-data preprocessing stage. The serial interval is an
%       external epidemiological assumption; it is never inferred from the case
%       series being analysed.
%
%   Inputs:
%       mean_days - Positive serial-interval mean in days.
%       sd_days   - Positive serial-interval standard deviation in days.
%       max_lag   - Positive integer maximum lag in days.
%
%   Outputs:
%       weights   - max_lag-by-one normalized weight vector for lags 1..max_lag.
%
%   See also ESTIMATE_RT_RENEWAL.
%
% A. M. Kaahin 2026-06-12

    %% 1. Input Validation
    if mean_days <= 0 || sd_days <= 0 || max_lag < 1
        error('EPIDEMIC:InvalidSerialInterval', ...
            'Serial interval mean, standard deviation, and max lag must be positive.');
    end

    %% 2. Gamma Discretization and Normalization
    lag_days = (1:max_lag)';
    shape = (mean_days / sd_days)^2;
    scale = (sd_days^2) / mean_days;
    weights = (lag_days.^(shape - 1) .* exp(-lag_days / scale)) ./ ...
        (gamma(shape) * scale^shape);
    weights = weights / sum(weights);
end
