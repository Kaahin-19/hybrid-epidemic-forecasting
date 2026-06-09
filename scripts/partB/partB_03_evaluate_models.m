%PARTB_03_EVALUATE_MODELS Evaluate Part B robustness-ladder forecasts.
%
%   Description:
%       Loads Part B forecast artifacts across all active robustness cases,
%       computes the same Rt metrics used by Part A, summarizes performance
%       by case/scenario/model/horizon, and writes case-specific
%       plus cross-case evaluation artifacts and tables. Figure generation is
%       intentionally delegated to Part B 04.
%
%   Workflow:
%       1. Load forecast artifacts from all active case directories.
%       2. Compute WIS, RMSE, MAE, coverage, calibration, and interval width.
%       3. Build case-level and cross-case robustness summaries.
%       4. Save evaluation .mat artifacts and table files.
%
%   See also PARTB_CONFIG, EVALUATE_FORECAST_WINDOW_METRICS, ...
%            SUMMARIZE_FORECAST_SCORES, PARTB_04_GENERATE_FIGURES.
%
% A. M. Kaahin 2026-05-18
% Modified: 2026-06-09

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Robustness-Ladder Forecast Evaluation ===\n');

cfg = partB_config();
evaluation_dir = cfg.output.evaluation_dir;
table_dir = cfg.output.table_dir;

if ~exist(evaluation_dir, 'dir'), mkdir(evaluation_dir); end
if ~exist(table_dir, 'dir'), mkdir(table_dir); end

forecast_paths = local_forecast_artifact_paths(cfg);
if isempty(forecast_paths)
    error('EVAL:NoForecastArtifacts', ...
        'No Part B forecast artifacts found under %s.', cfg.output.root_dir);
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
            local_evaluate_window(window_entry, loaded, artifact_path);
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
        'No usable Part B forecast windows were found.');
end

summary_tables = local_summary_tables(window_scores, pointwise_scores, interval_scores);
summary_tables.generic_partA_style = summarize_forecast_scores( ...
    window_scores, pointwise_scores, interval_scores);

[degradation_summary, partA_baseline_summary, degradation_status] = ...
    local_degradation_summary(cfg, summary_tables.case_model_summary);
summary_tables.degradation_summary = degradation_summary;
summary_tables.partA_baseline_summary = partA_baseline_summary;

metrics = struct( ...
    'window_scores', window_scores, ...
    'pointwise_scores', pointwise_scores, ...
    'interval_scores', interval_scores);

fprintf('Evaluated %d forecast windows and %d pointwise horizon rows.\n', ...
    height(window_scores), height(pointwise_scores));

%% 3. Save Cross-Case Evaluation Artifact
experiment_id = string(cfg.experiment_id);
experiment_name = string(cfg.experiment_name);
case_id = unique(window_scores.CaseID, 'stable');
case_name = unique(window_scores.CaseName, 'stable');
truth_model = unique(window_scores.TruthModel, 'stable');
solver = unique(window_scores.Solver, 'stable');
forecast_assumption = string(cfg.forecast_assumption);
model_type = unique(window_scores.Model, 'stable');
exo_mode = unique(window_scores.ExoMode, 'stable');
cfg_snapshot = local_cfg_snapshot(cfg);

evaluation_artifact = fullfile(evaluation_dir, ...
    'partB_robustness_ladder_evaluation_results.mat');

save(evaluation_artifact, ...
    'experiment_id', 'experiment_name', 'case_id', 'case_name', ...
    'truth_model', 'solver', 'forecast_assumption', 'model_type', ...
    'exo_mode', 'metrics', 'summary_tables', 'window_scores', ...
    'pointwise_scores', 'interval_scores', 'selection_summary', ...
    'degradation_summary', 'partA_baseline_summary', 'degradation_status', ...
    'source_forecast_artifacts', 'skipped_forecast_artifacts', 'cfg_snapshot');

fprintf('Cross-case evaluation artifact saved to: %s\n', evaluation_artifact);

%% 4. Save Case-Specific Evaluation Artifacts
case_ids = unique(window_scores.CaseID, 'stable');
for i = 1:numel(case_ids)
    this_case = case_ids(i);
    case_idx = window_scores.CaseID == this_case;
    point_idx = pointwise_scores.CaseID == this_case;
    interval_idx = interval_scores.CaseID == this_case;

    case_metrics = struct( ...
        'window_scores', window_scores(case_idx, :), ...
        'pointwise_scores', pointwise_scores(point_idx, :), ...
        'interval_scores', interval_scores(interval_idx, :));
    case_summary_tables = local_summary_tables(case_metrics.window_scores, ...
        case_metrics.pointwise_scores, case_metrics.interval_scores);

    case_dir = local_case_evaluation_dir(cfg, this_case);
    if ~exist(case_dir, 'dir'), mkdir(case_dir); end
    case_artifact = fullfile(case_dir, ...
        sprintf('partB_%s_evaluation_results.mat', char(this_case)));
    source_case_id = this_case; 
    save(case_artifact, 'experiment_id', 'experiment_name', 'source_case_id', ...
        'case_metrics', 'case_summary_tables', 'cfg_snapshot');
    fprintf('Case evaluation artifact saved to: %s\n', case_artifact);
