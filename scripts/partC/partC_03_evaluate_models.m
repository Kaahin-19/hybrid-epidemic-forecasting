%PARTC_03_EVALUATE_MODELS Evaluate Part C strategy forecast artifacts.
%
%   Description:
%       Loads the Part C strategy forecast artifacts, computes the shared
%       Part A/B Rt evaluation metrics, and writes strategy-aware evaluation
%       artifacts plus named CSV tables. Figure generation is intentionally
%       delegated to Part C 05.
%
%   Workflow:
%       1. Load canonical Part C forecast artifacts.
%       2. Compute WIS, WIS components, RMSE, MAE, coverage, calibration,
%          and interval-width scores with shared metric functions.
%       3. Build strategy/model, horizon, interval, calibration, and
%          selection tables.
%       4. Save evaluation .mat artifact and CSV tables.
%
%   See also PARTC_CONFIG, EVALUATE_FORECAST_WINDOW_METRICS, ...
%            SUMMARIZE_FORECAST_SCORES, PARTC_05_GENERATE_FIGURES.
%
% A. M. Kaahin 2026-05-18
% Modified: 2026-06-05

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Strategy Evaluation ===\n');

cfg = partC_config();
forecastDir = cfg.output.forecast_dir;
evaluationDir = cfg.output.evaluation_dir;
tableDir = cfg.output.table_dir;

if ~exist(evaluationDir, 'dir'), mkdir(evaluationDir); end
if ~exist(tableDir, 'dir'), mkdir(tableDir); end

forecast_paths = local_forecast_artifact_paths(cfg);
if isempty(forecast_paths)
    error('EVAL:NoForecastArtifacts', ...
        'No canonical Part C forecast artifacts found under %s.', forecastDir);
end

fprintf('Found %d forecast artifacts.\n', numel(forecast_paths));

%% 2. Forecast Evaluation
window_blocks = cell(numel(forecast_paths), 1);
pointwise_blocks = cell(numel(forecast_paths), 1);
interval_blocks = cell(numel(forecast_paths), 1);
selection_blocks = cell(numel(forecast_paths), 1);
source_forecast_artifacts = strings(numel(forecast_paths), 1);
skipped_forecast_artifacts = strings(0, 1);

for i = 1:numel(forecast_paths)
    artifact_path = forecast_paths(i);
    source_forecast_artifacts(i) = artifact_path;
    loaded = load(artifact_path);
    local_validate_forecast_artifact(loaded, artifact_path);

    date_lookup = local_load_processed_dates(loaded);
    forecast_results = loaded.forecast_results;
    selection_blocks{i} = local_selection_summary_row(loaded, artifact_path);

    if isempty(forecast_results)
        skipped_forecast_artifacts(end + 1, 1) = artifact_path; %#ok<SAGROW>
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
            local_evaluate_window(window_entry, loaded, artifact_path, ...
            date_lookup);
    end

    window_rows = window_rows(~cellfun('isempty', window_rows));
    pointwise_rows = pointwise_rows(~cellfun('isempty', pointwise_rows));
    interval_rows = interval_rows(~cellfun('isempty', interval_rows));

    if ~isempty(window_rows), window_blocks{i} = vertcat(window_rows{:}); end
    if ~isempty(pointwise_rows), pointwise_blocks{i} = vertcat(pointwise_rows{:}); end
    if ~isempty(interval_rows), interval_blocks{i} = vertcat(interval_rows{:}); end
end

window_scores = local_vertcat_or_empty(window_blocks);
pointwise_scores = local_vertcat_or_empty(pointwise_blocks);
interval_scores = local_vertcat_or_empty(interval_blocks);
selection_summary = unique(local_vertcat_or_empty(selection_blocks), 'rows');

if isempty(window_scores) || height(window_scores) == 0
    error('EVAL:NoUsableForecastArtifacts', ...
        'No usable Part C forecast windows were found.');
end

local_require_exact_configs(window_scores);

