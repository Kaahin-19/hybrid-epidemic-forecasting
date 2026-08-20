%PARTA_04_EVALUATE_FORECASTS Evaluate Part A forecast performance.
%
%   Description:
%       Scores final Part A Rt forecasts using WIS, point-forecast error, and
%       interval diagnostics. Also evaluates deterministic forecast-driven and
%       persistence-Rt SIRS projections of the infected compartment. Exports
%       window-level scores, horizon-level scores, and compact summaries.
%
%   Workflow:
%       1. Load final forecast artifacts.
%       2. Compute Rt and infected-state projection scores.
%       3. Aggregate Rt and infected-state projection summaries.
%       4. Save the evaluation artifact and report tables.
%
%   See also PARTA_CONFIG, PARTA_03_RUN_FORECASTS, COMPUTE_WIS, ...
%            COMPUTE_POINT_ERROR, COMPUTE_INTERVAL_DIAGNOSTICS.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-08-20

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Forecast Evaluation ===\n');

cfg            = partA_config();
forecast_dir   = cfg.output.forecast_dir;
evaluation_dir = cfg.output.score_dir;
table_dir      = cfg.output.table_dir;

if ~exist(evaluation_dir, 'dir'), mkdir(evaluation_dir); end
if ~exist(table_dir, 'dir'), mkdir(table_dir); end

%% 2. Forecast Artifact Evaluation
forecast_files = local_sort_dir_by_name(dir(fullfile(forecast_dir, 'partA_03_forecast_*.mat')));

if isempty(forecast_files)
    error('PARTA_04:NoForecastArtifacts', 'No forecast artifacts found under %s. Run partA_03 first.', forecast_dir);
end

[window_scores, horizon_scores, interval_scores, i_projection_window_scores, i_projection_horizon_scores] = local_evaluate_forecasts(forecast_files);

fprintf('Evaluated %d forecast windows and %d horizon rows.\n', height(window_scores), height(horizon_scores));
fprintf('Evaluated %d infected-state projection windows and %d projection horizon rows.\n', height(i_projection_window_scores), height(i_projection_horizon_scores));

%% 3. Score Summaries
summaries = local_summarize_scores(window_scores, horizon_scores, interval_scores, i_projection_window_scores, i_projection_horizon_scores);

%% 4. Save Evaluation Artifact
evaluation_artifact = fullfile(evaluation_dir, 'partA_04_evaluation_results.mat');

save(evaluation_artifact, 'window_scores', 'horizon_scores', 'i_projection_window_scores', 'i_projection_horizon_scores', 'summaries');

fprintf('Evaluation artifact saved to: %s\n', evaluation_artifact);

%% 5. Save Tables
local_write_table(table_dir, 'partA_04_window_scores.csv', window_scores);
local_write_table(table_dir, 'partA_04_horizon_scores.csv', horizon_scores);
local_write_table(table_dir, 'partA_04_scenario_summary.csv', summaries.scenario_summary);
local_write_table(table_dir, 'partA_04_horizon_summary.csv', summaries.horizon_summary);
local_write_table(table_dir, 'partA_04_interval_summary.csv', summaries.interval_summary);
local_write_table(table_dir, 'partA_04_i_projection_window_scores.csv', i_projection_window_scores);
local_write_table(table_dir, 'partA_04_i_projection_horizon_scores.csv', i_projection_horizon_scores);
local_write_table(table_dir, 'partA_04_i_projection_scenario_summary.csv', summaries.i_projection_scenario_summary);
local_write_table(table_dir, 'partA_04_i_projection_horizon_summary.csv', summaries.i_projection_horizon_summary);

fprintf('=== Part A Forecast Evaluation Complete ===\n\n');

%% 6. Local Functions
function [window_scores, horizon_scores, interval_scores, i_projection_window_scores, i_projection_horizon_scores] = local_evaluate_forecasts(forecast_files)
%LOCAL_EVALUATE_FORECASTS Score all Script 3 forecast artifacts.
num_files = numel(forecast_files);

window_blocks               = cell(num_files, 1);
horizon_blocks              = cell(num_files, 1);
interval_blocks             = cell(num_files, 1);
i_projection_window_blocks  = cell(num_files, 1);
i_projection_horizon_blocks = cell(num_files, 1);

