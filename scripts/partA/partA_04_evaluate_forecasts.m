%PARTA_04_EVALUATE_FORECASTS Evaluate Part A forecast artifacts and write tables.
%
%   Description:
%       Runs two independent reporting sections. Section A reads only the
%       Part A 02 model-selection artifacts and reports the selected
%       configuration and per-candidate AICc diagnostics. Section B reads only
%       the Part A 03 forecast artifacts, scores each forecast window with the
%       shared scoring kernels (compute_wis, compute_point_error,
%       compute_interval_diagnostics), aggregates the scores across scenarios,
%       horizons, model families, and exogenous modes, and writes evaluation
%       artifacts plus tabular outputs. Figure generation is delegated to
%       Part A 05. The two sections keep their inputs and outputs disjoint:
%       Section A never reads Script 3, Section B never reads Script 2.
%
%   Workflow:
%       1. Load selection artifacts and build Script 2-derived reporting tables.
%       2. Load forecast artifacts and build Script 3-derived score tables.
%       3. Aggregate forecast scores into summary tables.
%       4. Save the evaluation MAT artifact and CSV table outputs.
%
%   See also PARTA_CONFIG, COMPUTE_WIS, COMPUTE_POINT_ERROR, ...
%            COMPUTE_INTERVAL_DIAGNOSTICS, PARTA_05_GENERATE_FIGURES.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-06-22

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Forecast Evaluation ===\n');

repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(repo_root, 'src', 'scoring'));

cfg = partA_config();
forecast_dir = cfg.output.forecast_dir;
selection_dir = cfg.output.model_selection_dir;
evaluation_dir = cfg.output.score_dir;
table_dir = cfg.output.table_dir;

if ~exist(evaluation_dir, 'dir'), mkdir(evaluation_dir); end
if ~exist(table_dir, 'dir'), mkdir(table_dir); end

%% 2. Selection / Candidate Reporting
[selection_summary, candidate_aicc_summary, missing_selection_artifacts] = ...
    local_load_selection_reporting(selection_dir);

%% 3. Forecast-Window Evaluation
[window_scores, pointwise_scores, interval_scores, source_forecast_artifacts] = ...
    local_evaluate_forecast_artifacts(forecast_dir);

summaries = local_summarize_scores(window_scores, pointwise_scores, interval_scores);

fprintf('Evaluated %d forecast windows and %d pointwise horizon rows.\n', ...
    height(window_scores), height(pointwise_scores));

%% 4. Save Evaluation Artifact
cfg_snapshot = local_cfg_snapshot(cfg);
evaluation_artifact = fullfile(evaluation_dir, 'partA_04_evaluation_results.mat');

save(evaluation_artifact, ...
    'selection_summary', 'candidate_aicc_summary', 'missing_selection_artifacts', ...
    'window_scores', 'pointwise_scores', 'interval_scores', 'summaries', ...
    'source_forecast_artifacts', 'cfg_snapshot');

fprintf('Evaluation artifact saved to: %s\n', evaluation_artifact);

%% 5. Save Tables
table_outputs = local_write_tables(table_dir, window_scores, pointwise_scores, ...
    interval_scores, summaries, selection_summary, missing_selection_artifacts, ...
    candidate_aicc_summary, cfg);

fprintf('Saved %d table files under %s\n', numel(table_outputs), table_dir);
fprintf('=== Part A Forecast Evaluation Complete ===\n\n');

%% 6. Selection Reporting Functions
function [selection_summary, candidate_aicc_summary, missing_selection_artifacts] = ...
    local_load_selection_reporting(selection_dir)

selection_files = dir(fullfile(selection_dir, 'partA_02_global_hyperparameters_*.mat'));
selection_files = local_sort_dir_by_name(selection_files);
missing_selection_artifacts = strings(0, 1);

if isempty(selection_files)
    [selection_summary, candidate_aicc_summary] = local_empty_selection_tables();
    missing_selection_artifacts = string(selection_dir);
    warning('EVAL:NoSelectionArtifacts', ...
        'No model-selection artifacts found under %s.', selection_dir);
    return;
end

selection_rows = cell(numel(selection_files), 1);
candidate_blocks = cell(numel(selection_files), 1);

