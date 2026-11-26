%PARTA_04_EVALUATE_FORECASTS Evaluate Part A selection and forecast evidence.
%
%   Description:
%       Checks every Part A selection and forecast artifact against the
%       current configuration and selection identities, then scores the
%       cross-scenario transfer forecasts and the independent assessment
%       forecasts with WIS, point errors, and interval diagnostics alongside
%       the deterministic Rt persistence reference. Losses are aggregated
%       from forecast lead to origin, trajectory, scenario family, and the
%       equal-family global mean. The idealised infectious-population
%       projections of the assessment stage are evaluated, and selection,
%       candidate, trajectory, and feasibility diagnostics are exported.
%       Configurations without artifacts are reported as missing.
%
%   Workflow:
%       1. Initialize the evaluation paths.
%       2. Check and load the compatible Part A artifacts.
%       3. Score the forecasts and the persistence reference.
%       4. Summarise the model-selection evidence.
%       5. Aggregate the scores hierarchically.
%       6. Save the evaluation artifact and tables.
%
%   See also PARTA_CONFIG, PARTA_02_SELECT_HYPERPARAMETERS,
%            PARTA_03_RUN_FORECASTS, PARTA_05_GENERATE_FIGURES, COMPUTE_WIS,
%            COMPUTE_POINT_ERROR, COMPUTE_INTERVAL_DIAGNOSTICS,
%            COMPUTE_STRATIFIED_MEAN.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-11-26

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Forecast Evaluation ===\n');

cfg            = partA_config();
evaluation_dir = cfg.output.score_dir;
table_dir      = cfg.output.table_dir;

if ~exist(evaluation_dir, 'dir'), mkdir(evaluation_dir); end
if ~exist(table_dir, 'dir'), mkdir(table_dir); end

%% 2. Artifact Compatibility and Loading
incompatible = local_incompatible_artifacts(cfg);

if ~isempty(incompatible)
    error('PARTA_04:IncompatibleArtifact', 'These Part A artifacts were produced under a different configuration or artifact schema: %s. Rerun the affected configurations or use ./run_partA_pipeline.sh --fresh.', strjoin(incompatible, ', '));
end

[selections, forecast_artifacts, coverage] = local_load_artifacts(cfg);

if isempty(forecast_artifacts)
    error('PARTA_04:NoForecastArtifacts', 'No Part A forecast artifacts found under %s. Run partA_02 and partA_03 first.', cfg.output.forecast_dir);
end

is_complete = all(coverage{:, ["Selection", "Transfer", "Assessment"]}, 'all');

fprintf('Artifacts: selection %d/%d, transfer %d/%d, assessment %d/%d configurations\n', sum(coverage.Selection), height(coverage), sum(coverage.Transfer), height(coverage), sum(coverage.Assessment), height(coverage));

if ~is_complete
    fprintf('Evaluation covers an incomplete set of configurations; see the coverage table.\n');
end

%% 3. Forecast and Persistence Scoring
[window_scores, horizon_scores, interval_scores, i_projection_window_scores, i_projection_horizon_scores] = local_score_forecasts(forecast_artifacts, cfg.forecast.wis_alphas);

fprintf('Scored %d forecast origins (%d available) and %d infectious-projection origins.\n', height(window_scores), sum(window_scores.Status == "ok"), height(i_projection_window_scores));

%% 4. Model-Selection Evidence
[candidate_diagnostics, selection_summary, selection_trajectories, selection_feasibility] = local_selection_tables(selections);

%% 5. Hierarchical Aggregation
trajectory_summary = [selection_trajectories; local_trajectory_summary(window_scores)];
forecast_feasibility = local_forecast_feasibility(window_scores(window_scores.Model ~= "Persistence", :));
feasibility_summary  = [selection_feasibility; forecast_feasibility];

summaries = struct();
summaries.scenario_summary = local_scenario_summary(trajectory_summary);

ok_horizon = horizon_scores(horizon_scores.Status == "ok", :);
summaries.horizon_summary = renamevars(local_hierarchical_means(ok_horizon, ["Stage", "ConfigurationRole", "Model", "ExoMode", "HorizonIdx"], ["WIS", "AbsoluteError", "SquaredError", "MeanCoverage", "MeanIntervalWidth"]), ["WIS", "AbsoluteError", "SquaredError"], ["MeanWIS", "MeanAbsoluteError", "MeanSquaredError"]);

summaries.interval_summary = renamevars(local_hierarchical_means(interval_scores, ["Stage", "ConfigurationRole", "Model", "ExoMode", "Alpha", "NominalCoverage"], ["Coverage", "IntervalWidth"]), ["Coverage", "IntervalWidth"], ["MeanCoverage", "MeanIntervalWidth"]);

