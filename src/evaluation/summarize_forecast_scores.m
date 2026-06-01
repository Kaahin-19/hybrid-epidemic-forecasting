function summaries = summarize_forecast_scores(window_scores, pointwise_scores, interval_scores)
%SUMMARIZE_FORECAST_SCORES Build Part A evaluation summary tables.
%
%   Syntax:
%       summaries = summarize_forecast_scores(window_scores, pointwise_scores, interval_scores)
%
%   Description:
%       Aggregates Part A forecast scores into scenario-wise, horizon-wise,
%       model-wise, exogenous-mode, and interval-level summaries. The
%       function expects canonical score tables produced by
%       partA_04_evaluate_forecasts and keeps metric aggregation reusable
%       outside the orchestration script.
%
%   Inputs:
%       window_scores    - Per-window score table.
%       pointwise_scores - Per-horizon score table.
%       interval_scores  - Per-horizon/per-alpha interval score table.
%
%   Outputs:
%       summaries - Structure with scenario_summary, horizon_summary,
%                   model_summary, exo_mode_summary, and interval_summary.
%
%   See also COMPUTE_WIS, COMPUTE_RMSE, COMPUTE_COVERAGE.
%
% A. M. Kaahin 2026-06-01

    %% 1. Input Defaults
    if nargin < 1 || isempty(window_scores)
        window_scores = table();
    end
    if nargin < 2 || isempty(pointwise_scores)
        pointwise_scores = table();
    end
    if nargin < 3 || isempty(interval_scores)
        interval_scores = table();
    end

    %% 2. Summary Assembly
    summaries = struct();
    summaries.scenario_summary = local_summarize_window_scores( ...
        window_scores, {'Scenario', 'ScenarioName', 'Model', 'ExoMode'});
    summaries.horizon_summary = local_summarize_pointwise_scores( ...
        pointwise_scores, {'Model', 'ExoMode', 'HorizonIdx'});
    summaries.scenario_horizon_summary = local_summarize_pointwise_scores( ...
        pointwise_scores, {'Scenario', 'ScenarioName', 'Model', 'ExoMode', 'HorizonIdx'});
    summaries.model_summary = local_summarize_window_scores( ...
        window_scores, {'Model', 'ExoMode'});
    summaries.exo_mode_summary = local_summarize_window_scores( ...
        window_scores, {'ExoMode'});
    summaries.interval_summary = local_summarize_interval_scores( ...
        interval_scores, {'Model', 'ExoMode', 'Alpha'});
end

function summary = local_summarize_window_scores(scores, group_vars)
%LOCAL_SUMMARIZE_WINDOW_SCORES Aggregate window-level scores.
    summary = local_empty_summary(group_vars);
    if isempty(scores) || height(scores) == 0
        return;
    end

    group_vars = local_existing_vars(scores, group_vars);
    [G, keys] = findgroups(scores(:, group_vars));
    summary = keys;
    summary.NumWindows = splitapply(@numel, scores.WindowWIS, G);
    summary.NumValidWindows = splitapply(@local_count_valid, scores.IsValid, G);
    summary.NumFiniteWIS = splitapply(@local_count_finite, scores.WindowWIS, G);
    summary.MeanWIS = splitapply(@local_mean_finite, scores.WindowWIS, G);
    summary.MedianWIS = splitapply(@local_median_finite, scores.WindowWIS, G);
    summary.StdWIS = splitapply(@local_std_finite, scores.WindowWIS, G);
    summary.MinWIS = splitapply(@local_min_finite, scores.WindowWIS, G);
    summary.MaxWIS = splitapply(@local_max_finite, scores.WindowWIS, G);
    summary.MeanRMSE = splitapply(@local_mean_finite, scores.WindowRMSE, G);
    summary.MeanCoverage = splitapply(@local_mean_finite, scores.MeanCoverage, G);
    summary.MeanIntervalWidth = splitapply(@local_mean_finite, scores.MeanIntervalWidth, G);
