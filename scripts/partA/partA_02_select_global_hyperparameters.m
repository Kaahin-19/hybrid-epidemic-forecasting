%PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS Select global Part A model hyperparameters.
%
%   Description:
%       Evaluates the active model family and exogenous-input setting across
%       all Part A synthetic truth scenarios, using an expanding-window WIS
%       protocol. Closed-loop windows whose forecast-origin SIRS state already
%       lies outside the valid Rt-to-beta domain are inadmissible and excluded
%       from scoring (counts saved per scenario); admissible windows whose
%       forecast leaves the domain during the horizon stay invalid and receive
%       Inf WIS. Per-scenario WIS is the plain mean over admissible windows, and
%       the global score the equal-scenario mean. The raw best candidate has the
%       lowest global mean WIS; the final selected configuration is the simplest
%       candidate whose global mean WIS lies within one empirical standard error
%       of that raw best (one-SE parsimony rule). WIS remains the selection
%       metric; AICc stays diagnostic only.
%
%   Workflow:
%       1. Load configuration and synthetic truth artifacts.
%       2. Build the candidate grid, expanding-window data, and window admissibility.
%       3. Score each candidate via expanding-window WIS (parfor over candidates).
%       4. Apply one-SE parsimony rule and save one model-selection artifact.
%
%   See also PARTA_CONFIG, FORECAST_OPEN, FORECAST_CLOSED, INTERVAL_BOUNDS, COMPUTE_WIS.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-17

%% 1. Initialization
clear; close all; clc;

fprintf('=== Global Model-Configuration Selection ===\n');

cfg        = partA_config();
model_type = cfg.run.model_type;
exo_mode   = cfg.run.exo_mode;

fprintf('Configuration: Model = %s | Exogenous Mode = %s\n', model_type, exo_mode);

selectionDir = cfg.output.model_selection_dir;
if ~exist(selectionDir, 'dir')
    mkdir(selectionDir);
end

%% 2. Data Loading and Candidate Setup
data_dir  = cfg.output.data_dir;
file_list = dir(fullfile(data_dir, 'partA_01_truth_*.mat'));

if isempty(file_list)
    error('PARTA_02:NoData', ...
        'No synthetic truth files found in %s. Run partA_01 first.', data_dir);
end

horizon  = cfg.forecast.horizon;
pop_size = cfg.sirs.pop_size;
n_scenarios = numel(file_list);
scenario_template = struct( ...
    'scenario_id', "", ...
    'num_exo', 0, ...
    'windows', [], ...
    'window_data', struct('Rt_past', {}, 'truth_Rt', {}, 'U_past', {}, 'sirs_state', {}), ...
    'admissible', [], ...
    'num_admissible', 0, ...
    'num_inadmissible', 0);
scenario_data = repmat(scenario_template, n_scenarios, 1);

for i = 1:numel(file_list)
    loaded = load(fullfile(data_dir, file_list(i).name));

    Rt     = loaded.Rt_true;
    S_true = loaded.S_true;
    I_true = loaded.I_true;
    tspan  = loaded.tspan;

    assert(isnumeric(Rt)     && iscolumn(Rt),     'PARTA_02:BadArtifact', ...
        'Rt_true must be a numeric column vector in partA_01 artifact.');
    assert(isnumeric(S_true) && iscolumn(S_true), 'PARTA_02:BadArtifact', ...
        'S_true must be a numeric column vector in partA_01 artifact.');
    assert(isnumeric(I_true) && iscolumn(I_true), 'PARTA_02:BadArtifact', ...
        'I_true must be a numeric column vector in partA_01 artifact.');
    assert(isnumeric(tspan)  && iscolumn(tspan),  'PARTA_02:BadArtifact', ...
        'tspan must be a numeric column vector in partA_01 artifact.');

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

    num_exo       = size(U_true, 2);
    win_endpoints = cfg.forecast.min_window : cfg.forecast.step_size : (numel(Rt) - horizon);

    scenario_data(i).scenario_id = string(loaded.scenario_id);
    scenario_data(i).num_exo     = num_exo;
    scenario_data(i).windows     = win_endpoints;
    scenario_data(i).window_data = local_build_windows(Rt, U_true, S_true, I_true, ...
        tspan, win_endpoints, horizon, pop_size, num_exo > 0);

    % Window-admissibility pre-screen: a closed-loop window whose forecast-origin
    % SIRS state is already outside the valid Rt-to-beta domain (depleted S, etc.)
    % is inadmissible and excluded from scoring. Open-loop windows are always
    % admissible (no closed-loop origin). Same domain rule as the in-horizon guard.
    n_wins     = numel(scenario_data(i).window_data);
    admissible = true(n_wins, 1);
    if num_exo > 0
        for k = 1:n_wins
            st = scenario_data(i).window_data(k).sirs_state;
            admissible(k) = ~isempty(st) && isnumeric(st) && numel(st) == 3 ...
                && all(isfinite(st)) && all(st >= 0) ...
                && abs(sum(st) - pop_size) <= cfg.sirs.mass_tol * pop_size ...
                && st(1) >= cfg.sirs.min_susceptible;
        end
    end
    scenario_data(i).admissible       = admissible;
    scenario_data(i).num_admissible   = sum(admissible);
    scenario_data(i).num_inadmissible = sum(~admissible);

    fprintf(['Prepared scenario %d/%d (%s): %d windows, %d admissible, ' ...
        '%d inadmissible (depleted-S origin)\n'], i, numel(file_list), ...
        loaded.scenario_id, n_wins, sum(admissible), sum(~admissible));
