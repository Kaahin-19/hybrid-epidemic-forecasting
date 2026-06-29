function point_error = compute_point_error(truth, pred)
%COMPUTE_POINT_ERROR Point-forecast error metrics across H forecast horizons.
%
%   Syntax:
%       point_error = compute_point_error(truth, pred)
%
%   Description:
%       Computes signed, squared, and absolute point-forecast errors together
%       with the root-mean-square error and mean absolute error from an H-by-1
%       truth vector and an H-by-1 predictive-median vector. Inputs are assumed
%       to already follow the internal H-by-1 convention; no reshaping,
%       conversion, validation, or repair is performed.
%
%   Inputs:
%       truth - H-by-1 vector of observed values.
%       pred  - H-by-1 vector of point forecasts (predictive medians).
%
%   Outputs:
%       point_error - Struct with fields:
%           error          - H-by-1 signed errors (pred - truth).
%           squared_error  - H-by-1 squared errors.
%           absolute_error - H-by-1 absolute errors.
%           rmse           - Scalar root-mean-square error.
%           mae            - Scalar mean absolute error.
%
%   See also COMPUTE_WIS, COMPUTE_INTERVAL_DIAGNOSTICS.
%
% A. M. Kaahin 2026-06-22

%% 1. Main Computation
error          = pred - truth;
squared_error  = error.^2;
absolute_error = abs(error);

%% 2. Output Assembly
point_error = struct('error', error, 'squared_error', squared_error, 'absolute_error', absolute_error, 'rmse', sqrt(mean(squared_error)), 'mae', mean(absolute_error));
end
