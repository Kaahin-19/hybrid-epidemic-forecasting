%PARTB_03_EVALUATE_FORECASTS Evaluate infectious-population forecasts against synthetic truth.
%
%   Description:
%       Scores the persistence, oracle, AR, and ARX forecasts of I(T+h)
%       against the latent I_true with COMPUTE_POINT_ERROR. Method
%       comparisons use two matched sets, identified by the MatchedSet key:
%           primary  : windows in which persistence, oracle, and ARX all
%                      produced a valid forecast (the original three-method
%                      comparison; AR validity does not affect it);
%           extended : windows in which all four methods produced a valid
%                      forecast (every comparison involving AR).
%       Within each set, errors are aggregated with equal weights through
%       horizon -> window -> replicate -> scenario -> condition -> method;
%       RMSE is the square root of the averaged MSE. Condition aggregates are
%       withheld when any scenario has no matched window. Paired comparisons
%       report DeltaMAE = MAE_reference - MAE_candidate (positive: candidate
%       more accurate), DeltaRMSE, the candidate win share, and the change of
%       DeltaMAE relative to the clean baseline. The oracle uses the exact
%       future Rt but the estimated state X_hat_T and the SIRS forecasting
%       model, so it is not a guaranteed lower error bound. Degradation
%       relative to the clean baseline, execution support for every intended
%       window, and Rt-driver errors are also reported.
%
%   Workflow:
%       1. Initialize evaluation paths and configuration.
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
% Modified: 2026-11-25

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Forecast Evaluation ===\n');

cfg            = partB_config();
pb             = cfg.partB;
forecast_dir   = pb.output.forecast_dir;
evaluation_dir = pb.output.evaluation_dir;
table_dir      = pb.output.table_dir;
snapshot       = pb.snapshot;
method_ids     = pb.method_ids;
matched_sets   = pb.matched_sets;
matched_names  = cellstr("Matched_" + [matched_sets.set_id]);
num_origins    = numel(cfg.forecast.min_window:cfg.forecast.step_size:(cfg.time.T_end - cfg.forecast.horizon));

if ~exist(evaluation_dir, 'dir'), mkdir(evaluation_dir); end
if ~exist(table_dir, 'dir'), mkdir(table_dir); end

%% 2. Load and Validate Statuses
generation = load(fullfile(pb.output.data_dir, 'partB_01_generation_status.mat'));
local_require_snapshot(generation.snapshot, snapshot, 'Generation status');

status_path = fullfile(forecast_dir, 'partB_02_forecast_status.mat');
if ~exist(status_path, 'file')
    error('PARTB_03:MissingForecastStatus', 'Missing Part B forecast status: %s. Run partB_02 first.', status_path);
end

status = load(status_path);
local_require_snapshot(status.snapshot, snapshot, 'Forecast status');

if ~status.run_completed
    error('PARTB_03:ForecastIncomplete', 'Part B forecasting did not complete (run_completed is false).');
end

forecast_status = status.forecast_status;

%% 3. Score Saved Forecast Artifacts
[window_scores, horizon_scores] = local_score_all(forecast_status, forecast_dir, snapshot, method_ids, matched_sets);
fprintf('Scored %d window-method rows.\n', height(window_scores));
for k = 1:numel(matched_sets)
    fprintf('  %s: %d matched windows.\n', matched_sets(k).set_name, sum(window_scores.(matched_names{k})) / numel(method_ids));
end

matched_scores  = local_matched_rows(window_scores, matched_sets);
matched_horizon = local_matched_rows(horizon_scores, matched_sets);

%% 4. Summaries
summaries = struct();
summaries.support_summary    = local_support_summary(window_scores, forecast_status, method_ids, matched_sets, num_origins);
support_counts               = [{'IntendedWindows', 'Ok'}, matched_names, {'EstimationUnavailable', 'InsufficientHistory', 'DomainFailure', 'ForecastFailure', 'DatasetUnavailable'}]';
summaries.support_condition  = local_aggregate(summaries.support_summary, {'Case', 'Method'}, [support_counts, repmat({@sum}, numel(support_counts), 1), support_counts]);
summaries.estimation_summary = local_estimation_summary(generation.generation_status);

