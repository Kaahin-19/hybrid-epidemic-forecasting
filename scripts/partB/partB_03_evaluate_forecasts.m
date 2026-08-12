%PARTB_03_EVALUATE_FORECASTS Evaluate Part B robustness forecasts.
%
%   Description:
%       Scores every successfully saved Part B forecast artifact against its
%       latent Rt_true truth windows, aggregates the scores through the
%       replicate -> scenario -> stress-case hierarchy with equal scenario
%       weighting, compares Part B WIS with the matching Part A baseline at the
%       same scenario, model, exogenous mode, forecast origin and lead, and
%       reports the Script 2 execution outcomes. Lower WIS is better; a WIS
%       ratio above one indicates degradation relative to the Part A baseline.
%
%   Workflow:
%       1. Load and validate the Script 2 forecast-execution status.
%       2. Load the Part A baseline evaluation artifact.
%       3. Score each saved forecast artifact into raw window/horizon/interval
%          tables against truth_Rt_window.
%       4. Aggregate replicate, scenario, stress, horizon and interval
%          summaries, the execution summary, and the Part A degradation summary.
%       5. Save the evaluation artifact and compact summary CSV tables.
%
%   See also PARTB_CONFIG, PARTA_04_EVALUATE_FORECASTS, PARTB_02_RUN_FORECASTS, ...
%            COMPUTE_WIS, COMPUTE_POINT_ERROR, COMPUTE_INTERVAL_DIAGNOSTICS.
%
% A. M. Kaahin 2026-07-18

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Forecast Evaluation ===\n');

cfg            = partB_config();
forecast_dir   = cfg.partB.output.forecast_dir;
evaluation_dir = cfg.partB.output.evaluation_dir;
table_dir      = cfg.partB.output.table_dir;
horizon        = cfg.forecast.horizon;

if ~exist(evaluation_dir, 'dir'), mkdir(evaluation_dir); end
if ~exist(table_dir, 'dir'), mkdir(table_dir); end

%% 2. Load and Validate Script 2 Status
status_path = fullfile(forecast_dir, 'partB_02_forecast_status.mat');
if ~exist(status_path, 'file')
    error('PARTB_03:MissingForecastStatus', 'Missing Part B forecast status: %s. Run partB_02 first.', status_path);
end

status = load(status_path);
if ~isfield(status, 'run_completed') || ~status.run_completed
    error('PARTB_03:ForecastIncomplete', 'Part B forecasting did not complete (run_completed is not true).');
end

forecast_status     = status.forecast_status;
availability_report = status.availability_report;
status_values       = string({forecast_status.status});

if any(status_values == "pending")
    error('PARTB_03:PendingForecasts', '%d forecast attempts remain "pending" while run_completed is true.', sum(status_values == "pending"));
end

saved = forecast_status(status_values == "saved");
if isempty(saved)
    error('PARTB_03:NoSavedForecasts', 'No Part B forecast-status entries are marked "saved".');
end

status_counts = struct('attempts', numel(forecast_status), 'saved', sum(status_values == "saved"), 'no_windows', sum(status_values == "no_windows"), 'domain_failure', sum(status_values == "domain_failure"), 'pending', sum(status_values == "pending"));
fprintf('Status: %d attempts (%d saved, %d no_windows, %d domain_failure, %d pending).\n', status_counts.attempts, status_counts.saved, status_counts.no_windows, status_counts.domain_failure, status_counts.pending);
generation = load(fullfile(cfg.partB.output.data_dir, 'partB_01_generation_status.mat'));

%% 3. Load Part A Baseline
partA_eval_path = fullfile(cfg.output.score_dir, 'partA_04_evaluation_results.mat');
if ~exist(partA_eval_path, 'file')
    error('PARTB_03:MissingPartABaseline', 'Missing Part A evaluation artifact: %s. Run partA_04 first.', partA_eval_path);
end

partA = load(partA_eval_path);
if ~all(isfield(partA, {'window_scores', 'horizon_scores', 'summaries'}))
    error('PARTB_03:InvalidPartABaseline', 'Part A evaluation artifact must contain window_scores, horizon_scores, and summaries.');
end

%% 4. Score Saved Forecast Artifacts
[window_scores, horizon_scores, interval_scores] = local_score_all(saved, forecast_dir, horizon);

