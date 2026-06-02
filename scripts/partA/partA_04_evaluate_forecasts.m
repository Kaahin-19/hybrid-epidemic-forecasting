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
%   See also PARTA_CONFIG, COMPUTE_WIS, SUMMARIZE_FORECAST_SCORES, ...
%            PARTA_05_GENERATE_FIGURES.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-06-02

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

    [scenario_id, scenario_name, model_type, exo_mode] = ...
        local_resolve_artifact_identity(loaded, forecast_files(i).name, cfg);
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
    interval_scores, summaries, selection_summary, missing_selection_artifacts, cfg);

fprintf('Saved %d table files under %s\n', numel(table_outputs), table_dir);
fprintf('=== Part A Forecast Evaluation Complete ===\n\n');

%% 6. Local Functions
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

function [forecast_results, result_source] = local_get_forecast_results(loaded)
%LOCAL_GET_FORECAST_RESULTS Load canonical forecast results.
    forecast_results = [];
    result_source = "";

    if isfield(loaded, 'forecast_results') && ~isempty(loaded.forecast_results)
        forecast_results = loaded.forecast_results;
        result_source = "forecast_results";
    end
end

function [scenario_id, scenario_name, model_type, exo_mode] = ...
    local_resolve_artifact_identity(loaded, filename, cfg)
%LOCAL_RESOLVE_ARTIFACT_IDENTITY Resolve scenario/model metadata.
    [scenario_id, model_type, exo_mode] = local_parse_forecast_filename(filename);

    if isfield(loaded, 'scenario_id') && ~isempty(loaded.scenario_id)
        scenario_id = string(loaded.scenario_id);
    end
    if isfield(loaded, 'model_type') && ~isempty(loaded.model_type)
        model_type = string(loaded.model_type);
    end
    if isfield(loaded, 'exo_mode') && ~isempty(loaded.exo_mode)
        exo_mode = string(loaded.exo_mode);
    end
    if isfield(loaded, 'scenario_name') && ~isempty(loaded.scenario_name)
        scenario_name = string(loaded.scenario_name);
    else
        scenario_name = local_scenario_name_from_config(cfg, scenario_id);
    end
end

function [scenario_id, model_type, exo_mode] = local_parse_forecast_filename(filename)
%LOCAL_PARSE_FORECAST_FILENAME Parse Part A 03 forecast artifact names.
    [~, name_body] = fileparts(filename);
    tokens = split(string(name_body), "_");
    if numel(tokens) < 6
        error('EVAL:InvalidForecastFilename', ...
            'Forecast artifact name does not match expected pattern: %s.', filename);
    end
    scenario_id = tokens(4);
    model_type = tokens(5);
    exo_mode = tokens(6);
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

function scenario_name = local_scenario_name_from_config(cfg, scenario_id)
%LOCAL_SCENARIO_NAME_FROM_CONFIG Read scenario display name from config.
    scenario_name = string(scenario_id);
    if ~isfield(cfg, 'scenarios')
        return;
    end
    for i = 1:numel(cfg.scenarios)
        if strcmp(string(cfg.scenarios(i).id), string(scenario_id))
            scenario_name = string(cfg.scenarios(i).name);
            return;
        end
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

function [window_row, pointwise_rows, interval_rows] = local_evaluate_window( ...
    window_entry, scenario_id, scenario_name, model_type, exo_mode, ...
    artifact_path, result_source)
