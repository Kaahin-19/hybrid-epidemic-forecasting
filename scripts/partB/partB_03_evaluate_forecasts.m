%PARTB_03_EVALUATE_FORECASTS Evaluate infectious-population forecasts against synthetic truth.
%
%   Description:
%       Scores the persistence, oracle, and ARX infectious-population
%       forecasts against the latent synthetic I_true(T+h) with
%       COMPUTE_POINT_ERROR. Method comparisons use the matched set: forecast
%       windows (condition, scenario, replicate, origin) in which all three
%       methods produced a valid forecast, so every method is scored on
%       identical cases.
%
%       Aggregation hierarchy (equal weights at every level):
%           horizon -> window (mean over h)
%           window -> replicate (mean over matched windows)
%           replicate -> scenario (mean over replicates)
%           scenario -> condition (mean over scenarios)
%           condition -> method (mean over conditions)
%       MAE is averaged directly. RMSE is the square root of the
%       correspondingly averaged mean squared error. A condition-level
%       aggregate is withheld (NaN, Complete = false) when any scenario has
%       no matched window; method-level aggregates are withheld when any
%       condition is incomplete.
%
%       Paired comparison: DeltaMAE = MAE_persistence - MAE_ARX per matched
%       window (positive values favour ARX), excess error of each method
%       over the oracle, and the share of windows in which ARX beats
%       persistence. Robustness degradation compares each condition with the
%       clean baseline at scenario level (each condition on its own matched
%       set; supports are reported). Execution support counts every intended
%       window by status for every condition, scenario, replicate, and
%       method. Rt-driver errors are retained as a secondary diagnostic.
%
%   Workflow:
%       1. Initialize configuration, identity, and output paths.
%       2. Load and validate the generation and forecast statuses.
%       3. Score every saved forecast artifact.
%       4. Build support, accuracy, paired, and degradation summaries.
%       5. Save the evaluation artifact.
%       6. Export the summary tables.
%
%   See also PARTB_CONFIG, PARTB_02_RUN_FORECASTS,
%            PARTB_04_GENERATE_FIGURES, COMPUTE_POINT_ERROR.
%
% A. M. Kaahin 2026-07-18
% Modified: 2026-11-18

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Infectious-Population Forecast Evaluation ===\n');

cfg            = partB_config();
pb             = cfg.partB;
forecast_dir   = pb.output.forecast_dir;
evaluation_dir = pb.output.evaluation_dir;
table_dir      = pb.output.table_dir;
identity       = local_identity(cfg);
method_ids     = pb.method_ids;
num_origins    = numel(cfg.forecast.min_window:cfg.forecast.step_size:(cfg.time.T_end - cfg.forecast.horizon));

if ~exist(evaluation_dir, 'dir'), mkdir(evaluation_dir); end
if ~exist(table_dir, 'dir'), mkdir(table_dir); end

%% 2. Load and Validate Statuses
generation = load(fullfile(pb.output.data_dir, 'partB_01_generation_status.mat'));
local_require_identity(generation.identity, identity, 'generation status');

status_path = fullfile(forecast_dir, 'partB_02_forecast_status.mat');
if ~exist(status_path, 'file')
    error('PARTB_03:MissingForecastStatus', 'Missing Part B forecast status: %s. Run partB_02 first.', status_path);
end

status = load(status_path);
local_require_identity(status.identity, identity, 'forecast status');

if ~status.run_completed
    error('PARTB_03:ForecastIncomplete', 'Part B forecasting did not complete (run_completed is false).');
end

forecast_status = status.forecast_status;
if any([forecast_status.status] == "pending")
    error('PARTB_03:PendingForecasts', 'Forecast status contains pending datasets although run_completed is true.');
end

%% 3. Score Saved Forecast Artifacts
[window_scores, horizon_scores] = local_score_all(forecast_status, forecast_dir, identity, method_ids);
fprintf('Scored %d window-method rows (%d matched windows).\n', height(window_scores), sum(window_scores.Matched) / numel(method_ids));

