%PARTC_04_EVALUATE_FORECASTS Evaluate held-out Part C Rt forecasts.
%
%   Description:
%       Evaluates the six Part C held-out forecast artifacts against the
%       operational Rt estimates stored with their held-out targets. Computes
%       WIS, point-error diagnostics, empirical interval coverage, and interval
%       width by origin, lead time, interval level, model, and strategy.
%       Matched strategy comparisons are descriptive because the forecast
%       horizons overlap across successive origins.
%
%   Workflow:
%       1. Initialize evaluation paths and configuration.
%       2. Load and verify the held-out forecast artifacts.
%       3. Score every forecast origin, lead time, and interval level.
%       4. Build summaries, comparisons, and online-equivalence results.
%       5. Assemble the evaluation artifact.
%       6. Save the evaluation artifact and CSV tables.
%       7. Report the completed outputs.
%
%   See also PARTC_CONFIG, PARTC_03_RUN_FORECASTS,
%            PARTC_05_GENERATE_FIGURES, COMPUTE_WIS, COMPUTE_POINT_ERROR,
%            COMPUTE_INTERVAL_DIAGNOSTICS.
%
% A. M. Kaahin 2026-08-06
% Modified: 2026-08-23

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Held-Out Forecast Evaluation ===\n');

cfg = partC_config();

%% 2. Forecast Artifacts
artifacts = local_load_forecast_artifacts(cfg);

fprintf('Loaded six held-out forecast artifacts.\n');
fprintf('Held-out origins per artifact: %d\n', numel(artifacts{1}.results));

%% 3. Forecast Scoring
[origin_scores, horizon_scores, interval_scores, interval_pointwise] = local_score_artifacts(artifacts);

fprintf('Horizon rows: %d\n', height(horizon_scores));
fprintf('Interval rows: %d\n', height(interval_scores));

%% 4. Summaries and Comparisons
summaries = struct();
summaries.strategy_summary = local_strategy_summary(origin_scores);
summaries.horizon_summary = local_horizon_summary(horizon_scores);
summaries.interval_summary = local_interval_summary(interval_pointwise);

pairwise_comparisons = local_pairwise_comparisons(origin_scores, cfg);
online_equivalence = local_online_equivalence(artifacts);

%% 5. Evaluation Artifact
evaluation_payload = struct();
evaluation_payload.origin_scores = origin_scores;
evaluation_payload.horizon_scores = horizon_scores;
evaluation_payload.interval_scores = interval_scores;
evaluation_payload.summaries = summaries;
evaluation_payload.pairwise_comparisons = pairwise_comparisons;
evaluation_payload.online_equivalence = online_equivalence;

%% 6. Persistence
if ~exist(cfg.output.evaluation_dir, 'dir')
    mkdir(cfg.output.evaluation_dir);
end

if ~exist(cfg.output.table_dir, 'dir')
    mkdir(cfg.output.table_dir);
end

evaluation_artifact_path = fullfile(cfg.output.evaluation_dir, "partC_04_evaluation_results.mat");

save(evaluation_artifact_path, '-struct', 'evaluation_payload');

csv_names = [
    "partC_04_origin_scores.csv"
    "partC_04_horizon_scores.csv"
    "partC_04_interval_scores.csv"
    "partC_04_strategy_summary.csv"
    "partC_04_horizon_summary.csv"
    "partC_04_interval_summary.csv"
    "partC_04_pairwise_comparisons.csv"
    "partC_04_online_equivalence.csv"
    ];

csv_tables = {
    origin_scores
    horizon_scores
    interval_scores
    summaries.strategy_summary
    summaries.horizon_summary
    summaries.interval_summary
    pairwise_comparisons
    online_equivalence
    };

csv_paths = fullfile(cfg.output.table_dir, csv_names);

for csv_index = 1:numel(csv_paths)
    writetable(csv_tables{csv_index}, csv_paths(csv_index), 'QuoteStrings', true);
end

%% 7. Completion Report
disp(summaries.strategy_summary);
disp(online_equivalence);

fprintf('Saved MAT artifact: %s\n', evaluation_artifact_path);

for csv_index = 1:numel(csv_paths)
    fprintf('Saved CSV: %s\n', csv_paths(csv_index));
end

fprintf('=== Part C Held-Out Forecast Evaluation Complete ===\n\n');