for i = 1:numel(selection_files)
    artifact_path = fullfile(selection_files(i).folder, selection_files(i).name);
    loaded = load(artifact_path);

    selection_rows{i} = table(string(loaded.model_type), string(loaded.exo_mode), ...
        string(mat2str(loaded.selected_configuration)), loaded.selected_index, ...
        loaded.best_global_wis, string(artifact_path), ...
        'VariableNames', {'Model', 'ExoMode', 'SelectedConfiguration', ...
        'SelectedIndex', 'BestGlobalWIS', 'SelectionArtifact'});

    grid = loaded.candidate_grid;
    n = size(grid, 1);

    selected = false(n, 1);
    selected(loaded.selected_index) = true;

    candidate_text = string(arrayfun(@(r) mat2str(grid(r, :)), ...
        (1:n)', 'UniformOutput', false));

    candidate_blocks{i} = table(repmat(string(loaded.model_type), n, 1), ...
        repmat(string(loaded.exo_mode), n, 1), candidate_text, ...
        loaded.global_mean_wis(:), loaded.global_mean_aicc(:), selected, ...
        'VariableNames', {'Model', 'ExoMode', 'Candidate', ...
        'GlobalMeanWIS', 'GlobalMeanAICc', 'Selected'});
end

selection_summary = vertcat(selection_rows{:});
candidate_aicc_summary = vertcat(candidate_blocks{:});
end

function [selection_summary, candidate_aicc_summary] = local_empty_selection_tables()
selection_summary = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    'VariableNames', {'Model', 'ExoMode', 'SelectedConfiguration', ...
    'SelectedIndex', 'BestGlobalWIS', 'SelectionArtifact'});

candidate_aicc_summary = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), false(0, 1), ...
    'VariableNames', {'Model', 'ExoMode', 'Candidate', ...
    'GlobalMeanWIS', 'GlobalMeanAICc', 'Selected'});
end

%% 7. Forecast Evaluation Functions
function [window_scores, pointwise_scores, interval_scores, source_forecast_artifacts] = ...
    local_evaluate_forecast_artifacts(forecast_dir)

forecast_files = dir(fullfile(forecast_dir, 'partA_03_forecast_*.mat'));
if isempty(forecast_files)
    error('EVAL:NoForecastArtifacts', ...
        'No forecast artifacts found under %s.', forecast_dir);
end

forecast_files = local_sort_dir_by_name(forecast_files);
n_files = numel(forecast_files);

fprintf('Found %d forecast artifacts in %s\n', n_files, forecast_dir);

window_blocks = cell(n_files, 1);
pointwise_blocks = cell(n_files, 1);
interval_blocks = cell(n_files, 1);
source_forecast_artifacts = strings(n_files, 1);

for i = 1:n_files
    artifact_path = fullfile(forecast_files(i).folder, forecast_files(i).name);
    source_forecast_artifacts(i) = string(artifact_path);
    loaded = load(artifact_path);

    [window_blocks{i}, pointwise_blocks{i}, interval_blocks{i}] = ...
        local_build_score_rows(loaded.forecast_results, ...
        string(loaded.scenario_id), string(loaded.scenario_name), ...
        string(loaded.model_type), string(loaded.exo_mode), artifact_path);
end

window_scores = vertcat(window_blocks{:});
pointwise_scores = vertcat(pointwise_blocks{:});
interval_scores = vertcat(interval_blocks{:});
end

function [window_tbl, pointwise_tbl, interval_tbl] = local_build_score_rows( ...
    forecast_results, scenario_id, scenario_name, model_type, exo_mode, artifact_path)

n_win = numel(forecast_results);
window_rows = cell(n_win, 1);
pointwise_rows = cell(n_win, 1);
interval_rows = cell(n_win, 1);

