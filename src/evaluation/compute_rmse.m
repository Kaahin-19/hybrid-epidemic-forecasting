function rmse = compute_rmse(truth_Rt, pred_Rt)
%COMPUTE_RMSE Compute root mean squared forecast error.
%
%   Syntax:
%       rmse = compute_rmse(truth_Rt, pred_Rt)
%
%   Description:
%       Computes the root mean squared error between a truth trajectory and a
%       predictive median trajectory, ignoring only pairs where either value
%       is non-finite. If no finite pairs remain, Inf is returned so invalid
%       forecast windows remain penalized in downstream summaries.
%
%   Inputs:
%       truth_Rt - Vector of true Rt values.
%       pred_Rt  - Vector of predicted Rt values.
%
%   Outputs:
%       rmse - Scalar root mean squared error.
%
%   See also COMPUTE_WIS.
%
% A. M. Kaahin 2026-06-01

    %% 1. Input Validation
    truth_Rt = double(truth_Rt(:));
    pred_Rt = double(pred_Rt(:));

    if numel(truth_Rt) ~= numel(pred_Rt)
        error('EVALUATION:InvalidForecastShape', ...
            'truth_Rt and pred_Rt must have the same number of elements.');
    end

    %% 2. RMSE Computation
    finite_idx = isfinite(truth_Rt) & isfinite(pred_Rt);
    if ~any(finite_idx)
        rmse = inf;
        return;
    end

    residuals = pred_Rt(finite_idx) - truth_Rt(finite_idx);
    rmse = sqrt(mean(residuals .^ 2));
end