end

%% 5. Save Tables
cross_table_outputs = local_write_cross_tables(table_dir, metrics, ...
    summary_tables, selection_summary, degradation_status);
case_table_outputs = local_write_case_tables(cfg, metrics);

fprintf('Saved %d cross-case table files under %s\n', ...
    numel(cross_table_outputs), table_dir);
fprintf('Saved %d case-specific table files.\n', numel(case_table_outputs));
fprintf('=== Part B Robustness-Ladder Forecast Evaluation Complete ===\n\n');

%% 6. Local Functions
function paths = local_forecast_artifact_paths(cfg)
%LOCAL_FORECAST_ARTIFACT_PATHS Return active forecast artifacts.
    cases = local_active_cases(cfg);
    active_scenarios = local_active_scenario_ids(cfg);
    active_forecast_cases = local_active_forecast_cases(cfg);
    paths = strings(0, 1);
    for i = 1:numel(cases)
        for s = 1:numel(active_scenarios)
            for f = 1:numel(active_forecast_cases)
                artifact_path = fullfile(cfg.output.forecast_dir, ...
                    sprintf('partB_%s_forecast_%s_%s_%s.mat', ...
                    char(cases(i).case_id), char(active_scenarios(s)), ...
                    char(active_forecast_cases(f).model_type), ...
                    char(active_forecast_cases(f).exo_mode)));
                if exist(artifact_path, 'file') == 2
                    paths(end + 1, 1) = artifact_path; %#ok<AGROW>
                end
            end
        end
    end
end

function cases = local_active_cases(cfg)
%LOCAL_ACTIVE_CASES Apply optional smoke-test case limiting.
    cases = cfg.robustness_cases;
    if cfg.smoke_test.enabled
        cases = cases(1:min(numel(cases), cfg.smoke_test.num_cases));
    end
end

function scenario_ids = local_active_scenario_ids(cfg)
%LOCAL_ACTIVE_SCENARIO_IDS Return active scenario ids.
    scenarios = cfg.scenarios;
    if cfg.smoke_test.enabled
        scenarios = scenarios(1:min(numel(scenarios), cfg.smoke_test.num_scenarios));
    end
    scenario_ids = strings(numel(scenarios), 1);
    for i = 1:numel(scenarios)
        scenario_ids(i) = string(scenarios(i).id);
    end
end

function forecast_cases = local_active_forecast_cases(cfg)
%LOCAL_ACTIVE_FORECAST_CASES Return active fixed forecast cases.
    forecast_cases = cfg.fixed_forecast_cases;
    if cfg.smoke_test.enabled
        forecast_cases = forecast_cases(1:min(numel(forecast_cases), ...
            cfg.smoke_test.num_forecast_cases));
    end
end

function local_validate_forecast_artifact(loaded, artifact_path)
%LOCAL_VALIDATE_FORECAST_ARTIFACT Verify required forecast fields.
    required_fields = {'case_id', 'case_name', 'truth_model', 'solver', ...
        'forecast_assumption', 'structural_mismatch_enabled', ...
        'observation_noise_enabled', 'process_noise_enabled', ...
        'scenario_id', 'scenario_name', 'model_type', ...
        'exo_mode', 'selected_configuration', 'forecast_results'};
    if ~all(isfield(loaded, required_fields))
        error('EVAL:InvalidForecastArtifact', ...
            'Forecast artifact is missing required fields: %s.', artifact_path);
    end
end

function row = local_selection_summary_row(loaded, artifact_path)
%LOCAL_SELECTION_SUMMARY_ROW Summarize fixed selected configuration use.
    selected_configuration_text = string(mat2str(double(loaded.selected_configuration)));
    source = local_loaded_string(loaded, 'selected_configuration_source', "");
    selection_artifact = local_loaded_string(loaded, 'selected_configuration_artifact', "");

    row = table(string(loaded.case_id), string(loaded.case_name), ...
        string(loaded.model_type), string(loaded.exo_mode), ...
        selected_configuration_text, source, selection_artifact, ...
        string(artifact_path), ...
        'VariableNames', {'CaseID', 'CaseName', 'Model', 'ExoMode', ...
        'SelectedConfiguration', 'Source', 'SelectionArtifact', ...
        'ForecastArtifact'});
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
end