fprintf('Evaluated %d forecast artifacts: %d window rows, %d horizon rows, %d interval rows.\n', numel(saved), height(window_scores), height(horizon_scores), height(interval_scores));

%% 5. Summaries
summaries = struct();
summaries.replicate_summary = local_replicate_summary(horizon_scores, horizon);
summaries.scenario_summary  = local_scenario_summary(summaries.replicate_summary);
summaries.stress_summary    = local_stress_summary(summaries.scenario_summary);
summaries.horizon_summary   = local_horizon_summary(horizon_scores);
summaries.interval_summary  = local_interval_summary(interval_scores);
summaries.generation_summary = local_generation_summary(generation.generation_status);
summaries.execution_summary = local_execution_summary(forecast_status);

[summaries.degradation_summary, num_undefined_ratios] = local_degradation_summary(horizon_scores, partA.horizon_scores);

fprintf('Baseline comparison: %d Part B horizon rows matched to Part A; %d undefined WIS ratios (Part A WIS == 0).\n', height(horizon_scores), num_undefined_ratios);

%% 6. Save Evaluation Artifact
evaluation_snapshot = local_evaluation_snapshot(cfg, partA_eval_path, status_counts);

evaluation_artifact = fullfile(evaluation_dir, 'partB_03_evaluation_results.mat');
save(evaluation_artifact, 'window_scores', 'horizon_scores', 'interval_scores', 'summaries', 'availability_report', 'evaluation_snapshot');
fprintf('Evaluation artifact saved to: %s\n', evaluation_artifact);

%% 7. Save Summary Tables
local_write_table(table_dir, 'partB_03_replicate_summary.csv', summaries.replicate_summary);
local_write_table(table_dir, 'partB_03_scenario_summary.csv', summaries.scenario_summary);
local_write_table(table_dir, 'partB_03_stress_summary.csv', summaries.stress_summary);
local_write_table(table_dir, 'partB_03_horizon_summary.csv', summaries.horizon_summary);
local_write_table(table_dir, 'partB_03_interval_summary.csv', summaries.interval_summary);
local_write_table(table_dir, 'partB_03_generation_summary.csv', summaries.generation_summary);
local_write_table(table_dir, 'partB_03_execution_summary.csv', summaries.execution_summary);
local_write_table(table_dir, 'partB_03_degradation_summary.csv', summaries.degradation_summary);

fprintf('=== Part B Forecast Evaluation Complete ===\n\n');

%% 8. Local Functions
function [window_scores, horizon_scores, interval_scores] = local_score_all(saved, forecast_dir, horizon)
%LOCAL_SCORE_ALL Score every saved forecast artifact into raw score tables.
num_saved = numel(saved);
window_blocks   = cell(num_saved, 1);
horizon_blocks  = cell(num_saved, 1);
interval_blocks = cell(num_saved, 1);

for i = 1:num_saved
    entry         = saved(i);
    artifact_path = fullfile(forecast_dir, char(entry.output_filename));

    if ~exist(artifact_path, 'file')
        error('PARTB_03:MissingForecastArtifact', 'Status marks %s as "saved" but the forecast artifact is missing: %s.', entry.output_filename, artifact_path);
    end

    artifact = load(artifact_path);
    local_validate_artifact(artifact);
    local_check_identity(artifact, entry);

    [window_blocks{i}, horizon_blocks{i}, interval_blocks{i}] = local_score_artifact(artifact, horizon);
end

window_scores   = vertcat(window_blocks{:});
horizon_scores  = vertcat(horizon_blocks{:});
interval_scores = vertcat(interval_blocks{:});
end

function local_validate_artifact(artifact)
%LOCAL_VALIDATE_ARTIFACT Fail fast if required forecast-artifact fields are absent.
required = {'case_id', 'scenario_id', 'replicate_id', 'model_type', 'exo_mode', 'selected_configuration', 'wis_alphas', 'results'};
if ~all(isfield(artifact, required))
    error('PARTB_03:InvalidForecastArtifact', 'Forecast artifact is missing one or more required fields.');
end

result_fields = {'window_day', 'window_day_idx', 'time_horizon', 'truth_Rt_window', 'forecast_median', 'forecast_lower', 'forecast_upper'};
if ~all(isfield(artifact.results, result_fields))
    error('PARTB_03:InvalidForecastResult', 'A results entry is missing one or more required fields.');
end
end

