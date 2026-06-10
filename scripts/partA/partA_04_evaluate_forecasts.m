%PARTA_04_EVALUATE_FORECASTS Evaluate Part A forecast artifacts and tables.
%
%   Description:
%       Loads final Part A forecast artifacts, computes probabilistic and
%       point-forecast evaluation metrics, summarizes the scores across
%       scenarios, horizons, model families, and exogenous modes, and writes
%       evaluation artifacts plus tabular outputs. Figure generation is
%       intentionally delegated to Part A 05.
%
%   Workflow:
%       1. Load forecast and model-selection artifacts.
%       2. Load canonical forecast-result structures.
%       3. Compute WIS, WIS components, RMSE, MAE, calibration, coverage,
%          and interval-width scores.
%       4. Save evaluation .mat artifacts and table files.
%
%   See also PARTA_CONFIG, EVALUATE_FORECAST_WINDOW_METRICS, ...
%            SUMMARIZE_FORECAST_SCORES, PARTA_05_GENERATE_FIGURES.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-06-10

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Forecast Evaluation ===\n');

cfg = partA_config();
forecast_dir = cfg.output.forecast_dir;
selection_dir = cfg.output.model_selection_dir;
evaluation_dir = cfg.output.score_dir;
table_dir = cfg.output.table_dir;

if ~exist(evaluation_dir, 'dir'), mkdir(evaluation_dir); end
if ~exist(table_dir, 'dir'), mkdir(table_dir); end

forecast_files = dir(fullfile(forecast_dir, 'partA_03_forecast_*.mat'));
if isempty(forecast_files)
    error('EVAL:NoForecastArtifacts', ...
        'No forecast artifacts found under %s.', forecast_dir);
end
forecast_files = local_sort_dir_by_name(forecast_files);

fprintf('Found %d forecast artifacts in %s\n', numel(forecast_files), forecast_dir);

%% 2. Selection Artifact Summary
[selection_summary, missing_selection_artifacts] = ...
    local_load_selection_summary(selection_dir);
candidate_aicc_summary = local_load_candidate_aicc_summary(selection_dir);

%% 3. Forecast Evaluation
window_blocks = cell(numel(forecast_files), 1);
pointwise_blocks = cell(numel(forecast_files), 1);
interval_blocks = cell(numel(forecast_files), 1);
source_forecast_artifacts = strings(numel(forecast_files), 1);
skipped_forecast_artifacts = strings(0, 1);

for i = 1:numel(forecast_files)
    artifact_path = fullfile(forecast_files(i).folder, forecast_files(i).name);
    source_forecast_artifacts(i) = string(artifact_path);
    loaded = load(artifact_path);

    [scenario_id, scenario_name, model_type, exo_mode] = local_artifact_identity(loaded);
    [forecast_results, result_source] = local_get_forecast_results(loaded);

    if isempty(forecast_results)
        skipped_forecast_artifacts(end + 1, 1) = string(artifact_path); %#ok<SAGROW>
        warning('EVAL:EmptyForecastArtifact', ...
            'Skipping artifact with no forecast results: %s', artifact_path);
        continue;
    end

    window_rows = cell(numel(forecast_results), 1);
    pointwise_rows = cell(numel(forecast_results), 1);
    interval_rows = cell(numel(forecast_results), 1);

    for k = 1:numel(forecast_results)
        window_entry = local_normalize_forecast_window(forecast_results(k));
        [window_rows{k}, pointwise_rows{k}, interval_rows{k}] = ...
            local_evaluate_window(window_entry, scenario_id, scenario_name, ...
            model_type, exo_mode, artifact_path, result_source);
    end

    window_rows = window_rows(~cellfun('isempty', window_rows));
    pointwise_rows = pointwise_rows(~cellfun('isempty', pointwise_rows));
    interval_rows = interval_rows(~cellfun('isempty', interval_rows));

    if ~isempty(window_rows)
        window_blocks{i} = vertcat(window_rows{:});
    end
    if ~isempty(pointwise_rows)
        pointwise_blocks{i} = vertcat(pointwise_rows{:});
    end
    if ~isempty(interval_rows)
        interval_blocks{i} = vertcat(interval_rows{:});
    end
end

window_scores = local_vertcat_or_empty(window_blocks, local_empty_window_scores());
pointwise_scores = local_vertcat_or_empty(pointwise_blocks, local_empty_pointwise_scores());
interval_scores = local_vertcat_or_empty(interval_blocks, local_empty_interval_scores());

