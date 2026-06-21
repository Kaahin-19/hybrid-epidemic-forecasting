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
%       1. Section A: load selection artifacts; build selection and candidate
%          AICc reporting tables.
%       2. Section B: load forecast artifacts; score each window with the
%          scoring kernels and assemble window, pointwise, and interval tables.
%       3. Aggregate the forecast scores into summary tables.
%       4. Save the evaluation .mat artifact and the CSV tables.
%
%   See also PARTA_CONFIG, COMPUTE_WIS, COMPUTE_POINT_ERROR, ...
%            COMPUTE_INTERVAL_DIAGNOSTICS, PARTA_05_GENERATE_FIGURES.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-06-22

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Forecast Evaluation ===\n');

% The canonical scoring kernels live in src/scoring. startup adds the whole
% src tree with genpath, where src/evaluation/legacy sorts ahead of src/scoring
% and shadows compute_wis with an obsolete single-output copy. Prepend the
% scoring folder so this evaluation run resolves the canonical kernels; legacy
% resolution used by Part B/C in their own sessions is left untouched.
addpath(fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'src', 'scoring'));

cfg = partA_config();
forecast_dir = cfg.output.forecast_dir;
selection_dir = cfg.output.model_selection_dir;
evaluation_dir = cfg.output.score_dir;
table_dir = cfg.output.table_dir;

if ~exist(evaluation_dir, 'dir'), mkdir(evaluation_dir); end
if ~exist(table_dir, 'dir'), mkdir(table_dir); end

%% 2. Section A: Selection / Candidate Reporting (Script 2 artifacts only)
[selection_summary, missing_selection_artifacts] = ...
    local_load_selection_summary(selection_dir);
candidate_aicc_summary = local_load_candidate_aicc_summary(selection_dir);

%% 3. Section B: Forecast-Window Evaluation (Script 3 artifacts only)
forecast_files = dir(fullfile(forecast_dir, 'partA_03_forecast_*.mat'));
if isempty(forecast_files)
    error('EVAL:NoForecastArtifacts', ...
        'No forecast artifacts found under %s.', forecast_dir);
end
forecast_files = local_sort_dir_by_name(forecast_files);

fprintf('Found %d forecast artifacts in %s\n', numel(forecast_files), forecast_dir);

n_files = numel(forecast_files);
window_blocks    = cell(n_files, 1);
pointwise_blocks = cell(n_files, 1);
interval_blocks  = cell(n_files, 1);
source_forecast_artifacts = strings(n_files, 1);

for i = 1:n_files
    artifact_path = fullfile(forecast_files(i).folder, forecast_files(i).name);
    source_forecast_artifacts(i) = string(artifact_path);
    loaded = load(artifact_path);

    scenario_id   = string(loaded.scenario_id);
    scenario_name = string(loaded.scenario_name);
    model_type    = string(loaded.model_type);
    exo_mode      = string(loaded.exo_mode);

    [window_blocks{i}, pointwise_blocks{i}, interval_blocks{i}] = ...
        local_build_score_rows(loaded.forecast_results, scenario_id, ...
        scenario_name, model_type, exo_mode, artifact_path);
end

window_scores    = vertcat(window_blocks{:});
pointwise_scores = vertcat(pointwise_blocks{:});
interval_scores  = vertcat(interval_blocks{:});

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

%% 6. Local Functions - Section A: Selection / Candidate Reporting
function [selection_summary, missing_selection_artifacts] = local_load_selection_summary(selection_dir)
%LOCAL_LOAD_SELECTION_SUMMARY Report the selected configuration per Part A 02 artifact.
selection_files = dir(fullfile(selection_dir, 'partA_02_global_hyperparameters_*.mat'));
selection_files = local_sort_dir_by_name(selection_files);
missing_selection_artifacts = strings(0, 1);

if isempty(selection_files)
    selection_summary = local_empty_selection_summary();
    missing_selection_artifacts = string(selection_dir);
    warning('EVAL:NoSelectionArtifacts', ...
        'No model-selection artifacts found under %s.', selection_dir);
    return;
