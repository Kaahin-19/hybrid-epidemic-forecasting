function coverage = compute_coverage(truth_Rt, lower_Rt, upper_Rt)
%COMPUTE_COVERAGE Compute empirical interval coverage indicators.
%
%   Syntax:
%       coverage = compute_coverage(truth_Rt, lower_Rt, upper_Rt)
%
%   Description:
%       Computes pointwise indicators for whether each true Rt value falls
%       inside each predictive interval. Invalid or unordered interval entries
%       are returned as NaN so aggregate coverage summaries are not inflated
%       by malformed bounds.
%
%   Inputs:
%       truth_Rt - Horizon-by-one vector of true Rt values.
%       lower_Rt - Horizon-by-numIntervals lower interval matrix.
%       upper_Rt - Horizon-by-numIntervals upper interval matrix.
%
%   Outputs:
%       coverage - Horizon-by-numIntervals matrix with values 0, 1, or NaN.
%
%   See also COMPUTE_INTERVAL_WIDTH, COMPUTE_WIS.
%
% A. M. Kaahin 2026-06-01

    %% 1. Input Validation
    truth_Rt = double(truth_Rt(:));
    lower_Rt = double(lower_Rt);
    upper_Rt = double(upper_Rt);

    if isempty(truth_Rt) || size(lower_Rt, 1) ~= numel(truth_Rt) || ...
            size(upper_Rt, 1) ~= numel(truth_Rt) || ...
            size(lower_Rt, 2) ~= size(upper_Rt, 2)
        error('EVALUATION:InvalidForecastShape', ...
            'truth_Rt and interval matrices have incompatible dimensions.');
    end

    %% 2. Coverage Computation
    truth_matrix = repmat(truth_Rt, 1, size(lower_Rt, 2));
    valid_idx = isfinite(truth_matrix) & isfinite(lower_Rt) & ...
        isfinite(upper_Rt) & lower_Rt <= upper_Rt;

    coverage = nan(size(lower_Rt));
    coverage(valid_idx) = double(truth_matrix(valid_idx) >= lower_Rt(valid_idx) & ...
        truth_matrix(valid_idx) <= upper_Rt(valid_idx));
end