if isempty(window_scores) || height(window_scores) == 0
    error('EVAL:NoUsableForecastArtifacts', ...
        'No usable forecast windows were found under %s.', forecast_dir);
end

summaries = summarize_forecast_scores(window_scores, pointwise_scores, interval_scores);

fprintf('Evaluated %d forecast windows and %d pointwise horizon rows.\n', ...
    height(window_scores), height(pointwise_scores));

%% 4. Save Evaluation Artifact
cfg_snapshot = local_cfg_snapshot(cfg);
evaluation_artifact = fullfile(evaluation_dir, 'partA_04_evaluation_results.mat');

save(evaluation_artifact, ...
    'window_scores', 'pointwise_scores', 'interval_scores', 'summaries', ...
    'selection_summary', 'missing_selection_artifacts', ...
    'source_forecast_artifacts', 'skipped_forecast_artifacts', 'cfg_snapshot');

fprintf('Evaluation artifact saved to: %s\n', evaluation_artifact);

%% 5. Save Tables
table_outputs = local_write_tables(table_dir, window_scores, pointwise_scores, ...
    interval_scores, summaries, selection_summary, missing_selection_artifacts, ...
    candidate_aicc_summary, cfg);

fprintf('Saved %d table files under %s\n', numel(table_outputs), table_dir);
fprintf('=== Part A Forecast Evaluation Complete ===\n\n');

%% 6. Local Functions - Artifact Loading and Identity
function [selection_summary, missing_selection_artifacts] = local_load_selection_summary(selection_dir)
%LOCAL_LOAD_SELECTION_SUMMARY Load selected model-configuration artifacts.
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
    [model_type, exo_mode] = local_parse_selection_filename(selection_files(i).name);

    if isfield(loaded, 'model_type') && ~isempty(loaded.model_type)
        model_type = string(loaded.model_type);
    end
    if isfield(loaded, 'exo_mode') && ~isempty(loaded.exo_mode)
        exo_mode = string(loaded.exo_mode);
    end

    selected_configuration = local_selected_configuration_text(loaded);
    selected_index = local_numeric_field(loaded, 'selected_index');
    best_global_wis = local_numeric_field(loaded, 'best_global_wis');
    if isnan(best_global_wis) && isfield(loaded, 'global_mean_wis') && ...
            isfield(loaded, 'selected_index') && ...
            loaded.selected_index >= 1 && loaded.selected_index <= numel(loaded.global_mean_wis)
        best_global_wis = double(loaded.global_mean_wis(loaded.selected_index));
    end

    rows{i} = table(string(model_type), string(exo_mode), ...
        selected_configuration, selected_index, best_global_wis, ...
        string(artifact_path), ...
        'VariableNames', {'Model', 'ExoMode', 'SelectedConfiguration', ...
        'SelectedIndex', 'BestGlobalWIS', 'SelectionArtifact'});
end

selection_summary = vertcat(rows{:});
end

function aicc_summary = local_load_candidate_aicc_summary(selection_dir)
%LOCAL_LOAD_CANDIDATE_AICC_SUMMARY Per-candidate AICc complexity diagnostic.
%   Reads candidate_diagnostics from the Part A 02 selection artifacts and pairs
%   each candidate order's diagnostic AICc with its selection WIS. AICc is
%   diagnostic only; the Selected flag reflects the WIS-based choice.
selection_files = dir(fullfile(selection_dir, 'partA_02_global_hyperparameters_*.mat'));
selection_files = local_sort_dir_by_name(selection_files);
aicc_summary = local_empty_candidate_aicc_summary();
if isempty(selection_files)
    return;
end