ok_projection = i_projection_window_scores(i_projection_window_scores.Status == "ok", :);
projection_values = ["ForecastDrivenRMSE", "ForecastDrivenMAE", "PersistenceRtRMSE", "PersistenceRtMAE"];
[projection_overall, projection_by_stratum] = local_hierarchical_means(ok_projection, ["Stage", "Model", "ExoMode"], projection_values);
summaries.i_projection_scenario_summary = local_append_overall(projection_by_stratum, projection_overall);
summaries.i_projection_scenario_summary.RMSEImprovement = summaries.i_projection_scenario_summary.PersistenceRtRMSE - summaries.i_projection_scenario_summary.ForecastDrivenRMSE;
summaries.i_projection_scenario_summary.MAEImprovement  = summaries.i_projection_scenario_summary.PersistenceRtMAE - summaries.i_projection_scenario_summary.ForecastDrivenMAE;

ok_projection_horizon = i_projection_horizon_scores(i_projection_horizon_scores.Status == "ok", :);
summaries.i_projection_horizon_summary = renamevars(local_hierarchical_means(ok_projection_horizon, ["Stage", "Model", "ExoMode", "HorizonIdx"], ["ForecastDrivenAbsoluteError", "PersistenceRtAbsoluteError"]), ["ForecastDrivenAbsoluteError", "PersistenceRtAbsoluteError"], ["MeanForecastDrivenAbsoluteError", "MeanPersistenceRtAbsoluteError"]);
summaries.i_projection_horizon_summary.MeanAbsoluteErrorImprovement = summaries.i_projection_horizon_summary.MeanPersistenceRtAbsoluteError - summaries.i_projection_horizon_summary.MeanForecastDrivenAbsoluteError;

%% 6. Artifact and Table Saving
evaluation_artifact = fullfile(evaluation_dir, 'partA_04_evaluation_results.mat');
snapshot = cfg.snapshot.design;
created  = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

save(evaluation_artifact, 'window_scores', 'horizon_scores', 'interval_scores', 'i_projection_window_scores', 'i_projection_horizon_scores', 'trajectory_summary', 'candidate_diagnostics', 'selection_summary', 'feasibility_summary', 'summaries', 'coverage', 'is_complete', 'snapshot', 'created');

fprintf('Evaluation artifact saved to: %s\n', evaluation_artifact);

local_write_table(table_dir, 'partA_04_window_scores.csv', window_scores);
local_write_table(table_dir, 'partA_04_horizon_scores.csv', horizon_scores);
local_write_table(table_dir, 'partA_04_scenario_summary.csv', summaries.scenario_summary);
local_write_table(table_dir, 'partA_04_horizon_summary.csv', summaries.horizon_summary);
local_write_table(table_dir, 'partA_04_interval_summary.csv', summaries.interval_summary);
local_write_table(table_dir, 'partA_04_i_projection_window_scores.csv', i_projection_window_scores);
local_write_table(table_dir, 'partA_04_i_projection_horizon_scores.csv', i_projection_horizon_scores);
local_write_table(table_dir, 'partA_04_i_projection_scenario_summary.csv', summaries.i_projection_scenario_summary);
local_write_table(table_dir, 'partA_04_i_projection_horizon_summary.csv', summaries.i_projection_horizon_summary);
local_write_table(table_dir, 'partA_04_selection_summary.csv', selection_summary);
local_write_table(table_dir, 'partA_04_candidate_diagnostics.csv', candidate_diagnostics);
local_write_table(table_dir, 'partA_04_trajectory_summary.csv', trajectory_summary);
local_write_table(table_dir, 'partA_04_feasibility_summary.csv', feasibility_summary);

fprintf('=== Part A Forecast Evaluation Complete ===\n\n');

%% 7. Local Functions
function incompatible = local_incompatible_artifacts(cfg)
%LOCAL_INCOMPATIBLE_ARTIFACTS List Part A artifacts whose snapshot differs from the current configuration.
files = [dir(fullfile(cfg.output.model_selection_dir, 'partA_*.mat')); dir(fullfile(cfg.output.forecast_dir, 'partA_*.mat'))];
incompatible = strings(0, 1);

for i = 1:numel(files)
    name   = string(files(i).name);
    loaded = load(fullfile(files(i).folder, files(i).name), 'snapshot');

    if startsWith(name, "partA_02_forecast_") || startsWith(name, "partA_03_forecast_")
        expected = cfg.snapshot.forecast;
    else
        expected = cfg.snapshot.selection;
    end

    expected.model_type = loaded.snapshot.model_type;
    expected.exo_mode   = loaded.snapshot.exo_mode;

    if ~isequaln(loaded.snapshot, expected)
        incompatible(end + 1, 1) = name;
    end
end
end

function [selections, forecast_artifacts, coverage] = local_load_artifacts(cfg)
%LOCAL_LOAD_ARTIFACTS Load each configuration's artifacts and require one selection identity per configuration.
configurations = cfg.run.valid_configurations;
num_configs    = size(configurations, 1);
coverage       = table(configurations(:, 1), configurations(:, 2), false(num_configs, 1), false(num_configs, 1), false(num_configs, 1), 'VariableNames', {'Model', 'ExoMode', 'Selection', 'Transfer', 'Assessment'});