for w = 1:n_win
    result = forecast_results(w);

    truth_Rt = result.Rt_true_future;
    pred_Rt = result.Rt_pred;
    lower_Rt = result.lower_bounds;
    upper_Rt = result.upper_bounds;
    alphas = result.interval_alphas;

    [wis, wis_comp] = compute_wis(truth_Rt, pred_Rt, lower_Rt, upper_Rt, alphas);
    point = compute_point_error(truth_Rt, pred_Rt);
    interval = compute_interval_diagnostics(truth_Rt, lower_Rt, upper_Rt, alphas);

    H = numel(truth_Rt);
    horizon_idx = (1:H)';
    forecast_day = result.t_future;
    window_day = result.forecast_origin;
    window_day_idx = result.window_day_idx;
    artifact_label = string(artifact_path);

    window_rows{w} = table( ...
        scenario_id, scenario_name, model_type, exo_mode, artifact_label, ...
        window_day, window_day_idx, mean(wis), point.rmse, point.mae, ...
        mean(wis_comp.median_term), mean(wis_comp.dispersion), ...
        mean(wis_comp.underprediction), mean(wis_comp.overprediction), ...
        mean(interval.coverage_mean), mean(interval.calibration_bias_mean), ...
        mean(interval.absolute_calibration_mean), mean(interval.width_mean), ...
        result.aicc, ...
        'VariableNames', {'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
        'ForecastArtifact', 'WindowDay', 'WindowDayIdx', 'WindowWIS', ...
        'WindowRMSE', 'WindowMAE', 'MeanWISMedianComponent', ...
        'MeanWISDispersionComponent', 'MeanWISUnderpredictionComponent', ...
        'MeanWISOverpredictionComponent', 'MeanCoverage', 'MeanCalibrationBias', ...
        'MeanAbsoluteCalibrationError', 'MeanIntervalWidth', 'AICC'});

    pointwise_rows{w} = table( ...
        repmat(scenario_id, H, 1), repmat(scenario_name, H, 1), ...
        repmat(model_type, H, 1), repmat(exo_mode, H, 1), ...
        repmat(artifact_label, H, 1), repmat(window_day, H, 1), ...
        repmat(window_day_idx, H, 1), horizon_idx, forecast_day, truth_Rt, ...
        pred_Rt, point.error, point.squared_error, point.absolute_error, wis, ...
        wis_comp.median_term, wis_comp.dispersion, ...
        wis_comp.underprediction, wis_comp.overprediction, ...
        interval.coverage_mean, interval.calibration_bias_mean, ...
        interval.absolute_calibration_mean, interval.width_mean, ...
        'VariableNames', {'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
        'ForecastArtifact', 'WindowDay', 'WindowDayIdx', 'HorizonIdx', ...
        'ForecastDay', 'Truth_Rt', 'Median_Forecast', 'Error', 'SquaredError', ...
        'AbsoluteError', 'WIS', 'WISMedianComponent', 'WISDispersionComponent', ...
        'WISUnderpredictionComponent', 'WISOverpredictionComponent', ...
        'CoverageMean', 'CalibrationBiasMean', 'AbsoluteCalibrationErrorMean', ...
        'IntervalWidthMean'});

    interval_rows{w} = local_interval_rows(scenario_id, scenario_name, model_type, ...
        exo_mode, artifact_label, window_day, window_day_idx, horizon_idx, ...
        forecast_day, truth_Rt, alphas, lower_Rt, upper_Rt, interval);
end

window_tbl = vertcat(window_rows{:});
pointwise_tbl = vertcat(pointwise_rows{:});
interval_tbl = vertcat(interval_rows{:});
end

function interval_rows = local_interval_rows(scenario_id, scenario_name, model_type, ...
    exo_mode, artifact_label, window_day, window_day_idx, horizon_idx, forecast_day, ...
    truth_Rt, alphas, lower_Rt, upper_Rt, interval)

H = numel(horizon_idx);
K = numel(alphas);
N = H * K;

interval_rows = table( ...
    repmat(scenario_id, N, 1), repmat(scenario_name, N, 1), ...
    repmat(model_type, N, 1), repmat(exo_mode, N, 1), ...
    repmat(artifact_label, N, 1), repmat(window_day, N, 1), ...
    repmat(window_day_idx, N, 1), repmat(horizon_idx, K, 1), ...
    repmat(forecast_day, K, 1), repmat(truth_Rt, K, 1), ...
    repelem(alphas, H, 1), repelem(interval.nominal_coverage, H, 1), ...
    lower_Rt(:), upper_Rt(:), interval.coverage(:), ...
    interval.interval_width(:), interval.coverage_error(:), ...
    interval.absolute_coverage_error(:), interval.interval_score(:), ...
    interval.wis_interval_component(:), interval.wis_sharpness_component(:), ...
    interval.wis_underprediction_component(:), interval.wis_overprediction_component(:), ...
    'VariableNames', {'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
    'ForecastArtifact', 'WindowDay', 'WindowDayIdx', 'HorizonIdx', 'ForecastDay', ...
    'Truth_Rt', 'Alpha', 'NominalCoverage', 'LowerBound', 'UpperBound', 'Coverage', ...
    'IntervalWidth', 'CoverageError', 'AbsoluteCoverageError', 'IntervalScore', ...
    'WISIntervalComponent', 'WISSharpnessComponent', 'WISUnderpredictionComponent', ...
    'WISOverpredictionComponent'});
