function interval_width = compute_interval_width(lower_Rt, upper_Rt)
%COMPUTE_INTERVAL_WIDTH Compute predictive interval widths.
%
%   Syntax:
%       interval_width = compute_interval_width(lower_Rt, upper_Rt)
%
%   Description:
%       Computes upper-minus-lower interval widths for each horizon step and
%       interval level. Invalid, non-finite, or unordered bounds are returned
%       as NaN so summaries can distinguish malformed intervals from narrow
%       intervals.
%
%   Inputs:
%       lower_Rt - Horizon-by-numIntervals lower interval matrix.
%       upper_Rt - Horizon-by-numIntervals upper interval matrix.
%
%   Outputs:
%       interval_width - Horizon-by-numIntervals interval-width matrix.
%
%   See also COMPUTE_COVERAGE.
%
% A. M. Kaahin 2026-06-01

    %% 1. Input Validation
    lower_Rt = double(lower_Rt);
    upper_Rt = double(upper_Rt);

    if ~isequal(size(lower_Rt), size(upper_Rt))
        error('EVALUATION:InvalidForecastShape', ...
            'lower_Rt and upper_Rt must have identical dimensions.');
    end

    %% 2. Width Computation
    interval_width = upper_Rt - lower_Rt;
    invalid_idx = ~isfinite(lower_Rt) | ~isfinite(upper_Rt) | ...
        lower_Rt > upper_Rt;
    interval_width(invalid_idx) = nan;
end