summaries.replicate_summary  = local_replicate_summary(matched_scores);
summaries.scenario_summary   = local_scenario_summary(summaries.replicate_summary, cfg);
summaries.condition_summary  = local_condition_summary(summaries.scenario_summary, numel(cfg.scenarios));
summaries.method_summary     = local_method_summary(summaries.condition_summary, numel(pb.robustness_cases));
summaries.horizon_summary    = local_horizon_summary(matched_horizon, summaries.condition_summary);

[paired_windows, summaries.paired_scenario_summary, summaries.paired_condition_summary] = local_paired_summary(matched_scores, cfg);
[summaries.degradation_scenario_summary, summaries.degradation_summary] = local_degradation_summary(summaries.scenario_summary, numel(cfg.scenarios));

%% 5. Save Evaluation Artifact
evaluation_artifact = fullfile(evaluation_dir, 'partB_03_evaluation_results.mat');
save(evaluation_artifact, 'snapshot', 'window_scores', 'horizon_scores', 'paired_windows', 'summaries');
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

fprintf('=== Part B Forecast Evaluation Complete ===\n\n');

%% 7. Local Functions
function local_require_snapshot(found, expected, label)
%LOCAL_REQUIRE_SNAPSHOT Reject an input produced under a different Part B configuration.
if ~isequal(found, expected)
    error('PARTB_03:IncompatibleArtifact', '%s was produced under a different Part B configuration. Rerun with ./run_partB_pipeline.sh --fresh.', label);
end
end

function [window_scores, horizon_scores] = local_score_all(forecast_status, forecast_dir, snapshot, method_ids, matched_sets)
%LOCAL_SCORE_ALL Window- and horizon-level infectious-population errors for every saved artifact.
saved = forecast_status([forecast_status.status] == "saved");
window_parts  = cell(numel(saved), 1);
horizon_parts = cell(numel(saved), 1);

for i = 1:numel(saved)
    artifact = load(fullfile(forecast_dir, saved(i).output_filename));
    local_require_snapshot(artifact.snapshot, snapshot, saved(i).output_filename);
    [window_parts{i}, horizon_parts{i}] = local_score_artifact(artifact, method_ids, matched_sets);
end

window_scores  = vertcat(window_parts{:});
horizon_scores = vertcat(horizon_parts{:});
end

function [window_tbl, horizon_tbl] = local_score_artifact(artifact, method_ids, matched_sets)
%LOCAL_SCORE_ARTIFACT Score one forecast artifact; failed methods keep their status with NaN metrics.
%   Matched_<set_id> marks the windows in which every method of that
%   matched set produced a valid forecast.
windows       = artifact.windows;
num_methods   = numel(method_ids);
num_sets      = numel(matched_sets);
num_rows      = numel(windows) * num_methods;
H             = numel(windows(1).truth_I);
matched_names = cellstr("Matched_" + [matched_sets.set_id]);

WindowDay = zeros(num_rows, 1);
Method    = strings(num_rows, 1);
Status    = strings(num_rows, 1);
ErrorId   = strings(num_rows, 1);
InSet     = false(num_rows, num_sets);
MAE       = NaN(num_rows, 1);
MSE       = NaN(num_rows, 1);
RMSE      = NaN(num_rows, 1);
RtDriverMAE = NaN(num_rows, 1);

h_rows = cell(num_rows, 1);
row = 0;

