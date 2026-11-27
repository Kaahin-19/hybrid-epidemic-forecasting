%PARTA_02_SELECT_HYPERPARAMETERS Select Part A model hyperparameters.
%
%   Description:
%       Selects the hyperparameters of the active model/input configuration
%       in three stages. Preliminary identification evaluates the candidate
%       grid on the periodic development trajectories. Cross-scenario
%       validation forecasts the fixed preliminary configuration on the
%       refinement trajectories of A1-A4. Final refinement evaluates the
%       candidate grid on the refinement trajectories, reusing the validation
%       forecasts of the preliminary configuration. Coefficients are
%       re-estimated at every forecast origin, and each selection takes the
%       simplest feasible candidate within one standard error of the minimum
%       trajectory-level WIS.
%
%       A candidate is feasible only when it forecasts every origin of every
%       trajectory of the stage. When no candidate is feasible in preliminary
%       identification or final refinement, the stage evidence is saved with
%       an unsuccessful selection, the dependent stages are not applicable, and
%       a no-feasible-candidate record takes the place of the final
%       configuration handover. Artifacts of this configuration that belong to
%       a superseded selection in a stage that is not applicable (and any
%       earlier handover) are removed so that they cannot be reused; a
%       successful selection removes an earlier no-feasible-candidate record.
%
%   Workflow:
%       1. Initialize the configured selection run.
%       2. Load the development trajectories.
%       3. Construct the candidate grid and its complexity ranking.
%       4. Perform preliminary identification on the development data.
%       5. Validate the preliminary configuration across A1-A4.
%       6. Refine and save the final configuration, or record that no
%          candidate is feasible.
%
%   See also PARTA_CONFIG, PARTA_01_GENERATE_TRUTH, PARTA_03_RUN_FORECASTS,
%            BUILD_FORECAST_WINDOWS, FORECAST_OPEN, FORECAST_CLOSED,
%            COMPUTE_WIS, COMPUTE_POINT_ERROR, COMPUTE_STRATIFIED_MEAN.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-11-27

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Hyperparameter Selection ===\n');

cfg        = partA_config();
model_type = cfg.run.model_type;
exo_mode   = cfg.run.exo_mode;

fprintf('Configuration: Model = %s | Exogenous Mode = %s\n', model_type, exo_mode);

selection_dir = cfg.output.model_selection_dir;
forecast_dir  = cfg.output.forecast_dir;

if ~exist(selection_dir, 'dir'), mkdir(selection_dir); end
if ~exist(forecast_dir, 'dir'), mkdir(forecast_dir); end

file_suffix  = model_type + "_" + exo_mode;
selection_id = string(datetime('now', 'Format', 'yyyyMMdd''T''HHmmss.SSS')) + "_" + file_suffix;
created      = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
multipliers  = [cfg.selection.se_multiplier; cfg.selection.sensitivity_multipliers];

paths = struct('development', fullfile(selection_dir, "partA_02_development_" + file_suffix + ".mat"), 'transfer', fullfile(forecast_dir, "partA_02_forecast_transfer_" + file_suffix + ".mat"), 'refinement', fullfile(selection_dir, "partA_02_refinement_" + file_suffix + ".mat"), 'handover', fullfile(selection_dir, "partA_02_global_hyperparameters_" + file_suffix + ".mat"), 'no_feasible', fullfile(selection_dir, "partA_02_no_feasible_candidate_" + file_suffix + ".mat"), 'assessment', fullfile(forecast_dir, "partA_03_forecast_assessment_" + file_suffix + ".mat"));

protocol = struct('model_type', model_type, 'exo_mode', exo_mode, 'horizon', cfg.forecast.horizon, 'num_draws', cfg.intervals.num_draws, 'wis_alphas', cfg.forecast.wis_alphas, 'base_seed', cfg.run.seed, 'vary_epidemic_seed', cfg.intervals.include_epidemic_seed_variation, 'infeasibility_ids', cfg.forecast.infeasibility_ids);

