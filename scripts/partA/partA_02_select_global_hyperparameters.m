%PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS Select Part A model hyperparameters.
%
%   Description:
%       Evaluates candidate model configurations across all synthetic Rt
%       scenarios using expanding-window forecasts and WIS scoring. Exports
%       the selected configuration together with the valid candidate grid and
%       global candidate scores.
%
%   Workflow:
%       1. Load synthetic truth trajectories and build forecast windows.
%       2. Evaluate candidate configurations across all scenarios.
%       3. Select the simplest configuration within the one-standard-error rule.
%       4. Save the selected configuration and candidate-score evidence.
%
%   See also PARTA_CONFIG, PARTA_03_RUN_FORECASTS, FORECAST_OPEN, ...
%            FORECAST_CLOSED, INTERVAL_BOUNDS, COMPUTE_WIS.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-06-28

%% 1. Initialization
clear; close all; clc;

fprintf('=== Global Model-Configuration Selection ===\n');

cfg        = partA_config();
model_type = cfg.run.model_type;
exo_mode   = cfg.run.exo_mode;

fprintf('Configuration: Model = %s | Exogenous Mode = %s\n', model_type, exo_mode);

selection_dir = cfg.output.model_selection_dir;
if ~exist(selection_dir, 'dir')
    mkdir(selection_dir);
end

%% 2. Scenario Preparation
data_dir  = cfg.output.data_dir;
file_list = dir(fullfile(data_dir, 'partA_01_truth_*.mat'));
[~, order] = sort({file_list.name});
file_list = file_list(order);

if isempty(file_list)
    error('PARTA_02:NoData', 'No synthetic truth files found in %s. Run partA_01 first.', data_dir);
end

horizon       = cfg.forecast.horizon;
pop_size      = cfg.sirs.pop_size;
num_scenarios = numel(file_list);

scenario_template = struct('scenario_id', "", 'num_exo', 0, 'windows', [], 'window_data', struct('Rt_past', {}, 'U_past', {}, 'sirs_state', {}, 'truth_Rt', {}));
scenario_data = repmat(scenario_template, num_scenarios, 1);

for i = 1:num_scenarios
    loaded = load(fullfile(data_dir, file_list(i).name));

    Rt_true = loaded.Rt_true;
    S_true = loaded.S_true;
    I_true = loaded.I_true;
    tspan  = loaded.tspan;

    switch exo_mode
        case "None"
            U_true = [];
        case "S"
            U_true = S_true / pop_size;
        case "I"
            U_true = I_true / pop_size;
        case "Both"
            U_true = [S_true / pop_size, I_true / pop_size];
        otherwise
            error('PARTA_02:UnknownExoMode', 'Unsupported exo_mode: %s', exo_mode);
    end

    win_endpoints = cfg.forecast.min_window : cfg.forecast.step_size : (numel(Rt_true) - horizon);

    [windows, window_data] = local_build_windows(Rt_true, U_true, S_true, I_true, tspan, win_endpoints, horizon, pop_size, ~isempty(U_true));

    if isempty(window_data)
        error('PARTA_02:NoForecastWindows', ['Scenario %s has no intended forecast windows; check min_window/step_size/horizon against the truth length.'], loaded.scenario_id);
    end

    scenario_data(i).scenario_id = string(loaded.scenario_id);
    scenario_data(i).num_exo     = size(U_true, 2);
    scenario_data(i).windows     = windows;
    scenario_data(i).window_data = window_data;

    fprintf('Prepared scenario %d/%d (%s): %d intended windows\n', ...
        i, num_scenarios, loaded.scenario_id, numel(window_data));
end

