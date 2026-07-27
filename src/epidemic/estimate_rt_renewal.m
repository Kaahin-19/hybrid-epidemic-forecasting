function Rt_estimated = estimate_rt_renewal(incidence, weights, min_infectiousness)
%ESTIMATE_RT_RENEWAL Estimate Rt from incidence with fixed renewal weights.
%
%   Syntax:
%       Rt_estimated = estimate_rt_renewal(incidence, weights, min_infectiousness)
%
%   Description:
%       Estimates an operational effective reproduction-number series from
%       observed incidence using the renewal ratio
%
%           infectiousness(t) = sum_s weights(s) * incidence(t - s)
%           Rt_estimated(t)   = incidence(t) / infectiousness(t).
%
%       The weights represent lags 1 through numel(weights). Estimates are
%       produced only after a complete lag history is available and when
%       infectiousness is strictly positive and at least the configured
%       minimum. Undefined estimates remain NaN. The supplied weights must
%       sum to one within an absolute numerical tolerance of 1e-12.
%
%   Inputs:
%       incidence            - T-by-1 real, finite, nonnegative incidence
%                              column vector.
%       weights              - L-by-1 real, finite, nonnegative, nonempty
%                              serial-interval weight column vector.
%       min_infectiousness   - Real, finite, nonnegative scalar minimum
%                              renewal denominator.
%
%   Outputs:
%       Rt_estimated - T-by-1 renewal Rt estimate. The first L entries and
%                      entries with invalid infectiousness are NaN.
%
%   See also SERIAL_INTERVAL_WEIGHTS, PARTC_01_PREPARE_DATA.
%
% A. M. Kaahin 2026-06-30
% Modified: 2026-07-27

    %% 1. Input Validation
    if ~isnumeric(incidence) || ~isreal(incidence) || ~iscolumn(incidence)
        error('RENEWAL:InvalidIncidence', ...
            'incidence must be a real numeric column vector.');
    end

    if any(~isfinite(incidence)) || any(incidence < 0)
        error('RENEWAL:InvalidIncidence', ...
            'incidence must be finite and nonnegative.');
    end

    if ~isnumeric(weights) || ~isreal(weights) || ~iscolumn(weights) || isempty(weights)
        error('RENEWAL:InvalidWeights', ...
            'weights must be a real, nonempty numeric column vector.');
    end

    if any(~isfinite(weights)) || any(weights < 0)
        error('RENEWAL:InvalidWeights', ...
            'weights must be finite and nonnegative.');
    end

    weight_sum_tolerance = 1e-12;
    if abs(sum(weights) - 1) > weight_sum_tolerance
        error('RENEWAL:InvalidWeightSum', ...
            'weights must sum to one within an absolute tolerance of %.0e.', ...
            weight_sum_tolerance);
    end

    if ~isnumeric(min_infectiousness) || ~isreal(min_infectiousness) || ...
            ~isscalar(min_infectiousness) || ~isfinite(min_infectiousness) || ...
            min_infectiousness < 0
        error('RENEWAL:InvalidMinimumInfectiousness', ...
            'min_infectiousness must be a real, finite, nonnegative scalar.');
    end

    %% 2. Renewal Estimate
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