summary_tables = summarize_forecast_scores(window_scores, ...
    pointwise_scores, interval_scores);
evaluation_settings = local_evaluation_settings(cfg, source_forecast_artifacts, ...
    window_scores, pointwise_scores);
metrics = struct( ...
    'window_scores', window_scores, ...
    'pointwise_scores', pointwise_scores, ...
    'interval_scores', interval_scores);

fprintf('Evaluated %d forecast windows and %d pointwise horizon rows.\n', ...
    height(window_scores), height(pointwise_scores));

%% 3. Save Evaluation Artifact
experiment_id = string(cfg.experiment_id);
experiment_name = string(cfg.experiment_name);
data_source = string(cfg.data_source);
country_code = string(cfg.input.country_code);
country_name = string(cfg.input.country_name);
strategy_id = unique(window_scores.StrategyID, 'stable');
strategy_name = unique(window_scores.StrategyName, 'stable');
model_type = unique(window_scores.Model, 'stable');
exo_mode = unique(window_scores.ExoMode, 'stable');
cfg_snapshot = local_cfg_snapshot(cfg);

evaluation_artifact = fullfile(evaluationDir, ...
    'partC_evaluation_results.mat');

save(evaluation_artifact, ...
    'experiment_id', 'experiment_name', 'data_source', ...
    'country_code', 'country_name', 'strategy_id', 'strategy_name', ...
    'model_type', 'exo_mode', ...
    'metrics', 'summary_tables', 'window_scores', 'pointwise_scores', ...
    'interval_scores', 'selection_summary', 'evaluation_settings', ...
    'source_forecast_artifacts', 'skipped_forecast_artifacts', ...
    'cfg_snapshot');

fprintf('Evaluation artifact saved to: %s\n', evaluation_artifact);

%% 4. Save Tables
table_outputs = local_write_tables(tableDir, metrics, summary_tables, ...
    selection_summary, evaluation_settings);

fprintf('Saved %d table files under %s\n', numel(table_outputs), tableDir);
fprintf('=== Part C Strategy Evaluation Complete ===\n\n');

%% 5. Local Functions
function paths = local_forecast_artifact_paths(cfg)
%LOCAL_FORECAST_ARTIFACT_PATHS Return expected Part C forecast artifacts.
    paths = strings(0, 1);
    missing = strings(0, 1);

    for s = 1:numel(cfg.strategies)
        for c = 1:numel(cfg.fixed_forecast_cases)
            filename = sprintf('partC_forecast_%s_%s_%s.mat', ...
                char(cfg.strategies(s).strategy_id), ...
                char(cfg.fixed_forecast_cases(c).model_type), ...
                char(cfg.fixed_forecast_cases(c).exo_mode));
            artifact_path = string(fullfile(cfg.output.forecast_dir, filename));
            if exist(artifact_path, 'file') == 2
                paths(end + 1, 1) = artifact_path; %#ok<AGROW>
            else
                missing(end + 1, 1) = artifact_path; %#ok<AGROW>
            end
        end
    end

    if ~isempty(missing)
        error('EVAL:MissingForecastArtifacts', ...
            'Missing expected Part C forecast artifact(s): %s.', ...
            char(strjoin(missing, ', ')));
    end
end

function local_validate_forecast_artifact(loaded, artifact_path)
%LOCAL_VALIDATE_FORECAST_ARTIFACT Verify required forecast fields.
    required_fields = {'experiment_id', 'experiment_name', 'data_source', ...
        'country_code', 'country_name', 'date_range', 'strategy_id', ...
        'strategy_name', 'order_treatment', 'parameter_treatment', ...
        'model_type', 'exo_mode', 'selected_configuration', ...
        'selected_configuration_source', 'selected_configuration_artifact', ...
        'selected_order_for_strategy', 'forecast_results', ...
        'source_processed_artifact', 'cfg_snapshot'};
    if ~all(isfield(loaded, required_fields))
        error('EVAL:InvalidForecastArtifact', ...
            'Forecast artifact is missing required fields: %s.', artifact_path);
    end
