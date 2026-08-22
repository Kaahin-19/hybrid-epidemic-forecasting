function Rt_estimated = estimate_rt_renewal(incidence, weights, min_infectiousness)
%ESTIMATE_RT_RENEWAL Estimate Rt from incidence using renewal weights.
%
%   Description:
%       Estimates an operational effective reproduction-number series from
%       incidence using
%
%           infectiousness(t) = sum_s weights(s) * incidence(t - s)
%           Rt_estimated(t)   = incidence(t) / infectiousness(t).
%
%       Estimates begin only after the complete lag history is available.
%       Entries with insufficient infectiousness remain NaN.
%
%   Inputs:
%       incidence          - T-by-1 finite, nonnegative incidence.
%       weights            - L-by-1 finite, nonnegative normalized lag weights.
%       min_infectiousness - Nonnegative minimum renewal denominator.
%
%   Outputs:
%       Rt_estimated - T-by-1 renewal Rt estimate with undefined entries NaN.
%
%   See also SERIAL_INTERVAL_WEIGHTS, PARTC_01_PREPARE_DATA.
%
% A. M. Kaahin 2026-06-30
% Modified: 2026-08-22

%% 1. Input Domains
if isempty(incidence) || ~iscolumn(incidence) || ~isreal(incidence) || any(~isfinite(incidence)) || any(incidence < 0)
    error('RENEWAL:InvalidIncidence', 'incidence must be a nonempty, finite, nonnegative real column vector.');
end

if isempty(weights) || ~iscolumn(weights) || ~isreal(weights) || any(~isfinite(weights)) || any(weights < 0)
    error('RENEWAL:InvalidWeights', 'weights must be a nonempty, finite, nonnegative real column vector.');
end

weight_sum_tolerance = 1e-12;

if abs(sum(weights) - 1) > weight_sum_tolerance
    error('RENEWAL:InvalidWeightSum', 'weights must sum to one within an absolute tolerance of %.0e.', weight_sum_tolerance);
end

if ~isscalar(min_infectiousness) || ~isreal(min_infectiousness) || ~isfinite(min_infectiousness) || min_infectiousness < 0
    error('RENEWAL:InvalidMinimumInfectiousness', 'min_infectiousness must be a finite nonnegative real scalar.');
end

%% 2. Renewal Estimation
num_time = numel(incidence);
max_lag = numel(weights);

Rt_estimated = NaN(num_time, 1);

for time_index = (max_lag + 1):num_time
    lag_indices = time_index - (1:max_lag)';
    infectiousness = sum(weights .* incidence(lag_indices));

    if infectiousness > 0 && infectiousness >= min_infectiousness
        Rt_estimated(time_index) = incidence(time_index) / infectiousness;
    end
end

end