%% 2. Development Dataset Preparation
if exist(cfg.output.dataset_manifest, 'file') ~= 2
    error('PARTA_02:MissingDatasets', 'Missing dataset manifest %s. Run partA_01 first.', cfg.output.dataset_manifest);
end

manifest = load(cfg.output.dataset_manifest);

if ~isequaln(manifest.snapshot, cfg.snapshot.design)
    error('PARTA_02:DatasetDesignMismatch', 'The Part A datasets were generated under a different dataset design. Rerun with ./run_partA_pipeline.sh --fresh.');
end

development = local_load_role(cfg, manifest.datasets, "development", exo_mode);
num_exo     = development(1).num_exo;

%% 3. Candidate Grid
% Complexity counts estimated coefficients: AR p; ARX na + r*nb, where the
% input delay nk is not a coefficient; state space n*(2 + r) for an
% innovations-form model with D = 0 (A, B, and K in observability-canonical
% form). Ties are broken by the largest lag, then by WIS, then by grid order.
switch model_type
    case "AR"
        candidate_grid = (1:cfg.forecast.max_ar_order)';
        complexity     = candidate_grid;
        max_lag        = candidate_grid;
    case "ARX"
        [P, NB, NK]    = ndgrid(1:cfg.forecast.max_ar_order, 1:cfg.forecast.max_exo_order, 1:cfg.forecast.max_exo_delay);
        candidate_grid = [P(:), NB(:), NK(:)];
        complexity     = candidate_grid(:, 1) + num_exo * candidate_grid(:, 2);
        max_lag        = max(candidate_grid(:, 1), candidate_grid(:, 3) + candidate_grid(:, 2) - 1);
    case {"N4SID", "SSEST"}
        candidate_grid = (1:cfg.forecast.max_state_order)';
        complexity     = candidate_grid * (2 + num_exo);
        max_lag        = candidate_grid;
end

num_candidates = size(candidate_grid, 1);

%% 4. Preliminary Model Identification
fprintf('Stage 1: Preliminary identification - evaluating %d candidates on %d development trajectories\n', num_candidates, numel(development));

if isempty(gcp('nocreate'))
    parpool('Processes', cfg.run.num_workers);
    pool_cleanup = onCleanup(@local_shutdown_parallel_pool);
end

if exo_mode == "None"
    stepper_const = [];
else
    stepper_const = parallel.pool.Constant(@() sirs_init(cfg.sirs, struct('solver', 'uds', 'seed', cfg.run.seed)));
end

development_const = parallel.pool.Constant(development);
records = local_evaluate_candidates(candidate_grid, 1:num_candidates, development_const, stepper_const, protocol);
clear development_const

development_evidence = local_selection_evidence(records, development, candidate_grid, complexity, max_lag, multipliers);

preliminary_index         = development_evidence.selection.selected_index;
preliminary_configuration = nan(1, size(candidate_grid, 2));

if ~isnan(preliminary_index)
    preliminary_configuration = candidate_grid(preliminary_index, :);
end

development_artifact = development_evidence;
development_artifact.stage                     = "development";
development_artifact.model_type                = model_type;
development_artifact.exo_mode                  = exo_mode;
development_artifact.selection_id              = selection_id;
development_artifact.preliminary_configuration = preliminary_configuration;
development_artifact.snapshot                  = cfg.snapshot.selection;
development_artifact.created                   = created;

save(paths.development, '-struct', 'development_artifact');

local_print_selection("Preliminary", development_evidence, preliminary_configuration);
fprintf('Development artifact saved to: %s\n', paths.development);

if isnan(preliminary_index)
    clear pool_cleanup stepper_const
    local_record_no_feasible_candidate(paths, "development", ["transfer"; "refinement"; "assessment"], development_evidence, development_artifact);
    fprintf('=== Part A Hyperparameter Selection Complete ===\n\n');
    return;
end

%% 5. Cross-Scenario Validation
refinement = local_load_role(cfg, manifest.datasets, "refinement", exo_mode);

fprintf('Stage 2: Cross-scenario validation - forecasting the preliminary configuration on %d refinement trajectories\n', numel(refinement));