end

function date_lookup = local_load_processed_dates(loaded)
%LOCAL_LOAD_PROCESSED_DATES Load date vector for WindowDate/ForecastDate.
    date_lookup = NaT(0, 1);
    if ~isfield(loaded, 'source_processed_artifact') || ...
            strlength(string(loaded.source_processed_artifact)) == 0
        return;
    end

    source_path = string(loaded.source_processed_artifact);
    if exist(source_path, 'file') ~= 2
        return;
    end

    processed = load(source_path, 'date');
    if isfield(processed, 'date') && isdatetime(processed.date)
        date_lookup = processed.date(:);
    end
end

function row = local_selection_summary_row(loaded, artifact_path)
%LOCAL_SELECTION_SUMMARY_ROW Summarize strategy selected configuration use.
    selected_configuration_text = string(mat2str(double(loaded.selected_configuration)));
    selected_order_text = string(mat2str(double(loaded.selected_order_for_strategy)));
    fallback_used = false;
    if isfield(loaded, 'selection_metadata') && ...
            isfield(loaded.selection_metadata, 'fallback_used')
        fallback_used = logical(loaded.selection_metadata.fallback_used);
    end

    row = table(string(loaded.strategy_id), string(loaded.strategy_name), ...
        string(loaded.order_treatment), string(loaded.parameter_treatment), ...
        string(loaded.data_source), string(loaded.country_code), ...
        string(loaded.country_name), string(loaded.model_type), ...
        string(loaded.exo_mode), selected_configuration_text, ...
        selected_order_text, ...
        string(loaded.selected_configuration_source), ...
        string(loaded.selected_configuration_artifact), fallback_used, ...
        string(artifact_path), ...
        'VariableNames', {'StrategyID', 'StrategyName', 'OrderTreatment', ...
        'ParameterTreatment', 'DataSource', 'CountryCode', 'CountryName', ...
        'Model', 'ExoMode', 'SelectedConfiguration', ...
        'SelectedOrderForStrategy', 'Source', 'SelectionArtifact', ...
        'FallbackUsed', 'ForecastArtifact'});
end

function window_entry = local_normalize_forecast_window(raw_entry)
%LOCAL_NORMALIZE_FORECAST_WINDOW Normalize canonical forecast fields.
    window_entry = struct();
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
    window_entry.interval_method = local_get_string_field(raw_entry, ...
        'interval_method', "");
    window_entry.interval_status = local_get_string_field(raw_entry, ...
        'interval_status', "");
    window_entry.recorded_status = local_get_string_field(raw_entry, ...
        'status', "");
    window_entry.window_date = local_get_datetime_scalar(raw_entry, ...
        'forecast_origin_date');
    window_entry.forecast_dates = local_get_datetime_vector(raw_entry, ...
        't_future_date');
end

function [window_row, pointwise_rows, interval_rows] = local_evaluate_window( ...
    window_entry, loaded, artifact_path, date_lookup)