function [window_row, pointwise_rows, interval_rows] = local_evaluate_window( ...
    window_entry, loaded, artifact_path)
%LOCAL_EVALUATE_WINDOW Compute all score rows for one forecast window.
    truth_Rt = double(window_entry.truth_Rt(:));
    pred_Rt = double(window_entry.pred_Rt(:));
    lower_Rt = double(window_entry.lower_Rt);
    upper_Rt = double(window_entry.upper_Rt);
    alphas = reshape(double(window_entry.alphas), 1, []);
    result_source = "forecast_results";

    horizon = numel(truth_Rt);
    metrics = evaluate_forecast_window_metrics(truth_Rt, pred_Rt, ...
        lower_Rt, upper_Rt, alphas);

    metadata = local_score_metadata(loaded, artifact_path, result_source);
    window_row = local_window_row(metadata, window_entry, metrics.window_wis, ...
        metrics.window_rmse, metrics.window_mae, ...
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

    pointwise_rows = local_pointwise_rows(metadata, window_entry, horizon_idx, ...
        forecast_day, truth_Rt, pred_Rt, error_values, metrics.pointwise_wis, ...
        metrics.wis_components, metrics.coverage_mean, ...
        metrics.calibration_bias_mean, metrics.absolute_calibration_mean, ...
        metrics.width_mean);

    interval_rows = local_interval_rows(metadata, window_entry, horizon_idx, ...
        forecast_day, truth_Rt, alphas, lower_Rt, upper_Rt, metrics.coverage, ...
        metrics.interval_width, metrics.wis_components);
end

function metadata = local_score_metadata(loaded, artifact_path, result_source)
%LOCAL_SCORE_METADATA Create common score-row metadata.
    metadata = struct();
    metadata.CaseID = string(loaded.case_id);
    metadata.CaseName = string(loaded.case_name);
    metadata.TruthModel = string(loaded.truth_model);
    metadata.Solver = string(loaded.solver);
    metadata.StructuralMismatch = logical(loaded.structural_mismatch_enabled);
    metadata.ObservationNoise = logical(loaded.observation_noise_enabled);
    metadata.ProcessNoise = logical(loaded.process_noise_enabled);
    metadata.Scenario = string(loaded.scenario_id);
    metadata.ScenarioName = string(loaded.scenario_name);
    metadata.Model = string(loaded.model_type);
    metadata.ExoMode = string(loaded.exo_mode);
    metadata.ForecastArtifact = string(artifact_path);
    metadata.ResultSource = string(result_source);
end

function row = local_window_row(m, window_entry, window_wis, window_rmse, ...
    window_mae, median_component, dispersion_component, under_component, ...
    over_component, mean_coverage, mean_calibration_bias, ...
    mean_absolute_calibration_error, mean_interval_width, is_valid)
%LOCAL_WINDOW_ROW Build one window-level score row.
    row = table(m.CaseID, m.CaseName, m.TruthModel, m.Solver, ...
        m.StructuralMismatch, m.ObservationNoise, m.ProcessNoise, ...
        m.Scenario, m.ScenarioName, m.Model, m.ExoMode, ...
        m.ForecastArtifact, m.ResultSource, window_entry.window_day, ...
        window_entry.window_day_idx, window_wis, window_wis, window_rmse, ...
        window_mae, median_component, dispersion_component, under_component, ...
        over_component, mean_coverage, mean_calibration_bias, ...
        mean_absolute_calibration_error, mean_interval_width, is_valid, ...
        string(window_entry.interval_method), string(window_entry.interval_status), ...
        string(window_entry.recorded_status), window_entry.aicc, ...
        'VariableNames', {'CaseID', 'CaseName', 'TruthModel', 'Solver', ...
        'StructuralMismatch', 'ObservationNoise', 'ProcessNoise', ...
        'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
        'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDayIdx', ...
        'WindowWIS', 'WindowRawScaleWIS', 'WindowRMSE', 'WindowMAE', ...
        'MeanWISMedianComponent', 'MeanWISDispersionComponent', ...
        'MeanWISUnderpredictionComponent', 'MeanWISOverpredictionComponent', ...
        'MeanCoverage', 'MeanCalibrationBias', ...
        'MeanAbsoluteCalibrationError', 'MeanIntervalWidth', 'IsValid', ...
        'IntervalMethod', 'IntervalStatus', 'RecordedStatus', 'AICC'});
end

function rows = local_pointwise_rows(m, window_entry, horizon_idx, forecast_day, ...
    truth_Rt, pred_Rt, error_values, pointwise_wis, wis_components, ...
    coverage_mean, calibration_bias_mean, absolute_calibration_mean, width_mean)
%LOCAL_POINTWISE_ROWS Build horizon-level score rows for one window.
    horizon = numel(horizon_idx);
    rows = table( ...
        repmat(m.CaseID, horizon, 1), repmat(m.CaseName, horizon, 1), ...
        repmat(m.TruthModel, horizon, 1), repmat(m.Solver, horizon, 1), ...
        repmat(m.StructuralMismatch, horizon, 1), ...
        repmat(m.ObservationNoise, horizon, 1), ...
        repmat(m.ProcessNoise, horizon, 1), ...
        repmat(m.Scenario, horizon, 1), repmat(m.ScenarioName, horizon, 1), ...
        repmat(m.Model, horizon, 1), repmat(m.ExoMode, horizon, 1), ...
        repmat(m.ForecastArtifact, horizon, 1), ...
        repmat(m.ResultSource, horizon, 1), ...
        repmat(window_entry.window_day, horizon, 1), ...
        repmat(window_entry.window_day_idx, horizon, 1), ...
        horizon_idx, forecast_day, truth_Rt, pred_Rt, error_values, ...
        error_values .^ 2, abs(error_values), pointwise_wis, ...
        pointwise_wis, wis_components.median, wis_components.dispersion, ...
        wis_components.underprediction, wis_components.overprediction, ...
        coverage_mean, calibration_bias_mean, absolute_calibration_mean, ...
        width_mean, repmat(string(window_entry.interval_method), horizon, 1), ...
        repmat(string(window_entry.interval_status), horizon, 1), ...
        'VariableNames', {'CaseID', 'CaseName', 'TruthModel', 'Solver', ...
        'StructuralMismatch', 'ObservationNoise', 'ProcessNoise', ...
        'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
        'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDayIdx', ...
        'HorizonIdx', 'ForecastDay', 'Truth_Rt', 'Median_Forecast', ...
        'Error', 'SquaredError', 'AbsoluteError', 'WIS', 'RawScaleWIS', ...
        'WISMedianComponent', 'WISDispersionComponent', ...
        'WISUnderpredictionComponent', 'WISOverpredictionComponent', ...
        'CoverageMean', 'CalibrationBiasMean', ...
        'AbsoluteCalibrationErrorMean', 'IntervalWidthMean', ...
        'IntervalMethod', 'IntervalStatus'});
end

function rows = local_interval_rows(m, window_entry, horizon_idx, forecast_day, ...
    truth_Rt, alphas, lower_Rt, upper_Rt, coverage, interval_width, wis_components)
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
        strings(num_rows, 1), false(num_rows, 1), false(num_rows, 1), ...
        false(num_rows, 1), strings(num_rows, 1), ...
        strings(num_rows, 1), strings(num_rows, 1), strings(num_rows, 1), ...
        strings(num_rows, 1), strings(num_rows, 1), zeros(num_rows, 1), ...
        zeros(num_rows, 1), zeros(num_rows, 1), zeros(num_rows, 1), ...
        zeros(num_rows, 1), zeros(num_rows, 1), zeros(num_rows, 1), ...
        zeros(num_rows, 1), zeros(num_rows, 1), zeros(num_rows, 1), ...
        strings(num_rows, 1), strings(num_rows, 1), zeros(num_rows, 1), ...
        zeros(num_rows, 1), zeros(num_rows, 1), zeros(num_rows, 1), ...
        zeros(num_rows, 1), zeros(num_rows, 1), zeros(num_rows, 1), ...
        zeros(num_rows, 1), ...
        'VariableNames', {'CaseID', 'CaseName', 'TruthModel', 'Solver', ...
        'StructuralMismatch', 'ObservationNoise', 'ProcessNoise', ...
        'Scenario', 'ScenarioName', 'Model', 'ExoMode', ...
        'ForecastArtifact', 'ResultSource', 'WindowDay', 'WindowDayIdx', ...
        'HorizonIdx', 'ForecastDay', 'Truth_Rt', 'Alpha', 'NominalCoverage', ...
        'LowerBound', 'UpperBound', 'Coverage', 'IntervalMethod', ...
        'IntervalStatus', 'IntervalWidth', 'CoverageError', ...
        'AbsoluteCoverageError', 'IntervalScore', 'WISIntervalComponent', ...
        'WISSharpnessComponent', 'WISUnderpredictionComponent', ...
        'WISOverpredictionComponent'});

    row_idx = 0;
    for j = 1:num_alphas
        idx = row_idx + (1:horizon);
        coverage_error = coverage(:, j) - (1 - alphas(j));
        rows.CaseID(idx) = m.CaseID;
        rows.CaseName(idx) = m.CaseName;
        rows.TruthModel(idx) = m.TruthModel;
        rows.Solver(idx) = m.Solver;
        rows.StructuralMismatch(idx) = m.StructuralMismatch;
        rows.ObservationNoise(idx) = m.ObservationNoise;
        rows.ProcessNoise(idx) = m.ProcessNoise;
        rows.Scenario(idx) = m.Scenario;
        rows.ScenarioName(idx) = m.ScenarioName;
        rows.Model(idx) = m.Model;
        rows.ExoMode(idx) = m.ExoMode;
        rows.ForecastArtifact(idx) = m.ForecastArtifact;
        rows.ResultSource(idx) = m.ResultSource;
        rows.WindowDay(idx) = window_entry.window_day;
        rows.WindowDayIdx(idx) = window_entry.window_day_idx;
        rows.HorizonIdx(idx) = horizon_idx;
        rows.ForecastDay(idx) = forecast_day;
        rows.Truth_Rt(idx) = truth_Rt;
        rows.Alpha(idx) = alphas(j);
        rows.NominalCoverage(idx) = 1 - alphas(j);
        rows.LowerBound(idx) = lower_Rt(:, j);
        rows.UpperBound(idx) = upper_Rt(:, j);
        rows.Coverage(idx) = coverage(:, j);
        rows.IntervalMethod(idx) = string(window_entry.interval_method);
        rows.IntervalStatus(idx) = string(window_entry.interval_status);
        rows.IntervalWidth(idx) = interval_width(:, j);
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