%% 4. Summaries
summaries = struct();
summaries.support_summary    = local_support_summary(window_scores, forecast_status, method_ids, num_origins);
summaries.support_condition  = local_aggregate(summaries.support_summary, {'Case', 'Method'}, {'IntendedWindows', @sum, 'IntendedWindows'; 'Ok', @sum, 'Ok'; 'Matched', @sum, 'Matched'; 'EstimationUnavailable', @sum, 'EstimationUnavailable'; 'InsufficientHistory', @sum, 'InsufficientHistory'; 'DomainFailure', @sum, 'DomainFailure'; 'ForecastFailure', @sum, 'ForecastFailure'; 'DatasetUnavailable', @sum, 'DatasetUnavailable'});
summaries.estimation_summary = local_estimation_summary(generation.generation_status);

summaries.replicate_summary  = local_replicate_summary(window_scores);
summaries.scenario_summary   = local_scenario_summary(summaries.replicate_summary, cfg, method_ids);
summaries.condition_summary  = local_condition_summary(summaries.scenario_summary, numel(cfg.scenarios));
summaries.method_summary     = local_method_summary(summaries.condition_summary, numel(pb.robustness_cases));
summaries.horizon_summary    = local_horizon_summary(horizon_scores, summaries.condition_summary);

[paired_windows, summaries.paired_scenario_summary, summaries.paired_condition_summary] = local_paired_summary(window_scores, cfg);
[summaries.degradation_scenario_summary, summaries.degradation_summary] = local_degradation_summary(summaries.scenario_summary, summaries.paired_scenario_summary, numel(cfg.scenarios));

