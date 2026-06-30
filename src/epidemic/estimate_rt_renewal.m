function [Rt_est, info] = estimate_rt_renewal(incidence, opts)
%ESTIMATE_RT_RENEWAL Estimate effective Rt from incidence by the renewal ratio.
%
%   Syntax:
%       [Rt_est, info] = estimate_rt_renewal(incidence, opts)
%
%   Description:
%       Estimates the effective reproduction number from an incidence time
%       series using the renewal-equation ratio estimator:
%
%           lambda(t) = sum_s w(s) * incidence(t - s)
%           Rt_est(t) = incidence(t) / lambda(t)
%
%       The serial-interval weights w(s) are a discretized gamma distribution
%       over lags s = 1..max_lag. The estimator uses one fixed warmup policy:
%       entries with insufficient history (t <= max_lag) or a renewal
%       denominator below min_denominator are invalid and represented as NaN.
%       No values are filled, clipped, repaired, or smoothed.
%
%   Inputs:
%       incidence - T-by-1 nonnegative finite incidence column vector
%                   (new cases or new infections per time step).
%       opts      - Structure with fields:
%                     serial_interval_mean_days    - Gamma SI mean (days).
%                     serial_interval_sd_days      - Gamma SI std. dev. (days).
%                     serial_interval_max_lag_days - Maximum lag (days).
%                     min_denominator              - Minimum valid lambda.
%
%   Outputs:
%       Rt_est - T-by-1 renewal Rt estimate; warmup and low-denominator
%                entries are NaN.
%       info   - Structure with fields:
%                  renewal_lambda          - T-by-1 renewal denominator.
%                  serial_interval_weights - max_lag-by-1 normalized weights.
%                  valid_mask              - T-by-1 logical validity mask.
%                  options                 - Echo of opts plus the resolved
%                                            gamma parameters and the fixed
%                                            warmup_method = "nan".
%
%   See also PARTB_01_GENERATE_ROBUSTNESS_DATASETS.
%
% A. M. Kaahin 2026-06-30

    %% 1. Input Validation
    if ~isnumeric(incidence) || ~iscolumn(incidence)
        error('RENEWAL:InvalidIncidence', 'incidence must be a numeric column vector.');
    end

    if any(~isfinite(incidence)) || any(incidence < 0)
        error('RENEWAL:InvalidIncidence', 'incidence must be finite and nonnegative.');
    end

    local_assert_positive_scalar(opts, 'serial_interval_mean_days', false);
    local_assert_positive_scalar(opts, 'serial_interval_sd_days', false);
    local_assert_positive_scalar(opts, 'serial_interval_max_lag_days', true);
    local_assert_positive_scalar(opts, 'min_denominator', false);

    %% 2. Serial-Interval Weights
    max_lag = opts.serial_interval_max_lag_days;
    weights = local_serial_interval_weights(opts.serial_interval_mean_days, opts.serial_interval_sd_days, max_lag);

    %% 3. Renewal Denominator
    num_time = numel(incidence);
    renewal_lambda = zeros(num_time, 1);

    for t = 1:num_time
        num_lags = min(max_lag, t - 1);
        if num_lags >= 1
            renewal_lambda(t) = sum(weights(1:num_lags) .* incidence(t - 1:-1:t - num_lags));
        end
    end

    %% 4. Renewal Estimate and Warmup Policy
    valid_mask = true(num_time, 1);
    valid_mask(1:min(max_lag, num_time)) = false;
    valid_mask(renewal_lambda < opts.min_denominator) = false;

    Rt_est = NaN(num_time, 1);
    Rt_est(valid_mask) = incidence(valid_mask) ./ renewal_lambda(valid_mask);

    %% 5. Output Assembly
    gamma_shape = (opts.serial_interval_mean_days / opts.serial_interval_sd_days)^2;
    gamma_scale = opts.serial_interval_sd_days^2 / opts.serial_interval_mean_days;

    info = struct();
    info.renewal_lambda          = renewal_lambda;
    info.serial_interval_weights = weights;
    info.valid_mask              = valid_mask;
    info.options                 = opts;
    info.options.gamma_shape     = gamma_shape;
    info.options.gamma_scale     = gamma_scale;
    info.options.warmup_method   = "nan";
end

function local_assert_positive_scalar(opts, field_name, require_integer)
%LOCAL_ASSERT_POSITIVE_SCALAR Fail-fast check that an opts field is a positive finite scalar.
    if ~isfield(opts, field_name)
        error('RENEWAL:MissingOption', 'Missing required opts field: %s.', field_name);
    end

    value = opts.(field_name);
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
        error('RENEWAL:InvalidOption', 'opts.%s must be a finite positive scalar.', field_name);
    end

    if require_integer && mod(value, 1) ~= 0
        error('RENEWAL:InvalidOption', 'opts.%s must be integer-valued.', field_name);
    end
end

function weights = local_serial_interval_weights(mean_days, sd_days, max_lag_days)
%LOCAL_SERIAL_INTERVAL_WEIGHTS Discretized gamma serial-interval weights over lags 1..max_lag.
    shape = (mean_days / sd_days)^2;
    scale = sd_days^2 / mean_days;

    lags  = (1:max_lag_days)';
    upper = gammainc(lags ./ scale, shape);
    lower = gammainc((lags - 1) ./ scale, shape);
    weights = upper - lower;

    if any(~isfinite(weights)) || any(weights < 0) || sum(weights) <= 0
        error('RENEWAL:InvalidWeights', 'Serial-interval weights are nonfinite, negative, or have nonpositive total mass.');
    end

    weights = weights ./ sum(weights);
end