blocks = cell(numel(selection_files), 1);
for i = 1:numel(selection_files)
    loaded = load(fullfile(selection_files(i).folder, selection_files(i).name));
    if ~isfield(loaded, 'candidate_diagnostics') || ~isfield(loaded, 'candidate_grid') ...
            || isempty(loaded.candidate_grid)
        continue;
    end

    grid = double(loaded.candidate_grid);
    n = size(grid, 1);
    global_aicc = local_column_or_nan(loaded.candidate_diagnostics, 'global_mean_aicc', n);
    global_wis = local_column_or_nan(loaded, 'global_mean_wis', n);

    selected = false(n, 1);
    selected_index = local_numeric_field(loaded, 'selected_index');
    if ~isnan(selected_index) && selected_index >= 1 && selected_index <= n
        selected(round(selected_index)) = true;
    end

    [model_type, exo_mode] = local_parse_selection_filename(selection_files(i).name);
    if isfield(loaded, 'model_type') && ~isempty(loaded.model_type)
        model_type = string(loaded.model_type);
    end
    if isfield(loaded, 'exo_mode') && ~isempty(loaded.exo_mode)
        exo_mode = string(loaded.exo_mode);
    end

    candidate_text = strings(n, 1);
    for r = 1:n
        candidate_text(r) = string(mat2str(grid(r, :)));
    end

    blocks{i} = table(repmat(string(model_type), n, 1), ...
        repmat(string(exo_mode), n, 1), candidate_text, ...
        global_wis(:), global_aicc(:), selected, ...
        'VariableNames', {'Model', 'ExoMode', 'Candidate', ...
        'GlobalMeanWIS', 'GlobalMeanAICc', 'Selected'});
end

blocks = blocks(~cellfun('isempty', blocks));
if ~isempty(blocks)
    aicc_summary = vertcat(blocks{:});
end
end

function col = local_column_or_nan(s, field_name, n)
%LOCAL_COLUMN_OR_NAN Read an n-length numeric field or return NaNs.
col = nan(n, 1);
if isfield(s, field_name) && ~isempty(s.(field_name))
    raw = double(s.(field_name)(:));
    if numel(raw) == n
        col = raw;
    end
end
end

function [forecast_results, result_source] = local_get_forecast_results(loaded)
%LOCAL_GET_FORECAST_RESULTS Load canonical forecast results.
forecast_results = [];
result_source = "";

if isfield(loaded, 'forecast_results') && ~isempty(loaded.forecast_results)
    forecast_results = loaded.forecast_results;
    result_source = "forecast_results";
end
end

function [scenario_id, scenario_name, model_type, exo_mode] = local_artifact_identity(loaded)
%LOCAL_ARTIFACT_IDENTITY Read scenario/model metadata stored by partA_03.
scenario_id   = string(loaded.scenario_id);
scenario_name = string(loaded.scenario_name);
model_type    = string(loaded.model_type);
exo_mode      = string(loaded.exo_mode);
end

function [model_type, exo_mode] = local_parse_selection_filename(filename)
%LOCAL_PARSE_SELECTION_FILENAME Parse Part A 02 selection artifact names.
[~, name_body] = fileparts(filename);
prefix = "partA_02_global_hyperparameters_";
suffix = erase(string(name_body), prefix);
tokens = split(suffix, "_");
model_type = tokens(1);
if numel(tokens) >= 2
    exo_mode = tokens(2);
else
    exo_mode = "";
end
end

function value = local_selected_configuration_text(s)
%LOCAL_SELECTED_CONFIGURATION_TEXT Format selected configuration for tables.
if isfield(s, 'selected_configuration') && ~isempty(s.selected_configuration)
    value = string(mat2str(double(s.selected_configuration)));
else
    value = "";
end
end

function window_entry = local_normalize_forecast_window(raw_entry)
%LOCAL_NORMALIZE_FORECAST_WINDOW Normalize canonical forecast fields.
window_entry = struct();
window_entry.result_source = "forecast_results";
window_entry.truth_Rt = local_get_numeric_vector(raw_entry, 'Rt_true_future');
window_entry.pred_Rt = local_get_numeric_vector(raw_entry, 'Rt_pred');
window_entry.lower_Rt = local_get_numeric_matrix(raw_entry, 'lower_bounds');
window_entry.upper_Rt = local_get_numeric_matrix(raw_entry, 'upper_bounds');
window_entry.alphas = local_get_numeric_vector(raw_entry, 'interval_alphas');
window_entry.window_day = local_get_numeric_scalar(raw_entry, 'forecast_origin');
window_entry.window_day_idx = local_get_numeric_scalar(raw_entry, 'window_day_idx');
window_entry.forecast_day = local_get_numeric_vector(raw_entry, 't_future');
window_entry.horizon_indices = local_get_numeric_vector(raw_entry, 'horizon_indices');
window_entry.aicc = local_get_numeric_scalar(raw_entry, 'aicc');
window_entry.interval_method = local_get_string_field(raw_entry, 'interval_method', "");
window_entry.interval_status = local_get_string_field(raw_entry, 'interval_status', "");
window_entry.recorded_status = local_get_string_field(raw_entry, 'status', "");
end