end

rows = cell(numel(selection_files), 1);
for i = 1:numel(selection_files)
    artifact_path = fullfile(selection_files(i).folder, selection_files(i).name);
    loaded = load(artifact_path);

    rows{i} = table(string(loaded.model_type), string(loaded.exo_mode), ...
        string(mat2str(loaded.selected_configuration)), loaded.selected_index, ...
        loaded.best_global_wis, string(artifact_path), ...
        'VariableNames', {'Model', 'ExoMode', 'SelectedConfiguration', ...
        'SelectedIndex', 'BestGlobalWIS', 'SelectionArtifact'});
end

selection_summary = vertcat(rows{:});
end

function aicc_summary = local_load_candidate_aicc_summary(selection_dir)
%LOCAL_LOAD_CANDIDATE_AICC_SUMMARY Report per-candidate AICc complexity diagnostics.
selection_files = dir(fullfile(selection_dir, 'partA_02_global_hyperparameters_*.mat'));
selection_files = local_sort_dir_by_name(selection_files);
aicc_summary = local_empty_candidate_aicc_summary();
if isempty(selection_files)
    return;
end

blocks = cell(numel(selection_files), 1);
for i = 1:numel(selection_files)
    loaded = load(fullfile(selection_files(i).folder, selection_files(i).name));

    grid = loaded.candidate_grid;
    n    = size(grid, 1);

    selected = false(n, 1);
    selected(loaded.selected_index) = true;

    candidate_text = strings(n, 1);
    for r = 1:n
        candidate_text(r) = string(mat2str(grid(r, :)));
    end

    blocks{i} = table(repmat(string(loaded.model_type), n, 1), ...
        repmat(string(loaded.exo_mode), n, 1), candidate_text, ...
        loaded.global_mean_wis(:), loaded.global_mean_aicc(:), selected, ...
        'VariableNames', {'Model', 'ExoMode', 'Candidate', ...
        'GlobalMeanWIS', 'GlobalMeanAICc', 'Selected'});
end

aicc_summary = vertcat(blocks{:});
end

function table_data = local_empty_selection_summary()
%LOCAL_EMPTY_SELECTION_SUMMARY Create an empty selection-summary table.
table_data = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    'VariableNames', {'Model', 'ExoMode', 'SelectedConfiguration', ...
    'SelectedIndex', 'BestGlobalWIS', 'SelectionArtifact'});
end

function table_data = local_empty_candidate_aicc_summary()
%LOCAL_EMPTY_CANDIDATE_AICC_SUMMARY Create an empty per-candidate AICc table.
table_data = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), false(0, 1), ...
    'VariableNames', {'Model', 'ExoMode', 'Candidate', ...
    'GlobalMeanWIS', 'GlobalMeanAICc', 'Selected'});
end

%% 7. Local Functions - Section B: Per-Window Scoring
function [window_tbl, pointwise_tbl, interval_tbl] = local_build_score_rows( ...
    forecast_results, scenario_id, scenario_name, model_type, exo_mode, artifact_path)
%LOCAL_BUILD_SCORE_ROWS Score every forecast window of one artifact with the kernels.
n_win = numel(forecast_results);
window_rows    = cell(n_win, 1);
pointwise_rows = cell(n_win, 1);
interval_rows  = cell(n_win, 1);