function summary_tables = local_summary_tables(window_scores, pointwise_scores, interval_scores)
%LOCAL_SUMMARY_TABLES Build cross-case Part B summaries.
    summary_tables = struct();
    summary_tables.case_model_summary = local_summarize_window_scores( ...
        window_scores, {'CaseID', 'CaseName', 'TruthModel', 'Solver', ...
        'StructuralMismatch', 'ObservationNoise', 'ProcessNoise', 'Model', 'ExoMode'});
    summary_tables.case_horizon_summary = local_summarize_pointwise_scores( ...
        pointwise_scores, {'CaseID', 'CaseName', 'TruthModel', 'Solver', ...
        'StructuralMismatch', 'ObservationNoise', 'ProcessNoise', 'Model', ...
        'ExoMode', 'HorizonIdx'});
    summary_tables.case_scenario_summary = local_summarize_window_scores( ...
        window_scores, {'CaseID', 'CaseName', 'TruthModel', 'Solver', ...
        'StructuralMismatch', 'ObservationNoise', 'ProcessNoise', 'Scenario', ...
        'ScenarioName', 'Model', 'ExoMode'});
    summary_tables.case_interval_summary = local_summarize_interval_scores( ...
        interval_scores, {'CaseID', 'CaseName', 'TruthModel', 'Solver', ...
        'StructuralMismatch', 'ObservationNoise', 'ProcessNoise', 'Model', ...
        'ExoMode', 'Alpha'});
    summary_tables.case_calibration_summary = summary_tables.case_interval_summary;
    summary_tables.case_wis_component_summary = local_summarize_pointwise_scores( ...
        pointwise_scores, {'CaseID', 'CaseName', 'TruthModel', 'Solver', ...
        'StructuralMismatch', 'ObservationNoise', 'ProcessNoise', 'Model', 'ExoMode'});
