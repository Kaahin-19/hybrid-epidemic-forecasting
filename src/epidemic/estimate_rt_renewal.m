function Rt_estimated = estimate_rt_renewal(incidence, weights, min_infectiousness)

%ESTIMATE_RT_RENEWAL Estimate Rt from incidence using renewal weights.
%
%   Syntax:
%       Rt_estimated = estimate_rt_renewal(incidence, weights, min_infectiousness)
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
%       incidence          - T-by-1 nonnegative incidence.
%       weights            - L-by-1 normalized lag weights.
%       min_infectiousness - Nonnegative minimum renewal denominator.
%
%   Outputs:
%       Rt_estimated - T-by-1 renewal Rt estimate with undefined entries NaN.
%
%   See also PARTC_01_PREPARE_DATA, SERIAL_INTERVAL_WEIGHTS.
%
% A. M. Kaahin 2026-06-30
% Modified: 2026-08-23

%% 1. Parameter Domain
if min_infectiousness < 0
    error('RENEWAL:InvalidMinimumInfectiousness', 'min_infectiousness must be nonnegative.');
end

%% 2. Renewal Estimation
num_time = numel(incidence);
max_lag = numel(weights);

Rt_estimated = NaN(num_time, 1);

for time_index = (max_lag + 1):num_time
    lag_indices = time_index - (1:max_lag).';
    infectiousness = sum(weights .* incidence(lag_indices));

    if infectiousness > 0 && infectiousness >= min_infectiousness
        Rt_estimated(time_index) = incidence(time_index) / infectiousness;
    end
end

end