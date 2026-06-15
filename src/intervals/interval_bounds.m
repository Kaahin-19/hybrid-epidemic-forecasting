function [lower_bounds, upper_bounds, Rt_pred] = interval_bounds(ensemble, alphas)
%INTERVAL_BOUNDS Quantile reduction of a bootstrap ensemble to predictive bounds.
%
%   Syntax:
%       [lower_bounds, upper_bounds, Rt_pred] = interval_bounds(ensemble, alphas)
%
%   Description:
%       Filters ensemble columns to those that are entirely finite and lie
%       strictly within (1e-2, 1e2). If the number of valid columns is less
%       than max(2, ceil(0.2 * M)), all outputs are NaN. Otherwise computes
%       the per-horizon median across valid ensemble draws and, for each alpha_k, the
%       (alpha_k/2) and (1 - alpha_k/2) quantiles across valid columns as
%       the lower and upper bounds.
%
%   Inputs:
%       ensemble - H×M matrix of bootstrap Rt draws (NaN marks invalid draws).
%       alphas   - 1×K vector of miscoverage rates (0 < alpha_k < 1).
%
%   Outputs:
%       lower_bounds - H×K lower quantile bounds, or NaN(H,K) if insufficient
%                      valid draws.
%       upper_bounds - H×K upper quantile bounds, or NaN(H,K) if insufficient
%                      valid draws.
%
%   See also FORECAST_OPEN, FORECAST_CLOSED, COMPUTE_WIS.
%
% A. M. Kaahin 2026-06-15

    [H, M] = size(ensemble);
    K      = numel(alphas);
    alphas = reshape(double(alphas), 1, K);

    Rt_lo = 1e-2;
    Rt_hi = 1e2;
    is_valid = all(isfinite(ensemble), 1) & ...
               all(ensemble > Rt_lo, 1) & all(ensemble < Rt_hi, 1);
    num_valid = sum(is_valid);
    min_valid = max(2, ceil(0.2 * M));

    if num_valid < min_valid
        lower_bounds = nan(H, K);
        upper_bounds = nan(H, K);
        Rt_pred      = nan(H, 1);
        return;
    end

    valid   = ensemble(:, is_valid);
    Rt_pred = median(valid, 2);

    lower_bounds = nan(H, K);
    upper_bounds = nan(H, K);
    for k = 1:K
        lower_bounds(:, k) = quantile(valid, alphas(k) / 2,       2);
        upper_bounds(:, k) = quantile(valid, 1 - alphas(k) / 2,   2);
    end
end