for w = 1:n_win
    result = forecast_results(w);

    truth_Rt = result.Rt_true_future;   % H-by-1
    pred_Rt  = result.Rt_pred;          % H-by-1
    lower_Rt = result.lower_bounds;     % H-by-K
    upper_Rt = result.upper_bounds;     % H-by-K
    alphas   = result.interval_alphas;  % K-by-1

    [wis, wis_comp] = compute_wis(truth_Rt, pred_Rt, lower_Rt, upper_Rt, alphas);
    point    = compute_point_error(truth_Rt, pred_Rt);
    interval = compute_interval_diagnostics(truth_Rt, lower_Rt, upper_Rt, alphas);

    H              = numel(truth_Rt);
    horizon_idx    = (1:H)';
    forecast_day   = result.t_future;       % documented H-by-1
    window_day     = result.forecast_origin;
    window_day_idx = result.window_day_idx;

    window_rows{w} = table( ...
        scenario_id, scenario_name, model_type, exo_mode, string(artifact_path), ...
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
        repmat(string(artifact_path), H, 1), ...
        repmat(window_day, H, 1), repmat(window_day_idx, H, 1), ...
        horizon_idx, forecast_day, truth_Rt, pred_Rt, ...
        point.error, point.squared_error, point.absolute_error, wis, ...
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
        exo_mode, artifact_path, window_day, window_day_idx, horizon_idx, ...
        forecast_day, truth_Rt, alphas, lower_Rt, upper_Rt, interval);
end

window_tbl    = vertcat(window_rows{:});
pointwise_tbl = vertcat(pointwise_rows{:});
interval_tbl  = vertcat(interval_rows{:});
end

function interval_rows = local_interval_rows(scenario_id, scenario_name, model_type, ...
    exo_mode, artifact_path, window_day, window_day_idx, horizon_idx, forecast_day, ...
    truth_Rt, alphas, lower_Rt, upper_Rt, interval)
%LOCAL_INTERVAL_ROWS Expand interval diagnostics into long (horizon x alpha) rows.
H = numel(horizon_idx);
K = numel(alphas);
N = H * K;

% Column-major stacking of the H-by-K diagnostic matrices is alpha-major:
% rows (j-1)*H + (1:H) correspond to interval level alphas(j), horizons 1..H.
interval_rows = table( ...
    repmat(scenario_id, N, 1), repmat(scenario_name, N, 1), ...
    repmat(model_type, N, 1), repmat(exo_mode, N, 1), ...
    repmat(string(artifact_path), N, 1), ...
    repmat(window_day, N, 1), repmat(window_day_idx, N, 1), ...
    repmat(horizon_idx, K, 1), repmat(forecast_day, K, 1), repmat(truth_Rt, K, 1), ...
    repelem(alphas, H, 1), repelem(interval.nominal_coverage, H, 1), ...
    lower_Rt(:), upper_Rt(:), double(interval.coverage(:)), ...
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

%% 8. Local Functions - Section B: Score Aggregation
function summaries = local_summarize_scores(window_scores, pointwise_scores, interval_scores)
%LOCAL_SUMMARIZE_SCORES Aggregate window, pointwise, and interval scores into summaries.
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

% Window-score summaries.
summaries.scenario_summary = local_group_means(window_scores, ...
    {'Scenario', 'Model', 'ExoMode'}, win_vals, win_names);
summaries.model_summary = local_group_means(window_scores, ...
    {'Model', 'ExoMode'}, win_vals, win_names);
summaries.exo_mode_summary = local_group_means(window_scores, ...
    {'ExoMode'}, win_vals, win_names);

% Pointwise-score summaries.
summaries.scenario_performance_summary = local_group_means(pointwise_scores, ...
    {'Scenario'}, pw_vals, pw_names);
summaries.horizon_summary = local_group_means(pointwise_scores, ...
    {'Model', 'ExoMode', 'HorizonIdx'}, pw_vals, pw_names);
summaries.horizon_stratification_summary = local_group_means(pointwise_scores, ...
    {'HorizonIdx'}, pw_vals, pw_names);
summaries.scenario_horizon_summary = local_group_means(pointwise_scores, ...
    {'Scenario', 'Model', 'ExoMode', 'HorizonIdx'}, pw_vals, pw_names);

% Interval-score summaries.
summaries.interval_summary = local_group_means(interval_scores, ...
    {'Model', 'ExoMode', 'Alpha', 'NominalCoverage'}, iv_vals, iv_names);
summaries.scenario_calibration_summary = local_group_means(interval_scores, ...
    {'Scenario', 'Model', 'ExoMode', 'Alpha', 'NominalCoverage'}, iv_vals, iv_names);

% WIS decomposition shares.
summaries.wis_component_summary = local_wis_component_summary(window_scores);
end

function out = local_group_means(tbl, group_vars, value_vars, mean_names)
%LOCAL_GROUP_MEANS Group-wise means of value_vars with explicit output column names.
out = groupsummary(tbl, group_vars, "mean", value_vars);
out = renamevars(out, "mean_" + string(value_vars), string(mean_names));
end

function out = local_wis_component_summary(window_scores)
%LOCAL_WIS_COMPONENT_SUMMARY Mean WIS components and their decomposition shares.
out = local_group_means(window_scores, {'Model', 'ExoMode'}, ...
    {'MeanWISMedianComponent', 'MeanWISDispersionComponent', ...
    'MeanWISUnderpredictionComponent', 'MeanWISOverpredictionComponent'}, ...
    {'MeanMedianComponent', 'MeanDispersionComponent', ...
    'MeanUnderpredictionComponent', 'MeanOverpredictionComponent'});

total = out.MeanMedianComponent + out.MeanDispersionComponent ...
    + out.MeanUnderpredictionComponent + out.MeanOverpredictionComponent;

out.MedianShare          = out.MeanMedianComponent ./ total;
out.DispersionShare      = out.MeanDispersionComponent ./ total;
out.UnderpredictionShare = out.MeanUnderpredictionComponent ./ total;
out.OverpredictionShare  = out.MeanOverpredictionComponent ./ total;
end

%% 9. Local Functions - Output: Tables and Snapshot
function table_outputs = local_write_tables(table_dir, window_scores, ...
    pointwise_scores, interval_scores, summaries, selection_summary, ...
    missing_selection_artifacts, candidate_aicc_summary, cfg)
%LOCAL_WRITE_TABLES Persist Part A 04 CSV tables and a self-describing manifest.
missing_tbl = table(missing_selection_artifacts, ...
    'VariableNames', {'MissingSelectionArtifact'});

% {filename, table, contents}
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
    'partA_04_candidate_aicc.csv',                 candidate_aicc_summary,                  'Per-candidate AICc complexity diagnostic with selection WIS (AICc is not a selector)'
    'partA_04_missing_selection_artifacts.csv',    missing_tbl,                             'Selection artifacts that were missing'
    'partA_04_evaluation_settings.csv',            local_settings_table(cfg),               'Forecast horizon / window / alpha settings'
    };

