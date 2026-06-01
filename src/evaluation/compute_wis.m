function wis = compute_wis(truth_Rt, median_Rt, lower_Rt, upper_Rt, alphas)
%COMPUTE_WIS Compute pointwise weighted interval score values.
%
%   Syntax:
%       wis = compute_wis(truth_Rt, median_Rt, lower_Rt, upper_Rt, alphas)
%
%   Description:
%       Computes the pointwise weighted interval score for effective
%       reproduction-number forecasts using a predictive median and central
%       interval bounds. The formula matches the Part A model-selection
%       convention, with a median absolute-error term and alpha-weighted
%       interval scores.
%
%   Inputs:
%       truth_Rt  - Horizon-by-one vector of true Rt values.
%       median_Rt - Horizon-by-one vector of predictive medians.
%       lower_Rt  - Horizon-by-numAlphas lower interval matrix.
%       upper_Rt  - Horizon-by-numAlphas upper interval matrix.
%       alphas    - Row vector of interval miscoverage rates.
%
%   Outputs:
%       wis - Horizon-by-one vector of pointwise WIS values.
%
%   See also COMPUTE_WIS_COMPONENTS, COMPUTE_RMSE, COMPUTE_COVERAGE.
%
% A. M. Kaahin 2026-06-01

    %% 1. WIS Computation
    components = compute_wis_components(truth_Rt, median_Rt, lower_Rt, ...
        upper_Rt, alphas);
    wis = components.raw_scale_wis;
end