function local_check_identity(artifact, entry)
%LOCAL_CHECK_IDENTITY Fail fast if artifact identity disagrees with the status entry.
matches = string(artifact.case_id) == string(entry.case_id) && string(artifact.scenario_id) == string(entry.scenario_id) && string(artifact.replicate_id) == string(entry.replicate_id) && string(artifact.model_type) == string(entry.model_type) && string(artifact.exo_mode) == string(entry.exo_mode);
if ~matches
    error('PARTB_03:IdentityMismatch', 'Forecast artifact identity disagrees with the Script 2 status entry for %s.', entry.output_filename);
end
end

function [window_tbl, horizon_tbl, interval_tbl] = local_score_artifact(artifact, horizon)
%LOCAL_SCORE_ARTIFACT Score one Part B forecast artifact against latent truth windows.
case_id      = string(artifact.case_id);
scenario_id  = string(artifact.scenario_id);
replicate_id = string(artifact.replicate_id);
model_type   = string(artifact.model_type);
exo_mode     = string(artifact.exo_mode);
alphas       = artifact.wis_alphas(:);
K            = numel(alphas);
results      = artifact.results;

num_windows   = numel(results);
window_rows   = cell(num_windows, 1);
horizon_rows  = cell(num_windows, 1);
interval_rows = cell(num_windows, 1);

for w = 1:num_windows
    result = results(w);

    truth_Rt = result.truth_Rt_window(:);
    pred_Rt  = result.forecast_median(:);
    lower_Rt = result.forecast_lower;
    upper_Rt = result.forecast_upper;
    H        = numel(truth_Rt);

    local_validate_scoring(truth_Rt, pred_Rt, lower_Rt, upper_Rt, result.time_horizon, H, K, horizon);

    wis      = compute_wis(truth_Rt, pred_Rt, lower_Rt, upper_Rt, alphas);
    point    = compute_point_error(truth_Rt, pred_Rt);
    interval = compute_interval_diagnostics(truth_Rt, lower_Rt, upper_Rt, alphas);

    horizon_idx  = (1:H)';
    forecast_day = result.time_horizon(:);
    window_day   = result.window_day;
    window_idx   = result.window_day_idx;

    window_rows{w} = table(case_id, scenario_id, replicate_id, model_type, exo_mode, window_day, window_idx, mean(wis), point.rmse, point.mae, mean(interval.coverage_mean), mean(interval.width_mean), 'VariableNames', {'Case', 'Scenario', 'Replicate', 'Model', 'ExoMode', 'WindowDay', 'WindowDayIdx', 'WindowWIS', 'WindowRMSE', 'WindowMAE', 'MeanCoverage', 'MeanIntervalWidth'});

    horizon_rows{w} = table(repmat(case_id, H, 1), repmat(scenario_id, H, 1), repmat(replicate_id, H, 1), repmat(model_type, H, 1), repmat(exo_mode, H, 1), repmat(window_day, H, 1), repmat(window_idx, H, 1), horizon_idx, forecast_day, truth_Rt, pred_Rt, point.error, point.absolute_error, point.squared_error, wis, interval.coverage_mean, interval.width_mean, 'VariableNames', {'Case', 'Scenario', 'Replicate', 'Model', 'ExoMode', 'WindowDay', 'WindowDayIdx', 'HorizonIdx', 'ForecastDay', 'Truth_Rt', 'Median_Forecast', 'Error', 'AbsoluteError', 'SquaredError', 'WIS', 'MeanCoverage', 'MeanIntervalWidth'});

    interval_rows{w} = table(repmat(case_id, K, 1), repmat(scenario_id, K, 1), repmat(replicate_id, K, 1), repmat(model_type, K, 1), repmat(exo_mode, K, 1), repmat(window_day, K, 1), repmat(window_idx, K, 1), alphas, 1 - alphas, mean(interval.coverage, 1)', mean(interval.interval_width, 1)', 'VariableNames', {'Case', 'Scenario', 'Replicate', 'Model', 'ExoMode', 'WindowDay', 'WindowDayIdx', 'Alpha', 'NominalCoverage', 'Coverage', 'IntervalWidth'});
end

window_tbl   = vertcat(window_rows{:});
horizon_tbl  = vertcat(horizon_rows{:});
interval_tbl = vertcat(interval_rows{:});
end