end

function summary = local_summarize_window_scores(scores, group_vars)
%LOCAL_SUMMARIZE_WINDOW_SCORES Aggregate window-level metrics.
    if isempty(scores) || height(scores) == 0
        summary = table();
        return;
    end
    [G, keys] = findgroups(scores(:, group_vars));
    summary = keys;
    summary.NumWindows = splitapply(@numel, scores.WindowWIS, G);
    summary.NumValidWindows = splitapply(@(x) sum(logical(x)), scores.IsValid, G);
    summary.MeanWIS = splitapply(@local_mean_finite, scores.WindowWIS, G);
    summary.MedianWIS = splitapply(@local_median_finite, scores.WindowWIS, G);
    summary.StdWIS = splitapply(@local_std_finite, scores.WindowWIS, G);
    summary.MeanRMSE = splitapply(@local_mean_finite, scores.WindowRMSE, G);
    summary.MeanMAE = splitapply(@local_mean_finite, scores.WindowMAE, G);
    summary.MeanCoverage = splitapply(@local_mean_finite, scores.MeanCoverage, G);
    summary.MeanCalibrationBias = splitapply(@local_mean_finite, ...
        scores.MeanCalibrationBias, G);
    summary.MeanAbsoluteCalibrationError = splitapply(@local_mean_finite, ...
        scores.MeanAbsoluteCalibrationError, G);
    summary.MeanIntervalWidth = splitapply(@local_mean_finite, ...
        scores.MeanIntervalWidth, G);
    summary.MeanWISMedianComponent = splitapply(@local_mean_finite, ...
        scores.MeanWISMedianComponent, G);
    summary.MeanWISDispersionComponent = splitapply(@local_mean_finite, ...
        scores.MeanWISDispersionComponent, G);
    summary.MeanWISUnderpredictionComponent = splitapply(@local_mean_finite, ...
        scores.MeanWISUnderpredictionComponent, G);
    summary.MeanWISOverpredictionComponent = splitapply(@local_mean_finite, ...
        scores.MeanWISOverpredictionComponent, G);