%LOCAL_EVALUATE_WINDOW Compute all Part C score rows for one window.
    truth_Rt = double(window_entry.truth_Rt(:));
    pred_Rt = double(window_entry.pred_Rt(:));
    lower_Rt = double(window_entry.lower_Rt);
    upper_Rt = double(window_entry.upper_Rt);
    alphas = reshape(double(window_entry.alphas), 1, []);
    horizon = numel(truth_Rt);
    metrics = evaluate_forecast_window_metrics(truth_Rt, pred_Rt, ...
        lower_Rt, upper_Rt, alphas);

    metadata = local_score_metadata(loaded, artifact_path);
    window_date = local_window_date(window_entry, date_lookup);
    forecast_dates = local_forecast_dates(window_entry, date_lookup, horizon);

    window_row = local_window_row(metadata, window_entry, window_date, ...
        metrics.window_wis, metrics.window_rmse, metrics.window_mae, ...
        metrics.mean_wis_median_component, ...
        metrics.mean_wis_dispersion_component, metrics.mean_wis_under_component, ...
        metrics.mean_wis_over_component, metrics.mean_coverage, ...
        metrics.mean_calibration_bias, metrics.mean_absolute_calibration_error, ...
        metrics.mean_interval_width, metrics.is_valid);

    if horizon == 0
        pointwise_rows = table();
        interval_rows = table();
        return;
    end

    forecast_day = local_forecast_day(window_entry, horizon);
    horizon_idx = (1:horizon)';
    error_values = pred_Rt - truth_Rt;

    pointwise_rows = local_pointwise_rows(metadata, window_entry, window_date, ...
        horizon_idx, forecast_day, forecast_dates, truth_Rt, pred_Rt, ...
        error_values, metrics.pointwise_wis, metrics.wis_components, ...
        metrics.coverage_mean, metrics.calibration_bias_mean, ...
        metrics.absolute_calibration_mean, metrics.width_mean);

    interval_rows = local_interval_rows(metadata, window_entry, window_date, ...
        horizon_idx, forecast_day, forecast_dates, truth_Rt, alphas, ...
        lower_Rt, upper_Rt, metrics.coverage, metrics.interval_width, ...
        metrics.wis_components);
end

function metadata = local_score_metadata(loaded, artifact_path)
%LOCAL_SCORE_METADATA Create common score-row metadata.
    metadata = struct();
    metadata.StrategyID = string(loaded.strategy_id);
    metadata.StrategyName = string(loaded.strategy_name);
    metadata.OrderTreatment = string(loaded.order_treatment);
    metadata.ParameterTreatment = string(loaded.parameter_treatment);
    metadata.DataSource = string(loaded.data_source);
    metadata.CountryCode = string(loaded.country_code);
    metadata.CountryName = string(loaded.country_name);
    metadata.Scenario = "real";
    metadata.ScenarioName = string(loaded.country_name);
    metadata.Model = string(loaded.model_type);
    metadata.ExoMode = string(loaded.exo_mode);
    metadata.ForecastArtifact = string(artifact_path);
    metadata.ResultSource = "forecast_results";
end

function row = local_window_row(m, window_entry, window_date, window_wis, ...
    window_rmse, window_mae, median_component, dispersion_component, ...
    under_component, over_component, mean_coverage, mean_calibration_bias, ...
    mean_absolute_calibration_error, mean_interval_width, is_valid)
%LOCAL_WINDOW_ROW Build one window-level score row.
    row = table(m.StrategyID, m.StrategyName, m.OrderTreatment, ...
        m.ParameterTreatment, m.DataSource, m.CountryCode, ...
        m.CountryName, m.Scenario, m.ScenarioName, m.Model, ...
        m.ExoMode, m.ForecastArtifact, ...
        m.ResultSource, window_entry.window_day, window_date, ...
        window_entry.window_day_idx, window_wis, window_wis, window_rmse, ...
        window_mae, median_component, dispersion_component, under_component, ...
        over_component, mean_coverage, mean_calibration_bias, ...
        mean_absolute_calibration_error, mean_interval_width, is_valid, ...
        string(window_entry.interval_method), string(window_entry.interval_status), ...
        string(window_entry.recorded_status), window_entry.aicc, ...
        'VariableNames', {'StrategyID', 'StrategyName', 'OrderTreatment', ...
        'ParameterTreatment', 'DataSource', 'CountryCode', 'CountryName', ...
        'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
        'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDate', ...
        'WindowDayIdx', 'WindowWIS', 'WindowRawScaleWIS', 'WindowRMSE', ...
        'WindowMAE', 'MeanWISMedianComponent', ...
        'MeanWISDispersionComponent', 'MeanWISUnderpredictionComponent', ...
        'MeanWISOverpredictionComponent', 'MeanCoverage', ...
        'MeanCalibrationBias', 'MeanAbsoluteCalibrationError', ...
        'MeanIntervalWidth', 'IsValid', 'IntervalMethod', ...
        'IntervalStatus', 'RecordedStatus', 'AICC'});
