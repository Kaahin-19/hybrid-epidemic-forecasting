function [wis, components] = compute_wis(truth, pred, lower, upper, alphas)
%COMPUTE_WIS Weighted interval score across H forecast horizons and K interval levels.
%
%   Syntax:
%       wis = compute_wis(truth, pred, lower, upper, alphas)
%       [wis, components] = compute_wis(truth, pred, lower, upper, alphas)
%
%   Description:
%       For each horizon h, computes the weighted interval score from an H-by-1
%       truth vector, an H-by-1 predictive median vector, H-by-K interval-bound
%       matrices, and a K-by-1 vector of miscoverage rates.
%
%   Inputs:
%       truth  - H-by-1 vector of observed values.
%       pred   - H-by-1 vector of predictive medians.
%       lower  - H-by-K matrix of lower interval bounds.
%       upper  - H-by-K matrix of upper interval bounds.
%       alphas - K-by-1 vector of miscoverage rates.
%
%   Outputs:
%       wis        - H-by-1 per-horizon WIS values.
%       components - Struct with fields median_term, dispersion,
%                    underprediction, and overprediction.
%
%   See also FORECAST_OPEN, FORECAST_CLOSED.
%
% A. M. Kaahin 2026-06-15
% Modified: 2026-06-21

%% 1. Interval Count
K = numel(alphas);

%% 2. WIS Components
median_term = 0.5 * abs(truth - pred);
dispersion  = (upper - lower) .* (alphas.' / 2);
underpred   = max(lower - truth, 0);
overpred    = max(truth - upper, 0);

%% 3. Weighted Interval Score
wis = (1 / (K + 0.5)) * ...
    (median_term + sum(dispersion, 2) + sum(underpred, 2) + sum(overpred, 2));

%% 4. Optional Component Output
if nargout > 1
    components = struct( ...
        'median_term', median_term, ...
        'dispersion', sum(dispersion, 2), ...
        'underprediction', sum(underpred, 2), ...
        'overprediction', sum(overpred, 2));
end
end