function summaries = summarize_forecast_scores(window_scores, pointwise_scores, interval_scores)
%SUMMARIZE_FORECAST_SCORES Build Part A evaluation summary tables.
%
%   Syntax:
%       summaries = summarize_forecast_scores(window_scores, pointwise_scores, interval_scores)
%
%   Description:
%       Aggregates Part A forecast scores into scenario-wise, horizon-wise,
%       model-wise, exogenous-mode, calibration, and WIS-component summaries.
%       The function expects canonical score tables produced by
%       partA_04_evaluate_forecasts and keeps metric aggregation reusable
%       outside the orchestration script.
%
%   Inputs:
%       window_scores    - Per-window score table.
%       pointwise_scores - Per-horizon score table.
%       interval_scores  - Per-horizon/per-alpha interval score table.
%
%   Outputs:
%       summaries - Structure with scenario, horizon, model, calibration,
%                   and WIS-component summary tables.
%
%   See also COMPUTE_WIS, EVALUATE_FORECAST_WINDOW_METRICS.
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
        window_scores, local_strategy_group_vars(window_scores, ...
        {'Scenario', 'ScenarioName', 'Model', 'ExoMode'}));
    summaries.scenario_performance_summary = local_summarize_pointwise_scores( ...
        pointwise_scores, local_strategy_group_vars(pointwise_scores, ...
        {'Scenario', 'ScenarioName'}));
    summaries.horizon_summary = local_summarize_pointwise_scores( ...
        pointwise_scores, local_strategy_group_vars(pointwise_scores, ...
        {'Model', 'ExoMode', 'HorizonIdx'}));
    summaries.horizon_stratification_summary = local_summarize_pointwise_scores( ...
        pointwise_scores, local_strategy_group_vars(pointwise_scores, ...
        {'HorizonIdx'}));
    summaries.scenario_horizon_summary = local_summarize_pointwise_scores( ...
        pointwise_scores, local_strategy_group_vars(pointwise_scores, ...
        {'Scenario', 'ScenarioName', 'Model', 'ExoMode', 'HorizonIdx'}));
    summaries.model_summary = local_summarize_window_scores( ...
        window_scores, local_strategy_group_vars(window_scores, ...
        {'Model', 'ExoMode'}));
    summaries.exo_mode_summary = local_summarize_window_scores( ...
        window_scores, local_strategy_group_vars(window_scores, ...
        {'ExoMode'}));
    summaries.interval_summary = local_summarize_interval_scores( ...
        interval_scores, local_strategy_group_vars(interval_scores, ...
        {'Model', 'ExoMode', 'Alpha'}));
    summaries.scenario_calibration_summary = local_summarize_interval_scores( ...
        interval_scores, local_strategy_group_vars(interval_scores, ...
        {'Scenario', 'ScenarioName', 'Model', 'ExoMode', 'Alpha'}));
    summaries.wis_component_summary = local_summarize_wis_components( ...
        pointwise_scores, local_strategy_group_vars(pointwise_scores, ...
        {'Model', 'ExoMode'}));
end