for w = 1:numel(windows)
    win = windows(w);
    in_set = false(1, num_sets);
    for k = 1:num_sets
        in_set(k) = all(win.status(ismember(method_ids, matched_sets(k).method_ids)) == "ok");
    end

    for m = 1:num_methods
        row = row + 1;
        WindowDay(row)  = win.window_day;
        Method(row)     = method_ids(m);
        Status(row)     = win.status(m);
        ErrorId(row)    = win.error_id(m);
        InSet(row, :)   = in_set;

        if win.status(m) ~= "ok"
            continue;
        end

        point_error = compute_point_error(win.truth_I, win.I_pred(:, m));
        rt_error    = abs(win.drivers(:, m) - win.truth_Rt_drivers);

        MAE(row)         = point_error.mae;
        MSE(row)         = mean(point_error.squared_error);
        RMSE(row)        = point_error.rmse;
        RtDriverMAE(row) = mean(rt_error);

        h_rows{row} = [table(repmat(win.window_day, H, 1), repmat(method_ids(m), H, 1), (1:H)', 'VariableNames', {'WindowDay', 'Method', 'HorizonIdx'}), ...
            array2table(repmat(in_set, H, 1), 'VariableNames', matched_names), ...
            table(win.truth_I, win.I_pred(:, m), point_error.error, point_error.absolute_error, point_error.squared_error, rt_error, 'VariableNames', {'TruthI', 'PredI', 'Error', 'AbsoluteError', 'SquaredError', 'RtDriverAbsError'})];
    end
end

identity_columns = @(n) table(repmat(artifact.case_id, n, 1), repmat(artifact.scenario_id, n, 1), repmat(artifact.replicate_id, n, 1), 'VariableNames', {'Case', 'Scenario', 'Replicate'});

window_tbl  = [identity_columns(num_rows), table(WindowDay, Method, Status, ErrorId), array2table(InSet, 'VariableNames', matched_names), table(MAE, MSE, RMSE, RtDriverMAE)];
horizon_tbl = vertcat(h_rows{:});
horizon_tbl = [identity_columns(height(horizon_tbl)), horizon_tbl];
end

function matched = local_matched_rows(scores, matched_sets)
%LOCAL_MATCHED_ROWS Stack the rows of each matched set (its methods only) under a MatchedSet key.
parts = cell(numel(matched_sets), 1);
for k = 1:numel(matched_sets)
    set_def = matched_sets(k);
    rows = scores(scores.("Matched_" + set_def.set_id) & ismember(scores.Method, set_def.method_ids), :);
    rows.MatchedSet = repmat(set_def.set_id, height(rows), 1);
    parts{k} = movevars(rows, 'MatchedSet', 'Before', 1);
end
matched = vertcat(parts{:});
end

function support = local_support_summary(window_scores, forecast_status, method_ids, matched_sets, num_origins)
%LOCAL_SUPPORT_SUMMARY Status counts of every intended window per condition, scenario, replicate, and method.
%   Matched_<set_id> counts the windows of the dataset in that matched set;
%   it is NaN for methods outside the set.
num_rows = numel(forecast_status) * numel(method_ids);
num_sets = numel(matched_sets);
matched_names = cellstr("Matched_" + [matched_sets.set_id]);
Case = strings(num_rows, 1); Scenario = strings(num_rows, 1); Replicate = strings(num_rows, 1); Method = strings(num_rows, 1); DatasetStatus = strings(num_rows, 1);
IntendedWindows = zeros(num_rows, 1); Ok = zeros(num_rows, 1); MatchedCounts = zeros(num_rows, num_sets); EstimationUnavailable = zeros(num_rows, 1);
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
        for k = 1:num_sets
            if ~ismember(method_ids(m), matched_sets(k).method_ids)
                MatchedCounts(row, k) = NaN;
            elseif entry.status == "saved"
                MatchedCounts(row, k) = sum(rows.(matched_names{k}));
            end
        end

        if entry.status ~= "saved"
            DatasetUnavailable(row) = num_origins;
            continue;
        end

        Ok(row)                    = sum(rows.Status == "ok");
        EstimationUnavailable(row) = sum(rows.Status == "estimation_unavailable");
        InsufficientHistory(row)   = sum(rows.Status == "insufficient_history");
        DomainFailure(row)         = sum(rows.Status == "domain_failure");
        ForecastFailure(row)       = sum(rows.Status == "forecast_failure");
    end
end

support = [table(Case, Scenario, Replicate, Method, DatasetStatus, IntendedWindows, Ok), array2table(MatchedCounts, 'VariableNames', matched_names), table(EstimationUnavailable, InsufficientHistory, DomainFailure, ForecastFailure, DatasetUnavailable)];

if any(support.Ok + support.EstimationUnavailable + support.InsufficientHistory + support.DomainFailure + support.ForecastFailure + support.DatasetUnavailable ~= support.IntendedWindows)
    error('PARTB_03:SupportCountMismatch', 'Window status counts do not add up to the intended windows.');
end
end

function estimation_summary = local_estimation_summary(generation_status)
%LOCAL_ESTIMATION_SUMMARY Per-dataset generation and estimation outcome.
estimation_summary = table([generation_status.case_id]', [generation_status.scenario_id]', [generation_status.replicate_id]', [generation_status.status]', [generation_status.estimation_failure_idx]', [generation_status.zero_incidence_days]', [generation_status.valid_rt_estimates]', ...
    'VariableNames', {'Case', 'Scenario', 'Replicate', 'GenerationStatus', 'EstimationFailureIdx', 'ZeroIncidenceDays', 'ValidRtEstimates'});
end

function replicate_summary = local_replicate_summary(matched_scores)
%LOCAL_REPLICATE_SUMMARY Matched-window mean errors per matched set, replicate, and method.
replicate_summary = local_aggregate(matched_scores, {'MatchedSet', 'Case', 'Scenario', 'Replicate', 'Method'}, { ...
    'NumMatchedWindows', @numel, 'MAE'; ...
    'MAE',               @mean,  'MAE'; ...
    'MSE',               @mean,  'MSE'; ...
    'RtDriverMAE',       @mean,  'RtDriverMAE'});
replicate_summary.RMSE = sqrt(replicate_summary.MSE);
end

function scenario_summary = local_scenario_summary(replicate_summary, cfg)
%LOCAL_SCENARIO_SUMMARY Equal-weight replicate means per matched set, condition, scenario, and method (all slots listed).
scored = local_aggregate(replicate_summary, {'MatchedSet', 'Case', 'Scenario', 'Method'}, { ...
    'NumReplicatesScored', @numel, 'MAE'; ...
    'NumMatchedWindows',   @sum,   'NumMatchedWindows'; ...
    'MAE',                 @mean,  'MAE'; ...
    'MSE',                 @mean,  'MSE'; ...
    'RtDriverMAE',         @mean,  'RtDriverMAE'});
scored.RMSE = sqrt(scored.MSE);

grid_parts = cell(numel(cfg.partB.matched_sets), 1);
for k = 1:numel(cfg.partB.matched_sets)
    set_def = cfg.partB.matched_sets(k);
    [case_grid, scenario_grid, method_grid] = ndgrid([cfg.partB.robustness_cases.case_id], [cfg.scenarios.id], set_def.method_ids);
    replicates_expected = repmat([cfg.partB.robustness_cases.num_replicates]', 1, numel(cfg.scenarios), numel(set_def.method_ids));
    grid_parts{k} = table(repmat(set_def.set_id, numel(case_grid), 1), case_grid(:), scenario_grid(:), method_grid(:), replicates_expected(:), 'VariableNames', {'MatchedSet', 'Case', 'Scenario', 'Method', 'ReplicatesExpected'});
end
grid = vertcat(grid_parts{:});

scenario_summary = outerjoin(grid, scored, 'Keys', {'MatchedSet', 'Case', 'Scenario', 'Method'}, 'MergeKeys', true, 'Type', 'left');
scenario_summary.NumReplicatesScored(isnan(scenario_summary.NumReplicatesScored)) = 0;
scenario_summary.NumMatchedWindows(isnan(scenario_summary.NumMatchedWindows))     = 0;
scenario_summary.HasMatchedWindows = scenario_summary.NumMatchedWindows > 0;
scenario_summary = sortrows(scenario_summary, {'MatchedSet', 'Case', 'Scenario', 'Method'});
end

function condition_summary = local_condition_summary(scenario_summary, num_scenarios)
%LOCAL_CONDITION_SUMMARY Equal-weight scenario means; withheld when scenario coverage is incomplete.
condition_summary = local_aggregate(scenario_summary, {'MatchedSet', 'Case', 'Method'}, { ...
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
%LOCAL_METHOD_SUMMARY Equal-weight condition means per matched set and method; withheld unless every condition is complete.
method_summary = local_aggregate(condition_summary, {'MatchedSet', 'Method'}, { ...
    'NumConditionsComplete', @sum,  'Complete'; ...
    'MAE',                   @mean, 'MAE'; ...
    'MSE',                   @mean, 'MSE'});
method_summary.RMSE     = sqrt(method_summary.MSE);
method_summary.Complete = method_summary.NumConditionsComplete == num_conditions;
end

function horizon_summary = local_horizon_summary(matched_horizon, condition_summary)
%LOCAL_HORIZON_SUMMARY Matched-window horizon errors aggregated with the same equal-weight hierarchy.
replicate_level = local_aggregate(matched_horizon, {'MatchedSet', 'Case', 'Scenario', 'Replicate', 'Method', 'HorizonIdx'}, {'MAE', @mean, 'AbsoluteError'; 'MSE', @mean, 'SquaredError'; 'RtDriverMAE', @mean, 'RtDriverAbsError'});
scenario_level  = local_aggregate(replicate_level, {'MatchedSet', 'Case', 'Scenario', 'Method', 'HorizonIdx'}, {'MAE', @mean, 'MAE'; 'MSE', @mean, 'MSE'; 'RtDriverMAE', @mean, 'RtDriverMAE'});
horizon_summary = local_aggregate(scenario_level, {'MatchedSet', 'Case', 'Method', 'HorizonIdx'}, {'NumScenariosScored', @numel, 'MAE'; 'MAE', @mean, 'MAE'; 'MSE', @mean, 'MSE'; 'RtDriverMAE', @mean, 'RtDriverMAE'});
horizon_summary.RMSE = sqrt(horizon_summary.MSE);

horizon_summary = innerjoin(horizon_summary, condition_summary(:, {'MatchedSet', 'Case', 'Method', 'Complete'}), 'Keys', {'MatchedSet', 'Case', 'Method'});
metric_names = {'MAE', 'MSE', 'RMSE', 'RtDriverMAE'};
for i = 1:numel(metric_names)
    horizon_summary.(metric_names{i})(~horizon_summary.Complete) = NaN;
end
end

function [paired_windows, paired_scenario, paired_condition] = local_paired_summary(matched_scores, cfg)
%LOCAL_PAIRED_SUMMARY Paired reference-versus-candidate comparisons within each matched set.
%   DeltaMAE = MAE_reference - MAE_candidate (positive: candidate more
%   accurate). DeltaMAEChange is the scenario-level DeltaMAE minus its
%   clean-baseline value.
comparisons = cfg.partB.paired_comparisons;
window_keys = {'Case', 'Scenario', 'Replicate', 'WindowDay'};
comparison_keys = {'MatchedSet', 'Comparison', 'Reference', 'Candidate'};
parts = cell(size(comparisons, 1), 1);

for c = 1:size(comparisons, 1)
    in_set    = matched_scores.MatchedSet == comparisons(c, 1);
    reference = renamevars(matched_scores(in_set & matched_scores.Method == comparisons(c, 2), [window_keys, {'MAE', 'RMSE'}]), {'MAE', 'RMSE'}, {'MAE_reference', 'RMSE_reference'});
    candidate = renamevars(matched_scores(in_set & matched_scores.Method == comparisons(c, 3), [window_keys, {'MAE', 'RMSE'}]), {'MAE', 'RMSE'}, {'MAE_candidate', 'RMSE_candidate'});
    pair = innerjoin(reference, candidate, 'Keys', window_keys);

    n = height(pair);
    identity = table(repmat(comparisons(c, 1), n, 1), repmat(comparisons(c, 2) + "_vs_" + comparisons(c, 3), n, 1), repmat(comparisons(c, 2), n, 1), repmat(comparisons(c, 3), n, 1), 'VariableNames', comparison_keys);
    pair.DeltaMAE        = pair.MAE_reference - pair.MAE_candidate;
    pair.DeltaRMSE       = pair.RMSE_reference - pair.RMSE_candidate;
    pair.CandidateBetter = double(pair.MAE_candidate < pair.MAE_reference);
    parts{c} = [identity, pair(:, [window_keys, {'MAE_reference', 'MAE_candidate', 'DeltaMAE', 'DeltaRMSE', 'CandidateBetter'}])];
end
paired_windows = vertcat(parts{:});

specs = {'NumMatchedWindows', @numel, 'DeltaMAE'; 'DeltaMAE', @mean, 'DeltaMAE'; 'DeltaRMSE', @mean, 'DeltaRMSE'; 'CandidateWinShare', @mean, 'CandidateBetter'};
replicate_level = local_aggregate(paired_windows, [comparison_keys, {'Case', 'Scenario', 'Replicate'}], specs);

specs_up = {'NumMatchedWindows', @sum, 'NumMatchedWindows'; 'DeltaMAE', @mean, 'DeltaMAE'; 'DeltaRMSE', @mean, 'DeltaRMSE'; 'CandidateWinShare', @mean, 'CandidateWinShare'};
paired_scenario = local_aggregate(replicate_level, [comparison_keys, {'Case', 'Scenario'}], [{'NumReplicatesScored', @numel, 'DeltaMAE'}; specs_up]);

clean = renamevars(paired_scenario(paired_scenario.Case == "clean_baseline", [comparison_keys, {'Scenario', 'DeltaMAE'}]), 'DeltaMAE', 'CleanDeltaMAE');
paired_scenario = outerjoin(paired_scenario, clean, 'Keys', [comparison_keys, {'Scenario'}], 'MergeKeys', true, 'Type', 'left');
paired_scenario.DeltaMAEChange = paired_scenario.DeltaMAE - paired_scenario.CleanDeltaMAE;
paired_scenario = sortrows(removevars(paired_scenario, 'CleanDeltaMAE'), [comparison_keys, {'Case', 'Scenario'}]);

paired_condition = local_aggregate(paired_scenario, [comparison_keys, {'Case'}], [{'NumScenariosScored', @numel, 'DeltaMAE'}; specs_up; {'DeltaMAEChange', @mean, 'DeltaMAEChange'}]);

case_ids = [cfg.partB.robustness_cases.case_id]';
[comparison_idx, case_idx] = ndgrid(1:size(comparisons, 1), 1:numel(case_ids));
grid = table(comparisons(comparison_idx(:), 1), comparisons(comparison_idx(:), 2) + "_vs_" + comparisons(comparison_idx(:), 3), comparisons(comparison_idx(:), 2), comparisons(comparison_idx(:), 3), case_ids(case_idx(:)), ...
    'VariableNames', [comparison_keys, {'Case'}]);
paired_condition = outerjoin(grid, paired_condition, 'Keys', [comparison_keys, {'Case'}], 'MergeKeys', true, 'Type', 'left');
paired_condition.NumScenariosScored(isnan(paired_condition.NumScenariosScored)) = 0;
paired_condition.Complete = paired_condition.NumScenariosScored == numel(cfg.scenarios);

metric_names = {'DeltaMAE', 'DeltaRMSE', 'CandidateWinShare', 'DeltaMAEChange'};
for i = 1:numel(metric_names)
    paired_condition.(metric_names{i})(~paired_condition.Complete) = NaN;
end
end

function [degradation_scenario, degradation] = local_degradation_summary(scenario_summary, num_scenarios)
%LOCAL_DEGRADATION_SUMMARY Scenario-level change relative to the clean baseline, averaged over scenarios.
clean = scenario_summary(scenario_summary.Case == "clean_baseline", {'MatchedSet', 'Scenario', 'Method', 'MAE', 'RMSE', 'NumMatchedWindows'});
clean = renamevars(clean, {'MAE', 'RMSE', 'NumMatchedWindows'}, {'CleanMAE', 'CleanRMSE', 'CleanMatchedWindows'});

stressed = scenario_summary(scenario_summary.Case ~= "clean_baseline", {'MatchedSet', 'Case', 'Scenario', 'Method', 'MAE', 'RMSE', 'NumMatchedWindows'});
degradation_scenario = innerjoin(stressed, clean, 'Keys', {'MatchedSet', 'Scenario', 'Method'});
degradation_scenario.MAEChange  = degradation_scenario.MAE - degradation_scenario.CleanMAE;
degradation_scenario.RMSEChange = degradation_scenario.RMSE - degradation_scenario.CleanRMSE;
degradation_scenario.MAERatio   = degradation_scenario.MAE ./ degradation_scenario.CleanMAE;
degradation_scenario = sortrows(degradation_scenario, {'MatchedSet', 'Case', 'Method', 'Scenario'});

defined = isfinite(degradation_scenario.MAEChange);
degradation_scenario.Defined = defined;
degradation = local_aggregate(degradation_scenario, {'MatchedSet', 'Case', 'Method'}, { ...
    'NumScenariosDefined', @sum,  'Defined'; ...
    'MAEChange',           @mean, 'MAEChange'; ...
    'RMSEChange',          @mean, 'RMSEChange'; ...
    'MAERatio',            @mean, 'MAERatio'});
degradation.Complete = degradation.NumScenariosDefined == num_scenarios;

metric_names = {'MAEChange', 'RMSEChange', 'MAERatio'};
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