end

function rows = local_pointwise_rows(m, window_entry, window_date, horizon_idx, ...
    forecast_day, forecast_dates, truth_Rt, pred_Rt, error_values, ...
    pointwise_wis, wis_components, coverage_mean, calibration_bias_mean, ...
    absolute_calibration_mean, width_mean)
%LOCAL_POINTWISE_ROWS Build horizon-level score rows for one window.
    horizon = numel(horizon_idx);
    absolute_error = abs(error_values);
    rows = table( ...
        repmat(m.StrategyID, horizon, 1), ...
        repmat(m.StrategyName, horizon, 1), ...
        repmat(m.OrderTreatment, horizon, 1), ...
        repmat(m.ParameterTreatment, horizon, 1), ...
        repmat(m.DataSource, horizon, 1), ...
        repmat(m.CountryCode, horizon, 1), ...
        repmat(m.CountryName, horizon, 1), ...
        repmat(m.Scenario, horizon, 1), ...
        repmat(m.ScenarioName, horizon, 1), ...
        repmat(m.Model, horizon, 1), ...
        repmat(m.ExoMode, horizon, 1), ...
        repmat(m.ForecastArtifact, horizon, 1), ...
        repmat(m.ResultSource, horizon, 1), ...
        repmat(window_entry.window_day, horizon, 1), ...
        repmat(window_date, horizon, 1), ...
        repmat(window_entry.window_day_idx, horizon, 1), ...
        horizon_idx, forecast_day, forecast_dates, truth_Rt, pred_Rt, ...
        error_values, error_values .^ 2, absolute_error, pointwise_wis, ...
        absolute_error, absolute_error, pointwise_wis, ...
        wis_components.median, wis_components.dispersion, ...
        wis_components.underprediction, wis_components.overprediction, ...
        coverage_mean, calibration_bias_mean, absolute_calibration_mean, ...
        width_mean, coverage_mean, calibration_bias_mean, ...
        absolute_calibration_mean, width_mean, ...
        repmat(string(window_entry.interval_method), horizon, 1), ...
        repmat(string(window_entry.interval_status), horizon, 1), ...
        'VariableNames', {'StrategyID', 'StrategyName', 'OrderTreatment', ...
        'ParameterTreatment', 'DataSource', 'CountryCode', 'CountryName', ...
        'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
        'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDate', ...
        'WindowDayIdx', 'HorizonIdx', 'ForecastDay', 'ForecastDate', ...
        'Truth_Rt', 'Median_Forecast', 'Error', 'SquaredError', ...
        'AbsoluteError', 'WIS', 'RMSE', 'MAE', 'RawScaleWIS', ...
        'WISMedianComponent', 'WISDispersionComponent', ...
        'WISUnderpredictionComponent', 'WISOverpredictionComponent', ...
        'Coverage', 'CalibrationBias', 'AbsoluteCalibrationError', ...
        'IntervalWidth', 'CoverageMean', 'CalibrationBiasMean', ...
        'AbsoluteCalibrationErrorMean', 'IntervalWidthMean', ...
        'IntervalMethod', 'IntervalStatus'});
end

function rows = local_interval_rows(m, window_entry, window_date, horizon_idx, ...
    forecast_day, forecast_dates, truth_Rt, alphas, lower_Rt, upper_Rt, ...
    coverage, interval_width, wis_components)
