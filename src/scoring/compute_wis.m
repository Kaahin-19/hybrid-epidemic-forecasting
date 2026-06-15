function [wis, components] = compute_wis(truth, pred, lower, upper, alphas)
%COMPUTE_WIS Weighted interval score across H forecast horizons and K interval levels.
%
%   Syntax:
%       wis = compute_wis(truth, pred, lower, upper, alphas)
%       [wis, components] = compute_wis(truth, pred, lower, upper, alphas)
%
%   Description:
%       For each horizon h, computes:
%
%         WIS_h = (1/(K+0.5)) * [ 0.5*|y_h - m_h|
%                                + sum_{k=1}^{K} (alpha_k/2)*(u_{k,h} - l_{k,h})
%                                + sum_{k=1}^{K} max(l_{k,h} - y_h, 0)
%                                + sum_{k=1}^{K} max(y_h - u_{k,h}, 0) ]
%
%       where y_h is the observation, m_h the predictive median, and
%       (l_{k,h}, u_{k,h}) the (alpha_k/2, 1-alpha_k/2) quantile interval.
%
%   Inputs:
%       truth  - H×1 vector of observed values.
%       pred   - H×1 vector of predictive medians.
%       lower  - H×K matrix of lower interval bounds.
%       upper  - H×K matrix of upper interval bounds.
%       alphas - 1×K vector of miscoverage rates (0 < alpha_k < 1).
%
%   Outputs:
%       wis        - H×1 per-horizon WIS values.
%       components - Struct with fields median_term, dispersion,
%                    underprediction, overprediction (all H×1). Each field
%                    holds the corresponding sum before the 1/(K+0.5) factor.
%
%   See also INTERVAL_BOUNDS, FORECAST_OPEN, FORECAST_CLOSED.
%
% A. M. Kaahin 2026-06-15

    K      = numel(alphas);
    alphas = reshape(double(alphas), 1, K);
    truth  = double(truth(:));
    pred   = double(pred(:));
    lower  = double(lower);
    upper  = double(upper);

    median_term = 0.5 * abs(truth - pred);
    dispersion  = (alphas / 2) .* (upper - lower);
    underpred   = max(lower - truth, 0);
    overpred    = max(truth - upper, 0);

    wis = (1 / (K + 0.5)) * ...
        (median_term + sum(dispersion, 2) + sum(underpred, 2) + sum(overpred, 2));

    if nargout > 1
        components = struct( ...
            'median_term',    median_term, ...
            'dispersion',     sum(dispersion, 2), ...
            'underprediction', sum(underpred, 2), ...
            'overprediction',  sum(overpred, 2));
    end
end