end

function summary = local_summarize_pointwise_scores(scores, group_vars)
%LOCAL_SUMMARIZE_POINTWISE_SCORES Aggregate horizon-level metrics.
    if isempty(scores) || height(scores) == 0
        summary = table();
        return;
    end
    [G, keys] = findgroups(scores(:, group_vars));
    summary = keys;
    summary.NumPoints = splitapply(@numel, scores.WIS, G);
    summary.MeanWIS = splitapply(@local_mean_finite, scores.WIS, G);
    summary.MedianWIS = splitapply(@local_median_finite, scores.WIS, G);
    summary.StdWIS = splitapply(@local_std_finite, scores.WIS, G);
    summary.RMSE = sqrt(splitapply(@local_mean_finite, scores.SquaredError, G));
    summary.MAE = splitapply(@local_mean_finite, scores.AbsoluteError, G);
    summary.MeanCoverage = splitapply(@local_mean_finite, scores.CoverageMean, G);
    summary.MeanCalibrationBias = splitapply(@local_mean_finite, ...
        scores.CalibrationBiasMean, G);
    summary.MeanAbsoluteCalibrationError = splitapply(@local_mean_finite, ...
        scores.AbsoluteCalibrationErrorMean, G);
    summary.MeanIntervalWidth = splitapply(@local_mean_finite, ...
        scores.IntervalWidthMean, G);
    summary.MeanWISMedianComponent = splitapply(@local_mean_finite, ...
        scores.WISMedianComponent, G);
    summary.MeanWISDispersionComponent = splitapply(@local_mean_finite, ...
        scores.WISDispersionComponent, G);
    summary.MeanWISUnderpredictionComponent = splitapply(@local_mean_finite, ...
        scores.WISUnderpredictionComponent, G);
    summary.MeanWISOverpredictionComponent = splitapply(@local_mean_finite, ...
        scores.WISOverpredictionComponent, G);
end

function summary = local_summarize_interval_scores(scores, group_vars)
%LOCAL_SUMMARIZE_INTERVAL_SCORES Aggregate interval-level metrics.
    if isempty(scores) || height(scores) == 0
        summary = table();
        return;
    end
    [G, keys] = findgroups(scores(:, group_vars));
    summary = keys;
    summary.NumIntervalPoints = splitapply(@numel, scores.Coverage, G);
    summary.NominalCoverage = splitapply(@local_mean_finite, scores.NominalCoverage, G);
    summary.MeanCoverage = splitapply(@local_mean_finite, scores.Coverage, G);
    summary.CoverageBias = summary.MeanCoverage - summary.NominalCoverage;
    summary.AbsoluteCalibrationError = abs(summary.CoverageBias);
    summary.MeanIntervalWidth = splitapply(@local_mean_finite, ...
        scores.IntervalWidth, G);
    summary.MeanIntervalScore = splitapply(@local_mean_finite, ...
        scores.IntervalScore, G);
    summary.MeanWISIntervalComponent = splitapply(@local_mean_finite, ...
        scores.WISIntervalComponent, G);
    summary.MeanWISSharpnessComponent = splitapply(@local_mean_finite, ...
        scores.WISSharpnessComponent, G);
    summary.MeanWISUnderpredictionComponent = splitapply(@local_mean_finite, ...
        scores.WISUnderpredictionComponent, G);
    summary.MeanWISOverpredictionComponent = splitapply(@local_mean_finite, ...
        scores.WISOverpredictionComponent, G);
end