for i = 1:num_files
    artifact_path = fullfile(forecast_files(i).folder, forecast_files(i).name);
    loaded = load(artifact_path);

    [window_blocks{i}, horizon_blocks{i}, interval_blocks{i}, i_projection_window_blocks{i}, i_projection_horizon_blocks{i}] = local_score_forecast_artifact(loaded);
end

window_scores               = vertcat(window_blocks{:});
horizon_scores              = vertcat(horizon_blocks{:});
interval_scores             = vertcat(interval_blocks{:});
i_projection_window_scores  = vertcat(i_projection_window_blocks{:});
i_projection_horizon_scores = vertcat(i_projection_horizon_blocks{:});
end

function [window_tbl, horizon_tbl, interval_tbl, i_projection_window_tbl, i_projection_horizon_tbl] = local_score_forecast_artifact(artifact)
%LOCAL_SCORE_FORECAST_ARTIFACT Score one scenario forecast artifact.
scenario_id = string(artifact.scenario_id);
model_type  = string(artifact.model_type);
exo_mode    = string(artifact.exo_mode);
alphas      = artifact.wis_alphas(:);
results     = artifact.results;

num_windows = numel(results);

window_rows               = cell(num_windows, 1);
horizon_rows              = cell(num_windows, 1);
interval_rows             = cell(num_windows, 1);
i_projection_window_rows  = cell(num_windows, 1);
i_projection_horizon_rows = cell(num_windows, 1);

for w = 1:num_windows
    result = results(w);

    truth_Rt = result.truth_Rt_window(:);
    pred_Rt  = result.forecast_median(:);
    lower_Rt = result.forecast_lower;
    upper_Rt = result.forecast_upper;

    [wis, ~] = compute_wis(truth_Rt, pred_Rt, lower_Rt, upper_Rt, alphas);
    point    = compute_point_error(truth_Rt, pred_Rt);
    interval = compute_interval_diagnostics(truth_Rt, lower_Rt, upper_Rt, alphas);

    forecast_i_point    = compute_point_error(result.truth_I_window, result.projected_I);
    persistence_i_point = compute_point_error(result.truth_I_window, result.persistence_I);

    H = numel(truth_Rt);
    K = numel(alphas);

    horizon_idx  = (1:H)';
    forecast_day = result.time_horizon(:);
    window_day   = result.window_day;
    window_idx   = result.window_day_idx;

    window_rows{w} = table(scenario_id, model_type, exo_mode, window_day, window_idx, mean(wis), point.rmse, point.mae, mean(interval.coverage_mean), mean(interval.width_mean), 'VariableNames', {'Scenario', 'Model', 'ExoMode', 'WindowDay', 'WindowDayIdx', 'WindowWIS', 'WindowRMSE', 'WindowMAE', 'MeanCoverage', 'MeanIntervalWidth'});

    horizon_rows{w} = table(repmat(scenario_id, H, 1), repmat(model_type, H, 1), repmat(exo_mode, H, 1), repmat(window_day, H, 1), repmat(window_idx, H, 1), horizon_idx, forecast_day, truth_Rt, pred_Rt, point.error, point.absolute_error, point.squared_error, wis, interval.coverage_mean, interval.width_mean, 'VariableNames', {'Scenario', 'Model', 'ExoMode', 'WindowDay', 'WindowDayIdx', 'HorizonIdx', 'ForecastDay', 'Truth_Rt', 'Median_Forecast', 'Error', 'AbsoluteError', 'SquaredError', 'WIS', 'MeanCoverage', 'MeanIntervalWidth'});

    interval_rows{w} = table(repmat(scenario_id, K, 1), repmat(model_type, K, 1), repmat(exo_mode, K, 1), alphas, 1 - alphas, mean(interval.coverage, 1)', mean(interval.interval_width, 1)', 'VariableNames', {'Scenario', 'Model', 'ExoMode', 'Alpha', 'NominalCoverage', 'Coverage', 'IntervalWidth'});

    i_projection_window_rows{w} = table(scenario_id, model_type, exo_mode, window_day, window_idx, forecast_i_point.rmse, forecast_i_point.mae, persistence_i_point.rmse, persistence_i_point.mae, 'VariableNames', {'Scenario', 'Model', 'ExoMode', 'WindowDay', 'WindowDayIdx', 'ForecastDrivenRMSE', 'ForecastDrivenMAE', 'PersistenceRtRMSE', 'PersistenceRtMAE'});

    i_projection_horizon_rows{w} = table(repmat(scenario_id, H, 1), repmat(model_type, H, 1), repmat(exo_mode, H, 1), repmat(window_day, H, 1), repmat(window_idx, H, 1), horizon_idx, forecast_day, result.truth_I_window, result.projected_I, result.persistence_I, forecast_i_point.absolute_error, persistence_i_point.absolute_error, 'VariableNames', {'Scenario', 'Model', 'ExoMode', 'WindowDay', 'WindowDayIdx', 'HorizonIdx', 'ForecastDay', 'Truth_I', 'ForecastDriven_I', 'PersistenceRt_I', 'ForecastDrivenAbsoluteError', 'PersistenceRtAbsoluteError'});