function local_validate_scoring(truth, pred, lower, upper, time_horizon, H, K, horizon)
%LOCAL_VALIDATE_SCORING Fail fast on malformed score inputs for one window.
if numel(pred) ~= H || numel(time_horizon) ~= H
    error('PARTB_03:DimensionMismatch', 'Truth, median, and time-horizon lengths disagree.');
end
if H ~= horizon
    error('PARTB_03:HorizonMismatch', 'Saved horizon length %d differs from configured horizon %d.', H, horizon);
end
if ~isequal(size(lower), [H, K]) || ~isequal(size(upper), [H, K])
    error('PARTB_03:IntervalShape', 'Interval-bound dimensions disagree with truth length or wis_alphas count.');
end
if ~all(isfinite(truth)) || ~all(isfinite(pred)) || ~all(isfinite(lower(:))) || ~all(isfinite(upper(:)))
    error('PARTB_03:NonFiniteScoreInput', 'Score inputs contain non-finite values.');
end
if ~all(pred > 0)
    error('PARTB_03:NonPositiveMedian', 'Forecast medians must be positive.');
end
if any(lower(:) > upper(:))
    error('PARTB_03:LowerAboveUpper', 'A lower interval bound exceeds its upper bound.');
end
end

function replicate_summary = local_replicate_summary(horizon_scores, horizon)
%LOCAL_REPLICATE_SUMMARY Aggregate horizon rows to one row per replicate.
keys = {'Case', 'Scenario', 'Replicate', 'Model', 'ExoMode'};
replicate_summary = local_aggregate(horizon_scores, keys, { ...
    'MeanWIS',           @mean,              'WIS'; ...
    'MAE',               @mean,              'AbsoluteError'; ...
    'RMSE',              @(x) sqrt(mean(x)), 'SquaredError'; ...
    'MeanCoverage',      @mean,              'MeanCoverage'; ...
    'MeanIntervalWidth', @mean,              'MeanIntervalWidth'; ...
    'NumHorizonRows',    @numel,             'WIS'});
replicate_summary.NumWindows = replicate_summary.NumHorizonRows / horizon;
replicate_summary = movevars(replicate_summary, 'NumWindows', 'Before', 'NumHorizonRows');
end

function scenario_summary = local_scenario_summary(replicate_summary)
%LOCAL_SCENARIO_SUMMARY Aggregate replicate rows to one row per scenario.
keys = {'Case', 'Scenario', 'Model', 'ExoMode'};
scenario_summary = local_aggregate(replicate_summary, keys, { ...
    'NumReplicates',     @numel,             'MeanWIS'; ...
    'MeanWIS',           @mean,              'MeanWIS'; ...
    'StdWIS',            @local_sample_std,  'MeanWIS'; ...
    'MedianWIS',         @median,            'MeanWIS'; ...
    'MeanMAE',           @mean,              'MAE'; ...
    'MeanRMSE',          @mean,              'RMSE'; ...
    'MeanCoverage',      @mean,              'MeanCoverage'; ...
    'MeanIntervalWidth', @mean,              'MeanIntervalWidth'});
end

function stress_summary = local_stress_summary(scenario_summary)
%LOCAL_STRESS_SUMMARY Aggregate scenario rows to one row per stress case with equal scenario weight.
keys = {'Case', 'Model', 'ExoMode'};
stress_summary = local_aggregate(scenario_summary, keys, { ...
    'NumScenarios',      @numel, 'MeanWIS'; ...
    'TotalReplicates',   @sum,   'NumReplicates'; ...
    'MeanWIS',           @mean,  'MeanWIS'; ...
    'MeanMAE',           @mean,  'MeanMAE'; ...
    'MeanRMSE',          @mean,  'MeanRMSE'; ...
    'MeanCoverage',      @mean,  'MeanCoverage'; ...
    'MeanIntervalWidth', @mean,  'MeanIntervalWidth'});
end

function horizon_summary = local_horizon_summary(horizon_scores)
%LOCAL_HORIZON_SUMMARY Hierarchical horizon-wise aggregation with equal scenario weight.
replicate_level = local_aggregate(horizon_scores, {'Case', 'Scenario', 'Replicate', 'Model', 'ExoMode', 'HorizonIdx'}, { ...
    'MeanWIS',           @mean, 'WIS'; ...
    'MeanAbsoluteError', @mean, 'AbsoluteError'; ...
    'MeanSquaredError',  @mean, 'SquaredError'; ...
    'MeanCoverage',      @mean, 'MeanCoverage'; ...
    'MeanIntervalWidth', @mean, 'MeanIntervalWidth'});