function group_vars = local_strategy_group_vars(scores, base_vars)
%LOCAL_STRATEGY_GROUP_VARS Prefix strategy variables when present.
    strategy_vars = {'StrategyID', 'StrategyName', ...
        'OrderTreatment', 'ParameterTreatment'};
    group_vars = [local_existing_vars(scores, strategy_vars), base_vars];
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
    summary.MeanMAE = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'WindowMAE'), G);
    summary.MeanWISMedianComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'MeanWISMedianComponent'), G);
    summary.MeanWISDispersionComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'MeanWISDispersionComponent'), G);
    summary.MeanWISUnderpredictionComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'MeanWISUnderpredictionComponent'), G);
    summary.MeanWISOverpredictionComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'MeanWISOverpredictionComponent'), G);
    summary.MeanCoverage = splitapply(@local_mean_finite, scores.MeanCoverage, G);
    summary.MeanCalibrationBias = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'MeanCalibrationBias'), G);
    summary.MeanAbsoluteCalibrationError = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'MeanAbsoluteCalibrationError'), G);
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
    wis = local_numeric_column(scores, 'WIS');
    squared_error = local_numeric_column(scores, 'SquaredError');
    absolute_error = local_numeric_column(scores, 'AbsoluteError');

    summary.NumPoints = splitapply(@numel, wis, G);
    summary.NumFiniteWIS = splitapply(@local_count_finite, wis, G);
    summary.MeanWIS = splitapply(@local_mean_finite, wis, G);
    summary.MedianWIS = splitapply(@local_median_finite, wis, G);
    summary.StdWIS = splitapply(@local_std_finite, wis, G);
    summary.RMSE = sqrt(splitapply(@local_mean_finite, squared_error, G));
    summary.MAE = splitapply(@local_mean_finite, absolute_error, G);
    summary.MeanWISMedianComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'WISMedianComponent'), G);
    summary.MeanWISDispersionComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'WISDispersionComponent'), G);
    summary.MeanWISUnderpredictionComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'WISUnderpredictionComponent'), G);
    summary.MeanWISOverpredictionComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'WISOverpredictionComponent'), G);
    summary.MeanCoverage = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'CoverageMean'), G);
    summary.MeanCalibrationBias = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'CalibrationBiasMean'), G);
    summary.MeanAbsoluteCalibrationError = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'AbsoluteCalibrationErrorMean'), G);
    summary.MeanIntervalWidth = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'IntervalWidthMean'), G);
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
    coverage = local_numeric_column(scores, 'Coverage');
    nominal_coverage = local_numeric_column(scores, 'NominalCoverage');

    summary.NumIntervalPoints = splitapply(@numel, coverage, G);
    summary.NominalCoverage = splitapply(@local_mean_finite, nominal_coverage, G);
    summary.MeanCoverage = splitapply(@local_mean_finite, coverage, G);
    summary.CoverageBias = summary.MeanCoverage - summary.NominalCoverage;
    summary.AbsoluteCalibrationError = abs(summary.CoverageBias);
    summary.UnderCoverage = max(-summary.CoverageBias, 0);
    summary.OverCoverage = max(summary.CoverageBias, 0);
    summary.MeanIntervalWidth = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'IntervalWidth'), G);
    summary.MeanIntervalScore = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'IntervalScore'), G);
    summary.MeanWISIntervalComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'WISIntervalComponent'), G);
    summary.MeanWISSharpnessComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'WISSharpnessComponent'), G);
    summary.MeanWISUnderpredictionComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'WISUnderpredictionComponent'), G);
    summary.MeanWISOverpredictionComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'WISOverpredictionComponent'), G);
end

function summary = local_summarize_wis_components(scores, group_vars)
%LOCAL_SUMMARIZE_WIS_COMPONENTS Aggregate pointwise WIS decomposition terms.
    summary = local_empty_summary(group_vars);
    if isempty(scores) || height(scores) == 0
        return;
    end

    group_vars = local_existing_vars(scores, group_vars);
    [G, keys] = findgroups(scores(:, group_vars));
    summary = keys;
    summary.NumPoints = splitapply(@numel, local_numeric_column(scores, 'WIS'), G);
    summary.MeanRawScaleWIS = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'RawScaleWIS', 'WIS'), G);
    summary.MeanMedianComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'WISMedianComponent'), G);
    summary.MeanDispersionComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'WISDispersionComponent'), G);
    summary.MeanUnderpredictionComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'WISUnderpredictionComponent'), G);
    summary.MeanOverpredictionComponent = splitapply(@local_mean_finite, ...
        local_numeric_column(scores, 'WISOverpredictionComponent'), G);
    summary.MedianComponentShare = local_safe_divide( ...
        summary.MeanMedianComponent, summary.MeanRawScaleWIS);
    summary.DispersionComponentShare = local_safe_divide( ...
        summary.MeanDispersionComponent, summary.MeanRawScaleWIS);
    summary.UnderpredictionComponentShare = local_safe_divide( ...
        summary.MeanUnderpredictionComponent, summary.MeanRawScaleWIS);
    summary.OverpredictionComponentShare = local_safe_divide( ...
        summary.MeanOverpredictionComponent, summary.MeanRawScaleWIS);
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

function values = local_numeric_column(scores, var_name, fallback_var)
%LOCAL_NUMERIC_COLUMN Return a numeric column with optional fallback.
    if ismember(var_name, scores.Properties.VariableNames)
        values = double(scores.(var_name));
        return;
    end

    if nargin >= 3 && ismember(fallback_var, scores.Properties.VariableNames)
        values = double(scores.(fallback_var));
        return;
    end

    values = nan(height(scores), 1);
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

function values = local_safe_divide(numerator, denominator)
%LOCAL_SAFE_DIVIDE Divide finite numeric vectors with NaN for invalid rows.
    numerator = double(numerator);
    denominator = double(denominator);
    values = nan(size(numerator));
    valid_idx = isfinite(numerator) & isfinite(denominator) & denominator ~= 0;
    values(valid_idx) = numerator(valid_idx) ./ denominator(valid_idx);
end