function [degradation, baseline, status] = local_degradation_summary(cfg, case_model_summary)
%LOCAL_DEGRADATION_SUMMARY Compare Part B cases against Part A when available.
    [baseline, status] = local_load_partA_baseline(cfg);
    if isempty(baseline) || height(baseline) == 0 || isempty(case_model_summary)
        degradation = table();
        warning('EVAL:NoPartABaseline', ...
            'Part A evaluation artifact unavailable or incomplete; degradation summaries skipped.');
        return;
    end

    degradation = case_model_summary;
    n = height(degradation);
    degradation.PartAMeanWIS = nan(n, 1);
    degradation.PartAMeanRMSE = nan(n, 1);
    degradation.PartAMeanCoverage = nan(n, 1);
    degradation.PartAMeanIntervalWidth = nan(n, 1);

    for i = 1:n
        idx = baseline.Model == degradation.Model(i) & ...
            baseline.ExoMode == degradation.ExoMode(i);
        if ~any(idx)
            continue;
        end
        first_idx = find(idx, 1);
        degradation.PartAMeanWIS(i) = baseline.PartAMeanWIS(first_idx);
        degradation.PartAMeanRMSE(i) = baseline.PartAMeanRMSE(first_idx);
        degradation.PartAMeanCoverage(i) = baseline.PartAMeanCoverage(first_idx);
        degradation.PartAMeanIntervalWidth(i) = ...
            baseline.PartAMeanIntervalWidth(first_idx);
    end

    degradation.DeltaMeanWIS = degradation.MeanWIS - degradation.PartAMeanWIS;
    degradation.RelativeMeanWIS = degradation.MeanWIS ./ degradation.PartAMeanWIS;
    degradation.DeltaRMSE = degradation.MeanRMSE - degradation.PartAMeanRMSE;
    degradation.DeltaCoverage = degradation.MeanCoverage - degradation.PartAMeanCoverage;
    degradation.DeltaIntervalWidth = degradation.MeanIntervalWidth - ...
        degradation.PartAMeanIntervalWidth;
end

function [baseline, status] = local_load_partA_baseline(cfg)
%LOCAL_LOAD_PARTA_BASELINE Load Part A model summary when available.
    artifact_path = fullfile(cfg.output.partA_evaluation_dir, ...
        'partA_04_evaluation_results.mat');
    status = struct('available', false, 'artifact_path', string(artifact_path), ...
        'message', "");
    baseline = table();

    if exist(artifact_path, 'file') ~= 2
        status.message = "missing_partA_evaluation_artifact";
        return;
    end

    loaded = load(artifact_path);
    if ~isfield(loaded, 'summaries') || ...
            ~isfield(loaded.summaries, 'model_summary')
        status.message = "missing_partA_model_summary";
        return;
    end

    model_summary = loaded.summaries.model_summary;
    required = {'Model', 'ExoMode', 'MeanWIS'};
    if ~all(ismember(required, model_summary.Properties.VariableNames))
        status.message = "invalid_partA_model_summary";
        return;
    end

    baseline = table(string(model_summary.Model), string(model_summary.ExoMode), ...
        double(model_summary.MeanWIS), ...
        local_table_numeric(model_summary, 'MeanRMSE'), ...
        local_table_numeric(model_summary, 'MeanCoverage'), ...
        local_table_numeric(model_summary, 'MeanIntervalWidth'), ...
        'VariableNames', {'Model', 'ExoMode', 'PartAMeanWIS', ...
        'PartAMeanRMSE', 'PartAMeanCoverage', 'PartAMeanIntervalWidth'});
    status.available = true;
    status.message = "loaded";
end

function values = local_table_numeric(table_data, var_name)
%LOCAL_TABLE_NUMERIC Read a numeric table variable or NaNs.
    if ismember(var_name, table_data.Properties.VariableNames)
        values = double(table_data.(var_name));
    else
        values = nan(height(table_data), 1);
    end
end

function outputs = local_write_cross_tables(table_dir, metrics, summary_tables, ...
    selection_summary, degradation_status)
%LOCAL_WRITE_CROSS_TABLES Persist cross-case tables.
    if ~exist(table_dir, 'dir'), mkdir(table_dir); end
    prefix = 'partB_robustness_ladder';
    outputs = strings(0, 1);
    outputs(end + 1, 1) = local_write_table(table_dir, ...
        sprintf('%s_window_scores.csv', prefix), metrics.window_scores);
    outputs(end + 1, 1) = local_write_table(table_dir, ...
        sprintf('%s_pointwise_scores.csv', prefix), metrics.pointwise_scores);
    outputs(end + 1, 1) = local_write_table(table_dir, ...
        sprintf('%s_interval_scores.csv', prefix), metrics.interval_scores);
    outputs(end + 1, 1) = local_write_table(table_dir, ...
        sprintf('%s_case_model_summary.csv', prefix), summary_tables.case_model_summary);
    outputs(end + 1, 1) = local_write_table(table_dir, ...
        sprintf('%s_case_horizon_summary.csv', prefix), summary_tables.case_horizon_summary);
    outputs(end + 1, 1) = local_write_table(table_dir, ...
        sprintf('%s_case_scenario_summary.csv', prefix), summary_tables.case_scenario_summary);
    outputs(end + 1, 1) = local_write_table(table_dir, ...
        sprintf('%s_case_interval_summary.csv', prefix), summary_tables.case_interval_summary);
    outputs(end + 1, 1) = local_write_table(table_dir, ...
        sprintf('%s_case_calibration_summary.csv', prefix), summary_tables.case_calibration_summary);
    outputs(end + 1, 1) = local_write_table(table_dir, ...
        sprintf('%s_case_wis_component_summary.csv', prefix), ...
        summary_tables.case_wis_component_summary);
    outputs(end + 1, 1) = local_write_table(table_dir, ...
        sprintf('%s_degradation_summary.csv', prefix), summary_tables.degradation_summary);
    outputs(end + 1, 1) = local_write_table(table_dir, ...
        sprintf('%s_partA_baseline_summary.csv', prefix), summary_tables.partA_baseline_summary);
    outputs(end + 1, 1) = local_write_table(table_dir, ...
        sprintf('%s_selection_summary.csv', prefix), selection_summary);
    outputs(end + 1, 1) = local_write_table(table_dir, ...
        sprintf('%s_degradation_status.csv', prefix), struct2table(degradation_status));
