%PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS Select global Part A model configuration.
%
%   Description:
%       Evaluates candidate AR/ARX/state-space model configurations using the
%       Part A expanding-window forecast protocol, then selects one global
%       configuration by WIS with a one-standard-error parsimony rule.
%
%       Candidates that leave the SIRS susceptible domain are rejected. Other
%       unscoreable forecast outputs stop the script immediately.
%
%   Workflow:
%       1. Load Part A truth artifacts and build forecast windows.
%       2. Evaluate candidate configurations across all scenarios.
%       3. Select the simplest candidate within one standard error of the raw
%          best global WIS.
%       4. Save the model-selection result.
%
%   See also PARTA_01_GENERATE_TRUTH, PARTA_CONFIG, FORECAST_OPEN, ...
%            FORECAST_CLOSED, INTERVAL_BOUNDS, SIRS_INIT, COMPUTE_WIS.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-21

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

if isempty(file_list)
    error('PARTA_02:NoData', ...
        'No synthetic truth files found in %s. Run partA_01 first.', data_dir);
end

horizon       = cfg.forecast.horizon;
pop_size      = cfg.sirs.pop_size;
num_scenarios = numel(file_list);

scenario_template = struct( ...
    'scenario_id', "", ...
    'num_exo', 0, ...
    'windows', [], ...
    'window_data', struct('Rt_past', {}, 'truth_Rt', {}, 'U_past', {}, 'sirs_state', {}));
scenario_data = repmat(scenario_template, num_scenarios, 1);

for i = 1:num_scenarios
    loaded = load(fullfile(data_dir, file_list(i).name));

    Rt     = loaded.Rt_true;
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

    win_endpoints = cfg.forecast.min_window : cfg.forecast.step_size : (numel(Rt) - horizon);

    [windows, window_data] = local_build_windows(Rt, U_true, S_true, I_true, ...
        tspan, win_endpoints, horizon, pop_size, ~isempty(U_true));

    if isempty(window_data)
        error('PARTA_02:NoForecastWindows', ...
            ['Scenario %s has no intended forecast windows; check ' ...
            'min_window/step_size/horizon against the truth length.'], ...
            loaded.scenario_id);
    end

    scenario_data(i).scenario_id = string(loaded.scenario_id);
    scenario_data(i).num_exo     = size(U_true, 2);
    scenario_data(i).windows     = windows;
    scenario_data(i).window_data = window_data;

    fprintf('Prepared scenario %d/%d (%s): %d intended windows\n', ...
        i, num_scenarios, loaded.scenario_id, numel(window_data));
end