%LOCAL_EVALUATE_WINDOW Compute all score rows for one forecast window.
    truth_Rt = double(window_entry.truth_Rt(:));
    pred_Rt = double(window_entry.pred_Rt(:));
    lower_Rt = double(window_entry.lower_Rt);
    upper_Rt = double(window_entry.upper_Rt);
    alphas = reshape(double(window_entry.alphas), 1, []);

    is_valid = local_is_valid_forecast(truth_Rt, pred_Rt, lower_Rt, upper_Rt, alphas);
    horizon = numel(truth_Rt);

    if is_valid
        wis_components = compute_wis_components(truth_Rt, pred_Rt, ...
            lower_Rt, upper_Rt, alphas);
        pointwise_wis = wis_components.raw_scale_wis;
        window_rmse = compute_rmse(truth_Rt, pred_Rt);
        window_mae = compute_mae(truth_Rt, pred_Rt);
        coverage = compute_coverage(truth_Rt, lower_Rt, upper_Rt);
        interval_width = compute_interval_width(lower_Rt, upper_Rt);
        nominal_coverage = local_nominal_coverage_matrix(horizon, alphas);
        calibration_error = coverage - nominal_coverage;
        window_wis = mean(pointwise_wis);
        mean_wis_median_component = local_mean_finite(wis_components.median);
        mean_wis_dispersion_component = local_mean_finite(wis_components.dispersion);
        mean_wis_under_component = local_mean_finite(wis_components.underprediction);
        mean_wis_over_component = local_mean_finite(wis_components.overprediction);
        mean_coverage = local_mean_finite(coverage(:));
        mean_calibration_bias = local_mean_finite(calibration_error(:));
        mean_absolute_calibration_error = local_mean_finite(abs(calibration_error(:)));
        mean_interval_width = local_mean_finite(interval_width(:));
    else
        pointwise_wis = inf(max(horizon, 0), 1);
        wis_components = local_nan_wis_components(max(horizon, 0), numel(alphas));
        window_rmse = inf;
        window_mae = inf;
        coverage = nan(max(horizon, 0), numel(alphas));
        interval_width = nan(max(horizon, 0), numel(alphas));
        calibration_error = nan(max(horizon, 0), numel(alphas));
        window_wis = inf;
        mean_wis_median_component = nan;
        mean_wis_dispersion_component = nan;
        mean_wis_under_component = nan;
        mean_wis_over_component = nan;
        mean_coverage = nan;
        mean_calibration_bias = nan;
        mean_absolute_calibration_error = nan;
        mean_interval_width = nan;
    end

    window_row = table( ...
        string(scenario_id), string(scenario_name), string(model_type), ...
        string(exo_mode), string(artifact_path), string(result_source), ...
        window_entry.window_day, window_entry.window_day_idx, window_wis, ...
        window_wis, window_rmse, window_mae, mean_wis_median_component, ...
        mean_wis_dispersion_component, mean_wis_under_component, ...
        mean_wis_over_component, mean_coverage, mean_calibration_bias, ...
        mean_absolute_calibration_error, mean_interval_width, is_valid, ...
        string(window_entry.interval_method), string(window_entry.interval_status), ...
        string(window_entry.recorded_status), window_entry.aicc, ...
        'VariableNames', {'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
        'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDayIdx', ...
        'WindowWIS', 'WindowRawScaleWIS', 'WindowRMSE', 'WindowMAE', ...
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

    coverage_mean = local_row_mean_finite(coverage);
    calibration_bias_mean = local_row_mean_finite(calibration_error);
    absolute_calibration_mean = local_row_mean_finite(abs(calibration_error));
    width_mean = local_row_mean_finite(interval_width);

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
        error_values .^ 2, abs(error_values), pointwise_wis, ...
        pointwise_wis, wis_components.median, wis_components.dispersion, ...
        wis_components.underprediction, wis_components.overprediction, ...
        coverage_mean, calibration_bias_mean, absolute_calibration_mean, ...
        width_mean, ...
        repmat(string(window_entry.interval_method), horizon, 1), ...
        repmat(string(window_entry.interval_status), horizon, 1), ...
        'VariableNames', {'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
        'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDayIdx', ...
        'HorizonIdx', 'ForecastDay', 'Truth_Rt', 'Median_Forecast', ...
        'Error', 'SquaredError', 'AbsoluteError', 'WIS', 'RawScaleWIS', ...
        'WISMedianComponent', 'WISDispersionComponent', ...
        'WISUnderpredictionComponent', 'WISOverpredictionComponent', ...
        'CoverageMean', 'CalibrationBiasMean', ...
        'AbsoluteCalibrationErrorMean', 'IntervalWidthMean', ...
        'IntervalMethod', 'IntervalStatus'});

    interval_rows = local_interval_rows(window_entry, scenario_id, scenario_name, ...
        model_type, exo_mode, artifact_path, result_source, horizon_idx, ...
        forecast_day, truth_Rt, alphas, lower_Rt, upper_Rt, coverage, ...
        interval_width, wis_components);
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

function is_valid = local_is_valid_forecast(truth_Rt, pred_Rt, lower_Rt, upper_Rt, alphas)
%LOCAL_IS_VALID_FORECAST Verify forecast metric input shape and values.
    is_valid = ...
        ~isempty(truth_Rt) && ~isempty(alphas) && ...
        numel(pred_Rt) == numel(truth_Rt) && ...
        size(lower_Rt, 1) == numel(truth_Rt) && ...
        size(upper_Rt, 1) == numel(truth_Rt) && ...
        size(lower_Rt, 2) == numel(alphas) && ...
        size(upper_Rt, 2) == numel(alphas) && ...
        all(isfinite(truth_Rt(:))) && all(isfinite(pred_Rt(:))) && ...
        all(pred_Rt(:) > 0) && all(isfinite(lower_Rt(:))) && ...
        all(isfinite(upper_Rt(:))) && all(lower_Rt(:) > 0) && ...
        all(upper_Rt(:) > 0) && all(lower_Rt(:) <= upper_Rt(:));
end

function forecast_day = local_forecast_day(window_entry, horizon)
%LOCAL_FORECAST_DAY Return future time values or horizon indices.
    forecast_day = double(window_entry.forecast_day(:));
    if numel(forecast_day) ~= horizon
        forecast_day = (1:horizon)';
    end
end

function table_outputs = local_write_tables(table_dir, window_scores, ...
    pointwise_scores, interval_scores, summaries, selection_summary, ...
    missing_selection_artifacts, cfg)
%LOCAL_WRITE_TABLES Persist Part A 04 CSV tables under table_dir.
    table_outputs = strings(0, 1);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_window_scores.csv', window_scores);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_pointwise_scores.csv', pointwise_scores);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_interval_scores.csv', interval_scores);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_scenario_summary.csv', summaries.scenario_summary);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_scenario_performance_summary.csv', ...
        summaries.scenario_performance_summary);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_horizon_summary.csv', summaries.horizon_summary);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_horizon_stratification_summary.csv', ...
        summaries.horizon_stratification_summary);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_scenario_horizon_summary.csv', summaries.scenario_horizon_summary);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_model_summary.csv', summaries.model_summary);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_exo_mode_summary.csv', summaries.exo_mode_summary);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_interval_summary.csv', summaries.interval_summary);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_calibration_summary.csv', summaries.calibration_summary);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_scenario_calibration_summary.csv', ...
        summaries.scenario_calibration_summary);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_wis_component_summary.csv', summaries.wis_component_summary);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_selection_summary.csv', selection_summary);
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_missing_selection_artifacts.csv', ...
        table(missing_selection_artifacts, 'VariableNames', {'MissingSelectionArtifact'}));
    table_outputs(end + 1, 1) = local_write_table(table_dir, ...
        'partA_04_evaluation_settings.csv', local_settings_table(cfg));
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