selections         = cell(0, 1);
forecast_artifacts = cell(0, 1);

for c = 1:num_configs
    suffix = configurations(c, 1) + "_" + configurations(c, 2);
    paths  = [
        fullfile(cfg.output.model_selection_dir, "partA_02_development_" + suffix + ".mat");
        fullfile(cfg.output.model_selection_dir, "partA_02_refinement_" + suffix + ".mat");
        fullfile(cfg.output.model_selection_dir, "partA_02_global_hyperparameters_" + suffix + ".mat");
        fullfile(cfg.output.forecast_dir, "partA_02_forecast_transfer_" + suffix + ".mat");
        fullfile(cfg.output.forecast_dir, "partA_03_forecast_assessment_" + suffix + ".mat")];
    present = isfile(paths);

    if ~any(present)
        continue;
    end

    if ~all(present(1:4))
        error('PARTA_04:IncompleteSelection', 'The selection artifacts of %s are incomplete (its last partA_02 run stopped, for example without a feasible candidate); missing: %s. Rerun partA_02 for this configuration or remove its artifacts.', suffix, strjoin(paths(~present(1:4)), ', '));
    end

    development = load(paths(1));
    refinement  = load(paths(2));
    handover    = load(paths(3));
    transfer    = load(paths(4));

    if any([development.selection_id, refinement.selection_id, transfer.selection_id] ~= handover.selection_id)
        error('PARTA_04:InconsistentSelection', 'The selection artifacts of %s come from different partA_02 runs. Rerun partA_02 for this configuration.', suffix);
    end

    selections{end + 1, 1} = struct('model_type', configurations(c, 1), 'exo_mode', configurations(c, 2), 'development', development, 'refinement', refinement);
    forecast_artifacts{end + 1, 1} = transfer;
    coverage.Selection(c) = true;
    coverage.Transfer(c)  = true;

    if present(5)
        assessment = load(paths(5));

        if assessment.selection_id ~= handover.selection_id || ~isequal(assessment.configuration, handover.selected_configuration)
            error('PARTA_04:StaleAssessment', 'The assessment artifact of %s was generated from an earlier selection (%s, current %s). Rerun partA_03 for this configuration.', suffix, assessment.selection_id, handover.selection_id);
        end

        forecast_artifacts{end + 1, 1} = assessment;
        coverage.Assessment(c) = true;
    end
end
end

function [window_scores, horizon_scores, interval_scores, i_projection_window_scores, i_projection_horizon_scores] = local_score_forecasts(forecast_artifacts, alphas)
%LOCAL_SCORE_FORECASTS Score every forecast artifact and, once per stage, the persistence reference.
window_blocks     = cell(0, 1);
horizon_blocks    = cell(0, 1);
interval_blocks   = cell(0, 1);
projection_blocks = cell(0, 1);
projection_h_blocks = cell(0, 1);
reference_stages  = strings(0, 1);

for a = 1:numel(forecast_artifacts)
    artifact = forecast_artifacts{a};
    meta     = struct('stage', artifact.stage, 'role', artifact.configuration_role, 'model', artifact.model_type, 'exo', artifact.exo_mode, 'configuration', string(mat2str(artifact.configuration)));

    for j = 1:numel(artifact.forecasts)
        forecast = artifact.forecasts(j);

        [window_blocks{end + 1, 1}, horizon_blocks{end + 1, 1}, interval_blocks{end + 1, 1}] = local_score_trajectory(meta, forecast, alphas);

        if artifact.stage == "assessment"
            [projection_blocks{end + 1, 1}, projection_h_blocks{end + 1, 1}] = local_score_projection(meta, forecast);
        end
    end

    if ~any(reference_stages == artifact.stage)
        reference_stages(end + 1, 1) = artifact.stage;
        reference_meta = struct('stage', artifact.stage, 'role', "reference", 'model', "Persistence", 'exo', "None", 'configuration', "R_T");

        for j = 1:numel(artifact.forecasts)
            [window_blocks{end + 1, 1}, horizon_blocks{end + 1, 1}] = local_score_trajectory(reference_meta, local_persistence_forecast(artifact.forecasts(j), numel(alphas)), alphas);
        end
    end
end

window_scores              = vertcat(window_blocks{:});
horizon_scores             = vertcat(horizon_blocks{:});
interval_scores            = vertcat(interval_blocks{:});
i_projection_window_scores = vertcat(projection_blocks{:});
i_projection_horizon_scores = vertcat(projection_h_blocks{:});

if isempty(projection_blocks)
    i_projection_window_scores  = local_empty_projection_table(true);
    i_projection_horizon_scores = local_empty_projection_table(false);
end
end