end

window_tbl               = vertcat(window_rows{:});
horizon_tbl              = vertcat(horizon_rows{:});
interval_tbl             = vertcat(interval_rows{:});
i_projection_window_tbl  = vertcat(i_projection_window_rows{:});
i_projection_horizon_tbl = vertcat(i_projection_horizon_rows{:});
end

function summaries = local_summarize_scores(window_scores, horizon_scores, interval_scores, i_projection_window_scores, i_projection_horizon_scores)
%LOCAL_SUMMARIZE_SCORES Build compact report-level score summaries.
summaries = struct();

summaries.scenario_summary = local_group_means(window_scores, {'Scenario', 'Model', 'ExoMode'}, {'WindowWIS', 'WindowRMSE', 'WindowMAE', 'MeanCoverage', 'MeanIntervalWidth'}, {'MeanWindowWIS', 'MeanWindowRMSE', 'MeanWindowMAE', 'MeanCoverage', 'MeanIntervalWidth'});

summaries.horizon_summary = local_group_means(horizon_scores, {'Model', 'ExoMode', 'HorizonIdx'}, {'WIS', 'AbsoluteError', 'SquaredError', 'MeanCoverage', 'MeanIntervalWidth'}, {'MeanWIS', 'MeanAbsoluteError', 'MeanSquaredError', 'MeanCoverage', 'MeanIntervalWidth'});

summaries.interval_summary = local_group_means(interval_scores, {'Model', 'ExoMode', 'Alpha', 'NominalCoverage'}, {'Coverage', 'IntervalWidth'}, {'MeanCoverage', 'MeanIntervalWidth'});

summaries.i_projection_scenario_summary = local_group_means(i_projection_window_scores, {'Scenario', 'Model', 'ExoMode'}, {'ForecastDrivenRMSE', 'ForecastDrivenMAE', 'PersistenceRtRMSE', 'PersistenceRtMAE'}, {'MeanForecastDrivenRMSE', 'MeanForecastDrivenMAE', 'MeanPersistenceRtRMSE', 'MeanPersistenceRtMAE'});
summaries.i_projection_scenario_summary.MeanRMSEImprovement = summaries.i_projection_scenario_summary.MeanPersistenceRtRMSE - summaries.i_projection_scenario_summary.MeanForecastDrivenRMSE;
summaries.i_projection_scenario_summary.MeanMAEImprovement = summaries.i_projection_scenario_summary.MeanPersistenceRtMAE - summaries.i_projection_scenario_summary.MeanForecastDrivenMAE;

summaries.i_projection_horizon_summary = local_group_means(i_projection_horizon_scores, {'Model', 'ExoMode', 'HorizonIdx'}, {'ForecastDrivenAbsoluteError', 'PersistenceRtAbsoluteError'}, {'MeanForecastDrivenAbsoluteError', 'MeanPersistenceRtAbsoluteError'});
summaries.i_projection_horizon_summary.MeanAbsoluteErrorImprovement = summaries.i_projection_horizon_summary.MeanPersistenceRtAbsoluteError - summaries.i_projection_horizon_summary.MeanForecastDrivenAbsoluteError;
end

function out = local_group_means(tbl, group_vars, value_vars, mean_names)
%LOCAL_GROUP_MEANS Group a table and rename mean columns.
out = groupsummary(tbl, group_vars, "mean", value_vars);
out = renamevars(out, "mean_" + string(value_vars), string(mean_names));
end

function output_path = local_write_table(table_dir, filename, table_data)
%LOCAL_WRITE_TABLE Write one CSV table.
output_path = fullfile(table_dir, filename);
writetable(table_data, output_path);
fprintf('Table saved to: %s\n', output_path);
end

function files = local_sort_dir_by_name(files)
%LOCAL_SORT_DIR_BY_NAME Sort a dir struct array by file name.
[~, order] = sort({files.name});
files = files(order);
end