function table_data = local_vertcat_or_empty(blocks, empty_table)
%LOCAL_VERTCAT_OR_EMPTY Vertically concatenate nonempty table blocks.
    blocks = blocks(~cellfun('isempty', blocks));
    if isempty(blocks)
        table_data = empty_table;
    else
        table_data = vertcat(blocks{:});
    end
end

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

function value = local_selected_configuration_text(s)
%LOCAL_SELECTED_CONFIGURATION_TEXT Format selected configuration for tables.
    if isfield(s, 'selected_configuration') && ~isempty(s.selected_configuration)
        value = string(mat2str(double(s.selected_configuration)));
    else
        value = "";
    end
end

function values = local_row_mean_finite(matrix_values)
%LOCAL_ROW_MEAN_FINITE Compute finite row means without toolboxes.
    values = nan(size(matrix_values, 1), 1);
    for i = 1:size(matrix_values, 1)
        values(i) = local_mean_finite(matrix_values(i, :));
    end
end

function nominal_coverage = local_nominal_coverage_matrix(horizon, alphas)
%LOCAL_NOMINAL_COVERAGE_MATRIX Expand nominal coverage by horizon.
    nominal_coverage = repmat(1 - reshape(double(alphas), 1, []), horizon, 1);
end

function components = local_nan_wis_components(horizon, num_alphas)
%LOCAL_NAN_WIS_COMPONENTS Create placeholder WIS component arrays.
    components = struct();
    components.raw_scale_wis = inf(horizon, 1);
    components.median = nan(horizon, 1);
    components.dispersion = nan(horizon, 1);
    components.underprediction = nan(horizon, 1);
    components.overprediction = nan(horizon, 1);
    components.interval_score = nan(horizon, num_alphas);
    components.interval_component = nan(horizon, num_alphas);
    components.sharpness_by_interval = nan(horizon, num_alphas);
    components.underprediction_by_interval = nan(horizon, num_alphas);
    components.overprediction_by_interval = nan(horizon, num_alphas);
end

function value = local_mean_finite(values)
%LOCAL_MEAN_FINITE Mean over finite numeric values only.
    values = double(values(:));
    values = values(isfinite(values));
    if isempty(values)
        value = nan;
    else
        value = mean(values);
    end
end

function files = local_sort_dir_by_name(files)
%LOCAL_SORT_DIR_BY_NAME Sort a dir struct by name.
    [~, order] = sort({files.name});
    files = files(order);
end

function table_data = local_empty_window_scores()
%LOCAL_EMPTY_WINDOW_SCORES Create an empty per-window table.
    table_data = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
        strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
        zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
        zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
        zeros(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), ...
        strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
        'VariableNames', {'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
        'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDayIdx', ...
        'WindowWIS', 'WindowRawScaleWIS', 'WindowRMSE', 'WindowMAE', ...
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
        zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
        zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
        zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
        zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
        'VariableNames', {'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
        'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDayIdx', ...
        'HorizonIdx', 'ForecastDay', 'Truth_Rt', 'Median_Forecast', ...
        'Error', 'SquaredError', 'AbsoluteError', 'WIS', 'RawScaleWIS', ...
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
