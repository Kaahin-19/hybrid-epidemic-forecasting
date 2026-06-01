function [Rt_pred, lower_bounds, upper_bounds] = ...
    compute_interval_bounds_from_ensemble(ensemble_Rt, alphas)
%COMPUTE_INTERVAL_BOUNDS_FROM_ENSEMBLE Empirical quantile intervals from draws.
%
%   Syntax:
%       [Rt_pred, lower_bounds, upper_bounds] = ...
%           compute_interval_bounds_from_ensemble(ensemble_Rt, alphas)
%
%   Description:
%       Reduces a horizon-by-draws ensemble of Rt trajectories to the
%       empirical predictive median and central interval bounds. For each WIS
%       miscoverage rate alpha, the central (1 - alpha) interval uses the
%       alpha/2 and (1 - alpha/2) empirical quantiles across the ensemble.
%       This matches the analytic interval convention previously used in the
%       pipeline, where the same nominal coverage was produced from a
%       log-normal predictive distribution.
%
%   Inputs:
%       ensemble_Rt - horizon-by-numDraws matrix of positive Rt draws.
%       alphas      - Vector of WIS interval miscoverage rates.
%
%   Outputs:
%       Rt_pred      - horizon-by-one empirical predictive median.
%       lower_bounds - horizon-by-numAlphas lower interval matrix.
%       upper_bounds - horizon-by-numAlphas upper interval matrix.
%
%   See also SIMULATE_AR_ARX_INTERVALS, SIMULATE_STATESPACE_INTERVALS.
%
% A. M. Kaahin 2026-06-01

    %% 1. Input Validation
    ensemble_Rt = double(ensemble_Rt);
    if isempty(ensemble_Rt) || any(~isfinite(ensemble_Rt(:))) || any(ensemble_Rt(:) <= 0)
        error('INTERVALS:InvalidEnsemble', ...
            'ensemble_Rt must be a nonempty matrix of finite positive Rt draws.');
    end

    alphas = reshape(double(alphas), 1, []);
    if isempty(alphas) || any(~isfinite(alphas)) || any(alphas <= 0 | alphas >= 1)
        error('INTERVALS:InvalidAlpha', 'alphas must satisfy 0 < alpha < 1.');
    end

    horizon = size(ensemble_Rt, 1);
    num_alphas = numel(alphas);

    %% 2. Empirical Quantiles
    lower_probs = alphas / 2;
    upper_probs = 1 - alphas / 2;
    probs = [0.5, lower_probs, upper_probs];

    quantile_values = quantile(ensemble_Rt, probs, 2);

    Rt_pred = quantile_values(:, 1);
    lower_bounds = quantile_values(:, 1 + (1:num_alphas));
    upper_bounds = quantile_values(:, 1 + num_alphas + (1:num_alphas));

    %% 3. Numerical Guards
    % Quantile ordering guarantees lower <= median <= upper, but enforce it
    % explicitly to absorb any floating-point ties before returning.
    Rt_pred = reshape(Rt_pred, horizon, 1);
    lower_bounds = min(lower_bounds, Rt_pred);
    upper_bounds = max(upper_bounds, Rt_pred);

    if any(~isfinite(Rt_pred)) || any(Rt_pred <= 0) || ...
            any(~isfinite(lower_bounds(:))) || any(lower_bounds(:) <= 0) || ...
            any(~isfinite(upper_bounds(:))) || any(upper_bounds(:) <= 0) || ...
            any(lower_bounds(:) > upper_bounds(:))
        error('INTERVALS:InvalidBounds', ...
            'Empirical interval bounds must be finite, positive, and ordered.');
    end
end