end

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

scenario_ids  = [scenario_data.scenario_id];
window_counts = arrayfun(@(s) numel(s.windows), scenario_data(:)');
num_scenarios = numel(scenario_data);

if isempty(gcp('nocreate'))
    parpool('Processes', cfg.run.num_workers);
    pool_cleanup = onCleanup(@local_shutdown_parallel_pool);
end

scenario_data_const = parallel.pool.Constant(scenario_data);

%% 3. Candidate Evaluation
fprintf('Stage: Evaluating %d candidate configurations across %d scenarios\n', ...
    num_candidates, num_scenarios);

base_seed  = cfg.intervals.seed;
vary       = cfg.intervals.include_epidemic_seed_variation;
num_draws  = cfg.intervals.num_draws;
wis_alphas = cfg.forecast.wis_alphas;
sirs_cfg   = cfg.sirs;

candidate_scores = inf(num_candidates, num_scenarios);
global_mean_wis  = inf(num_candidates, 1);
candidate_aicc   = nan(num_candidates, num_scenarios);
global_mean_aicc = nan(num_candidates, 1);

parfor idx = 1:num_candidates
    params    = candidate_grid(idx, :);
    scen_wis  = inf(1, num_scenarios);
    scen_aicc = nan(1, num_scenarios);
    scenario_data_local = scenario_data_const.Value;

    for s = 1:num_scenarios
        data        = scenario_data_local(s);
        adm         = data.admissible;
        window_wis  = inf(numel(data.window_data), 1);
        window_aicc = nan(numel(data.window_data), 1);

        for w = 1:numel(data.window_data)
            if ~adm(w)
                continue;   % inadmissible forecast origin: excluded from scoring
            end
            win    = data.window_data(w);
            r_seed = local_resample_seed(base_seed, data.scenario_id, w, model_type, exo_mode);
            e_seed = local_epidemic_seed(base_seed, data.scenario_id, w, model_type, exo_mode);

            if data.num_exo == 0
                [ensemble, aicc_w] = forecast_open(model_type, params, win.Rt_past, ...
                    num_draws, horizon, r_seed);
            else
                [ensemble, aicc_w] = forecast_closed(model_type, params, ...
                    win.Rt_past, win.U_past, win.sirs_state, data.num_exo, ...
                    num_draws, horizon, exo_mode, sirs_cfg, r_seed, e_seed, vary);
            end

            [lower, upper, Rt_pred] = interval_bounds(ensemble, wis_alphas);
            truth_Rt = win.truth_Rt;

            valid = numel(Rt_pred) == horizon && all(isfinite(Rt_pred)) ...
                 && all(Rt_pred > 0) && all(isfinite(lower(:))) ...
                 && all(isfinite(upper(:))) && all(lower(:) <= upper(:)) ...
                 && numel(truth_Rt) == horizon;

            if valid
                wis_h = compute_wis(truth_Rt, Rt_pred, lower, upper, wis_alphas);
                if all(isfinite(wis_h))
                    window_wis(w) = mean(wis_h);
                end
            end
            window_aicc(w) = aicc_w;
        end

        if any(adm)
            % Plain mean over admissible windows: an in-horizon domain exit leaves
            % that window at inf, which propagates (the candidate is not credited
            % for a forecast it could not complete). AICc stays a finite-only mean.
            scen_wis(s)  = mean(window_wis(adm));
            scen_aicc(s) = local_mean_finite(window_aicc(adm));
        else
            scen_wis(s)  = nan;   % no admissible window in this scenario
            scen_aicc(s) = nan;
        end
    end

    candidate_scores(idx, :) = scen_wis;
    global_mean_wis(idx)     = mean(scen_wis);
    candidate_aicc(idx, :)   = scen_aicc;
    global_mean_aicc(idx)    = local_mean_finite(scen_aicc);
end

fprintf('Stage: Candidate evaluation complete\n');
clear pool_cleanup

[best_global_wis, raw_best_index] = min(global_mean_wis);

if ~isfinite(best_global_wis)
    error('MODEL_SELECTION:NoValidCandidate', ...
        'All candidate model configurations produced invalid global WIS scores.');
end

one_se_threshold     = best_global_wis + local_one_se(candidate_scores(raw_best_index, :));
candidate_complexity = local_candidate_complexity(model_type, candidate_grid, ...
    scenario_data(1).num_exo);
eligible             = isfinite(global_mean_wis) & (global_mean_wis <= one_se_threshold);
eligible(raw_best_index) = true;
selected_index       = local_select_simplest(candidate_complexity, global_mean_wis, eligible);

selected_configuration = candidate_grid(selected_index, :);

%% 4. Artifact Generation
aggregation_mode = "equal_scenario_mean_over_admissible_windows";
failure_policy   = "exclude_inadmissible_origin_windows; inf_wis_on_inhorizon_domain_exit";
cfg_snapshot     = cfg.run_snapshot;

window_admissibility = struct( ...
    'rule', "closed-loop forecast origin must lie in the Rt-to-beta domain: numeric, finite, length 3, nonnegative, mass-conserving (S+I+R == pop_size), and S >= min_susceptible", ...
    'min_susceptible', cfg.sirs.min_susceptible, ...
    'mass_tol_rel', cfg.sirs.mass_tol, ...
    'scenario_ids', scenario_ids, ...
    'num_windows', window_counts, ...
    'num_admissible', [scenario_data.num_admissible], ...
    'num_inadmissible', [scenario_data.num_inadmissible]);

candidate_diagnostics = struct( ...
    'description', "Fitted-model AICc complexity diagnostic; not a selection criterion.", ...
    'scenario_ids', scenario_ids, ...
    'candidate_aicc', candidate_aicc, ...
    'global_mean_aicc', global_mean_aicc, ...
    'selected_global_mean_aicc', global_mean_aicc(selected_index), ...
    'aicc_source', "sys.Report.Fit.AICc per fit, averaged over finite expanding windows then over scenarios", ...
    'interpretation', "Compare AICc within a model family/likelihood; cross-family AICc differences are weak evidence.");

file_prefix   = sprintf('partA_02_global_hyperparameters_%s_%s', model_type, exo_mode);
artifact_path = fullfile(selectionDir, [file_prefix, '.mat']);

save(artifact_path, ...
    'model_type', 'exo_mode', ...
    'candidate_grid', 'candidate_scores', 'global_mean_wis', ...
    'selected_configuration', 'selected_index', ...
    'scenario_ids', 'window_counts', 'cfg_snapshot', ...
    'wis_alphas', 'aggregation_mode', 'failure_policy', 'best_global_wis', ...
    'candidate_diagnostics', 'window_admissibility');

fprintf('Selected global model configuration: %s\n', mat2str(selected_configuration));
fprintf('Global model-selection artifact saved to: %s\n', artifact_path);
fprintf('=== Global Model-Configuration Selection Complete ===\n\n');

%% 5. Local Functions

function window_data = local_build_windows(Rt, U_true, S_true, I_true, tspan, ...
    win_endpoints, horizon, pop_size, has_exo)
%LOCAL_BUILD_WINDOWS Build expanding-window forecast entries for one scenario.
    n_wins      = numel(win_endpoints);
    template    = struct('Rt_past', [], 'truth_Rt', [], 'U_past', [], 'sirs_state', []);
    window_data = repmat(template, n_wins, 1);
    for k = 1:n_wins
        idx_T = find(tspan == win_endpoints(k), 1);
        if isempty(idx_T) || idx_T + horizon > numel(Rt)
            continue;
        end
        window_data(k).Rt_past  = Rt(1:idx_T);
        window_data(k).truth_Rt = Rt(idx_T + 1 : idx_T + horizon);
        if has_exo
            R_at_T = pop_size - S_true(idx_T) - I_true(idx_T);
            window_data(k).U_past     = U_true(1:idx_T, :);
            window_data(k).sirs_state = [S_true(idx_T), I_true(idx_T), R_at_T];
        else
            window_data(k).U_past     = [];
            window_data(k).sirs_state = [];
        end
    end
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
scenario_scores = scenario_scores(isfinite(scenario_scores));
n = numel(scenario_scores);
if n < 2
    one_se = 0;
else
    one_se = std(scenario_scores, 0) / sqrt(n);
end
if ~isscalar(one_se) || ~isfinite(one_se) || one_se < 0
    one_se = 0;
end
end

function complexity = local_candidate_complexity(model_type, candidate_grid, num_exo)
%LOCAL_CANDIDATE_COMPLEXITY Estimated free-parameter count per candidate.
n = size(candidate_grid, 1);
complexity = nan(n, 1);
for i = 1:n
    row = candidate_grid(i, :);
    switch model_type
        case "AR"
            complexity(i) = row(1);
        case "ARX"
            complexity(i) = row(1) + num_exo * row(2) + row(3);
        case {"N4SID", "SSEST"}
            complexity(i) = row(1) + row(2);
        otherwise
            complexity(i) = sum(row);
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

function m = local_mean_finite(v)
%LOCAL_MEAN_FINITE Mean over finite elements; NaN if none are finite.
v = v(isfinite(v));
if isempty(v)
    m = nan;
else
    m = mean(v);
end
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