scenario_ids          = [scenario_data.scenario_id];
window_counts         = arrayfun(@(s) numel(s.windows), scenario_data(:)');
intended_window_count = sum(window_counts);

%% 3. Candidate Grid
switch model_type
    case "AR"
        candidate_grid = (1:cfg.forecast.max_ar_order)';
    case "ARX"
        [P, NB, NK] = ndgrid( ...
            1:cfg.forecast.max_ar_order, ...
            1:cfg.forecast.max_exo_order, ...
            1:cfg.forecast.max_exo_delay);
        candidate_grid = [P(:), NB(:), NK(:)];
    case {"N4SID", "SSEST"}
        [N_order, D_order] = ndgrid( ...
            1:cfg.forecast.max_state_order, ...
            cfg.forecast.state_diff_orders);
        candidate_grid = [N_order(:), D_order(:)];
    otherwise
        error('PARTA_02:UnknownModel', 'Unsupported model type: %s', model_type);
end

num_candidates = size(candidate_grid, 1);

%% 4. Candidate Evaluation
fprintf('Stage: Evaluating %d candidate configurations across %d scenarios\n', ...
    num_candidates, num_scenarios);

if isempty(gcp('nocreate'))
    parpool('Processes', cfg.run.num_workers);
    pool_cleanup = onCleanup(@local_shutdown_parallel_pool);
end

base_seed  = cfg.intervals.seed;
num_draws  = cfg.intervals.num_draws;
wis_alphas = cfg.forecast.wis_alphas;
vary       = cfg.intervals.include_epidemic_seed_variation;

scenario_data_const = parallel.pool.Constant(scenario_data);

if exo_mode == "None"
    sirs_stepper_const = [];
else
    sirs_stepper_const = parallel.pool.Constant(@() sirs_init(cfg.sirs, ...
        struct('solver', 'uds', 'compile', false, 'seed', base_seed)));
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
            win    = data.window_data(w);
            r_seed = local_resample_seed(base_seed, data.scenario_id, w, model_type, exo_mode);

            try
                if data.num_exo == 0
                    [~, ens] = forecast_open(model_type, params, win.Rt_past, ...
                        num_draws, horizon, r_seed);
                else
                    e_seed       = local_epidemic_seed(base_seed, data.scenario_id, w, model_type, exo_mode);
                    base_stepper = sirs_stepper_const.Value;
                    [~, ens] = forecast_closed(model_type, params, ...
                        win.Rt_past, win.U_past, win.sirs_state, data.num_exo, ...
                        num_draws, horizon, exo_mode, base_stepper, r_seed, e_seed, vary);
                end

                [lower, upper, Rt_pred] = interval_bounds(ens, wis_alphas);

                valid = numel(Rt_pred) == horizon && all(isfinite(Rt_pred)) ...
                    && all(Rt_pred > 0) && all(isfinite(lower(:))) ...
                    && all(isfinite(upper(:))) && all(lower(:) <= upper(:));
                if ~valid
                    error('PARTA_02:UnscoreableWindow', ...
                        'Forecast window produced invalid intervals or non-finite WIS.');
                end

                wis_h = compute_wis(win.truth_Rt, Rt_pred, lower, upper, wis_alphas);
                if numel(wis_h) ~= horizon || ~all(isfinite(wis_h))
                    error('PARTA_02:UnscoreableWindow', ...
                        'Forecast window produced invalid intervals or non-finite WIS.');
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
    error('PARTA_02:NoFeasibleCandidate', ...
        'No candidate completed all intended windows without domain failures.');
end

one_se_threshold     = best_global_wis + local_one_se(candidate_scores(raw_best_index, :));
candidate_complexity = local_candidate_complexity(model_type, candidate_grid, scenario_data(1).num_exo);
eligible             = isfinite(global_mean_wis) & (global_mean_wis <= one_se_threshold);
selected_index       = local_select_simplest(candidate_complexity, global_mean_wis, eligible);

selected_configuration = candidate_grid(selected_index, :);

%% 6. Artifact Saving
selection_rule = "minimum_global_wis_with_one_standard_error_parsimony";
cfg_snapshot   = cfg.run_snapshot;

file_prefix   = sprintf('partA_02_global_hyperparameters_%s_%s', model_type, exo_mode);
artifact_path = fullfile(selection_dir, [file_prefix, '.mat']);

save(artifact_path, ...
    'model_type', 'exo_mode', ...
    'selected_configuration', 'selected_index', ...
    'candidate_grid', 'candidate_scores', 'global_mean_wis', ...
    'scenario_ids', 'window_counts', ...
    'cfg_snapshot', 'wis_alphas', ...
    'best_global_wis', 'one_se_threshold', 'selection_rule');

fprintf('Selected global model configuration: %s\n', mat2str(selected_configuration));
fprintf('Global model-selection artifact saved to: %s\n', artifact_path);
fprintf('=== Global Model-Configuration Selection Complete ===\n\n');

%% 7. Local Functions

function [windows, window_data] = local_build_windows(Rt, U_true, S_true, I_true, ...
    tspan, win_endpoints, horizon, pop_size, has_exo)
%LOCAL_BUILD_WINDOWS Build expanding-window forecast entries for one scenario.
template = struct('Rt_past', [], 'truth_Rt', [], 'U_past', [], 'sirs_state', []);
built    = repmat(template, numel(win_endpoints), 1);
keep     = false(numel(win_endpoints), 1);

for k = 1:numel(win_endpoints)
    idx_T = find(tspan == win_endpoints(k), 1);
    if isempty(idx_T) || idx_T + horizon > numel(Rt)
        continue;
    end

    built(k).Rt_past  = Rt(1:idx_T);
    built(k).truth_Rt = Rt(idx_T + 1 : idx_T + horizon);
    keep(k) = true;

    if has_exo
        R_at_T = pop_size - S_true(idx_T) - I_true(idx_T);
        built(k).U_past     = U_true(1:idx_T, :);
        built(k).sirs_state = [S_true(idx_T), I_true(idx_T), R_at_T];
    end
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

function seed = local_resample_seed(base, scenario_id, w, model_type, exo_mode)
%LOCAL_RESAMPLE_SEED Deterministic resample seed for a given window context.
seed = local_hash_seed(base, {scenario_id, w, model_type, exo_mode});
end

function seed = local_epidemic_seed(base, scenario_id, w, model_type, exo_mode)
%LOCAL_EPIDEMIC_SEED Deterministic epidemic base seed for a given window context.
seed = local_hash_seed(base + 7919, {scenario_id, w, model_type, exo_mode});
end

function seed = local_hash_seed(base, parts)
%LOCAL_HASH_SEED Map identifiers to a deterministic positive integer seed.
modulus = 2147483647;
seed    = mod(double(base), modulus);

for i = 1:numel(parts)
    part = parts{i};

    if ischar(part) || isstring(part)
        chars = double(char(string(part)));
    else
        chars = double(part(:)).';
    end

    for c = chars
        seed = mod(seed * 131 + c + 7, modulus);
    end
end

if seed < 1
    seed = 1;
end
end