function [Rt_est, renewal_lambda] = estimate_rt_renewal(incidence, weights)
%ESTIMATE_RT_RENEWAL Renewal-ratio Rt proxy from incidence; NaN in warmup.
%
%   Syntax:
%       [Rt_est, renewal_lambda] = estimate_rt_renewal(incidence, weights)
%
%   Description:
%       Estimates an effective reproduction-number proxy by the renewal-ratio
%       method. The renewal infectiousness at time t is the serial-interval
%       weighted sum of past incidence,
%
%           renewal_lambda(t) = sum_s weights(s) * incidence(t-s),
%
%       and the estimate is Rt_est(t) = incidence(t) / renewal_lambda(t). The
%       first numel(weights) steps have no complete lag window and are returned
%       as NaN warmup. The result is a smoothing-dependent proxy for the latent
%       reproduction number, not the true latent Rt.
%
%   Inputs:
%       incidence - Nonnegative incidence (or smoothed incidence) vector.
%       weights   - Serial-interval weights for lags 1..numel(weights).
%
%   Outputs:
%       Rt_est         - Column vector of renewal-ratio Rt estimates (NaN warmup).
%       renewal_lambda - Column vector of renewal infectiousness (NaN warmup).
%
%   See also SERIAL_INTERVAL_WEIGHTS.
%
% A. M. Kaahin 2026-06-12

    %% 1. Input Preparation
    incidence = double(incidence(:));
    weights = double(weights(:));
    max_lag = numel(weights);
    n = numel(incidence);

    %% 2. Renewal Infectiousness
    renewal_lambda = nan(n, 1);
    for t_idx = (max_lag + 1):n
        lagged_incidence = incidence(t_idx - (1:max_lag));
        renewal_lambda(t_idx) = sum(weights .* lagged_incidence(:));
    end

    %% 3. Renewal-Ratio Estimate
    Rt_est = incidence ./ renewal_lambda;
end