%% 8. Local Functions
function artifacts = local_load_forecast_artifacts(cfg)
%LOCAL_LOAD_FORECAST_ARTIFACTS Load the six Script 3 artifacts.

artifact_paths = cfg.evaluation.expected_forecast_artifact_paths;
configurations = cfg.final_forecast.configurations;
strategies = cfg.final_forecast.strategies;

num_strategies = numel(strategies);
artifacts = cell(numel(artifact_paths), 1);

for artifact_index = 1:numel(artifact_paths)
    artifact_path = artifact_paths(artifact_index);

    if ~isfile(artifact_path)
        error('PARTC_04:MissingForecastArtifact', 'Missing required forecast artifact: %s. Run Part C Script 3 first.', artifact_path);
    end

    pair_index = ceil(artifact_index / num_strategies);
    strategy_index = mod(artifact_index - 1, num_strategies) + 1;

    expected_configuration = configurations(pair_index);
    expected_strategy = strategies(strategy_index);

    artifact = load(artifact_path);

    if artifact.model_type ~= expected_configuration.model_type || artifact.exo_mode ~= expected_configuration.exo_mode || artifact.strategy ~= expected_strategy.identifier
        error('PARTC_04:ForecastIdentityMismatch', 'Forecast artifact identity does not match its configured model and strategy.');
    end

    artifacts{artifact_index} = artifact;
end

local_validate_common_forecast_grid(artifacts, cfg);

end

function local_validate_common_forecast_grid(artifacts, cfg)
%LOCAL_VALIDATE_COMMON_FORECAST_GRID Require common held-out origins and targets.

reference = artifacts{1};
num_origins = numel(reference.results);

if num_origins == 0
    error('PARTC_04:MissingForecastOrigins', 'Forecast artifacts contain no held-out forecast origins.');
end

if reference.results(1).origin_date ~= cfg.validation.calibration_end_date
    error('PARTC_04:HeldOutOriginMismatch', 'The first held-out forecast origin must equal the configured calibration end date.');
end

if reference.results(1).target_dates(1) ~= cfg.validation.test_start_date
    error('PARTC_04:HeldOutTargetMismatch', 'The first held-out target must equal the configured test start date.');
end

if reference.results(end).target_dates(end) > cfg.study.end_date
    error('PARTC_04:HeldOutTargetMismatch', 'Held-out forecast targets extend beyond the configured study period.');
end

for origin_position = 1:num_origins
    if numel(reference.results(origin_position).target_dates) ~= cfg.final_forecast.horizon
        error('PARTC_04:HorizonMismatch', 'Forecast origin %d does not contain the configured forecast horizon.', origin_position);
    end
end

for artifact_index = 1:numel(artifacts)
    artifact = artifacts{artifact_index};

    if numel(artifact.results) ~= num_origins
        error('PARTC_04:CommonOriginMismatch', 'All six forecast artifacts must contain the same number of forecast origins.');
    end

    for origin_position = 1:num_origins
        reference_result = reference.results(origin_position);
        result = artifact.results(origin_position);

        if result.origin_date ~= reference_result.origin_date
            error('PARTC_04:CommonOriginMismatch', 'All six forecast artifacts must use identical forecast origins.');
        end

        if ~isequal(result.target_dates, reference_result.target_dates) || ~isequal(result.target_Rt_estimated, reference_result.target_Rt_estimated)
            error('PARTC_04:CommonTargetMismatch', 'All six forecast artifacts must use identical held-out targets.');
        end
    end
end

end

function [origin_scores, horizon_scores, interval_scores, pointwise] = local_score_artifacts(artifacts)
%LOCAL_SCORE_ARTIFACTS Score every model-strategy forecast artifact.

num_artifacts = numel(artifacts);

origin_blocks = cell(num_artifacts, 1);
horizon_blocks = cell(num_artifacts, 1);
interval_blocks = cell(num_artifacts, 1);
pointwise_blocks = cell(num_artifacts, 1);

for artifact_index = 1:num_artifacts
    [origin_blocks{artifact_index}, horizon_blocks{artifact_index}, interval_blocks{artifact_index}, pointwise_blocks{artifact_index}] = local_score_artifact(artifacts{artifact_index});
end

origin_scores = vertcat(origin_blocks{:});
horizon_scores = vertcat(horizon_blocks{:});
interval_scores = vertcat(interval_blocks{:});
pointwise = vertcat(pointwise_blocks{:});

end