%% 7. Local Functions - Per-Window Evaluation
function [window_row, pointwise_rows, interval_rows] = local_evaluate_window( ...
    window_entry, scenario_id, scenario_name, model_type, exo_mode, ...
    artifact_path, result_source)
%LOCAL_EVALUATE_WINDOW Compute all score rows for one forecast window.
truth_Rt = double(window_entry.truth_Rt(:));
pred_Rt = double(window_entry.pred_Rt(:));
lower_Rt = double(window_entry.lower_Rt);
upper_Rt = double(window_entry.upper_Rt);
alphas = reshape(double(window_entry.alphas), 1, []);

horizon = numel(truth_Rt);
metrics = evaluate_forecast_window_metrics(truth_Rt, pred_Rt, ...
    lower_Rt, upper_Rt, alphas);

window_row = table( ...
    string(scenario_id), string(scenario_name), string(model_type), ...
    string(exo_mode), string(artifact_path), string(result_source), ...
    window_entry.window_day, window_entry.window_day_idx, metrics.window_wis, ...
    metrics.window_rmse, metrics.window_mae, ...
    metrics.mean_wis_median_component, ...
    metrics.mean_wis_dispersion_component, metrics.mean_wis_under_component, ...
    metrics.mean_wis_over_component, metrics.mean_coverage, ...
    metrics.mean_calibration_bias, metrics.mean_absolute_calibration_error, ...
    metrics.mean_interval_width, metrics.is_valid, ...
    string(window_entry.interval_method), string(window_entry.interval_status), ...
    string(window_entry.recorded_status), window_entry.aicc, ...
    'VariableNames', {'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
    'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDayIdx', ...
    'WindowWIS', 'WindowRMSE', 'WindowMAE', ...
    'MeanWISMedianComponent', 'MeanWISDispersionComponent', ...
    'MeanWISUnderpredictionComponent', 'MeanWISOverpredictionComponent', ...
    'MeanCoverage', 'MeanCalibrationBias', ...
    'MeanAbsoluteCalibrationError', 'MeanIntervalWidth', 'IsValid', ...
    'IntervalMethod', 'IntervalStatus', 'RecordedStatus', 'AICC'});

if horizon == 0
    pointwise_rows = local_empty_pointwise_scores();
    interval_rows = local_empty_interval_scores();
    return;
end

forecast_day = local_forecast_day(window_entry, horizon);
horizon_idx = (1:horizon)';
error_values = pred_Rt - truth_Rt;

pointwise_rows = table( ...
    repmat(string(scenario_id), horizon, 1), ...
    repmat(string(scenario_name), horizon, 1), ...
    repmat(string(model_type), horizon, 1), ...
    repmat(string(exo_mode), horizon, 1), ...
    repmat(string(artifact_path), horizon, 1), ...
    repmat(string(result_source), horizon, 1), ...
    repmat(window_entry.window_day, horizon, 1), ...
    repmat(window_entry.window_day_idx, horizon, 1), ...
    horizon_idx, forecast_day, truth_Rt, pred_Rt, error_values, ...
    error_values .^ 2, abs(error_values), metrics.pointwise_wis, ...
    metrics.wis_components.median, metrics.wis_components.dispersion, ...
    metrics.wis_components.underprediction, ...
    metrics.wis_components.overprediction, metrics.coverage_mean, ...
    metrics.calibration_bias_mean, metrics.absolute_calibration_mean, ...
    metrics.width_mean, ...
    repmat(string(window_entry.interval_method), horizon, 1), ...
    repmat(string(window_entry.interval_status), horizon, 1), ...
    'VariableNames', {'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
    'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDayIdx', ...
    'HorizonIdx', 'ForecastDay', 'Truth_Rt', 'Median_Forecast', ...
    'Error', 'SquaredError', 'AbsoluteError', 'WIS', ...
    'WISMedianComponent', 'WISDispersionComponent', ...
    'WISUnderpredictionComponent', 'WISOverpredictionComponent', ...
    'CoverageMean', 'CalibrationBiasMean', ...
    'AbsoluteCalibrationErrorMean', 'IntervalWidthMean', ...
    'IntervalMethod', 'IntervalStatus'});

interval_rows = local_interval_rows(window_entry, scenario_id, scenario_name, ...
    model_type, exo_mode, artifact_path, result_source, horizon_idx, ...
    forecast_day, truth_Rt, alphas, lower_Rt, upper_Rt, metrics.coverage, ...
    metrics.interval_width, metrics.wis_components);
end