end

function summary = local_summarize_pointwise_scores(scores, group_vars)
%LOCAL_SUMMARIZE_POINTWISE_SCORES Aggregate horizon-level scores.
    summary = local_empty_summary(group_vars);
    if isempty(scores) || height(scores) == 0
        return;
    end

    group_vars = local_existing_vars(scores, group_vars);
    [G, keys] = findgroups(scores(:, group_vars));
    summary = keys;
    summary.NumPoints = splitapply(@numel, scores.WIS, G);
    summary.NumFiniteWIS = splitapply(@local_count_finite, scores.WIS, G);
    summary.MeanWIS = splitapply(@local_mean_finite, scores.WIS, G);
    summary.MedianWIS = splitapply(@local_median_finite, scores.WIS, G);
    summary.StdWIS = splitapply(@local_std_finite, scores.WIS, G);
    summary.RMSE = sqrt(splitapply(@local_mean_finite, scores.SquaredError, G));
    summary.MeanCoverage = splitapply(@local_mean_finite, scores.CoverageMean, G);
    summary.MeanIntervalWidth = splitapply(@local_mean_finite, scores.IntervalWidthMean, G);
end

function summary = local_summarize_interval_scores(scores, group_vars)
%LOCAL_SUMMARIZE_INTERVAL_SCORES Aggregate alpha-level interval scores.
    summary = local_empty_summary(group_vars);
    if isempty(scores) || height(scores) == 0
        return;
    end

    group_vars = local_existing_vars(scores, group_vars);
    [G, keys] = findgroups(scores(:, group_vars));
    summary = keys;
    summary.NumIntervalPoints = splitapply(@numel, scores.Coverage, G);
    summary.MeanCoverage = splitapply(@local_mean_finite, scores.Coverage, G);
    summary.MeanIntervalWidth = splitapply(@local_mean_finite, scores.IntervalWidth, G);
end

function vars = local_existing_vars(scores, requested_vars)
%LOCAL_EXISTING_VARS Keep only grouping variables present in the table.
    vars = requested_vars(ismember(requested_vars, scores.Properties.VariableNames));
end

function summary = local_empty_summary(group_vars)
%LOCAL_EMPTY_SUMMARY Create an empty summary table placeholder.
    summary = table();
    for i = 1:numel(group_vars)
        summary.(group_vars{i}) = strings(0, 1);
    end
end

function count = local_count_valid(values)
%LOCAL_COUNT_VALID Count true validity flags.
    count = sum(logical(values));
end

function count = local_count_finite(values)
%LOCAL_COUNT_FINITE Count finite numeric values.
    values = double(values);
    count = sum(isfinite(values));
end

function value = local_mean_finite(values)
%LOCAL_MEAN_FINITE Mean over finite values only.
    values = double(values);
    values = values(isfinite(values));
    if isempty(values)
        value = nan;
    else
        value = mean(values);
    end
end

function value = local_median_finite(values)
%LOCAL_MEDIAN_FINITE Median over finite values only.
    values = double(values);
    values = values(isfinite(values));
    if isempty(values)
        value = nan;
    else
        value = median(values);
    end
end

function value = local_std_finite(values)
%LOCAL_STD_FINITE Standard deviation over finite values only.
    values = double(values);
    values = values(isfinite(values));
    if numel(values) < 2
        value = nan;
    else
        value = std(values);
    end
end

function value = local_min_finite(values)
%LOCAL_MIN_FINITE Minimum over finite values only.
    values = double(values);
    values = values(isfinite(values));
    if isempty(values)
        value = nan;
    else
        value = min(values);
    end
end

function value = local_max_finite(values)
%LOCAL_MAX_FINITE Maximum over finite values only.
    values = double(values);
    values = values(isfinite(values));
    if isempty(values)
        value = nan;
    else
        value = max(values);
    end
end