scenario_level = local_aggregate(replicate_level, {'Case', 'Scenario', 'Model', 'ExoMode', 'HorizonIdx'}, { ...
    'MeanWIS',           @mean, 'MeanWIS'; ...
    'MeanAbsoluteError', @mean, 'MeanAbsoluteError'; ...
    'MeanSquaredError',  @mean, 'MeanSquaredError'; ...
    'MeanCoverage',      @mean, 'MeanCoverage'; ...
    'MeanIntervalWidth', @mean, 'MeanIntervalWidth'});

horizon_summary = local_aggregate(scenario_level, {'Case', 'Model', 'ExoMode', 'HorizonIdx'}, { ...
    'MeanWIS',           @mean, 'MeanWIS'; ...
    'MeanAbsoluteError', @mean, 'MeanAbsoluteError'; ...
    'MeanSquaredError',  @mean, 'MeanSquaredError'; ...
    'MeanCoverage',      @mean, 'MeanCoverage'; ...
    'MeanIntervalWidth', @mean, 'MeanIntervalWidth'});

horizon_summary.RMSE = sqrt(horizon_summary.MeanSquaredError);
horizon_summary = movevars(horizon_summary, 'RMSE', 'After', 'MeanSquaredError');
end

function interval_summary = local_interval_summary(interval_scores)
%LOCAL_INTERVAL_SUMMARY Hierarchical interval-calibration aggregation with equal scenario weight.
replicate_level = local_aggregate(interval_scores, {'Case', 'Scenario', 'Replicate', 'Model', 'ExoMode', 'Alpha', 'NominalCoverage'}, { ...
    'MeanCoverage',      @mean, 'Coverage'; ...
    'MeanIntervalWidth', @mean, 'IntervalWidth'});

scenario_level = local_aggregate(replicate_level, {'Case', 'Scenario', 'Model', 'ExoMode', 'Alpha', 'NominalCoverage'}, { ...
    'MeanCoverage',      @mean, 'MeanCoverage'; ...
    'MeanIntervalWidth', @mean, 'MeanIntervalWidth'});

interval_summary = local_aggregate(scenario_level, {'Case', 'Model', 'ExoMode', 'Alpha', 'NominalCoverage'}, { ...
    'MeanCoverage',      @mean, 'MeanCoverage'; ...
    'MeanIntervalWidth', @mean, 'MeanIntervalWidth'});

interval_summary.CoverageError = interval_summary.MeanCoverage - interval_summary.NominalCoverage;
end

function generation_summary = local_generation_summary(generation_status)
%LOCAL_GENERATION_SUMMARY Per stress-case dataset-generation outcome counts.
status_tbl = table(string({generation_status.case_id})', string({generation_status.status})', 'VariableNames', {'Case', 'Status'});

generation_summary = local_aggregate(status_tbl, {'Case'}, { ...
    'Attempts',       @numel,                          'Status'; ...
    'Saved',          @(x) sum(x == "saved"),          'Status'; ...
    'DomainFailures', @(x) sum(x == "domain_failure"), 'Status'});
end

function execution_summary = local_execution_summary(forecast_status)
%LOCAL_EXECUTION_SUMMARY Per stress-case forecast outcome counts from all Script 2 attempts.
status_tbl = table(string({forecast_status.case_id})', string({forecast_status.model_type})', string({forecast_status.exo_mode})', string({forecast_status.status})', 'VariableNames', {'Case', 'Model', 'ExoMode', 'Status'});

execution_summary = local_aggregate(status_tbl, {'Case', 'Model', 'ExoMode'}, { ...
    'Attempts',       @numel,                          'Status'; ...
    'Saved',          @(x) sum(x == "saved"),          'Status'; ...
    'NoWindows',      @(x) sum(x == "no_windows"),     'Status'; ...
    'DomainFailures', @(x) sum(x == "domain_failure"), 'Status'; ...
    'Pending',        @(x) sum(x == "pending"),        'Status'});
execution_summary.SuccessRate = execution_summary.Saved ./ execution_summary.Attempts;
end

function [degradation_summary, num_undefined] = local_degradation_summary(horizon_scores, partA_horizon)
%LOCAL_DEGRADATION_SUMMARY Match Part B horizon WIS to the Part A baseline and aggregate degradation.
match_keys = {'Scenario', 'Model', 'ExoMode', 'WindowDay', 'HorizonIdx'};