function reference = local_persistence_forecast(forecast, K)
%LOCAL_PERSISTENCE_FORECAST Degenerate predictive distribution at the origin Rt for every lead.
[H, W] = size(forecast.truth_Rt);
median_Rt = repmat(forecast.origin_Rt.', H, 1);

reference = forecast;
reference.status                  = repmat("ok", W, 1);
reference.error_id                = strings(W, 1);
reference.forecast_median         = median_Rt;
reference.forecast_lower          = repmat(reshape(median_Rt, H, 1, W), 1, K, 1);
reference.forecast_upper          = reference.forecast_lower;
reference.aicc                    = nan(W, 1);
reference.spectral_radius         = nan(W, 1);
reference.iteration_limit_reached = false(W, 1);
end

function [window_tbl, horizon_tbl, interval_tbl] = local_score_trajectory(meta, forecast, alphas)
%LOCAL_SCORE_TRAJECTORY Score the Rt forecasts of one trajectory at every available origin.
[H, W] = size(forecast.truth_Rt);
K      = numel(alphas);
ok     = forecast.status == "ok";
Wk     = nnz(ok);

truth = forecast.truth_Rt(:, ok);
pred  = forecast.forecast_median(:, ok);
lower = reshape(permute(forecast.forecast_lower(:, :, ok), [1, 3, 2]), H * Wk, K);
upper = reshape(permute(forecast.forecast_upper(:, :, ok), [1, 3, 2]), H * Wk, K);

wis      = compute_wis(truth(:), pred(:), lower, upper, alphas);
point    = compute_point_error(truth(:), pred(:));
interval = compute_interval_diagnostics(truth(:), lower, upper, alphas);

window_wis   = nan(W, 1);
window_mae   = nan(W, 1);
window_rmse  = nan(W, 1);
window_cover = nan(W, 1);
window_width = nan(W, 1);

window_wis(ok)   = mean(reshape(wis, H, Wk), 1).';
window_mae(ok)   = mean(reshape(point.absolute_error, H, Wk), 1).';
window_rmse(ok)  = sqrt(mean(reshape(point.squared_error, H, Wk), 1)).';
window_cover(ok) = mean(reshape(interval.coverage_mean, H, Wk), 1).';
window_width(ok) = mean(reshape(interval.width_mean, H, Wk), 1).';

window_tbl = [local_id_columns(meta, forecast, W), table(forecast.window_day, forecast.window_idx, forecast.status, forecast.error_id, window_wis, window_rmse, window_mae, window_cover, window_width, forecast.aicc, forecast.spectral_radius, forecast.iteration_limit_reached, 'VariableNames', {'WindowDay', 'WindowIdx', 'Status', 'ErrorId', 'WindowWIS', 'WindowRMSE', 'WindowMAE', 'MeanCoverage', 'MeanIntervalWidth', 'AICc', 'SpectralRadius', 'IterationLimitReached'})];

window_day  = repelem(forecast.window_day(ok), H, 1);
horizon_idx = repmat((1:H)', Wk, 1);

horizon_tbl = [local_id_columns(meta, forecast, H * Wk), table(window_day, horizon_idx, window_day + horizon_idx, repmat("ok", H * Wk, 1), truth(:), pred(:), point.error, point.absolute_error, point.squared_error, wis, interval.coverage_mean, interval.width_mean, 'VariableNames', {'WindowDay', 'HorizonIdx', 'ForecastDay', 'Status', 'Truth_Rt', 'Median_Forecast', 'Error', 'AbsoluteError', 'SquaredError', 'WIS', 'MeanCoverage', 'MeanIntervalWidth'})];

window_coverage = reshape(mean(reshape(double(interval.coverage), H, Wk, K), 1), Wk, K);
window_widths   = reshape(mean(reshape(interval.interval_width, H, Wk, K), 1), Wk, K);

interval_tbl = [local_id_columns(meta, forecast, Wk * K), table(repmat(forecast.window_day(ok), K, 1), repelem(alphas, Wk, 1), repelem(1 - alphas, Wk, 1), window_coverage(:), window_widths(:), 'VariableNames', {'WindowDay', 'Alpha', 'NominalCoverage', 'Coverage', 'IntervalWidth'})];
end

function [window_tbl, horizon_tbl] = local_score_projection(meta, forecast)
%LOCAL_SCORE_PROJECTION Score the idealised infectious-population projections of one trajectory.
[H, W] = size(forecast.truth_I);
ok     = forecast.status == "ok";
Wk     = nnz(ok);

forecast_point    = compute_point_error(forecast.truth_I(:), forecast.projected_I(:));
persistence_point = compute_point_error(forecast.truth_I(:), forecast.persistence_I(:));

forecast_abs    = reshape(forecast_point.absolute_error, H, W);
persistence_abs = reshape(persistence_point.absolute_error, H, W);

window_tbl = [local_id_columns(meta, forecast, W), table(forecast.window_day, forecast.status, sqrt(mean(forecast_abs.^2, 1)).', mean(forecast_abs, 1).', sqrt(mean(persistence_abs.^2, 1)).', mean(persistence_abs, 1).', 'VariableNames', {'WindowDay', 'Status', 'ForecastDrivenRMSE', 'ForecastDrivenMAE', 'PersistenceRtRMSE', 'PersistenceRtMAE'})];

window_day  = repelem(forecast.window_day(ok), H, 1);
horizon_idx = repmat((1:H)', Wk, 1);
truth_I     = forecast.truth_I(:, ok);
projected_I = forecast.projected_I(:, ok);
persist_I   = forecast.persistence_I(:, ok);
forecast_ok = forecast_abs(:, ok);
persist_ok  = persistence_abs(:, ok);

horizon_tbl = [local_id_columns(meta, forecast, H * Wk), table(window_day, horizon_idx, window_day + horizon_idx, repmat("ok", H * Wk, 1), truth_I(:), projected_I(:), persist_I(:), forecast_ok(:), persist_ok(:), 'VariableNames', {'WindowDay', 'HorizonIdx', 'ForecastDay', 'Status', 'Truth_I', 'ForecastDriven_I', 'PersistenceRt_I', 'ForecastDrivenAbsoluteError', 'PersistenceRtAbsoluteError'})];
end

function ids = local_id_columns(meta, forecast, n)
%LOCAL_ID_COLUMNS Stage, configuration, and trajectory identity columns repeated over n rows.
ids = table(repmat(meta.stage, n, 1), repmat(meta.role, n, 1), repmat(meta.model, n, 1), repmat(meta.exo, n, 1), repmat(meta.configuration, n, 1), repmat(forecast.family, n, 1), repmat(forecast.stratum, n, 1), repmat(forecast.dataset_id, n, 1), repmat(forecast.is_canonical, n, 1), 'VariableNames', {'Stage', 'ConfigurationRole', 'Model', 'ExoMode', 'Configuration', 'Family', 'Stratum', 'DatasetId', 'IsCanonical'});
end

function tbl = local_empty_projection_table(window_level)
%LOCAL_EMPTY_PROJECTION_TABLE Zero-row projection table when no assessment artifact exists.
id_names = {'Stage', 'ConfigurationRole', 'Model', 'ExoMode', 'Configuration', 'Family', 'Stratum', 'DatasetId', 'IsCanonical'};

if window_level
    names = [id_names, {'WindowDay', 'Status', 'ForecastDrivenRMSE', 'ForecastDrivenMAE', 'PersistenceRtRMSE', 'PersistenceRtMAE'}];
    types = [repmat({'string'}, 1, 8), {'logical', 'double', 'string', 'double', 'double', 'double', 'double'}];
else
    names = [id_names, {'WindowDay', 'HorizonIdx', 'ForecastDay', 'Status', 'Truth_I', 'ForecastDriven_I', 'PersistenceRt_I', 'ForecastDrivenAbsoluteError', 'PersistenceRtAbsoluteError'}];
    types = [repmat({'string'}, 1, 8), {'logical', 'double', 'double', 'double', 'string', 'double', 'double', 'double', 'double', 'double'}];
end

tbl = table('Size', [0, numel(names)], 'VariableTypes', types, 'VariableNames', names);
end

function [candidate_tbl, summary_tbl, trajectory_tbl, feasibility_tbl] = local_selection_tables(selections)
%LOCAL_SELECTION_TABLES Candidate, selection, trajectory, and feasibility evidence of both selection stages.
candidate_blocks   = cell(0, 1);
summary_blocks     = cell(0, 1);
trajectory_blocks  = cell(0, 1);
feasibility_blocks = cell(0, 1);

for s = 1:numel(selections)
    entry = selections{s};

    stages = struct('name', {"development"; "refinement"}, 'evidence', {entry.development; entry.refinement}, 'preliminary_index', {entry.development.selection.selected_index; entry.refinement.preliminary_index});

    for k = 1:numel(stages)
        evidence          = stages(k).evidence;
        preliminary_index = stages(k).preliminary_index;
        selected_index    = evidence.selection.selected_index;

        candidate_blocks{end + 1, 1}   = local_candidate_table(entry.model_type, entry.exo_mode, stages(k).name, evidence, preliminary_index);
        summary_blocks{end + 1, 1}     = local_selection_row(entry.model_type, entry.exo_mode, stages(k).name, evidence, preliminary_index);
        feasibility_blocks{end + 1, 1} = local_selection_feasibility(entry.model_type, entry.exo_mode, stages(k).name, evidence);
        trajectory_blocks{end + 1, 1}  = local_selection_trajectories(entry.model_type, entry.exo_mode, stages(k).name, "preliminary", evidence, preliminary_index);

        if stages(k).name == "refinement"
            trajectory_blocks{end + 1, 1} = local_selection_trajectories(entry.model_type, entry.exo_mode, stages(k).name, "final", evidence, selected_index);
        end
    end
end

candidate_tbl   = vertcat(candidate_blocks{:});
summary_tbl     = vertcat(summary_blocks{:});
trajectory_tbl  = vertcat(trajectory_blocks{:});
feasibility_tbl = vertcat(feasibility_blocks{:});
end

function tbl = local_candidate_table(model, exo, stage, evidence, preliminary_index)
%LOCAL_CANDIDATE_TABLE One row of selection evidence per evaluated candidate.
grid       = evidence.candidate_grid;
evaluation = evidence.evaluation;
selection  = evidence.selection;
[C, J, W]  = size(evaluation.status);

configuration   = strings(C, 1);
mean_mae        = nan(C, 1);
mean_rmse       = nan(C, 1);
mean_aicc       = nan(C, 1);
unstable        = nan(C, 1);
iteration_limit = nan(C, 1);
failure_dataset = strings(C, 1);
failure_day     = nan(C, 1);
failure_id      = strings(C, 1);

for c = 1:C
    configuration(c) = string(mat2str(grid(c, :)));
    status           = reshape(evaluation.status(c, :, :), J, W);
    ok               = status == "ok";

    if evidence.feasible(c)
        mean_mae(c)  = compute_stratified_mean(mean(reshape(evaluation.mae(c, :, :), J, W), 2), evidence.strata, evidence.is_random);
        mean_rmse(c) = compute_stratified_mean(mean(reshape(evaluation.rmse(c, :, :), J, W), 2), evidence.strata, evidence.is_random);
    end

    if any(ok, 'all')
        aicc            = reshape(evaluation.aicc(c, :, :), J, W);
        radius          = reshape(evaluation.spectral_radius(c, :, :), J, W);
        limit           = reshape(evaluation.iteration_limit_reached(c, :, :), J, W);
        mean_aicc(c)    = mean(aicc(ok));
        unstable(c)     = mean(radius(ok) >= 1);
        iteration_limit(c) = mean(limit(ok));
    end

    first_failure = find(status.' == "infeasible", 1);
    if ~isempty(first_failure)
        [w, j] = ind2sub([W, J], first_failure);
        failure_dataset(c) = evidence.dataset_ids(j);
        failure_day(c)     = evidence.window_days(w);
        failure_id(c)      = evaluation.error_id(c, j, w);
    end
end

counts = @(value) sum(evaluation.status == value, [2, 3]);
index  = (1:C)';

tbl = table(repmat(model, C, 1), repmat(exo, C, 1), repmat(stage, C, 1), index, configuration, evidence.complexity, evidence.max_lag, evidence.feasible, selection.global_score, selection.global_se, mean_mae, mean_rmse, mean_aicc, counts("ok"), counts("infeasible"), counts("not_evaluated"), failure_dataset, failure_day, failure_id, unstable, iteration_limit, selection.eligible(:, 1), index == selection.selected_index, index == selection.best_index, index == preliminary_index, 'VariableNames', {'Model', 'ExoMode', 'SelectionStage', 'CandidateIndex', 'Configuration', 'Complexity', 'MaxLag', 'Feasible', 'GlobalWIS', 'GlobalSE', 'MeanMAE', 'MeanRMSE', 'MeanAICc', 'NumOk', 'NumInfeasible', 'NumNotEvaluated', 'FirstFailureDataset', 'FirstFailureDay', 'FirstFailureId', 'UnstableFitFraction', 'IterationLimitFraction', 'Eligible', 'Selected', 'IsMinimumWIS', 'IsPreliminary'});
end

function row = local_selection_row(model, exo, stage, evidence, preliminary_index)
%LOCAL_SELECTION_ROW Summary of one one-SE selection, its threshold sensitivity, and the preliminary configuration.
selection = evidence.selection;
grid      = evidence.candidate_grid;
selected  = selection.selected_index;

row = table(model, exo, stage, size(grid, 1), nnz(evidence.feasible), nnz(selection.eligible(:, 1)), string(mat2str(grid(selection.best_index, :))), selection.best_score, selection.se, selection.threshold, string(mat2str(grid(selected, :))), selection.global_score(selected), evidence.complexity(selected), selection.minimum_on_grid_boundary, selection.selected_on_grid_boundary, string(mat2str(grid(preliminary_index, :))), selection.global_score(preliminary_index), evidence.complexity(preliminary_index), evidence.complexity(selected) - evidence.complexity(preliminary_index), 'VariableNames', {'Model', 'ExoMode', 'SelectionStage', 'NumCandidates', 'NumFeasible', 'NumEligible', 'MinimumWISConfiguration', 'MinimumWIS', 'SE', 'Threshold', 'SelectedConfiguration', 'SelectedWIS', 'SelectedComplexity', 'MinimumOnGridBoundary', 'SelectedOnGridBoundary', 'PreliminaryConfiguration', 'PreliminaryWIS', 'PreliminaryComplexity', 'ComplexityChange'});

for m = 1:numel(selection.multipliers)
    row.("SelectedAt" + replace(string(selection.multipliers(m)), ".", "p") + "SE") = string(mat2str(grid(selection.selected_indices(m), :)));
end
end

function tbl = local_selection_trajectories(model, exo, stage, role, evidence, index)
%LOCAL_SELECTION_TRAJECTORIES Trajectory means of one candidate's selection-stage scores over its available origins.
evaluation = evidence.evaluation;
[~, J, W]  = size(evaluation.status);
status     = reshape(evaluation.status(index, :, :), J, W);

tbl = table(repmat(stage, J, 1), repmat(role, J, 1), repmat(model, J, 1), repmat(exo, J, 1), repmat(string(mat2str(evidence.candidate_grid(index, :))), J, 1), evidence.families, evidence.strata, evidence.dataset_ids, ~evidence.is_random, repmat(W, J, 1), sum(status == "ok", 2), mean(reshape(evaluation.wis(index, :, :), J, W), 2, 'omitnan'), mean(reshape(evaluation.mae(index, :, :), J, W), 2, 'omitnan'), mean(reshape(evaluation.rmse(index, :, :), J, W), 2, 'omitnan'), nan(J, 1), nan(J, 1), nan(J, 1), nan(J, 1), 'VariableNames', {'Stage', 'ConfigurationRole', 'Model', 'ExoMode', 'Configuration', 'Family', 'Stratum', 'DatasetId', 'IsCanonical', 'NumWindows', 'NumAvailable', 'MeanWIS', 'MeanMAE', 'MeanRMSE', 'MeanCoverage', 'MeanIntervalWidth', 'PersistenceWIS', 'RelativeWIS'});
end

function row = local_selection_feasibility(model, exo, stage, evidence)
%LOCAL_SELECTION_FEASIBILITY Candidate feasibility and fit diagnostics of one selection stage.
evaluation = evidence.evaluation;
ok         = evaluation.status == "ok";
failed     = evaluation.status == "infeasible";
classes    = local_failure_class(evaluation.error_id(failed));

row = table(model, exo, stage, numel(evidence.feasible), nnz(evidence.feasible), numel(evaluation.status), nnz(ok), nnz(failed), nnz(evaluation.status == "not_evaluated"), NaN, sum(classes == "invalid_draw"), sum(classes == "susceptible_domain"), sum(classes == "invalid_state"), sum(classes == "identification"), mean(evaluation.spectral_radius(ok) >= 1), mean(evaluation.iteration_limit_reached(ok)), 'VariableNames', local_feasibility_names());
end

function tbl = local_forecast_feasibility(window_scores)
%LOCAL_FORECAST_FEASIBILITY Forecast availability and fit diagnostics of each fixed-configuration stage.
[group_index, groups] = findgroups(window_scores(:, ["Model", "ExoMode", "Stage"]));
blocks = cell(height(groups), 1);

for g = 1:height(groups)
    rows    = window_scores(group_index == g, :);
    ok      = rows.Status == "ok";
    classes = local_failure_class(rows.ErrorId(~ok));

    blocks{g} = table(groups.Model(g), groups.ExoMode(g), groups.Stage(g), NaN, NaN, height(rows), nnz(ok), nnz(~ok), 0, mean(ok), sum(classes == "invalid_draw"), sum(classes == "susceptible_domain"), sum(classes == "invalid_state"), sum(classes == "identification"), mean(rows.SpectralRadius(ok) >= 1), mean(rows.IterationLimitReached(ok)), 'VariableNames', local_feasibility_names());
end

tbl = vertcat(blocks{:});
end

function names = local_feasibility_names()
%LOCAL_FEASIBILITY_NAMES Column names of the feasibility summary.
names = {'Model', 'ExoMode', 'Stage', 'NumCandidates', 'NumFeasibleCandidates', 'NumOrigins', 'NumOriginsOk', 'NumOriginsInfeasible', 'NumOriginsNotEvaluated', 'Availability', 'InvalidDrawFailures', 'SusceptibleDomainFailures', 'InvalidStateFailures', 'IdentificationFailures', 'UnstableFitFraction', 'IterationLimitFraction'};
end

function failure_class = local_failure_class(error_ids)
%LOCAL_FAILURE_CLASS Classify recognised infeasibility identifiers.
failure_class = repmat("identification", size(error_ids));
failure_class(endsWith(error_ids, "InvalidForecastDraw"))       = "invalid_draw";
failure_class(endsWith(error_ids, "SusceptibleBelowThreshold")) = "susceptible_domain";
failure_class(endsWith(error_ids, "InvalidState"))              = "invalid_state";
end

function tbl = local_trajectory_summary(window_scores)
%LOCAL_TRAJECTORY_SUMMARY Trajectory means over available origins with persistence matched to the same origins.
keys   = ["Stage", "ConfigurationRole", "Model", "ExoMode", "Configuration", "Family", "Stratum", "DatasetId", "IsCanonical"];
counts = renamevars(groupsummary(window_scores, keys), "GroupCount", "NumWindows");

reference = renamevars(window_scores(window_scores.Model == "Persistence", ["Stage", "DatasetId", "WindowDay", "WindowWIS"]), "WindowWIS", "PersistenceWIS");
ok_rows   = join(window_scores(window_scores.Status == "ok", :), reference, 'Keys', ["Stage", "DatasetId", "WindowDay"]);

means = groupsummary(ok_rows, keys, "mean", ["WindowWIS", "WindowMAE", "WindowRMSE", "MeanCoverage", "MeanIntervalWidth", "PersistenceWIS"]);
means = renamevars(means, ["GroupCount", "mean_WindowWIS", "mean_WindowMAE", "mean_WindowRMSE", "mean_MeanCoverage", "mean_MeanIntervalWidth", "mean_PersistenceWIS"], ["NumAvailable", "MeanWIS", "MeanMAE", "MeanRMSE", "MeanCoverage", "MeanIntervalWidth", "PersistenceWIS"]);

tbl = outerjoin(counts, means, 'Keys', keys, 'MergeKeys', true, 'Type', 'left');
tbl.NumAvailable(isnan(tbl.NumAvailable)) = 0;
tbl.RelativeWIS = tbl.MeanWIS ./ tbl.PersistenceWIS;
end

function summary = local_scenario_summary(trajectory_summary)
%LOCAL_SCENARIO_SUMMARY Family means with standard errors and the equal-family global mean.
group_keys = ["Stage", "ConfigurationRole", "Model", "ExoMode", "Configuration"];
metrics    = ["MeanWIS", "MeanMAE", "MeanRMSE", "MeanCoverage", "MeanIntervalWidth", "PersistenceWIS"];

[group_index, groups] = findgroups(trajectory_summary(:, group_keys));
blocks = cell(height(groups), 1);

for g = 1:height(groups)
    rows = trajectory_summary(group_index == g, :);
    [strata, first] = unique(rows.Stratum, 'stable');
    S = numel(strata);

    block = [repmat(groups(g, :), S + 1, 1), table([rows.Family(first); "All"], [strata; "All"], 'VariableNames', {'Family', 'Stratum'})];

    for m = 1:numel(metrics)
        [overall, overall_se, stratum_mean, stratum_se] = compute_stratified_mean(rows.(metrics(m)), rows.Stratum, ~rows.IsCanonical);
        block.(metrics(m)) = [stratum_mean; overall];

        if metrics(m) == "MeanWIS"
            block.SE = [stratum_se; overall_se];
        end
    end

    member_counts = arrayfun(@(stratum) nnz(rows.Stratum == stratum), strata);
    window_counts = arrayfun(@(stratum) sum(rows.NumWindows(rows.Stratum == stratum)), strata);
    available     = arrayfun(@(stratum) sum(rows.NumAvailable(rows.Stratum == stratum)), strata);

    block.NumTrajectories = [member_counts; sum(member_counts)];
    block.NumWindows      = [window_counts; sum(window_counts)];
    block.NumAvailable    = [available; sum(available)];
    block.RelativeWIS     = block.MeanWIS ./ block.PersistenceWIS;

    blocks{g} = block;
end

summary = vertcat(blocks{:});
end

function [overall, by_stratum] = local_hierarchical_means(tbl, keys, values)
%LOCAL_HIERARCHICAL_MEANS Average over origins within trajectories, trajectories within strata, then strata.
by_trajectory = local_group_means(tbl, [keys, "Family", "Stratum", "DatasetId"], values);
by_stratum    = local_group_means(by_trajectory, [keys, "Family", "Stratum"], values);
overall       = local_group_means(by_stratum, keys, values);
end

function out = local_group_means(tbl, keys, values)
%LOCAL_GROUP_MEANS Group a table and keep the mean columns under their original names.
out = groupsummary(tbl, keys, "mean", values);
out = renamevars(out, "mean_" + values, values);
out = removevars(out, "GroupCount");
end

function combined = local_append_overall(by_stratum, overall)
%LOCAL_APPEND_OVERALL Append the equal-stratum overall rows to stratum-level rows.
overall.Family  = repmat("All", height(overall), 1);
overall.Stratum = repmat("All", height(overall), 1);
combined = [by_stratum; overall(:, by_stratum.Properties.VariableNames)];
end

function local_write_table(table_dir, filename, table_data)
%LOCAL_WRITE_TABLE Write one CSV table.
output_path = fullfile(table_dir, filename);
writetable(table_data, output_path);
fprintf('Table saved to: %s\n', output_path);
end