end

%% 8. Summary Functions
function summaries = local_summarize_scores(window_scores, pointwise_scores, interval_scores)
win_vals = {'WindowWIS', 'WindowRMSE', 'WindowMAE', 'MeanCoverage', ...
    'MeanIntervalWidth', 'MeanCalibrationBias', 'MeanAbsoluteCalibrationError'};
win_names = {'MeanWindowWIS', 'MeanWindowRMSE', 'MeanWindowMAE', 'MeanCoverage', ...
    'MeanIntervalWidth', 'MeanCalibrationBias', 'MeanAbsoluteCalibrationError'};

pw_vals = {'WIS', 'Error', 'AbsoluteError', 'SquaredError', 'CoverageMean', ...
    'IntervalWidthMean'};
pw_names = {'MeanWIS', 'MeanError', 'MeanAbsoluteError', 'MeanSquaredError', ...
    'MeanCoverage', 'MeanIntervalWidth'};

iv_vals = {'Coverage', 'IntervalWidth', 'CoverageError', 'AbsoluteCoverageError', ...
    'IntervalScore', 'WISIntervalComponent'};
iv_names = {'MeanCoverage', 'MeanIntervalWidth', 'MeanCoverageError', ...
    'MeanAbsoluteCoverageError', 'MeanIntervalScore', 'MeanWISIntervalComponent'};

summaries = struct();
summaries.scenario_summary = local_group_means(window_scores, ...
    {'Scenario', 'Model', 'ExoMode'}, win_vals, win_names);
summaries.model_summary = local_group_means(window_scores, ...
    {'Model', 'ExoMode'}, win_vals, win_names);
summaries.exo_mode_summary = local_group_means(window_scores, ...
    {'ExoMode'}, win_vals, win_names);
summaries.scenario_performance_summary = local_group_means(pointwise_scores, ...
    {'Scenario'}, pw_vals, pw_names);
summaries.horizon_summary = local_group_means(pointwise_scores, ...
    {'Model', 'ExoMode', 'HorizonIdx'}, pw_vals, pw_names);
summaries.horizon_stratification_summary = local_group_means(pointwise_scores, ...
    {'HorizonIdx'}, pw_vals, pw_names);
summaries.scenario_horizon_summary = local_group_means(pointwise_scores, ...
    {'Scenario', 'Model', 'ExoMode', 'HorizonIdx'}, pw_vals, pw_names);
summaries.interval_summary = local_group_means(interval_scores, ...
    {'Model', 'ExoMode', 'Alpha', 'NominalCoverage'}, iv_vals, iv_names);
summaries.scenario_calibration_summary = local_group_means(interval_scores, ...
    {'Scenario', 'Model', 'ExoMode', 'Alpha', 'NominalCoverage'}, iv_vals, iv_names);
summaries.wis_component_summary = local_wis_component_summary(window_scores);
end

function out = local_group_means(tbl, group_vars, value_vars, mean_names)
out = groupsummary(tbl, group_vars, "mean", value_vars);
out = renamevars(out, "mean_" + string(value_vars), string(mean_names));
end

function out = local_wis_component_summary(window_scores)
out = local_group_means(window_scores, {'Model', 'ExoMode'}, ...
    {'MeanWISMedianComponent', 'MeanWISDispersionComponent', ...
    'MeanWISUnderpredictionComponent', 'MeanWISOverpredictionComponent'}, ...
    {'MeanMedianComponent', 'MeanDispersionComponent', ...
    'MeanUnderpredictionComponent', 'MeanOverpredictionComponent'});

total = out.MeanMedianComponent + out.MeanDispersionComponent ...
    + out.MeanUnderpredictionComponent + out.MeanOverpredictionComponent;

