function weights = serial_interval_weights(mean_days, sd_days, tail_probability)

%SERIAL_INTERVAL_WEIGHTS Construct normalized discrete lognormal lag weights.
%
%   Syntax:
%       weights = serial_interval_weights(mean_days, sd_days, tail_probability)
%
%   Description:
%       Converts the supplied arithmetic serial-interval mean and standard
%       deviation to log-space parameters, integrates the resulting lognormal
%       probability mass over daily lag bins, and normalizes the finite weights
%       to sum to one. The support ends at the smallest positive integer lag
%       whose remaining upper-tail probability does not exceed the configured
%       tolerance.
%
%   Inputs:
%       mean_days       - Positive arithmetic serial-interval mean in days.
%       sd_days         - Positive arithmetic serial-interval standard
%                         deviation in days.
%       tail_probability - Upper-tail probability tolerance strictly between
%                          zero and one.
%
%   Outputs:
%       weights - L-by-1 normalized lag weights for days 1:L, where L is
%                 determined automatically from the lognormal distribution.
%
%   See also PARTC_01_PREPARE_DATA, ESTIMATE_RT_RENEWAL.
%
% A. M. Kaahin 2026-07-27
% Modified: 2026-09-26

%% 1. Parameter Domains
if ~isscalar(mean_days) || ~isfinite(mean_days) || mean_days <= 0
    error('EPIDEMIC:InvalidSerialIntervalMean', 'The arithmetic mean mean_days must be a finite positive scalar.');
end

if ~isscalar(sd_days) || ~isfinite(sd_days) || sd_days <= 0
    error('EPIDEMIC:InvalidSerialIntervalSD', 'The arithmetic standard deviation sd_days must be a finite positive scalar.');
end

if ~isscalar(tail_probability) || ~isfinite(tail_probability) || tail_probability <= 0 || tail_probability >= 1
    error('EPIDEMIC:InvalidSerialIntervalTailProbability', 'tail_probability must be a finite scalar strictly between zero and one.');
end

%% 2. Lognormal Parameters and Support
sigma_log_squared = log(1 + sd_days^2 / mean_days^2);
sigma_log = sqrt(sigma_log_squared);
mu_log = log(mean_days) - 0.5 * sigma_log_squared;

if ~isfinite(mu_log) || ~isfinite(sigma_log) || sigma_log <= 0
    error('EPIDEMIC:InvalidLognormalParameters', 'The arithmetic moments must produce finite lognormal parameters with positive sigma_log.');
end

log_support_quantile = mu_log + sigma_log * sqrt(2) * erfcinv(2 * tail_probability);
support_quantile = exp(log_support_quantile);
support_length = max(1, ceil(support_quantile));

if ~isfinite(support_length) || support_length < 1 || support_length ~= floor(support_length) || support_length > flintmax
    error('EPIDEMIC:InvalidSerialIntervalSupport', 'The tail probability must produce a finite positive integer support length.');
end

remaining_tail_probability = 0.5 * erfc((log(support_length) - mu_log) / (sigma_log * sqrt(2)));

while remaining_tail_probability > tail_probability
    support_length = support_length + 1;

    if ~isfinite(support_length) || support_length > flintmax
        error('EPIDEMIC:InvalidSerialIntervalSupport', 'The tail probability must produce a finite positive integer support length.');
    end

    remaining_tail_probability = 0.5 * erfc((log(support_length) - mu_log) / (sigma_log * sqrt(2)));
end

while support_length > 1
    previous_tail_probability = 0.5 * erfc((log(support_length - 1) - mu_log) / (sigma_log * sqrt(2)));

    if previous_tail_probability > tail_probability
        break;
    end

    support_length = support_length - 1;
    remaining_tail_probability = previous_tail_probability;
end

%% 3. Daily Discretization
lag_boundaries = (1:support_length).';
cumulative_probability = zeros(support_length + 1, 1);
cumulative_probability(2:end) = 0.5 * erfc(-(log(lag_boundaries) - mu_log) / (sigma_log * sqrt(2)));
weights = diff(cumulative_probability);

if any(~isfinite(weights))
    error('EPIDEMIC:InvalidSerialIntervalWeights', 'The lognormal discretization produced nonfinite serial-interval weights.');
end

if any(weights < 0)
    error('EPIDEMIC:InvalidSerialIntervalWeights', 'The lognormal discretization produced negative serial-interval weights.');
end

retained_probability = sum(weights);

if ~isfinite(retained_probability) || retained_probability <= 0
    error('EPIDEMIC:InvalidRetainedProbability', 'The finite lognormal support must retain positive finite probability mass.');
end

if ~isfinite(remaining_tail_probability) || remaining_tail_probability > tail_probability
    error('EPIDEMIC:SerialIntervalTailTolerance', 'The remaining lognormal upper-tail probability exceeds tail_probability.');
end

weights = weights / retained_probability;

if abs(sum(weights) - 1) > 10 * eps(1)
    error('EPIDEMIC:SerialIntervalNormalization', 'Normalized lognormal serial-interval weights must sum to one within floating-point precision.');
end

end