%LOCAL_INTERVAL_ROWS Build long-format interval score rows.
    horizon = numel(horizon_idx);
    num_alphas = numel(alphas);
    if horizon == 0 || num_alphas == 0
        rows = table();
        return;
    end

    num_rows = horizon * num_alphas;
    rows = table( ...
        strings(num_rows, 1), strings(num_rows, 1), strings(num_rows, 1), ...
        strings(num_rows, 1), ...
        strings(num_rows, 1), strings(num_rows, 1), strings(num_rows, 1), ...
        strings(num_rows, 1), strings(num_rows, 1), strings(num_rows, 1), ...
        strings(num_rows, 1), strings(num_rows, 1), strings(num_rows, 1), ...
        zeros(num_rows, 1), NaT(num_rows, 1), zeros(num_rows, 1), ...
        zeros(num_rows, 1), zeros(num_rows, 1), NaT(num_rows, 1), ...
        zeros(num_rows, 1), zeros(num_rows, 1), zeros(num_rows, 1), ...
        zeros(num_rows, 1), zeros(num_rows, 1), zeros(num_rows, 1), ...
        zeros(num_rows, 1), strings(num_rows, 1), strings(num_rows, 1), ...
        zeros(num_rows, 1), zeros(num_rows, 1), zeros(num_rows, 1), ...
        zeros(num_rows, 1), zeros(num_rows, 1), zeros(num_rows, 1), ...
        zeros(num_rows, 1), ...
        'VariableNames', {'StrategyID', 'StrategyName', 'OrderTreatment', ...
        'ParameterTreatment', 'DataSource', 'CountryCode', 'CountryName', ...
        'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
        'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDate', ...
        'WindowDayIdx', 'HorizonIdx', 'ForecastDay', 'ForecastDate', ...
        'Truth_Rt', 'Alpha', 'NominalCoverage', 'LowerBound', ...
        'UpperBound', 'Coverage', 'IntervalWidth', 'IntervalMethod', ...
        'IntervalStatus', 'CoverageError', 'AbsoluteCoverageError', ...
        'IntervalScore', 'WISIntervalComponent', 'WISSharpnessComponent', ...
        'WISUnderpredictionComponent', 'WISOverpredictionComponent'});

    row_idx = 0;
    for j = 1:num_alphas
        idx = row_idx + (1:horizon);
        coverage_error = coverage(:, j) - (1 - alphas(j));
        rows.StrategyID(idx) = m.StrategyID;
        rows.StrategyName(idx) = m.StrategyName;
        rows.OrderTreatment(idx) = m.OrderTreatment;
        rows.ParameterTreatment(idx) = m.ParameterTreatment;
        rows.DataSource(idx) = m.DataSource;
        rows.CountryCode(idx) = m.CountryCode;
        rows.CountryName(idx) = m.CountryName;
        rows.Scenario(idx) = m.Scenario;
        rows.ScenarioName(idx) = m.ScenarioName;
        rows.Model(idx) = m.Model;
        rows.ExoMode(idx) = m.ExoMode;
        rows.ForecastArtifact(idx) = m.ForecastArtifact;
        rows.ResultSource(idx) = m.ResultSource;
        rows.WindowDay(idx) = window_entry.window_day;
        rows.WindowDate(idx) = window_date;
        rows.WindowDayIdx(idx) = window_entry.window_day_idx;
        rows.HorizonIdx(idx) = horizon_idx;
        rows.ForecastDay(idx) = forecast_day;
        rows.ForecastDate(idx) = forecast_dates;
        rows.Truth_Rt(idx) = truth_Rt;
        rows.Alpha(idx) = alphas(j);
        rows.NominalCoverage(idx) = 1 - alphas(j);
        rows.LowerBound(idx) = lower_Rt(:, j);
        rows.UpperBound(idx) = upper_Rt(:, j);
        rows.Coverage(idx) = coverage(:, j);
        rows.IntervalWidth(idx) = interval_width(:, j);
        rows.IntervalMethod(idx) = string(window_entry.interval_method);
        rows.IntervalStatus(idx) = string(window_entry.interval_status);
        rows.CoverageError(idx) = coverage_error;
        rows.AbsoluteCoverageError(idx) = abs(coverage_error);
        rows.IntervalScore(idx) = wis_components.interval_score(:, j);
        rows.WISIntervalComponent(idx) = wis_components.interval_component(:, j);
        rows.WISSharpnessComponent(idx) = wis_components.sharpness_by_interval(:, j);
        rows.WISUnderpredictionComponent(idx) = ...
            wis_components.underprediction_by_interval(:, j);
        rows.WISOverpredictionComponent(idx) = ...
            wis_components.overprediction_by_interval(:, j);
        row_idx = row_idx + horizon;
    end