out.MedianShare = out.MeanMedianComponent ./ total;
out.DispersionShare = out.MeanDispersionComponent ./ total;
out.UnderpredictionShare = out.MeanUnderpredictionComponent ./ total;
out.OverpredictionShare = out.MeanOverpredictionComponent ./ total;
end

%% 9. Output Functions
function table_outputs = local_write_tables(table_dir, window_scores, ...
    pointwise_scores, interval_scores, summaries, selection_summary, ...
    missing_selection_artifacts, candidate_aicc_summary, cfg)

missing_tbl = table(missing_selection_artifacts, ...
    'VariableNames', {'MissingSelectionArtifact'});

spec = {
    'partA_04_window_scores.csv',                  window_scores,                           'Per-window scores (one row per forecast origin)'
    'partA_04_pointwise_scores.csv',               pointwise_scores,                        'Per-horizon scores (one row per horizon step)'
    'partA_04_interval_scores.csv',                interval_scores,                         'Per-horizon/alpha interval scores'
    'partA_04_scenario_summary.csv',               summaries.scenario_summary,              'Window scores by Scenario+Model+ExoMode'
    'partA_04_scenario_performance_summary.csv',   summaries.scenario_performance_summary,  'Pointwise scores by Scenario'
    'partA_04_horizon_summary.csv',                summaries.horizon_summary,               'Pointwise scores by Model+ExoMode+Horizon'
    'partA_04_horizon_stratification_summary.csv', summaries.horizon_stratification_summary,'Pointwise scores by Horizon'
    'partA_04_scenario_horizon_summary.csv',       summaries.scenario_horizon_summary,      'Pointwise scores by Scenario+Model+ExoMode+Horizon'
    'partA_04_model_summary.csv',                  summaries.model_summary,                 'Window scores by Model+ExoMode'
    'partA_04_exo_mode_summary.csv',               summaries.exo_mode_summary,              'Window scores by ExoMode'
    'partA_04_interval_summary.csv',               summaries.interval_summary,              'Interval scores by Model+ExoMode+Alpha'
    'partA_04_scenario_calibration_summary.csv',   summaries.scenario_calibration_summary,  'Interval scores by Scenario+Model+ExoMode+Alpha'
    'partA_04_wis_component_summary.csv',          summaries.wis_component_summary,         'WIS decomposition shares by Model+ExoMode'
    'partA_04_selection_summary.csv',              selection_summary,                       'Selected configuration per Model+ExoMode'
    'partA_04_candidate_aicc.csv',                 candidate_aicc_summary,                  'Per-candidate AICc complexity diagnostic with selection WIS'
    'partA_04_missing_selection_artifacts.csv',    missing_tbl,                             'Selection artifacts that were missing'
    'partA_04_evaluation_settings.csv',            local_settings_table(cfg),               'Forecast horizon / window / alpha settings'
    };

n = size(spec, 1);
table_outputs = strings(n + 1, 1);

for i = 1:n
    table_outputs(i) = local_write_table(table_dir, spec{i, 1}, spec{i, 2});
end

manifest = table(string(spec(:, 1)), string(spec(:, 3)), ...
    'VariableNames', {'File', 'Contents'});
table_outputs(n + 1) = local_write_table(table_dir, ...
    'partA_04_output_manifest.csv', manifest);
end

function output_path = local_write_table(table_dir, filename, table_data)
output_path = fullfile(table_dir, filename);
writetable(table_data, output_path);
fprintf('Table saved to: %s\n', output_path);
end

function settings = local_settings_table(cfg)
settings = table( ...
    cfg.forecast.horizon, cfg.forecast.min_window, cfg.forecast.step_size, ...
    string(strjoin(compose('%.4g', cfg.forecast.wis_alphas), ',')), ...
    'VariableNames', {'ForecastHorizon', 'MinWindow', 'StepSize', 'WISAlphas'});
end

function cfg_snapshot = local_cfg_snapshot(cfg)
cfg_snapshot = struct();
cfg_snapshot.forecast = cfg.forecast;
cfg_snapshot.output = cfg.output;
cfg_snapshot.intervals = cfg.intervals;
end

%% 10. Utility Functions
function files = local_sort_dir_by_name(files)
[~, order] = sort({files.name});
files = files(order);
end