function ensemble_Rt = simulate_ar_residual_bootstrap_paths( ...
    a_values, log_history, innovations)
%SIMULATE_AR_RESIDUAL_BOOTSTRAP_PATHS Recursive AR bootstrap Rt trajectories.
%
%   Syntax:
%       ensemble_Rt = simulate_ar_residual_bootstrap_paths( ...
%           a_values, log_history, innovations)
%
%   Description:
%       Generates an ensemble of recursive AR forecast trajectories on the
%       log-Rt scale. Each draw rolls the fitted AR recursion forward over the
%       horizon, adding one sampled residual innovation per step, and the
%       perturbed prediction feeds the next step so innovation uncertainty
%       propagates through the autoregressive memory. No epidemic state is
%       required for the output-only AR case.
%
%   Inputs:
%       a_values    - AR coefficients a_values (from extract_ar_coefficients),
%                     where y(t) = -a1*y(t-1) - ... - ap*y(t-p) + e(t).
%       log_history - Column vector of historical log-Rt values.
%       innovations - horizon-by-numDraws matrix of sampled innovations.
%
%   Outputs:
%       ensemble_Rt - horizon-by-numDraws matrix of positive Rt draws.
%
%   See also SIMULATE_AR_ARX_INTERVALS, SAMPLE_CENTERED_RESIDUALS.
%
% A. M. Kaahin 2026-06-01

    %% 1. Input Preparation
    a_values = reshape(double(a_values), [], 1);
    p = numel(a_values);
    log_history = double(log_history(:));
    if numel(log_history) < p
        error('INTERVALS:InsufficientHistory', ...
            'log_history is too short for the requested AR order.');
    end

    [horizon, num_draws] = size(innovations);

    %% 2. Recursive Bootstrap (vectorized across draws)
    [log_lo, log_hi] = local_log_clip_range();
    roll = repmat(log_history, 1, num_draws);
    ensemble_Rt = zeros(horizon, num_draws);

    for h = 1:horizon
        recent = roll(end - p + 1:end, :);     % oldest..newest by row
        recent_newest_first = flipud(recent);  % newest first, aligns with a_values
        y_hat = -(a_values.' * recent_newest_first);
        y_next = y_hat + innovations(h, :);
        y_next = min(max(y_next, log_lo), log_hi);
        ensemble_Rt(h, :) = exp(y_next);
        roll = [roll; y_next]; %#ok<AGROW>
    end
end

function [log_lo, log_hi] = local_log_clip_range()
%LOCAL_LOG_CLIP_RANGE Plausibility guard range for log-Rt draws.
%   Draws that reach these bounds are treated as divergent and are dropped by
%   the family entry before quantile reduction.
    log_lo = log(1e-2);
    log_hi = log(1e2);
end
