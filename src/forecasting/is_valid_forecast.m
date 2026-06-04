function is_valid = is_valid_forecast(Rt_pred, out_alphas, Rt_lower, Rt_upper, truth_Rt)
%IS_VALID_FORECAST Verify forecast output dimensions and finiteness.
%
%   Syntax:
%       is_valid = is_valid_forecast(Rt_pred, out_alphas, Rt_lower, Rt_upper, truth_Rt)
%
%   Description:
%       Shared validity predicate for Part A forecasts. Confirms that the
%       median forecast, interval bounds, and miscoverage rates are mutually
%       consistent in shape, finite, and ordered (lower <= upper). Used by both
%       the model-selection scoring path and the final forecasting path so the
%       two stages share one definition of a usable forecast.
%
%   Inputs:
%       Rt_pred    - Horizon-by-one predictive median vector.
%       out_alphas - Interval miscoverage rates.
%       Rt_lower   - Horizon-by-numAlphas lower interval matrix.
%       Rt_upper   - Horizon-by-numAlphas upper interval matrix.
%       truth_Rt   - Horizon-by-one future truth vector.
%
%   Outputs:
%       is_valid - Logical scalar.
%
%   See also EVALUATE_CANDIDATE, RUN_EXPANDING_WINDOW_FORECAST.
%
% A. M. Kaahin 2026-06-04

    out_alphas = reshape(double(out_alphas), 1, []);
    Rt_pred = double(Rt_pred(:));
    Rt_lower = double(Rt_lower);
    Rt_upper = double(Rt_upper);
    truth_Rt = double(truth_Rt(:));

    is_valid = ...
        ~isempty(out_alphas) && ...
        numel(Rt_pred) == numel(truth_Rt) && ...
        size(Rt_lower, 1) == numel(truth_Rt) && ...
        size(Rt_upper, 1) == numel(truth_Rt) && ...
        size(Rt_lower, 2) == numel(out_alphas) && ...
        size(Rt_upper, 2) == numel(out_alphas) && ...
        all(isfinite(Rt_pred)) && ...
        all(isfinite(Rt_lower(:))) && ...
        all(isfinite(Rt_upper(:))) && ...
        all(Rt_lower(:) <= Rt_upper(:));
end