function interval_rows = local_interval_rows(window_entry, scenario_id, scenario_name, ...
    model_type, exo_mode, artifact_path, result_source, horizon_idx, ...
    forecast_day, truth_Rt, alphas, lower_Rt, upper_Rt, coverage, ...
    interval_width, wis_components)
%LOCAL_INTERVAL_ROWS Build long-format interval score rows.
horizon = numel(horizon_idx);
num_alphas = numel(alphas);
if horizon == 0 || num_alphas == 0
    interval_rows = local_empty_interval_scores();
    return;
end

num_rows = horizon * num_alphas;
interval_rows = table( ...
    strings(num_rows, 1), strings(num_rows, 1), strings(num_rows, 1), ...
    strings(num_rows, 1), strings(num_rows, 1), strings(num_rows, 1), ...
    zeros(num_rows, 1), zeros(num_rows, 1), zeros(num_rows, 1), ...
    zeros(num_rows, 1), zeros(num_rows, 1), zeros(num_rows, 1), ...
    zeros(num_rows, 1), zeros(num_rows, 1), zeros(num_rows, 1), ...
    zeros(num_rows, 1), strings(num_rows, 1), strings(num_rows, 1), ...
    'VariableNames', {'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
    'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDayIdx', ...
    'HorizonIdx', 'ForecastDay', 'Truth_Rt', 'Alpha', 'NominalCoverage', ...
    'LowerBound', 'UpperBound', 'Coverage', 'IntervalMethod', 'IntervalStatus'});
interval_rows.IntervalWidth = zeros(num_rows, 1);
interval_rows.CoverageError = zeros(num_rows, 1);
interval_rows.AbsoluteCoverageError = zeros(num_rows, 1);
interval_rows.IntervalScore = zeros(num_rows, 1);
interval_rows.WISIntervalComponent = zeros(num_rows, 1);
interval_rows.WISSharpnessComponent = zeros(num_rows, 1);
interval_rows.WISUnderpredictionComponent = zeros(num_rows, 1);
interval_rows.WISOverpredictionComponent = zeros(num_rows, 1);

row_idx = 0;
for j = 1:num_alphas
    idx = row_idx + (1:horizon);
    coverage_error = coverage(:, j) - (1 - alphas(j));
    interval_rows.Scenario(idx) = string(scenario_id);
    interval_rows.ScenarioName(idx) = string(scenario_name);
    interval_rows.Model(idx) = string(model_type);
    interval_rows.ExoMode(idx) = string(exo_mode);
    interval_rows.ForecastArtifact(idx) = string(artifact_path);
    interval_rows.ResultSource(idx) = string(result_source);
    interval_rows.WindowDay(idx) = window_entry.window_day;
    interval_rows.WindowDayIdx(idx) = window_entry.window_day_idx;
    interval_rows.HorizonIdx(idx) = horizon_idx;
    interval_rows.ForecastDay(idx) = forecast_day;
    interval_rows.Truth_Rt(idx) = truth_Rt;
    interval_rows.Alpha(idx) = alphas(j);
    interval_rows.NominalCoverage(idx) = 1 - alphas(j);
    interval_rows.LowerBound(idx) = lower_Rt(:, j);
    interval_rows.UpperBound(idx) = upper_Rt(:, j);
    interval_rows.Coverage(idx) = coverage(:, j);
    interval_rows.IntervalWidth(idx) = interval_width(:, j);
    interval_rows.CoverageError(idx) = coverage_error;
    interval_rows.AbsoluteCoverageError(idx) = abs(coverage_error);
    interval_rows.IntervalScore(idx) = wis_components.interval_score(:, j);
    interval_rows.WISIntervalComponent(idx) = ...
        wis_components.interval_component(:, j);
    interval_rows.WISSharpnessComponent(idx) = ...
        wis_components.sharpness_by_interval(:, j);
    interval_rows.WISUnderpredictionComponent(idx) = ...
        wis_components.underprediction_by_interval(:, j);
    interval_rows.WISOverpredictionComponent(idx) = ...
        wis_components.overprediction_by_interval(:, j);
    interval_rows.IntervalMethod(idx) = string(window_entry.interval_method);
    interval_rows.IntervalStatus(idx) = string(window_entry.interval_status);
    row_idx = row_idx + horizon;
end
end

function forecast_day = local_forecast_day(window_entry, horizon)
%LOCAL_FORECAST_DAY Return future time values or horizon indices.
forecast_day = double(window_entry.forecast_day(:));
if numel(forecast_day) ~= horizon
    forecast_day = (1:horizon)';