n = size(spec, 1);
table_outputs = strings(n, 1);
for i = 1:n
    table_outputs(i) = local_write_table(table_dir, spec{i, 1}, spec{i, 2});
end

manifest = table(string(spec(:, 1)), string(spec(:, 3)), ...
    'VariableNames', {'File', 'Contents'});
local_write_table(table_dir, 'partA_04_output_manifest.csv', manifest);
end

function output_path = local_write_table(table_dir, filename, table_data)
%LOCAL_WRITE_TABLE Write one CSV table.
output_path = fullfile(table_dir, filename);
writetable(table_data, output_path);
fprintf('Table saved to: %s\n', output_path);
end

function settings = local_settings_table(cfg)
%LOCAL_SETTINGS_TABLE Create evaluation settings table.
settings = table( ...
    cfg.forecast.horizon, cfg.forecast.min_window, cfg.forecast.step_size, ...
    string(strjoin(compose('%.4g', double(cfg.forecast.wis_alphas)), ',')), ...
    'VariableNames', {'ForecastHorizon', 'MinWindow', 'StepSize', 'WISAlphas'});
end

function cfg_snapshot = local_cfg_snapshot(cfg)
%LOCAL_CFG_SNAPSHOT Store relevant evaluation configuration.
cfg_snapshot = struct();
cfg_snapshot.forecast = cfg.forecast;
cfg_snapshot.output = cfg.output;
cfg_snapshot.intervals = cfg.intervals;
end

%% 10. Local Functions - Utilities
function files = local_sort_dir_by_name(files)
%LOCAL_SORT_DIR_BY_NAME Sort a dir struct by name.
[~, order] = sort({files.name});
files = files(order);
end