end

function settings = local_evaluation_settings(cfg, source_forecast_artifacts, ...
    window_scores, pointwise_scores)
%LOCAL_EVALUATION_SETTINGS Build a one-row settings table.
    wis_alpha_text = string(strjoin(compose('%.3g', ...
        double(cfg.forecast.wis_alphas(:)')), ', '));
    strategy_text = strjoin(string({cfg.strategies.strategy_id}), ', ');
    settings = table(string(cfg.experiment_id), string(cfg.experiment_name), ...
        string(cfg.data_source), string(cfg.input.country_code), ...
        string(cfg.input.country_name), string(strategy_text), ...
        cfg.forecast.min_window, ...
        cfg.forecast.step_size, cfg.forecast.horizon, wis_alpha_text, ...
        numel(source_forecast_artifacts), height(window_scores), ...
        height(pointwise_scores), ...
        'VariableNames', {'ExperimentID', 'ExperimentName', 'DataSource', ...
        'CountryCode', 'CountryName', 'Strategies', 'MinWindow', 'StepSize', ...
        'ForecastHorizon', 'WISAlphas', 'NumForecastArtifacts', ...
        'NumWindowScores', 'NumPointwiseScores'});
end

function outputs = local_write_tables(tableDir, metrics, summary_tables, ...
    selection_summary, evaluation_settings)
%LOCAL_WRITE_TABLES Persist required Part C CSV tables.
    if ~exist(tableDir, 'dir'), mkdir(tableDir); end
    outputs = strings(0, 1);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_window_scores.csv', metrics.window_scores);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_pointwise_scores.csv', metrics.pointwise_scores);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_interval_scores.csv', metrics.interval_scores);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_strategy_model_summary.csv', summary_tables.model_summary);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_strategy_horizon_summary.csv', summary_tables.horizon_summary);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_strategy_interval_summary.csv', summary_tables.interval_summary);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_strategy_calibration_summary.csv', summary_tables.scenario_calibration_summary);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_strategy_wis_component_summary.csv', ...
        summary_tables.wis_component_summary);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_strategy_selection_summary.csv', selection_summary);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_evaluation_settings.csv', evaluation_settings);

    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_model_summary.csv', summary_tables.model_summary);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_horizon_summary.csv', summary_tables.horizon_summary);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_interval_summary.csv', summary_tables.interval_summary);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_calibration_summary.csv', summary_tables.scenario_calibration_summary);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_wis_component_summary.csv', summary_tables.wis_component_summary);
    outputs(end + 1, 1) = local_write_table(tableDir, ...
        'partC_selection_summary.csv', selection_summary);
end

function output_path = local_write_table(tableDir, filename, table_data)
%LOCAL_WRITE_TABLE Write one CSV table.
    output_path = fullfile(tableDir, filename);
    writetable(table_data, output_path);
    fprintf('Table saved to: %s\n', output_path);
end

function local_require_exact_configs(window_scores)
%LOCAL_REQUIRE_EXACT_CONFIGS Ensure all strategy/model cases are present.
    observed_configs = unique(window_scores(:, ...
        {'StrategyID', 'Model', 'ExoMode'}), 'rows');
    observed_keys = sort(string(observed_configs.StrategyID) + "_" + ...
        string(observed_configs.Model) + "_" + string(observed_configs.ExoMode));
    expected_keys = sort([ ...
        "fixed_parameters_AR_None"; ...
        "fixed_parameters_ARX_I"; ...
        "online_reestimate_AR_None"; ...
        "online_reestimate_ARX_I"; ...
        "local_order_retuning_AR_None"; ...
        "local_order_retuning_ARX_I"]);

    if ~isequal(observed_keys, expected_keys)
        error('EVAL:UnexpectedPartCConfigs', ...
            'Part C evaluation must contain all strategy x AR/None, ARX/I cases.');
    end
