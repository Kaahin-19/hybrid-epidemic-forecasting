function weights = serial_interval_weights(mean_days, sd_days, max_lag_days)
%SERIAL_INTERVAL_WEIGHTS Construct normalized discrete gamma lag weights.
%
%   Description:
%       Matches a gamma distribution to the supplied serial-interval mean and
%       standard deviation, integrates its probability mass over daily lag
%       bins, and normalizes the truncated weights to sum to one.
%
%   Inputs:
%       mean_days    - Positive serial-interval mean in days.
%       sd_days      - Positive serial-interval standard deviation in days.
%       max_lag_days - Positive integer maximum lag in days.
%
%   Outputs:
%       weights - Normalized lag weights for days 1:max_lag_days.
%
%   See also ESTIMATE_RT_RENEWAL, PARTC_CONFIG.
%
% A. M. Kaahin 2026-07-27
% Modified: 2026-08-22

%% 1. Parameter Domains
if ~isfinite(mean_days) || mean_days <= 0
    error('EPIDEMIC:InvalidSerialIntervalMean', 'mean_days must be finite and positive.');
end

if ~isfinite(sd_days) || sd_days <= 0
    error('EPIDEMIC:InvalidSerialIntervalSD', 'sd_days must be finite and positive.');
end

if ~isfinite(max_lag_days) || max_lag_days < 1 || max_lag_days ~= floor(max_lag_days)
    error('EPIDEMIC:InvalidSerialIntervalLag', 'max_lag_days must be a finite positive integer.');
end

%% 2. Gamma Discretization
gamma_shape = (mean_days / sd_days)^2;
gamma_scale = sd_days^2 / mean_days;
lag_days = (1:max_lag_days).';

upper_probability = gammainc(lag_days / gamma_scale, gamma_shape);
lower_probability = gammainc((lag_days - 1) / gamma_scale, gamma_shape);
weights = upper_probability - lower_probability;

if any(~isfinite(weights)) || any(weights < 0) || sum(weights) <= 0
    error('EPIDEMIC:InvalidSerialIntervalWeights', 'The gamma approximation produced invalid serial-interval weights.');
end

weights = weights / sum(weights);

end