intended_window_count = sum(arrayfun(@(s) numel(s.windows), scenario_data(:)'));

%% 3. Candidate Grid
switch model_type
    case "AR"
        candidate_grid = (1:cfg.forecast.max_ar_order)';
    case "ARX"
        [P, NB, NK] = ndgrid(1:cfg.forecast.max_ar_order, 1:cfg.forecast.max_exo_order, 1:cfg.forecast.max_exo_delay);
        candidate_grid = [P(:), NB(:), NK(:)];
    case {"N4SID", "SSEST"}
        [N_order, D_order] = ndgrid(1:cfg.forecast.max_state_order, cfg.forecast.state_diff_orders);
        candidate_grid = [N_order(:), D_order(:)];
    otherwise
        error('PARTA_02:UnknownModel', 'Unsupported model type: %s', model_type);
end

num_candidates = size(candidate_grid, 1);

%% 4. Candidate Evaluation
fprintf('Stage: Evaluating %d candidate configurations across %d scenarios\n', num_candidates, num_scenarios);

if isempty(gcp('nocreate'))
    parpool('Processes', cfg.run.num_workers);
    pool_cleanup = onCleanup(@local_shutdown_parallel_pool);
end

base_seed  = cfg.run.seed;
num_draws  = cfg.intervals.num_draws;
wis_alphas = cfg.forecast.wis_alphas;
vary       = cfg.intervals.include_epidemic_seed_variation;

scenario_data_const = parallel.pool.Constant(scenario_data);

if exo_mode == "None"
    sirs_stepper_const = [];
else
    sirs_stepper_const = parallel.pool.Constant(@() sirs_init(cfg.sirs, struct('solver', 'uds', 'seed', base_seed)));
end

candidate_scores = inf(num_candidates, num_scenarios);
global_mean_wis  = inf(num_candidates, 1);

parfor idx = 1:num_candidates
    params              = candidate_grid(idx, :);
    scen_wis            = nan(1, num_scenarios);
    completed_count     = 0;
    domain_failure      = false;
    scenario_data_local = scenario_data_const.Value;

    for s = 1:num_scenarios
        data       = scenario_data_local(s);
        window_wis = inf(numel(data.window_data), 1);

        for w = 1:numel(data.window_data)
            win         = data.window_data(w);

            window_seed = base_seed + 10000 * s + w;
            r_seed      = window_seed;

            try
                if data.num_exo == 0
                    [~, ens] = forecast_open(model_type, params, win.Rt_past, num_draws, horizon, r_seed);
                else
                    e_seed = window_seed + 1000000;
                    base_stepper = sirs_stepper_const.Value;
                    [~, ens] = forecast_closed(model_type, params, win.Rt_past, win.U_past, win.sirs_state, data.num_exo, num_draws, horizon, exo_mode, base_stepper, r_seed, e_seed, vary);
                end

                [lower, upper, Rt_pred] = interval_bounds(ens, wis_alphas);

                valid = numel(Rt_pred) == horizon && all(isfinite(Rt_pred)) && all(Rt_pred > 0) && all(isfinite(lower(:))) && all(isfinite(upper(:))) && all(lower(:) <= upper(:));
                if ~valid
                    error('PARTA_02:UnscoreableWindow', 'Forecast window produced invalid intervals or non-finite WIS.');
                end

                wis_h = compute_wis(win.truth_Rt, Rt_pred, lower, upper, wis_alphas);
                if numel(wis_h) ~= horizon || ~all(isfinite(wis_h))
                    error('PARTA_02:UnscoreableWindow', 'Forecast window produced invalid intervals or non-finite WIS.');
                end

                window_wis(w)  = mean(wis_h);
                completed_count = completed_count + 1;
            catch ME
                if strcmp(ME.identifier, 'EPIDEMIC:SusceptibleBelowThreshold')
                    domain_failure = true;
                    break;
                else
                    rethrow(ME);
                end
            end
        end

        if domain_failure
            break;
        end

        scen_wis(s) = mean(window_wis);
    end

    if ~domain_failure && completed_count == intended_window_count
        candidate_scores(idx, :) = scen_wis;
        global_mean_wis(idx)     = mean(scen_wis);
    end
end

fprintf('Stage: Candidate evaluation complete\n');
clear pool_cleanup

%% 5. Model Selection
[best_global_wis, raw_best_index] = min(global_mean_wis);

if ~isfinite(best_global_wis)
    error('PARTA_02:NoFeasibleCandidate', 'No candidate completed all intended windows without domain failures.');
end

one_se_threshold     = best_global_wis + local_one_se(candidate_scores(raw_best_index, :));
candidate_complexity = local_candidate_complexity(model_type, candidate_grid, scenario_data(1).num_exo);
eligible             = isfinite(global_mean_wis) & (global_mean_wis <= one_se_threshold);
selected_index       = local_select_simplest(candidate_complexity, global_mean_wis, eligible);

selected_configuration = candidate_grid(selected_index, :);

%% 6. Artifact Saving
selection_snapshot = cfg.snapshot.selection;
valid_candidates   = isfinite(global_mean_wis);

candidate_grid   = candidate_grid(valid_candidates, :);
candidate_scores = candidate_scores(valid_candidates, :);
global_mean_wis  = global_mean_wis(valid_candidates);

file_prefix   = sprintf('partA_02_global_hyperparameters_%s_%s', model_type, exo_mode);
artifact_path = fullfile(selection_dir, [file_prefix, '.mat']);

artifact = struct( ...
    'selected_configuration', selected_configuration, ...
    'snapshot', selection_snapshot, ...
    'candidate_grid', candidate_grid, ...
    'candidate_scores', candidate_scores, ...
    'global_mean_wis', global_mean_wis);

save(artifact_path, '-struct', 'artifact');

fprintf('Selected global model configuration: %s\n', mat2str(selected_configuration));
fprintf('Global model-selection artifact saved to: %s\n', artifact_path);
fprintf('=== Global Model-Configuration Selection Complete ===\n\n');

%% 7. Local Functions

function [windows, window_data] = local_build_windows(Rt, U_true, S_true, I_true, tspan, win_endpoints, horizon, pop_size, has_exo)
%LOCAL_BUILD_WINDOWS Build expanding-window forecast entries for one scenario.
template = struct('Rt_past', [], 'U_past', [], 'sirs_state', [], 'truth_Rt', []);
built    = repmat(template, numel(win_endpoints), 1);
keep     = false(numel(win_endpoints), 1);

for k = 1:numel(win_endpoints)
    idx_T = find(tspan == win_endpoints(k), 1);
    if isempty(idx_T) || idx_T + horizon > numel(Rt)
        continue;
    end

    built(k).Rt_past = Rt(1:idx_T);

    if has_exo
        R_at_T = pop_size - S_true(idx_T) - I_true(idx_T);
        built(k).U_past     = U_true(1:idx_T, :);
        built(k).sirs_state = [S_true(idx_T); I_true(idx_T); R_at_T];
    end

    built(k).truth_Rt = Rt(idx_T + 1 : idx_T + horizon);
    keep(k) = true;
end

windows     = win_endpoints(keep);
window_data = built(keep);
end

function local_shutdown_parallel_pool()
%LOCAL_SHUTDOWN_PARALLEL_POOL Close the local parallel pool before MATLAB exits.
pool = gcp('nocreate');
if ~isempty(pool)
    delete(pool);
end
end

function one_se = local_one_se(scenario_scores)
%LOCAL_ONE_SE Empirical standard error of the equal-scenario mean WIS.
n = numel(scenario_scores);
if n < 2
    one_se = 0;
else
    one_se = std(scenario_scores, 0) / sqrt(n);
end
end

function complexity = local_candidate_complexity(model_type, candidate_grid, num_exo)
%LOCAL_CANDIDATE_COMPLEXITY Estimated free-parameter count per candidate.
complexity = nan(size(candidate_grid, 1), 1);

for i = 1:size(candidate_grid, 1)
    row = candidate_grid(i, :);

    switch model_type
        case "AR"
            complexity(i) = row(1);
        case "ARX"
            complexity(i) = row(1) + num_exo * row(2) + row(3);
        case {"N4SID", "SSEST"}
            complexity(i) = row(1) + row(2);
        otherwise
            error('PARTA_02:UnknownModel', 'Unsupported model type: %s', model_type);
    end
end
end

function idx = local_select_simplest(candidate_complexity, global_mean_wis, eligible)
%LOCAL_SELECT_SIMPLEST Simplest eligible candidate; ties broken by WIS then index.
candidate_indices = find(eligible);
keys = [candidate_complexity(candidate_indices), ...
    global_mean_wis(candidate_indices), candidate_indices];
keys = sortrows(keys, [1 2 3]);
idx  = keys(1, 3);
end