end

function cfg_snapshot = local_cfg_snapshot(cfg)
%LOCAL_CFG_SNAPSHOT Store relevant evaluation configuration.
    cfg_snapshot = struct();
    cfg_snapshot.experiment_id = cfg.experiment_id;
    cfg_snapshot.experiment_name = cfg.experiment_name;
    cfg_snapshot.data_source = cfg.data_source;
    cfg_snapshot.forecast = cfg.forecast;
    cfg_snapshot.output = cfg.output;
    cfg_snapshot.intervals = cfg.intervals;
    cfg_snapshot.fixed_forecast_cases = cfg.fixed_forecast_cases;
    cfg_snapshot.strategies = cfg.strategies;
    cfg_snapshot.local_order_grid = cfg.local_order_grid;
    cfg_snapshot.sirs_projection = cfg.sirs_projection;
end

function window_date = local_window_date(window_entry, date_lookup)
%LOCAL_WINDOW_DATE Return recorded or lookup forecast-origin date.
    window_date = window_entry.window_date;
    if ~isnat(window_date)
        return;
    end
    window_date = local_date_from_index(date_lookup, window_entry.window_day_idx);
end

function forecast_dates = local_forecast_dates(window_entry, date_lookup, horizon)
%LOCAL_FORECAST_DATES Return recorded or lookup future dates.
    forecast_dates = window_entry.forecast_dates;
    if numel(forecast_dates) == horizon && all(~isnat(forecast_dates))
        forecast_dates = forecast_dates(:);
        return;
    end
    forecast_dates = local_dates_from_indices(date_lookup, ...
        window_entry.horizon_indices, horizon);
end

function value = local_date_from_index(date_lookup, idx)
%LOCAL_DATE_FROM_INDEX Resolve one datetime from a numeric index.
    value = NaT;
    idx = double(idx);
    if ~isempty(date_lookup) && isfinite(idx) && idx >= 1 && ...
            idx <= numel(date_lookup)
        value = date_lookup(idx);
    end
end

function values = local_dates_from_indices(date_lookup, indices, horizon)
%LOCAL_DATES_FROM_INDICES Resolve datetime vector from numeric indices.
    values = NaT(horizon, 1);
    indices = double(indices(:));
    if isempty(date_lookup) || numel(indices) ~= horizon
        return;
    end
    valid = indices >= 1 & indices <= numel(date_lookup);
    if all(valid)
        values = date_lookup(indices);
    end
end

function forecast_day = local_forecast_day(window_entry, horizon)
%LOCAL_FORECAST_DAY Return future time values or horizon indices.
    forecast_day = double(window_entry.forecast_day(:));
    if numel(forecast_day) ~= horizon
        forecast_day = (1:horizon)';
    end
end

function table_data = local_vertcat_or_empty(blocks)
%LOCAL_VERTCAT_OR_EMPTY Vertically concatenate nonempty table blocks.
    blocks = blocks(~cellfun('isempty', blocks));
    if isempty(blocks)
        table_data = table();
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

function value = local_get_datetime_scalar(s, field_name)
%LOCAL_GET_DATETIME_SCALAR Read a datetime scalar or NaT.
    value = NaT;
    if isfield(s, field_name) && ~isempty(s.(field_name)) && ...
            isdatetime(s.(field_name))
        raw = s.(field_name);
        value = raw(1);
    end
end

function value = local_get_datetime_vector(s, field_name)
%LOCAL_GET_DATETIME_VECTOR Read a datetime vector or empty NaT vector.
    value = NaT(0, 1);
    if isfield(s, field_name) && ~isempty(s.(field_name)) && ...
            isdatetime(s.(field_name))
        value = s.(field_name)(:);
    end
end
