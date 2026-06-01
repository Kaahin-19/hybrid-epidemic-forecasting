function mae = compute_mae(truth_Rt, pred_Rt)
%COMPUTE_MAE Compute median point-forecast mean absolute error.
%
%   Syntax:
%       mae = compute_mae(truth_Rt, pred_Rt)
%
%   Description:
%       Computes mean absolute error between true effective reproduction
%       numbers and median point forecasts over finite paired values.
%
%   Inputs:
%       truth_Rt - Numeric vector of true Rt values.
%       pred_Rt  - Numeric vector of median forecast Rt values.
%
%   Outputs:
%       mae - Scalar mean absolute error. Returns Inf when no finite paired
%             values are available.
%
%   See also COMPUTE_RMSE.
%
% A. M. Kaahin 2026-06-01

    %% 1. Input Validation
    truth_Rt = double(truth_Rt(:));
    pred_Rt = double(pred_Rt(:));

    if numel(truth_Rt) ~= numel(pred_Rt)
        error('EVALUATION:InvalidForecastShape', ...
            'Truth and prediction vectors must have the same length.');
    end

    %% 2. Error Computation
    valid_idx = isfinite(truth_Rt) & isfinite(pred_Rt);
    if ~any(valid_idx)
        mae = inf;
        return;
    end

    mae = mean(abs(pred_Rt(valid_idx) - truth_Rt(valid_idx)));
end