end

function outputs = local_write_case_tables(cfg, metrics)
%LOCAL_WRITE_CASE_TABLES Persist case-specific tables under case folders.
    case_ids = unique(metrics.window_scores.CaseID, 'stable');
    outputs = strings(0, 1);
    for i = 1:numel(case_ids)
        this_case = case_ids(i);
        table_dir = cfg.output.table_dir;

        w_idx = metrics.window_scores.CaseID == this_case;
        p_idx = metrics.pointwise_scores.CaseID == this_case;
        int_idx = metrics.interval_scores.CaseID == this_case;

        case_metrics = struct( ...
            'window_scores', metrics.window_scores(w_idx, :), ...
            'pointwise_scores', metrics.pointwise_scores(p_idx, :), ...
            'interval_scores', metrics.interval_scores(int_idx, :));
        case_summary = local_summary_tables(case_metrics.window_scores, ...
            case_metrics.pointwise_scores, case_metrics.interval_scores);
        prefix = sprintf('partB_%s', char(this_case));

        outputs(end + 1, 1) = local_write_table(table_dir, ...
            sprintf('%s_window_scores.csv', prefix), case_metrics.window_scores); %#ok<AGROW>
        outputs(end + 1, 1) = local_write_table(table_dir, ...
            sprintf('%s_pointwise_scores.csv', prefix), case_metrics.pointwise_scores); %#ok<AGROW>
        outputs(end + 1, 1) = local_write_table(table_dir, ...
            sprintf('%s_interval_scores.csv', prefix), case_metrics.interval_scores); %#ok<AGROW>
        outputs(end + 1, 1) = local_write_table(table_dir, ...
            sprintf('%s_case_model_summary.csv', prefix), case_summary.case_model_summary); %#ok<AGROW>
        outputs(end + 1, 1) = local_write_table(table_dir, ...
            sprintf('%s_case_horizon_summary.csv', prefix), case_summary.case_horizon_summary); %#ok<AGROW>
    end
end

function output_path = local_write_table(table_dir, filename, table_data)
%LOCAL_WRITE_TABLE Write one CSV table.
    output_path = fullfile(table_dir, filename);
    writetable(table_data, output_path);
    fprintf('Table saved to: %s\n', output_path);
end

function cfg_snapshot = local_cfg_snapshot(cfg)
%LOCAL_CFG_SNAPSHOT Store relevant evaluation configuration.
    cfg_snapshot = struct();
    cfg_snapshot.experiment_id = cfg.experiment_id;
    cfg_snapshot.experiment_name = cfg.experiment_name;
    cfg_snapshot.forecast = cfg.forecast;
    cfg_snapshot.output = cfg.output;
    cfg_snapshot.intervals = cfg.intervals;
    cfg_snapshot.fixed_forecast_cases = cfg.fixed_forecast_cases;
    cfg_snapshot.robustness_cases = cfg.robustness_cases;
    cfg_snapshot.smoke_test = cfg.smoke_test;
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

function value = local_loaded_string(s, field_name, default_value)
%LOCAL_LOADED_STRING Read a top-level string field with fallback.
    value = string(default_value);
    if isfield(s, field_name) && ~isempty(s.(field_name))
        value = string(s.(field_name));
    end
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

function value = local_median_finite(values)
%LOCAL_MEDIAN_FINITE Median over finite numeric values only.
    values = double(values(:));
    values = values(isfinite(values));
    if isempty(values)
        value = nan;
    else
        value = median(values);
    end
end

function value = local_std_finite(values)
%LOCAL_STD_FINITE Standard deviation over finite numeric values only.
    values = double(values(:));
    values = values(isfinite(values));
    if numel(values) <= 1
        value = nan;
    else
        value = std(values);
    end
end

function dir_path = local_case_evaluation_dir(cfg, ~)
%LOCAL_CASE_EVALUATION_DIR Return the shared Part B evaluation directory.
    dir_path = cfg.output.evaluation_dir;
end