%% 5. Save Evaluation Artifact
evaluation_metadata = struct('num_origins_per_dataset', num_origins, 'num_datasets_attempted', numel(forecast_status), 'num_forecast_artifacts', sum([forecast_status.status] == "saved"), 'source_forecasts', [forecast_status([forecast_status.status] == "saved").output_filename]', 'matched_definition', "all three methods ok in the same window", 'weighting', "equal weights: horizon->window->replicate->scenario->condition->method");

evaluation_artifact = fullfile(evaluation_dir, 'partB_03_evaluation_results.mat');
snapshot = pb.snapshot;
save(evaluation_artifact, 'identity', 'snapshot', 'window_scores', 'horizon_scores', 'paired_windows', 'summaries', 'evaluation_metadata');
fprintf('Evaluation artifact saved to: %s\n', evaluation_artifact);

%% 6. Save Summary Tables
local_write_table(table_dir, 'partB_03_window_scores.csv', window_scores);
local_write_table(table_dir, 'partB_03_support_summary.csv', summaries.support_summary);
local_write_table(table_dir, 'partB_03_support_condition_summary.csv', summaries.support_condition);
local_write_table(table_dir, 'partB_03_estimation_summary.csv', summaries.estimation_summary);
local_write_table(table_dir, 'partB_03_replicate_summary.csv', summaries.replicate_summary);
local_write_table(table_dir, 'partB_03_scenario_summary.csv', summaries.scenario_summary);
local_write_table(table_dir, 'partB_03_condition_summary.csv', summaries.condition_summary);
local_write_table(table_dir, 'partB_03_method_summary.csv', summaries.method_summary);
local_write_table(table_dir, 'partB_03_horizon_summary.csv', summaries.horizon_summary);
local_write_table(table_dir, 'partB_03_paired_scenario_summary.csv', summaries.paired_scenario_summary);
local_write_table(table_dir, 'partB_03_paired_condition_summary.csv', summaries.paired_condition_summary);
local_write_table(table_dir, 'partB_03_degradation_scenario_summary.csv', summaries.degradation_scenario_summary);
local_write_table(table_dir, 'partB_03_degradation_summary.csv', summaries.degradation_summary);

fprintf('=== Part B Infectious-Population Forecast Evaluation Complete ===\n\n');

%% 7. Local Functions
function identity = local_identity(cfg)
%LOCAL_IDENTITY Experiment, configuration, and source identity shared by all Part B artifacts.
identity = struct('experiment_id', cfg.partB.experiment_id, 'protocol_version', cfg.partB.protocol_version, 'config_id', cfg.partB.config_id, 'source_id', cfg.partB.provenance.source_id);
end

function local_require_identity(found, expected, label)
%LOCAL_REQUIRE_IDENTITY Reject inputs produced under a different protocol, configuration, or source.
if ~isequal(found, expected)
    error('PARTB_03:IncompatibleArtifact', ['%s was produced under protocol %s, config_id %s, source_id %s; the current run expects protocol %s, ' ...
        'config_id %s, source_id %s. Rerun with ./run_partB_pipeline.sh --fresh.'], label, found.protocol_version, found.config_id, found.source_id, expected.protocol_version, expected.config_id, expected.source_id);
end
end

function [window_scores, horizon_scores] = local_score_all(forecast_status, forecast_dir, identity, method_ids)
%LOCAL_SCORE_ALL Window- and horizon-level infectious-population errors for every saved artifact.
saved = forecast_status([forecast_status.status] == "saved");
window_parts  = cell(numel(saved), 1);
horizon_parts = cell(numel(saved), 1);

for i = 1:numel(saved)
    artifact = load(fullfile(forecast_dir, saved(i).output_filename));
    local_require_identity(artifact.identity, identity, saved(i).output_filename);
    [window_parts{i}, horizon_parts{i}] = local_score_artifact(artifact, method_ids);
end

window_scores  = vertcat(window_parts{:});
horizon_scores = vertcat(horizon_parts{:});
end

function [window_tbl, horizon_tbl] = local_score_artifact(artifact, method_ids)
%LOCAL_SCORE_ARTIFACT Score one forecast artifact; failed methods keep their status with NaN metrics.
windows     = artifact.windows;
num_methods = numel(method_ids);
num_rows    = numel(windows) * num_methods;
H           = numel(windows(1).truth_I);

WindowDay = zeros(num_rows, 1);
Method    = strings(num_rows, 1);
Status    = strings(num_rows, 1);
ErrorId   = strings(num_rows, 1);
Matched   = false(num_rows, 1);
MAE       = NaN(num_rows, 1);
MSE       = NaN(num_rows, 1);
RMSE      = NaN(num_rows, 1);
RtDriverMAE = NaN(num_rows, 1);

h_rows = cell(num_rows, 1);
row = 0;

for w = 1:numel(windows)
    win = windows(w);
    matched = all(win.status == "ok");

    for m = 1:num_methods
        row = row + 1;
        WindowDay(row) = win.window_day;
        Method(row)    = method_ids(m);
        Status(row)    = win.status(m);
        ErrorId(row)   = win.error_id(m);
        Matched(row)   = matched;

        if win.status(m) ~= "ok"
            continue;
        end

        point_error = compute_point_error(win.truth_I, win.I_pred(:, m));
        rt_error    = abs(win.drivers(:, m) - win.truth_Rt_drivers);

        MAE(row)         = point_error.mae;
        MSE(row)         = mean(point_error.squared_error);
        RMSE(row)        = point_error.rmse;
        RtDriverMAE(row) = mean(rt_error);

        h_rows{row} = table(repmat(win.window_day, H, 1), repmat(method_ids(m), H, 1), (1:H)', repmat(matched, H, 1), win.truth_I, win.I_pred(:, m), point_error.error, point_error.absolute_error, point_error.squared_error, rt_error, ...
            'VariableNames', {'WindowDay', 'Method', 'HorizonIdx', 'Matched', 'TruthI', 'PredI', 'Error', 'AbsoluteError', 'SquaredError', 'RtDriverAbsError'});
    end
end

identity_columns = @(n) table(repmat(artifact.case_id, n, 1), repmat(artifact.scenario_id, n, 1), repmat(artifact.replicate_id, n, 1), 'VariableNames', {'Case', 'Scenario', 'Replicate'});

window_tbl  = [identity_columns(num_rows), table(WindowDay, Method, Status, ErrorId, Matched, MAE, MSE, RMSE, RtDriverMAE)];
horizon_tbl = vertcat(h_rows{:});
horizon_tbl = [identity_columns(height(horizon_tbl)), horizon_tbl];
end

function support = local_support_summary(window_scores, forecast_status, method_ids, num_origins)
%LOCAL_SUPPORT_SUMMARY Status counts of every intended window per condition, scenario, replicate, and method.
num_rows = numel(forecast_status) * numel(method_ids);
Case = strings(num_rows, 1); Scenario = strings(num_rows, 1); Replicate = strings(num_rows, 1); Method = strings(num_rows, 1); DatasetStatus = strings(num_rows, 1);
IntendedWindows = zeros(num_rows, 1); Ok = zeros(num_rows, 1); Matched = zeros(num_rows, 1); EstimationUnavailable = zeros(num_rows, 1);
InsufficientHistory = zeros(num_rows, 1); DomainFailure = zeros(num_rows, 1); ForecastFailure = zeros(num_rows, 1); DatasetUnavailable = zeros(num_rows, 1);

row = 0;
for i = 1:numel(forecast_status)
    entry = forecast_status(i);
    mask_dataset = window_scores.Case == entry.case_id & window_scores.Scenario == entry.scenario_id & window_scores.Replicate == entry.replicate_id;

    for m = 1:numel(method_ids)
        row = row + 1;
        rows = window_scores(mask_dataset & window_scores.Method == method_ids(m), :);

        Case(row) = entry.case_id; Scenario(row) = entry.scenario_id; Replicate(row) = entry.replicate_id; Method(row) = method_ids(m);
        DatasetStatus(row)   = entry.status;
        IntendedWindows(row) = num_origins;

        if entry.status ~= "saved"
            DatasetUnavailable(row) = num_origins;
            continue;
        end

        Ok(row)                    = sum(rows.Status == "ok");
        Matched(row)               = sum(rows.Matched);
        EstimationUnavailable(row) = sum(rows.Status == "estimation_unavailable");
        InsufficientHistory(row)   = sum(rows.Status == "insufficient_history");
        DomainFailure(row)         = sum(rows.Status == "domain_failure");
        ForecastFailure(row)       = sum(rows.Status == "forecast_failure");
    end
end

support = table(Case, Scenario, Replicate, Method, DatasetStatus, IntendedWindows, Ok, Matched, EstimationUnavailable, InsufficientHistory, DomainFailure, ForecastFailure, DatasetUnavailable);

if any(support.Ok + support.EstimationUnavailable + support.InsufficientHistory + support.DomainFailure + support.ForecastFailure + support.DatasetUnavailable ~= support.IntendedWindows)
    error('PARTB_03:SupportCountMismatch', 'Window status counts do not add up to the intended windows.');
end
end

function estimation_summary = local_estimation_summary(generation_status)
%LOCAL_ESTIMATION_SUMMARY Per-dataset generation and estimation outcome.
estimation_summary = table([generation_status.case_id]', [generation_status.scenario_id]', [generation_status.replicate_id]', [generation_status.status]', [generation_status.estimation_failure_idx]', [generation_status.zero_incidence_days]', [generation_status.valid_rt_estimates]', ...
    'VariableNames', {'Case', 'Scenario', 'Replicate', 'GenerationStatus', 'EstimationFailureIdx', 'ZeroIncidenceDays', 'ValidRtEstimates'});
end

function replicate_summary = local_replicate_summary(window_scores)
%LOCAL_REPLICATE_SUMMARY Matched-window mean errors per replicate and method.
matched = window_scores(window_scores.Matched, :);
replicate_summary = local_aggregate(matched, {'Case', 'Scenario', 'Replicate', 'Method'}, { ...
    'NumMatchedWindows', @numel, 'MAE'; ...
    'MAE',               @mean,  'MAE'; ...
    'MSE',               @mean,  'MSE'; ...
    'RtDriverMAE',       @mean,  'RtDriverMAE'});
replicate_summary.RMSE = sqrt(replicate_summary.MSE);
end

function scenario_summary = local_scenario_summary(replicate_summary, cfg, method_ids)
%LOCAL_SCENARIO_SUMMARY Equal-weight replicate means per condition, scenario, and method (all slots listed).
scored = local_aggregate(replicate_summary, {'Case', 'Scenario', 'Method'}, { ...
    'NumReplicatesScored', @numel, 'MAE'; ...
    'NumMatchedWindows',   @sum,   'NumMatchedWindows'; ...
    'MAE',                 @mean,  'MAE'; ...
    'MSE',                 @mean,  'MSE'; ...
    'RtDriverMAE',         @mean,  'RtDriverMAE'});
scored.RMSE = sqrt(scored.MSE);

[case_grid, scenario_grid, method_grid] = ndgrid([cfg.partB.robustness_cases.case_id], [cfg.scenarios.id], method_ids);
replicates_expected = repmat([cfg.partB.robustness_cases.num_replicates]', 1, numel(cfg.scenarios), numel(method_ids));
grid = table(case_grid(:), scenario_grid(:), method_grid(:), replicates_expected(:), 'VariableNames', {'Case', 'Scenario', 'Method', 'ReplicatesExpected'});

scenario_summary = outerjoin(grid, scored, 'Keys', {'Case', 'Scenario', 'Method'}, 'MergeKeys', true, 'Type', 'left');
scenario_summary.NumReplicatesScored(isnan(scenario_summary.NumReplicatesScored)) = 0;
scenario_summary.NumMatchedWindows(isnan(scenario_summary.NumMatchedWindows))     = 0;
scenario_summary.HasMatchedWindows = scenario_summary.NumMatchedWindows > 0;
scenario_summary = sortrows(scenario_summary, {'Case', 'Scenario', 'Method'});
end

function condition_summary = local_condition_summary(scenario_summary, num_scenarios)
%LOCAL_CONDITION_SUMMARY Equal-weight scenario means; withheld when scenario coverage is incomplete.
condition_summary = local_aggregate(scenario_summary, {'Case', 'Method'}, { ...
    'NumScenariosExpected',   @numel, 'Scenario'; ...
    'NumScenariosScored',     @sum,   'HasMatchedWindows'; ...
    'NumMatchedWindows',      @sum,   'NumMatchedWindows'; ...
    'MAE',                    @mean,  'MAE'; ...
    'MSE',                    @mean,  'MSE'; ...
    'RtDriverMAE',            @mean,  'RtDriverMAE'});
condition_summary.RMSE     = sqrt(condition_summary.MSE);
condition_summary.Complete = condition_summary.NumScenariosScored == num_scenarios;

metric_names = {'MAE', 'MSE', 'RMSE', 'RtDriverMAE'};
for i = 1:numel(metric_names)
    condition_summary.(metric_names{i})(~condition_summary.Complete) = NaN;
end
end

function method_summary = local_method_summary(condition_summary, num_conditions)
%LOCAL_METHOD_SUMMARY Equal-weight condition means per method; withheld unless every condition is complete.
method_summary = local_aggregate(condition_summary, {'Method'}, { ...
    'NumConditionsComplete', @sum,  'Complete'; ...
    'MAE',                   @mean, 'MAE'; ...
    'MSE',                   @mean, 'MSE'});
method_summary.RMSE     = sqrt(method_summary.MSE);
method_summary.Complete = method_summary.NumConditionsComplete == num_conditions;
end

function horizon_summary = local_horizon_summary(horizon_scores, condition_summary)
%LOCAL_HORIZON_SUMMARY Matched-window horizon errors aggregated with the same equal-weight hierarchy.
matched = horizon_scores(horizon_scores.Matched, :);
replicate_level = local_aggregate(matched, {'Case', 'Scenario', 'Replicate', 'Method', 'HorizonIdx'}, {'MAE', @mean, 'AbsoluteError'; 'MSE', @mean, 'SquaredError'; 'RtDriverMAE', @mean, 'RtDriverAbsError'});
scenario_level  = local_aggregate(replicate_level, {'Case', 'Scenario', 'Method', 'HorizonIdx'}, {'MAE', @mean, 'MAE'; 'MSE', @mean, 'MSE'; 'RtDriverMAE', @mean, 'RtDriverMAE'});
horizon_summary = local_aggregate(scenario_level, {'Case', 'Method', 'HorizonIdx'}, {'NumScenariosScored', @numel, 'MAE'; 'MAE', @mean, 'MAE'; 'MSE', @mean, 'MSE'; 'RtDriverMAE', @mean, 'RtDriverMAE'});
horizon_summary.RMSE = sqrt(horizon_summary.MSE);

horizon_summary = innerjoin(horizon_summary, condition_summary(:, {'Case', 'Method', 'Complete'}), 'Keys', {'Case', 'Method'});
metric_names = {'MAE', 'MSE', 'RMSE', 'RtDriverMAE'};
for i = 1:numel(metric_names)
    horizon_summary.(metric_names{i})(~horizon_summary.Complete) = NaN;
end
end

function [paired_windows, paired_scenario, paired_condition] = local_paired_summary(window_scores, cfg)
%LOCAL_PAIRED_SUMMARY Matched-window ARX-versus-persistence and oracle comparisons.
matched = window_scores(window_scores.Matched, {'Case', 'Scenario', 'Replicate', 'WindowDay', 'Method', 'MAE', 'RMSE'});
wide = unstack(matched, {'MAE', 'RMSE'}, 'Method');

paired_windows = wide(:, {'Case', 'Scenario', 'Replicate', 'WindowDay'});
paired_windows.MAE_persistence = wide.MAE_persistence;
paired_windows.MAE_oracle      = wide.MAE_oracle;
paired_windows.MAE_arx         = wide.MAE_arx;
paired_windows.DeltaMAE        = wide.MAE_persistence - wide.MAE_arx;
paired_windows.DeltaRMSE       = wide.RMSE_persistence - wide.RMSE_arx;
paired_windows.PersistenceExcessMAE = wide.MAE_persistence - wide.MAE_oracle;
paired_windows.ArxExcessMAE    = wide.MAE_arx - wide.MAE_oracle;
paired_windows.ArxBetter       = double(wide.MAE_arx < wide.MAE_persistence);

specs = {'NumMatchedWindows', @numel, 'DeltaMAE'; 'DeltaMAE', @mean, 'DeltaMAE'; 'DeltaRMSE', @mean, 'DeltaRMSE'; 'PersistenceExcessMAE', @mean, 'PersistenceExcessMAE'; 'ArxExcessMAE', @mean, 'ArxExcessMAE'; 'ArxWinShare', @mean, 'ArxBetter'};
replicate_level = local_aggregate(paired_windows, {'Case', 'Scenario', 'Replicate'}, specs);

specs_up = {'NumMatchedWindows', @sum, 'NumMatchedWindows'; 'DeltaMAE', @mean, 'DeltaMAE'; 'DeltaRMSE', @mean, 'DeltaRMSE'; 'PersistenceExcessMAE', @mean, 'PersistenceExcessMAE'; 'ArxExcessMAE', @mean, 'ArxExcessMAE'; 'ArxWinShare', @mean, 'ArxWinShare'};
paired_scenario  = local_aggregate(replicate_level, {'Case', 'Scenario'}, [{'NumReplicatesScored', @numel, 'DeltaMAE'}; specs_up]);
paired_condition = local_aggregate(paired_scenario, {'Case'}, [{'NumScenariosScored', @numel, 'DeltaMAE'}; specs_up]);

all_cases = table([cfg.partB.robustness_cases.case_id]', 'VariableNames', {'Case'});
paired_condition = outerjoin(all_cases, paired_condition, 'Keys', 'Case', 'MergeKeys', true, 'Type', 'left');
paired_condition.NumScenariosScored(isnan(paired_condition.NumScenariosScored)) = 0;
paired_condition.Complete = paired_condition.NumScenariosScored == numel(cfg.scenarios);

metric_names = {'DeltaMAE', 'DeltaRMSE', 'PersistenceExcessMAE', 'ArxExcessMAE', 'ArxWinShare'};
for i = 1:numel(metric_names)
    paired_condition.(metric_names{i})(~paired_condition.Complete) = NaN;
end
end

function [degradation_scenario, degradation] = local_degradation_summary(scenario_summary, paired_scenario, num_scenarios)
%LOCAL_DEGRADATION_SUMMARY Scenario-level change relative to the clean baseline, averaged over scenarios.
clean = scenario_summary(scenario_summary.Case == "clean_baseline", {'Scenario', 'Method', 'MAE', 'RMSE', 'NumMatchedWindows'});
clean = renamevars(clean, {'MAE', 'RMSE', 'NumMatchedWindows'}, {'CleanMAE', 'CleanRMSE', 'CleanMatchedWindows'});

stressed = scenario_summary(scenario_summary.Case ~= "clean_baseline", {'Case', 'Scenario', 'Method', 'MAE', 'RMSE', 'NumMatchedWindows'});
degradation_scenario = innerjoin(stressed, clean, 'Keys', {'Scenario', 'Method'});
degradation_scenario.MAEChange  = degradation_scenario.MAE - degradation_scenario.CleanMAE;
degradation_scenario.RMSEChange = degradation_scenario.RMSE - degradation_scenario.CleanRMSE;
degradation_scenario.MAERatio   = degradation_scenario.MAE ./ degradation_scenario.CleanMAE;

clean_delta = paired_scenario(paired_scenario.Case == "clean_baseline", {'Scenario', 'DeltaMAE'});
clean_delta = renamevars(clean_delta, 'DeltaMAE', 'CleanDeltaMAE');
delta = outerjoin(paired_scenario(:, {'Case', 'Scenario', 'DeltaMAE'}), clean_delta, 'Keys', 'Scenario', 'MergeKeys', true, 'Type', 'left');
delta.ArxAdvantageChange = delta.DeltaMAE - delta.CleanDeltaMAE;
degradation_scenario = outerjoin(degradation_scenario, delta(:, {'Case', 'Scenario', 'ArxAdvantageChange'}), 'Keys', {'Case', 'Scenario'}, 'MergeKeys', true, 'Type', 'left');
degradation_scenario = degradation_scenario(~ismissing(degradation_scenario.Method), :);
degradation_scenario = sortrows(degradation_scenario, {'Case', 'Method', 'Scenario'});

defined = isfinite(degradation_scenario.MAEChange);
degradation_scenario.Defined = defined;
degradation = local_aggregate(degradation_scenario, {'Case', 'Method'}, { ...
    'NumScenariosDefined', @sum,  'Defined'; ...
    'MAEChange',           @mean, 'MAEChange'; ...
    'RMSEChange',          @mean, 'RMSEChange'; ...
    'MAERatio',            @mean, 'MAERatio'; ...
    'ArxAdvantageChange',  @mean, 'ArxAdvantageChange'});
degradation.Complete = degradation.NumScenariosDefined == num_scenarios;

metric_names = {'MAEChange', 'RMSEChange', 'MAERatio', 'ArxAdvantageChange'};
for i = 1:numel(metric_names)
    degradation.(metric_names{i})(~degradation.Complete) = NaN;
end
end

function out = local_aggregate(tbl, keys, specs)
%LOCAL_AGGREGATE Group a table by keys and apply per-column aggregation specs.
[group, out] = findgroups(tbl(:, keys));
for i = 1:size(specs, 1)
    out.(specs{i, 1}) = splitapply(specs{i, 2}, tbl.(specs{i, 3}), group);
end
end

function local_write_table(table_dir, filename, table_data)
%LOCAL_WRITE_TABLE Write one summary CSV table.
output_path = fullfile(table_dir, filename);
writetable(table_data, output_path);
fprintf('Table saved to: %s\n', output_path);
end
