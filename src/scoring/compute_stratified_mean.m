function [mean_value, se, stratum_mean, stratum_se] = compute_stratified_mean(scores, strata, is_random)

%COMPUTE_STRATIFIED_MEAN Equal-stratum-weight mean and its standard error.
%
%   Syntax:
%       [mean_value, se] = compute_stratified_mean(scores, strata, is_random)
%       [mean_value, se, stratum_mean, stratum_se] = compute_stratified_mean(...)
%
%   Description:
%       Averages trajectory-level scores with equal weight per trajectory
%       within each stratum and equal weight per stratum. Trajectories marked
%       random are independent draws from their stratum's generating
%       distribution; the others are fixed design points, such as canonical
%       scenarios, that carry no sampling variance. For stratum s with n_s
%       members, m_s of them random with sample variance v_s,
%           se_s = (m_s / n_s) * sqrt(v_s / m_s),
%       and over S strata
%           mean_value = (1 / S) * sum_s mean_s,
%           se         = (1 / S) * sqrt(sum_s se_s^2).
%       Forecast leads and origins must already be averaged within each
%       trajectory: overlapping origins are not independent samples. Every
%       stratum needs at least two random members.
%
%   Inputs:
%       scores    - N-by-1 trajectory-level scores.
%       strata    - N-by-1 string stratum labels.
%       is_random - N-by-1 logical; true for random trajectory draws.
%
%   Outputs:
%       mean_value   - Equal-stratum-weight mean score.
%       se           - Standard error of mean_value.
%       stratum_mean - S-by-1 stratum means, strata in first-appearance order.
%       stratum_se   - S-by-1 standard errors of the stratum means.
%
%   See also PARTA_02_SELECT_HYPERPARAMETERS, PARTA_04_EVALUATE_FORECASTS.
%
% A. M. Kaahin 2026-11-26

%% 1. Stratum Means and Standard Errors
stratum_ids  = unique(strata, 'stable');
num_strata   = numel(stratum_ids);
stratum_mean = zeros(num_strata, 1);
stratum_se   = zeros(num_strata, 1);

for s = 1:num_strata
    members       = strata == stratum_ids(s);
    random_scores = scores(members & is_random);
    num_random    = numel(random_scores);

    if num_random < 2
        error('COMPUTE_STRATIFIED_MEAN:InsufficientRandomMembers', 'Stratum %s has %d random members; at least two are needed for a standard error.', stratum_ids(s), num_random);
    end

    stratum_mean(s) = mean(scores(members));
    stratum_se(s)   = (num_random / nnz(members)) * std(random_scores) / sqrt(num_random);
end

%% 2. Equal-Stratum Aggregation
mean_value = mean(stratum_mean);
se         = sqrt(sum(stratum_se.^2)) / num_strata;
end