end
end

%% 8. Local Functions - Empty Table Schemas
function table_data = local_empty_window_scores()
%LOCAL_EMPTY_WINDOW_SCORES Create an empty per-window table.
table_data = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
    'VariableNames', {'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
    'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDayIdx', ...
    'WindowWIS', 'WindowRMSE', 'WindowMAE', ...
    'MeanWISMedianComponent', 'MeanWISDispersionComponent', ...
    'MeanWISUnderpredictionComponent', 'MeanWISOverpredictionComponent', ...
    'MeanCoverage', 'MeanCalibrationBias', ...
    'MeanAbsoluteCalibrationError', 'MeanIntervalWidth', 'IsValid', ...
    'IntervalMethod', 'IntervalStatus', 'RecordedStatus', 'AICC'});
end

function table_data = local_empty_pointwise_scores()
%LOCAL_EMPTY_POINTWISE_SCORES Create an empty pointwise score table.
table_data = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    'VariableNames', {'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
    'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDayIdx', ...
    'HorizonIdx', 'ForecastDay', 'Truth_Rt', 'Median_Forecast', ...
    'Error', 'SquaredError', 'AbsoluteError', 'WIS', ...
    'WISMedianComponent', 'WISDispersionComponent', ...
    'WISUnderpredictionComponent', 'WISOverpredictionComponent', ...
    'CoverageMean', 'CalibrationBiasMean', ...
    'AbsoluteCalibrationErrorMean', 'IntervalWidthMean', ...
    'IntervalMethod', 'IntervalStatus'});
end

function table_data = local_empty_interval_scores()
%LOCAL_EMPTY_INTERVAL_SCORES Create an empty long-format interval table.
table_data = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    'VariableNames', {'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
    'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDayIdx', ...
    'HorizonIdx', 'ForecastDay', 'Truth_Rt', 'Alpha', 'NominalCoverage', ...
    'LowerBound', 'UpperBound', 'Coverage', 'IntervalMethod', ...
    'IntervalStatus', 'IntervalWidth', 'CoverageError', ...
    'AbsoluteCoverageError', 'IntervalScore', 'WISIntervalComponent', ...
    'WISSharpnessComponent', 'WISUnderpredictionComponent', ...
    'WISOverpredictionComponent'});
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

%% 9. Local Functions - Output: Tables and Snapshot
function table_data = local_vertcat_or_empty(blocks, empty_table)
%LOCAL_VERTCAT_OR_EMPTY Vertically concatenate nonempty table blocks.
blocks = blocks(~cellfun('isempty', blocks));
if isempty(blocks)
    table_data = empty_table;
else
    table_data = vertcat(blocks{:});
end
end

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

%% 10. Local Functions - Field and Value Readers
function value = local_get_numeric_scalar(s, field_name)
%LOCAL_GET_NUMERIC_SCALAR Read a numeric scalar field or NaN.
value = nan;
if isfield(s, field_name) && ~isempty(s.(field_name))
    raw = double(s.(field_name));
    if isscalar(raw)
        value = raw;
    end
end
end

function value = local_get_numeric_vector(s, field_name)
%LOCAL_GET_NUMERIC_VECTOR Read a numeric vector field or [].
value = [];
if isfield(s, field_name) && ~isempty(s.(field_name))
    value = double(s.(field_name)(:));
end
end

function value = local_get_numeric_matrix(s, field_name)
%LOCAL_GET_NUMERIC_MATRIX Read a numeric matrix field or [].
value = [];
if isfield(s, field_name) && ~isempty(s.(field_name))
    value = double(s.(field_name));
end
end

function value = local_get_string_field(s, field_name, default_value)
%LOCAL_GET_STRING_FIELD Read a string-compatible field with fallback.
value = string(default_value);
if isfield(s, field_name) && ~isempty(s.(field_name))
    value = string(s.(field_name));
end
end

function value = local_numeric_field(s, field_name)
%LOCAL_NUMERIC_FIELD Read a scalar numeric variable from a loaded artifact.
value = nan;
if isfield(s, field_name) && ~isempty(s.(field_name)) && isnumeric(s.(field_name))
    raw = double(s.(field_name));
    if isscalar(raw)
        value = raw;
    end
end
end

%% 11. Local Functions - Utilities
function files = local_sort_dir_by_name(files)
%LOCAL_SORT_DIR_BY_NAME Sort a dir struct by name.
[~, order] = sort({files.name});
files = files(order);
end