function [origin_table, horizon_table, interval_table, pointwise_table] = local_score_artifact(artifact)
%LOCAL_SCORE_ARTIFACT Score one model-strategy artifact.

model = artifact.model_type;
exo_mode = artifact.exo_mode;
strategy = artifact.strategy;
forecast_configuration = string(mat2str(artifact.forecast_configuration));

alphas = artifact.wis_alphas;
num_origins = numel(artifact.results);

origin_rows = cell(num_origins, 1);
horizon_rows = cell(num_origins, 1);
interval_rows = cell(num_origins, 1);
pointwise_rows = cell(num_origins, 1);

for origin_position = 1:num_origins
    result = artifact.results(origin_position);

    target_Rt = result.target_Rt_estimated;
    median_Rt = result.forecast_median;
    lower_Rt = result.forecast_lower;
    upper_Rt = result.forecast_upper;

    [pointwise_wis, ~] = compute_wis(target_Rt, median_Rt, lower_Rt, upper_Rt, alphas);
    point_error = compute_point_error(target_Rt, median_Rt);
    interval_diagnostics = compute_interval_diagnostics(target_Rt, lower_Rt, upper_Rt, alphas);

    if any(~isfinite(pointwise_wis)) || any(~isfinite(point_error.error)) || any(~isfinite(interval_diagnostics.interval_width), 'all') || any(interval_diagnostics.interval_width < 0, 'all')
        error('PARTC_04:InvalidMetricOutput', 'Evaluation metrics are invalid for %s/%s/%s at origin %s.', model, exo_mode, strategy, string(result.origin_date));
    end

    horizon = numel(target_Rt);
    num_alphas = numel(alphas);

    origin_rows{origin_position} = table(model, exo_mode, strategy, forecast_configuration, origin_position, result.origin_date, result.target_dates(1), result.target_dates(end), mean(pointwise_wis), point_error.rmse, point_error.mae, mean(point_error.error), mean(interval_diagnostics.coverage, 'all'), mean(interval_diagnostics.interval_width, 'all'), 'VariableNames', {'Model', 'ExoMode', 'Strategy', 'ForecastConfiguration', 'OriginPosition', 'OriginDate', 'TargetStartDate', 'TargetEndDate', 'MeanWIS', 'RMSE', 'MAE', 'MeanError', 'MeanCoverage', 'MeanIntervalWidth'});

    horizon_rows{origin_position} = table(repmat(model, horizon, 1), repmat(exo_mode, horizon, 1), repmat(strategy, horizon, 1), repmat(forecast_configuration, horizon, 1), repmat(origin_position, horizon, 1), repmat(result.origin_date, horizon, 1), (1:horizon).', result.target_dates, target_Rt, median_Rt, point_error.error, point_error.absolute_error, point_error.squared_error, pointwise_wis, interval_diagnostics.coverage_mean, interval_diagnostics.width_mean, 'VariableNames', {'Model', 'ExoMode', 'Strategy', 'ForecastConfiguration', 'OriginPosition', 'OriginDate', 'LeadTime', 'TargetDate', 'TargetRtEstimated', 'MedianForecast', 'Error', 'AbsoluteError', 'SquaredError', 'WIS', 'MeanCoverage', 'MeanIntervalWidth'});

    empirical_coverage = mean(interval_diagnostics.coverage, 1).';
    mean_interval_width = mean(interval_diagnostics.interval_width, 1).';

    interval_rows{origin_position} = table(repmat(model, num_alphas, 1), repmat(exo_mode, num_alphas, 1), repmat(strategy, num_alphas, 1), repmat(forecast_configuration, num_alphas, 1), repmat(origin_position, num_alphas, 1), repmat(result.origin_date, num_alphas, 1), alphas, 1 - alphas, empirical_coverage, empirical_coverage - (1 - alphas), mean_interval_width, 'VariableNames', {'Model', 'ExoMode', 'Strategy', 'ForecastConfiguration', 'OriginPosition', 'OriginDate', 'Alpha', 'NominalCoverage', 'EmpiricalCoverage', 'CoverageError', 'MeanIntervalWidth'});

    pointwise_rows{origin_position} = table(repelem(model, horizon * num_alphas, 1), repelem(exo_mode, horizon * num_alphas, 1), repelem(strategy, horizon * num_alphas, 1), repmat((1:horizon).', num_alphas, 1), repelem(alphas, horizon, 1), repelem(1 - alphas, horizon, 1), interval_diagnostics.coverage(:), interval_diagnostics.interval_width(:), 'VariableNames', {'Model', 'ExoMode', 'Strategy', 'LeadTime', 'Alpha', 'NominalCoverage', 'Coverage', 'IntervalWidth'});
end

origin_table = vertcat(origin_rows{:});
horizon_table = vertcat(horizon_rows{:});
interval_table = vertcat(interval_rows{:});
pointwise_table = vertcat(pointwise_rows{:});

end

function summary = local_strategy_summary(origin_scores)
%LOCAL_STRATEGY_SUMMARY Summarize origin-level performance by strategy.

keys = {'Model', 'ExoMode', 'Strategy', 'ForecastConfiguration'};
identities = unique(origin_scores(:, keys), 'rows', 'stable');

rows = cell(height(identities), 1);

for group_index = 1:height(identities)
    identity = identities(group_index, :);
    mask = local_identity_mask(origin_scores, identity, keys);
    group = origin_scores(mask, :);

    rows{group_index} = table(identity.Model, identity.ExoMode, identity.Strategy, identity.ForecastConfiguration, height(group), mean(group.MeanWIS), median(group.MeanWIS), std(group.MeanWIS), min(group.MeanWIS), max(group.MeanWIS), mean(group.RMSE), mean(group.MAE), mean(group.MeanError), mean(group.MeanCoverage), mean(group.MeanIntervalWidth), 'VariableNames', {'Model', 'ExoMode', 'Strategy', 'ForecastConfiguration', 'NumOrigins', 'MeanOriginWIS', 'MedianOriginWIS', 'StdOriginWIS', 'MinOriginWIS', 'MaxOriginWIS', 'MeanRMSE', 'MeanMAE', 'MeanError', 'MeanCoverage', 'MeanIntervalWidth'});
end

summary = vertcat(rows{:});

end

function summary = local_horizon_summary(horizon_scores)
%LOCAL_HORIZON_SUMMARY Summarize performance by model, strategy, and lead time.

keys = {'Model', 'ExoMode', 'Strategy', 'LeadTime'};
identities = unique(horizon_scores(:, keys), 'rows', 'stable');

rows = cell(height(identities), 1);

for group_index = 1:height(identities)
    identity = identities(group_index, :);
    mask = local_identity_mask(horizon_scores, identity, keys);
    group = horizon_scores(mask, :);

    rows{group_index} = table(identity.Model, identity.ExoMode, identity.Strategy, identity.LeadTime, height(group), mean(group.WIS), median(group.WIS), mean(group.AbsoluteError), mean(group.SquaredError), sqrt(mean(group.SquaredError)), mean(group.Error), mean(group.MeanCoverage), mean(group.MeanIntervalWidth), 'VariableNames', {'Model', 'ExoMode', 'Strategy', 'LeadTime', 'NumForecasts', 'MeanWIS', 'MedianWIS', 'MeanAbsoluteError', 'MeanSquaredError', 'RMSE', 'MeanError', 'MeanCoverage', 'MeanIntervalWidth'});
end

summary = vertcat(rows{:});

end

function summary = local_interval_summary(pointwise)
%LOCAL_INTERVAL_SUMMARY Summarize empirical interval performance.

keys = {'Model', 'ExoMode', 'Strategy', 'Alpha', 'NominalCoverage'};
identities = unique(pointwise(:, keys), 'rows', 'stable');

rows = cell(height(identities), 1);

for group_index = 1:height(identities)
    identity = identities(group_index, :);
    mask = local_identity_mask(pointwise, identity, keys);
    group = pointwise(mask, :);

    empirical_coverage = mean(group.Coverage);

    rows{group_index} = table(identity.Model, identity.ExoMode, identity.Strategy, identity.Alpha, identity.NominalCoverage, height(group), empirical_coverage, empirical_coverage - identity.NominalCoverage, mean(group.IntervalWidth), 'VariableNames', {'Model', 'ExoMode', 'Strategy', 'Alpha', 'NominalCoverage', 'NumIntervalForecasts', 'EmpiricalCoverage', 'CoverageError', 'MeanIntervalWidth'});
end

summary = vertcat(rows{:});

end

function mask = local_identity_mask(data, identity, keys)
%LOCAL_IDENTITY_MASK Match rows to one grouping identity.

mask = true(height(data), 1);

for key_index = 1:numel(keys)
    key = keys{key_index};
    mask = mask & data.(key) == identity.(key);
end

end

function comparisons = local_pairwise_comparisons(origin_scores, cfg)
%LOCAL_PAIRWISE_COMPARISONS Build the seven planned matched comparisons.

rows = cell(7, 1);
row_index = 0;

for strategy_index = 1:numel(cfg.final_forecast.strategies)
    strategy = cfg.final_forecast.strategies(strategy_index).identifier;

    left = origin_scores(origin_scores.Model == "ARX" & origin_scores.ExoMode == "I" & origin_scores.Strategy == strategy, :);
    right = origin_scores(origin_scores.Model == "AR" & origin_scores.ExoMode == "None" & origin_scores.Strategy == strategy, :);

    row_index = row_index + 1;
    rows{row_index} = local_matched_comparison(left, right, "model_within_strategy", strategy, "ARX/I", "AR/None", cfg.evaluation.wis_equality_tolerance);
end

models = [
    "AR", "None"
    "ARX", "I"
    ];

for model_index = 1:size(models, 1)
    model = models(model_index, 1);
    exo_mode = models(model_index, 2);
    model_label = model + "/" + exo_mode;

    model_rows = origin_scores(origin_scores.Model == model & origin_scores.ExoMode == exo_mode, :);

    row_index = row_index + 1;
    rows{row_index} = local_matched_comparison(model_rows(model_rows.Strategy == "partA_fixed_fit", :), model_rows(model_rows.Strategy == "partA_online_fit", :), "fixed_vs_online_within_model", model_label, "partA_fixed_fit", "partA_online_fit", cfg.evaluation.wis_equality_tolerance);

    row_index = row_index + 1;
    rows{row_index} = local_matched_comparison(model_rows(model_rows.Strategy == "local_online_fit", :), model_rows(model_rows.Strategy == "partA_online_fit", :), "local_vs_partA_online_within_model", model_label, "local_online_fit", "partA_online_fit", cfg.evaluation.wis_equality_tolerance);
end

comparisons = vertcat(rows{:});

end

function row = local_matched_comparison(left, right, comparison_type, context, left_label, right_label, tolerance)
%LOCAL_MATCHED_COMPARISON Compare WIS across common forecast origins.

if isempty(left) || isempty(right) || height(left) ~= height(right)
    error('PARTC_04:MissingPairwiseComparison', 'A planned matched WIS comparison is missing forecast origins.');
end

differences = left.MeanWIS - right.MeanWIS;

left_better = differences < -tolerance;
equal = abs(differences) <= tolerance;
right_better = differences > tolerance;

row = table(comparison_type, context, left_label, right_label, numel(differences), mean(differences), median(differences), min(differences), max(differences), mean(left_better), mean(equal), mean(right_better), 'VariableNames', {'ComparisonType', 'ModelOrStrategy', 'LeftLabel', 'RightLabel', 'NumMatchedOrigins', 'MeanWISDifference', 'MedianWISDifference', 'MinWISDifference', 'MaxWISDifference', 'ProportionLeftBetter', 'ProportionEqual', 'ProportionRightBetter'});

end

function equivalence = local_online_equivalence(artifacts)
%LOCAL_ONLINE_EQUIVALENCE Compare Part A and locally selected online strategies.

rows = cell(2, 1);

for pair_index = 1:2
    base_index = (pair_index - 1) * 3;

    partA_online = artifacts{base_index + 1};
    local_online = artifacts{base_index + 2};

    configurations_equal = isequal(partA_online.forecast_configuration, local_online.forecast_configuration);
    forecasts_identical = true;

    for origin_position = 1:numel(partA_online.results)
        partA_result = partA_online.results(origin_position);
        local_result = local_online.results(origin_position);

        if ~isequal(partA_result.forecast_median, local_result.forecast_median) || ~isequal(partA_result.forecast_lower, local_result.forecast_lower) || ~isequal(partA_result.forecast_upper, local_result.forecast_upper)
            forecasts_identical = false;
            break;
        end
    end

    rows{pair_index} = table(partA_online.model_type, partA_online.exo_mode, string(mat2str(partA_online.forecast_configuration)), string(mat2str(local_online.forecast_configuration)), configurations_equal, forecasts_identical, 'VariableNames', {'Model', 'ExoMode', 'PartAConfiguration', 'LocalConfiguration', 'ConfigurationsEqual', 'ForecastsExactlyIdentical'});
end

equivalence = vertcat(rows{:});

end