baseline = partA_horizon(:, [match_keys, {'WIS'}]);
baseline = renamevars(baseline, 'WIS', 'PartA_WIS');
if height(unique(baseline(:, match_keys))) ~= height(baseline)
    error('PARTB_03:AmbiguousBaseline', 'Part A baseline rows are not unique across the matching keys.');
end

matched = innerjoin(horizon_scores, baseline, 'Keys', match_keys);
if height(matched) ~= height(horizon_scores)
    error('PARTB_03:UnmatchedBaseline', '%d Part B horizon rows have no matching Part A baseline row.', height(horizon_scores) - height(matched));
end

matched.PartB_WIS      = matched.WIS;
matched.WIS_Difference = matched.PartB_WIS - matched.PartA_WIS;

ratio           = matched.PartB_WIS ./ matched.PartA_WIS;
undefined_mask  = matched.PartA_WIS == 0;
ratio(undefined_mask) = NaN;
matched.WIS_Ratio = ratio;
num_undefined     = sum(undefined_mask);

replicate_level = local_aggregate(matched, {'Case', 'Scenario', 'Replicate', 'Model', 'ExoMode'}, { ...
    'PartA_WIS',      @mean,                   'PartA_WIS'; ...
    'PartB_WIS',      @mean,                   'PartB_WIS'; ...
    'WIS_Difference', @mean,                   'WIS_Difference'; ...
    'WIS_Ratio',      @(x) mean(x, 'omitnan'), 'WIS_Ratio'});

scenario_level = local_aggregate(replicate_level, {'Case', 'Scenario', 'Model', 'ExoMode'}, { ...
    'PartA_WIS',      @mean,                   'PartA_WIS'; ...
    'PartB_WIS',      @mean,                   'PartB_WIS'; ...
    'WIS_Difference', @mean,                   'WIS_Difference'; ...
    'WIS_Ratio',      @(x) mean(x, 'omitnan'), 'WIS_Ratio'});

degradation_summary = local_aggregate(scenario_level, {'Case', 'Model', 'ExoMode'}, { ...
    'PartA_MeanWIS',     @mean, 'PartA_WIS'; ...
    'PartB_MeanWIS',     @mean, 'PartB_WIS'; ...
    'MeanWISDifference', @mean, 'WIS_Difference'});

degradation_summary.MeanWISRatio = degradation_summary.PartB_MeanWIS ./ degradation_summary.PartA_MeanWIS;

undefined_summary_mask = degradation_summary.PartA_MeanWIS == 0;
degradation_summary.MeanWISRatio(undefined_summary_mask) = NaN;

degradation_summary.RelativeWISIncrease = degradation_summary.MeanWISRatio - 1;
end

function value = local_sample_std(values)
%LOCAL_SAMPLE_STD Sample standard deviation when replicate variation is estimable.
if numel(values) < 2
    value = NaN;
else
    value = std(values);
end
end

function out = local_aggregate(tbl, keys, specs)
%LOCAL_AGGREGATE Group a table by keys and apply per-column aggregation specs.
[group, out] = findgroups(tbl(:, keys));
for i = 1:size(specs, 1)
    out.(specs{i, 1}) = splitapply(specs{i, 2}, tbl.(specs{i, 3}), group);
end
end

function snapshot = local_evaluation_snapshot(cfg, partA_eval_path, status_counts)
%LOCAL_EVALUATION_SNAPSHOT Minimal provenance for the Part B evaluation.
snapshot = struct();
snapshot.experiment_id           = cfg.partB.experiment_id;
snapshot.model_types             = cfg.partB.run.model_types;
snapshot.wis_alphas              = cfg.forecast.wis_alphas;
snapshot.horizon                 = cfg.forecast.horizon;
snapshot.min_window              = cfg.forecast.min_window;
snapshot.step_size               = cfg.forecast.step_size;
snapshot.partA_baseline_artifact = string(partA_eval_path);
snapshot.status_counts           = status_counts;
end

function local_write_table(table_dir, filename, table_data)
%LOCAL_WRITE_TABLE Write one compact summary CSV table.
output_path = fullfile(table_dir, filename);
writetable(table_data, output_path);
fprintf('Table saved to: %s\n', output_path);
end