refinement_const = parallel.pool.Constant(refinement);
transfer_cells   = cell(numel(refinement), 1);

parfor j = 1:numel(refinement)
    trajectories      = refinement_const.Value;
    transfer_cells{j} = local_forecast_trajectory(preliminary_configuration, trajectories(j), local_worker_stepper(stepper_const), protocol, false);
    fprintf('Forecast trajectory %s\n', trajectories(j).dataset_id);
end

transfer_forecasts = vertcat(transfer_cells{:});

transfer_artifact = struct('stage', "transfer", 'model_type', model_type, 'exo_mode', exo_mode, 'configuration', preliminary_configuration, 'configuration_role', "preliminary", 'selection_id', selection_id, 'wis_alphas', cfg.forecast.wis_alphas, 'horizon', cfg.forecast.horizon, 'seed_policy', cfg.forecast.seed_policy, 'dataset_ids', [refinement.dataset_id]', 'forecasts', transfer_forecasts, 'snapshot', cfg.snapshot.forecast, 'created', created);

save(paths.transfer, '-struct', 'transfer_artifact');

transfer_status = vertcat(transfer_forecasts.status);
fprintf('Preliminary configuration forecast at %d of %d refinement origins; transfer artifact saved to: %s\n', sum(transfer_status == "ok"), numel(transfer_status), paths.transfer);

%% 6. Final Model Refinement
fprintf('Stage 3: Final refinement - evaluating %d candidates on %d refinement trajectories\n', num_candidates - 1, numel(refinement));

records = local_evaluate_candidates(candidate_grid, setdiff(1:num_candidates, preliminary_index), refinement_const, stepper_const, protocol);
records{preliminary_index} = local_record_from_forecasts(transfer_forecasts);

clear pool_cleanup refinement_const stepper_const

refinement_evidence = local_selection_evidence(records, refinement, candidate_grid, complexity, max_lag, multipliers);

final_index         = refinement_evidence.selection.selected_index;
selection           = refinement_evidence.selection;
final_configuration = nan(1, size(candidate_grid, 2));
comparison          = struct('preliminary_global_score', selection.global_score(preliminary_index), 'final_global_score', NaN, 'preliminary_stratum_score', selection.stratum_score(preliminary_index, :).', 'final_stratum_score', nan(numel(selection.stratum_ids), 1), 'preliminary_complexity', complexity(preliminary_index), 'final_complexity', NaN);

if ~isnan(final_index)
    final_configuration            = candidate_grid(final_index, :);
    comparison.final_global_score  = selection.global_score(final_index);
    comparison.final_stratum_score = selection.stratum_score(final_index, :).';
    comparison.final_complexity    = complexity(final_index);
end

refinement_artifact = refinement_evidence;
refinement_artifact.stage                     = "refinement";
refinement_artifact.model_type                = model_type;
refinement_artifact.exo_mode                  = exo_mode;
refinement_artifact.selection_id              = selection_id;
refinement_artifact.preliminary_index         = preliminary_index;
refinement_artifact.preliminary_configuration = preliminary_configuration;
refinement_artifact.preliminary_source        = "Stage 2 transfer forecasts (identical trajectories, seeds, and protocol)";
refinement_artifact.final_configuration       = final_configuration;
refinement_artifact.comparison                = comparison;
refinement_artifact.snapshot                  = cfg.snapshot.selection;
refinement_artifact.created                   = created;

save(paths.refinement, '-struct', 'refinement_artifact');

local_print_selection("Final", refinement_evidence, final_configuration);
fprintf('Refinement artifact saved to: %s\n', paths.refinement);

if isnan(final_index)
    local_record_no_feasible_candidate(paths, "refinement", "assessment", refinement_evidence, refinement_artifact);
    fprintf('=== Part A Hyperparameter Selection Complete ===\n\n');
    return;
end

[~, refinement_name, refinement_ext] = fileparts(paths.refinement);
handover = struct('selected_configuration', final_configuration, 'snapshot', cfg.snapshot.selection, 'model_type', model_type, 'exo_mode', exo_mode, 'preliminary_configuration', preliminary_configuration, 'selection_stage', "refinement", 'selection_id', selection_id, 'source_artifact', refinement_name + refinement_ext, 'created', created);

save(paths.handover, '-struct', 'handover');
local_remove_superseded(paths.no_feasible);

fprintf('Selection outcome: final configuration %s\n', mat2str(final_configuration));
fprintf('Final configuration handover saved to: %s\n', paths.handover);
fprintf('=== Part A Hyperparameter Selection Complete ===\n\n');

%% 7. Local Functions
function local_shutdown_parallel_pool()
%LOCAL_SHUTDOWN_PARALLEL_POOL Close the local parallel pool before MATLAB exits.
pool = gcp('nocreate');
if ~isempty(pool)
    delete(pool);
end
end

function stepper = local_worker_stepper(stepper_const)
%LOCAL_WORKER_STEPPER Return the worker's SIRS stepper, or [] for output-only models.
if isempty(stepper_const)
    stepper = [];
else
    stepper = stepper_const.Value;
end
end

function trajectories = local_load_role(cfg, datasets, role, exo_mode)
%LOCAL_LOAD_ROLE Load the trajectories of one dataset role and construct their forecast windows.
rows     = datasets(datasets.Role == role, :);
template = struct('dataset_id', "", 'family', "", 'stratum', "", 'is_canonical', false, 'seed_index', 0, 'tspan', [], 'Rt_true', [], 'num_exo', 0, 'window_data', []);
trajectories = repmat(template, height(rows), 1);

for j = 1:height(rows)
    loaded = load(fullfile(cfg.output.data_dir, rows.File(j)));

    [window_data, num_exo] = build_forecast_windows(loaded.Rt_true, loaded.S_true, loaded.I_true, loaded.tspan, exo_mode, cfg.sirs.pop_size, cfg.forecast.min_window, cfg.forecast.step_size, cfg.forecast.horizon);

    if isempty(window_data)
        error('PARTA_02:NoForecastWindows', 'Trajectory %s has no forecast windows; check min_window, step_size, and horizon against the truth length.', loaded.dataset_id);
    end

    trajectories(j) = struct('dataset_id', loaded.dataset_id, 'family', loaded.family, 'stratum', loaded.stratum, 'is_canonical', loaded.is_canonical, 'seed_index', loaded.seed_index, 'tspan', loaded.tspan, 'Rt_true', loaded.Rt_true, 'num_exo', num_exo, 'window_data', window_data);
end

fprintf('Loaded %d %s trajectories with %d forecast origins each\n', height(rows), role, numel(trajectories(1).window_data));
end

function records = local_evaluate_candidates(candidate_grid, candidate_indices, trajectories_const, stepper_const, protocol)
%LOCAL_EVALUATE_CANDIDATES Evaluate the listed candidates in parallel under the complete-case rule.
records   = cell(size(candidate_grid, 1), 1);
evaluated = cell(numel(candidate_indices), 1);

parfor i = 1:numel(candidate_indices)
    evaluated{i} = local_evaluate_candidate(candidate_grid(candidate_indices(i), :), trajectories_const.Value, local_worker_stepper(stepper_const), protocol);
end

records(candidate_indices) = evaluated;
end

function record = local_evaluate_candidate(params, trajectories, stepper, protocol)
%LOCAL_EVALUATE_CANDIDATE Score one candidate on every trajectory until its first infeasible forecast.
record = local_empty_record(numel(trajectories), numel(trajectories(1).window_data));

for j = 1:numel(trajectories)
    forecasts = local_forecast_trajectory(params, trajectories(j), stepper, protocol, true);
    record    = local_add_to_record(record, j, forecasts);

    failed_window = find(forecasts.status == "infeasible", 1);
    if ~isempty(failed_window)
        fprintf('Infeasible candidate %s on %s at origin day %d: %s\n', mat2str(params), trajectories(j).dataset_id, forecasts.window_day(failed_window), forecasts.error_message(failed_window));
        break;
    end
end

fprintf('Evaluated candidate %s\n', mat2str(params));
end

function record = local_record_from_forecasts(forecasts)
%LOCAL_RECORD_FROM_FORECASTS Convert fixed-configuration trajectory forecasts into a candidate record.
record = local_empty_record(numel(forecasts), numel(forecasts(1).window_day));

for j = 1:numel(forecasts)
    record = local_add_to_record(record, j, forecasts(j));
end
end

function record = local_empty_record(num_trajectories, num_windows)
%LOCAL_EMPTY_RECORD Trajectory-by-origin candidate record with every origin not yet evaluated.
record = struct('status', repmat("not_evaluated", num_trajectories, num_windows), 'error_id', strings(num_trajectories, num_windows), 'wis', nan(num_trajectories, num_windows), 'mae', nan(num_trajectories, num_windows), 'rmse', nan(num_trajectories, num_windows), 'aicc', nan(num_trajectories, num_windows), 'spectral_radius', nan(num_trajectories, num_windows), 'iteration_limit_reached', false(num_trajectories, num_windows));
end

function record = local_add_to_record(record, j, forecasts)
%LOCAL_ADD_TO_RECORD Store the origin-level scores of one trajectory in a candidate record.
record.status(j, :)                  = forecasts.status.';
record.error_id(j, :)                = forecasts.error_id.';
record.wis(j, :)                     = forecasts.window_wis.';
record.mae(j, :)                     = forecasts.window_mae.';
record.rmse(j, :)                    = forecasts.window_rmse.';
record.aicc(j, :)                    = forecasts.aicc.';
record.spectral_radius(j, :)         = forecasts.spectral_radius.';
record.iteration_limit_reached(j, :) = forecasts.iteration_limit_reached.';
end

function forecasts = local_forecast_trajectory(params, trajectory, stepper, protocol, stop_on_failure)
%LOCAL_FORECAST_TRAJECTORY Forecast one fixed configuration at every origin of one trajectory.
window_data = trajectory.window_data;
num_windows = numel(window_data);
H           = protocol.horizon;
K           = numel(protocol.wis_alphas);

forecasts = struct('dataset_id', trajectory.dataset_id, 'family', trajectory.family, 'stratum', trajectory.stratum, 'is_canonical', trajectory.is_canonical, 'seed_index', trajectory.seed_index, 'tspan', trajectory.tspan, 'Rt_true', trajectory.Rt_true, 'window_day', [window_data.window_day].', 'window_idx', [window_data.window_day_idx].', 'status', repmat("not_evaluated", num_windows, 1), 'error_id', strings(num_windows, 1), 'error_message', strings(num_windows, 1), 'origin_Rt', arrayfun(@(win) win.Rt_past(end), window_data), 'truth_Rt', [window_data.truth_Rt], 'forecast_median', nan(H, num_windows), 'forecast_lower', nan(H, K, num_windows), 'forecast_upper', nan(H, K, num_windows), 'window_wis', nan(num_windows, 1), 'window_mae', nan(num_windows, 1), 'window_rmse', nan(num_windows, 1), 'aicc', nan(num_windows, 1), 'spectral_radius', nan(num_windows, 1), 'termination', strings(num_windows, 1), 'iteration_limit_reached', false(num_windows, 1));

for w = 1:num_windows
    win         = window_data(w);
    window_seed = protocol.base_seed + 10000 * trajectory.seed_index + w;

    try
        if isempty(win.U_past)
            [ensemble, fit_info] = forecast_open(protocol.model_type, params, win.Rt_past, protocol.num_draws, H, window_seed);
        else
            [ensemble, fit_info] = forecast_closed(protocol.model_type, params, win.Rt_past, win.U_past, win.sirs_state, size(win.U_past, 2), protocol.num_draws, H, protocol.exo_mode, stepper, window_seed, window_seed + 1000000, protocol.vary_epidemic_seed);
        end
    catch ME
        if ~any(ME.identifier == protocol.infeasibility_ids)
            rethrow(ME);
        end

        forecasts.status(w)        = "infeasible";
        forecasts.error_id(w)      = ME.identifier;
        forecasts.error_message(w) = ME.message;

        if stop_on_failure
            return;
        end
        continue;
    end

    median_Rt = median(ensemble, 2);
    lower     = quantile(ensemble, protocol.wis_alphas.' / 2, 2);
    upper     = quantile(ensemble, 1 - protocol.wis_alphas.' / 2, 2);
    wis       = compute_wis(win.truth_Rt, median_Rt, lower, upper, protocol.wis_alphas);
    point     = compute_point_error(win.truth_Rt, median_Rt);

    forecasts.status(w)                  = "ok";
    forecasts.forecast_median(:, w)      = median_Rt;
    forecasts.forecast_lower(:, :, w)    = lower;
    forecasts.forecast_upper(:, :, w)    = upper;
    forecasts.window_wis(w)              = mean(wis);
    forecasts.window_mae(w)              = point.mae;
    forecasts.window_rmse(w)             = point.rmse;
    forecasts.aicc(w)                    = fit_info.AICc;
    forecasts.spectral_radius(w)         = fit_info.spectral_radius;
    forecasts.termination(w)             = fit_info.termination;
    forecasts.iteration_limit_reached(w) = fit_info.iteration_limit_reached;
end
end

function evidence = local_selection_evidence(records, trajectories, candidate_grid, complexity, max_lag, multipliers)
%LOCAL_SELECTION_EVIDENCE Stack candidate records and apply the one-SE rule to their trajectory-level WIS.
fields     = fieldnames(records{1});
evaluation = struct();

for i = 1:numel(fields)
    blocks = cellfun(@(record) record.(fields{i}), records, 'UniformOutput', false);
    evaluation.(fields{i}) = permute(cat(3, blocks{:}), [3, 1, 2]);
end

feasible = all(evaluation.status == "ok", [2, 3]);

trajectory_scores = mean(evaluation.wis, 3);
trajectory_scores(~feasible, :) = NaN;

strata    = [trajectories.stratum]';
is_random = ~[trajectories.is_canonical]';
selection = local_select_one_se(trajectory_scores, feasible, complexity, max_lag, strata, is_random, multipliers);

selection.minimum_on_grid_boundary  = false;
selection.selected_on_grid_boundary = false;

if any(feasible)
    grid_upper = max(candidate_grid, [], 1);
    selection.minimum_on_grid_boundary  = any(candidate_grid(selection.best_index, :) == grid_upper);
    selection.selected_on_grid_boundary = any(candidate_grid(selection.selected_index, :) == grid_upper);
end

evidence = struct('dataset_ids', [trajectories.dataset_id]', 'families', [trajectories.family]', 'strata', strata, 'is_random', is_random, 'window_days', [trajectories(1).window_data.window_day]', 'candidate_grid', candidate_grid, 'complexity', complexity, 'max_lag', max_lag, 'evaluation', evaluation, 'feasible', feasible, 'trajectory_scores', trajectory_scores, 'selection', selection);
end

function selection = local_select_one_se(trajectory_scores, feasible, complexity, max_lag, strata, is_random, multipliers)
%LOCAL_SELECT_ONE_SE Select the simplest feasible candidate within a multiple of one SE of the minimum WIS; indices are NaN without a feasible candidate.
num_candidates = size(trajectory_scores, 1);
num_strata     = numel(unique(strata));
global_score   = nan(num_candidates, 1);
global_se      = nan(num_candidates, 1);
stratum_score  = nan(num_candidates, num_strata);
stratum_se     = nan(num_candidates, num_strata);

for c = find(feasible).'
    [global_score(c), global_se(c), stratum_mean, stratum_error] = compute_stratified_mean(trajectory_scores(c, :).', strata, is_random);
    stratum_score(c, :) = stratum_mean.';
    stratum_se(c, :)    = stratum_error.';
end

best_score       = NaN;
best_index       = NaN;
best_se          = NaN;
thresholds       = nan(numel(multipliers), 1);
eligible         = false(num_candidates, numel(multipliers));
selected_indices = nan(numel(multipliers), 1);

if any(feasible)
    [best_score, best_index] = min(global_score);
    best_se    = global_se(best_index);
    thresholds = best_score + multipliers * best_se;
    eligible   = feasible & global_score <= thresholds.';

    for m = 1:numel(multipliers)
        candidates          = find(eligible(:, m));
        ranking             = sortrows([complexity(candidates), max_lag(candidates), global_score(candidates), candidates]);
        selected_indices(m) = ranking(1, 4);
    end
end

selection = struct('stratum_ids', unique(strata, 'stable'), 'global_score', global_score, 'global_se', global_se, 'stratum_score', stratum_score, 'stratum_se', stratum_se, 'best_index', best_index, 'best_score', best_score, 'se', best_se, 'multipliers', multipliers, 'thresholds', thresholds, 'eligible', eligible, 'selected_indices', selected_indices, 'selected_index', selected_indices(1), 'threshold', thresholds(1));
end

function local_print_selection(label, evidence, configuration)
%LOCAL_PRINT_SELECTION Print the one-SE selection summary of one stage.
selection = evidence.selection;

if isnan(selection.selected_index)
    [ids, counts] = local_infeasibility_counts(evidence.evaluation);
    fprintf('%s configuration: none | feasible 0/%d | no candidate produced scoreable forecasts at every origin of every trajectory; recorded infeasible forecasts by identifier: %s\n', label, numel(evidence.feasible), strjoin(compose("%s = %d", ids, counts), ', '));
    return;
end

fprintf('%s configuration: %s | feasible %d/%d | minimum WIS %.4g at %s | SE %.3g | threshold %.4g | eligible %d\n', label, mat2str(configuration), nnz(evidence.feasible), numel(evidence.feasible), selection.best_score, mat2str(evidence.candidate_grid(selection.best_index, :)), selection.se, selection.threshold, nnz(selection.eligible(:, 1)));
end

function [ids, counts] = local_infeasibility_counts(evaluation)
%LOCAL_INFEASIBILITY_COUNTS Recorded infeasible forecasts of a selection stage by error identifier.
[ids, ~, id_index] = unique(evaluation.error_id(evaluation.status == "infeasible"));
counts = accumarray(id_index, 1, [numel(ids), 1]);
end

function local_record_no_feasible_candidate(paths, failed_stage, not_applicable, evidence, stage_artifact)
%LOCAL_RECORD_NO_FEASIBLE_CANDIDATE Remove superseded artifacts of the stages that are not applicable and save the no-feasible-candidate record.
superseded = paths.handover;
for stage = not_applicable.'
    superseded(end + 1, 1) = paths.(stage);
end
local_remove_superseded(superseded);

[ids, counts]  = local_infeasibility_counts(evidence.evaluation);
[~, name, ext] = fileparts(paths.(failed_stage));

record = struct('outcome', "no_feasible_candidate", 'failed_stage', failed_stage, 'not_applicable_stages', not_applicable, 'model_type', stage_artifact.model_type, 'exo_mode', stage_artifact.exo_mode, 'selection_id', stage_artifact.selection_id, 'source_artifact', name + ext, 'num_candidates', numel(evidence.feasible), 'infeasibility_ids', ids, 'infeasibility_counts', counts, 'snapshot', stage_artifact.snapshot, 'created', stage_artifact.created);
save(paths.no_feasible, '-struct', 'record');

fprintf('Selection outcome: no feasible candidate in %s; not applicable: %s\n', failed_stage, strjoin(not_applicable, ', '));
fprintf('No-feasible-candidate record saved to: %s\n', paths.no_feasible);
end

function local_remove_superseded(artifact_paths)
%LOCAL_REMOVE_SUPERSEDED Delete existing artifacts of this configuration that a newer selection supersedes.
for k = 1:numel(artifact_paths)
    if isfile(artifact_paths(k))
        delete(artifact_paths(k));
        fprintf('Removed superseded artifact: %s\n', artifact_paths(k));
    end
end
end
