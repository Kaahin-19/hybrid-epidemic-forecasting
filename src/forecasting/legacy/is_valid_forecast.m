function is_valid = is_valid_forecast(Rt_pred, out_alphas, Rt_lower, Rt_upper, truth_Rt)
%IS_VALID_FORECAST Check saved forecast-artifact invariants.
%
%   is_valid = is_valid_forecast(Rt_pred, out_alphas, Rt_lower, Rt_upper, truth_Rt)
%
%   This is a scientific output check, not an input-normalisation helper.
%   It verifies that a forecast result is well-formed before it is saved or
%   scored. It does not reshape, cast, clamp, repair, or replace anything.
%
%   A valid forecast artifact must satisfy:
%       - Rt_pred and truth_Rt are numeric vectors with the same horizon.
%       - out_alphas is a nonempty numeric vector with 0 < alpha < 1.
%       - Rt_lower and Rt_upper are horizon-by-numAlphas numeric matrices.
%       - All forecast, truth, and interval values are finite.
%       - Rt and interval values are positive.
%       - Lower bounds do not exceed upper bounds.
%
%   See also RUN_EXPANDING_WINDOW_FORECAST, EVALUATE_CANDIDATE.
%
% A. M. Kaahin 2026-06-04
% Modified: 2026-06-07

    is_valid = false;

    %% 1. Basic numeric shape checks
    if ~isnumeric(Rt_pred) || ~isnumeric(out_alphas) || ...
            ~isnumeric(Rt_lower) || ~isnumeric(Rt_upper) || ...
            ~isnumeric(truth_Rt)
        return;
    end

    if ~isvector(Rt_pred) || ~isvector(truth_Rt) || ~isvector(out_alphas)
        return;
    end

    horizon = numel(truth_Rt);
    num_alphas = numel(out_alphas);

    if horizon == 0 || num_alphas == 0
        return;
    end

    if numel(Rt_pred) ~= horizon
        return;
    end

    if ~ismatrix(Rt_lower) || ~ismatrix(Rt_upper)
        return;
    end

    if size(Rt_lower, 1) ~= horizon || size(Rt_upper, 1) ~= horizon
        return;
    end

    if size(Rt_lower, 2) ~= num_alphas || size(Rt_upper, 2) ~= num_alphas
        return;
    end

    %% 2. Scientific value checks
    if any(~isfinite(Rt_pred(:))) || any(~isfinite(truth_Rt(:))) || ...
            any(~isfinite(out_alphas(:))) || ...
            any(~isfinite(Rt_lower(:))) || any(~isfinite(Rt_upper(:)))
        return;
    end

    if any(out_alphas(:) <= 0 | out_alphas(:) >= 1)
        return;
    end

    if any(Rt_pred(:) <= 0) || any(truth_Rt(:) <= 0) || ...
            any(Rt_lower(:) <= 0) || any(Rt_upper(:) <= 0)
        return;
    end

    if any(Rt_lower(:) > Rt_upper(:))
        return;
    end

    is_valid = true;
end