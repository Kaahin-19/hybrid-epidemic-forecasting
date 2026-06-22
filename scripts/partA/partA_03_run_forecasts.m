%PARTA_03_RUN_FORECASTS Run final Part A expanding-window forecasts.
%
%   Description:
%       Generates the final Part A forecasts using the single globally selected
%       model configuration produced by partA_02. The script loads the
%       model-selection artifact for the active model family and exogenous
%       setting, uses only its selected_configuration, and never re-scans the
%       candidate grid. Forecast windows reproduce the Part A model-selection
%       protocol exactly (same truth artifacts, min_window, step_size, horizon,
%       and scenario set) and the same fail-fast forecasting helpers, so the
%       final forecasts match the configuration that selection scored. The
%       script is a thin orchestration layer over forecast_open / forecast_closed
%       / interval_bounds and saves only detailed MATLAB forecast artifacts.
%
%   Workflow:
%       1. Load configuration and resolve the active model/exogenous setting.
%       2. Load and validate the global model-selection artifact; keep only the
%          selected configuration and its index.
%       3. Build the intended expanding-window dataset and run each scenario's
%          forecasts in parallel using the selected configuration.
%       4. Save one detailed MATLAB forecast artifact per scenario.
%
%   See also PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS, PARTA_CONFIG, FORECAST_OPEN, FORECAST_CLOSED % %            INTERVAL_BOUNDS, SIRS_INIT.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-06-21

%% 1. Initialization
clear; close all; clc;

fprintf('=== Forecast Pipeline Execution ===\n');

cfg        = partA_config();
model_type = cfg.run.model_type;
exo_mode   = cfg.run.exo_mode;

fprintf('Configuration: Model = %s | Exogenous Mode = %s\n', model_type, exo_mode);

saveDir = cfg.output.forecast_dir;
if ~exist(saveDir, 'dir')
    mkdir(saveDir);
end

%% 2. Load Selected Configuration
[selected_configuration, selected_index, selection_artifact] = ...
    local_load_selection(cfg.output.model_selection_dir, model_type, exo_mode, cfg);
fprintf('Using global configuration: %s (index %d)\n', ...
    mat2str(selected_configuration), selected_index);

%% 3. Build Intended Forecast Windows
data_dir  = cfg.output.data_dir;
file_list = dir(fullfile(data_dir, 'partA_01_truth_*.mat'));
if isempty(file_list)
    error('PARTA_03:NoData', ...
        'No synthetic truth files found in %s. Run partA_01 first.', data_dir);
end

horizon     = cfg.forecast.horizon;
pop_size    = cfg.sirs.pop_size;
n_scenarios = numel(file_list);

scenario_template = struct( ...
    'scenario_id', "", 'scenario_name', "", 'num_exo', 0, ...
    'window_data', struct('forecast_origin', {}, 'window_day_idx', {}, ...
    'horizon_indices', {}, 't_future', {}, 'Rt_past', {}, ...
    'truth_Rt', {}, 'U_past', {}, 'sirs_state', {}));
scenario_data = repmat(scenario_template, n_scenarios, 1);

for i = 1:n_scenarios
    loaded = load(fullfile(data_dir, file_list(i).name));

    Rt     = loaded.Rt_true;
    S_true = loaded.S_true;
    I_true = loaded.I_true;
    tspan  = loaded.tspan;

    assert(isnumeric(Rt)     && iscolumn(Rt),     'PARTA_03:BadArtifact', ...
        'Rt_true must be a numeric column vector in partA_01 artifact.');
    assert(isnumeric(S_true) && iscolumn(S_true), 'PARTA_03:BadArtifact', ...
        'S_true must be a numeric column vector in partA_01 artifact.');
    assert(isnumeric(I_true) && iscolumn(I_true), 'PARTA_03:BadArtifact', ...
        'I_true must be a numeric column vector in partA_01 artifact.');
    assert(isnumeric(tspan)  && isvector(tspan),  'PARTA_03:BadArtifact', ...
        'tspan must be a numeric vector in partA_01 artifact.');

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
            error('PARTA_03:UnknownExoMode', 'Unsupported exo_mode: %s', exo_mode);
    end

    num_exo       = size(U_true, 2);
    win_endpoints = cfg.forecast.min_window : cfg.forecast.step_size : (numel(Rt) - horizon);

    % Intended forecast-origin set: every window with a full horizon of truth,
    % derived only from min_window/step_size/horizon and the truth length. This
    % is the same protocol partA_02 uses to score candidates.
    built    = local_build_windows(Rt, U_true, S_true, I_true, tspan, ...
        win_endpoints, horizon, pop_size, num_exo > 0);
    has_full = arrayfun(@(w) numel(w.truth_Rt) == horizon, built);

    scenario_data(i).scenario_id   = string(loaded.scenario_id);
    scenario_data(i).scenario_name = string(loaded.scenario_name);
    scenario_data(i).num_exo       = num_exo;
    scenario_data(i).window_data   = built(has_full);

    if isempty(scenario_data(i).window_data)
        error('PARTA_03:NoForecastWindows', ...
            ['Scenario %s has no intended forecast windows; check ' ...
            'min_window/step_size/horizon against the truth length.'], ...
            loaded.scenario_id);
    end

    fprintf('Prepared scenario %d/%d (%s): %d intended windows\n', ...
        i, n_scenarios, loaded.scenario_id, numel(scenario_data(i).window_data));
end

%% 4. Run Forecasts for the Selected Configuration
base_seed  = cfg.intervals.seed;
vary       = cfg.intervals.include_epidemic_seed_variation;
num_draws  = cfg.intervals.num_draws;
wis_alphas = cfg.forecast.wis_alphas;
sirs_cfg   = cfg.sirs;

cfg_snapshot          = cfg.run_snapshot;
forecast_run_snapshot = struct( ...
    'horizon',            horizon, ...
    'num_draws',          num_draws, ...
    'base_seed',          base_seed, ...
    'exo_mode',           exo_mode, ...
    'vary_epidemic_seed', vary);

if isempty(gcp('nocreate'))
    parpool('Processes', cfg.run.num_workers);
    pool_cleanup = onCleanup(@local_shutdown_parallel_pool);
end

% Build the SIRS stepper template once per worker, but only when the run actually
% uses closed-loop forecasting (num_exo > 0). Open-loop (exo_mode "None") runs
% never touch SIRS/URDME, so the constant stays an unused placeholder.
uses_closed_loop = any([scenario_data.num_exo] > 0);
if uses_closed_loop
    sirs_stepper_const = parallel.pool.Constant(@() sirs_init(sirs_cfg, ...
        struct('solver', 'uds', 'compile', false, 'seed', base_seed)));
else
    sirs_stepper_const = [];
end

results_by_scenario = cell(n_scenarios, 1);
scenario_ids        = strings(n_scenarios, 1);
scenario_names      = strings(n_scenarios, 1);

fprintf('Running forecasts for %d scenarios.\n', n_scenarios);

parfor s = 1:n_scenarios
    data              = scenario_data(s);
    scenario_ids(s)   = data.scenario_id;
    scenario_names(s) = data.scenario_name;
    n_wins            = numel(data.window_data);

    results = repmat(local_empty_window_result(), n_wins, 1);
    for w = 1:n_wins
        win    = data.window_data(w);
        r_seed = local_resample_seed(base_seed, data.scenario_id, w, model_type, exo_mode);
        e_seed = local_epidemic_seed(base_seed, data.scenario_id, w, model_type, exo_mode);

        if data.num_exo == 0
            [~, ens, fit] = forecast_open(model_type, selected_configuration, ...
                win.Rt_past, num_draws, horizon, r_seed);
        else
            base_stepper = sirs_stepper_const.Value;   % prebuilt once per worker
            [~, ens, fit] = forecast_closed(model_type, selected_configuration, ...
                win.Rt_past, win.U_past, win.sirs_state, data.num_exo, ...
                num_draws, horizon, exo_mode, base_stepper, r_seed, e_seed, vary);
        end

        [lower, upper, Rt_pred] = interval_bounds(ens, wis_alphas);

        % Final generation: invalid intervals, a non-finite/non-positive ensemble,
        % or non-finite forecasts are a hard error, never a saved status label.
        % Domain failures and toolbox errors from the helpers propagate and abort.
        valid = numel(Rt_pred) == horizon && all(isfinite(Rt_pred)) ...
            && all(Rt_pred > 0) && all(isfinite(lower(:))) ...
            && all(isfinite(upper(:))) && all(lower(:) <= upper(:)) ...
            && numel(win.truth_Rt) == horizon ...
            && all(isfinite(ens(:))) && all(ens(:) > 0);
        if ~valid
            error('PARTA_03:UnscoreableWindow', ...
                ['Scenario %s window at origin %d produced an invalid ensemble, ' ...
                'invalid intervals, or non-finite forecasts.'], ...
                data.scenario_id, win.forecast_origin);
        end

        results(w).forecast_origin    = win.forecast_origin;
        results(w).window_day_idx     = win.window_day_idx;
        results(w).horizon_indices    = win.horizon_indices;
        results(w).t_future           = win.t_future;
        results(w).Rt_true_future     = win.truth_Rt;
        results(w).Rt_pred            = Rt_pred;
        results(w).lower_bounds       = lower;
        results(w).upper_bounds       = upper;
        results(w).ensemble_paths     = ens;
        results(w).interval_alphas    = wis_alphas;
        results(w).aicc               = fit.AICc;
        results(w).resample_seed      = r_seed;
        results(w).epidemic_base_seed = e_seed;
        results(w).num_exo            = data.num_exo;
    end

    results_by_scenario{s} = results;
end

clear pool_cleanup

%% 5. Persist Detailed Forecast Artifacts
fprintf('Saving forecast artifacts to: %s\n', saveDir);

for s = 1:n_scenarios
    scenario_id      = scenario_ids(s);
    scenario_name    = scenario_names(s);
    forecast_results = results_by_scenario{s};

    file_prefix = sprintf('partA_03_forecast_%s_%s_%s', scenario_id, model_type, exo_mode);
    outName     = fullfile(saveDir, [file_prefix, '.mat']);

    save(outName, ...
        'model_type', 'exo_mode', 'scenario_id', 'scenario_name', ...
        'selected_configuration', 'selected_index', 'selection_artifact', ...
        'forecast_results', 'wis_alphas', 'cfg_snapshot', 'forecast_run_snapshot');
    fprintf('    saved %s\n', [file_prefix, '.mat']);
end

fprintf('=== Forecast Pipeline Complete ===\n\n');

%% 6. Local Functions

function [selected_configuration, selected_index, artifact_path] = ...
    local_load_selection(selection_dir, model_type, exo_mode, cfg)
%LOCAL_LOAD_SELECTION Load and validate the partA_02 model-selection artifact.
file_prefix   = sprintf('partA_02_global_hyperparameters_%s_%s', model_type, exo_mode);
artifact_path = fullfile(selection_dir, [file_prefix, '.mat']);

if ~exist(artifact_path, 'file')
    error('PARTA_03:MissingSelectionArtifact', ...
        ['Missing global model-selection artifact: %s. ', ...
        'Run partA_02_select_global_hyperparameters.m first.'], artifact_path);
end

selection = load(artifact_path);

if ~isfield(selection, 'selected_configuration') || isempty(selection.selected_configuration)
    error('PARTA_03:InvalidSelectionArtifact', ...
        'Selection artifact has no selected_configuration: %s.', artifact_path);
end
if ~isfield(selection, 'selected_index') || isempty(selection.selected_index)
    error('PARTA_03:InvalidSelectionArtifact', ...
        'Selection artifact has no selected_index: %s.', artifact_path);
end
if ~isfield(selection, 'model_type') || ~strcmp(string(selection.model_type), model_type)
    error('PARTA_03:SelectionConfigMismatch', ...
        'Selection artifact model_type does not match active model_type (%s): %s.', ...
        model_type, artifact_path);
end
if ~isfield(selection, 'exo_mode') || ~strcmp(string(selection.exo_mode), exo_mode)
    error('PARTA_03:SelectionConfigMismatch', ...
        'Selection artifact exo_mode does not match active exo_mode (%s): %s.', ...
        exo_mode, artifact_path);
end
if ~isfield(selection, 'cfg_snapshot') || ~isequal(selection.cfg_snapshot, cfg.run_snapshot)
    error('PARTA_03:SelectionConfigMismatch', ...
        'Selection artifact is incompatible with the current configuration: %s.', ...
        artifact_path);
end

selected_configuration = selection.selected_configuration;
selected_index         = selection.selected_index;
end

function window_data = local_build_windows(Rt, U_true, S_true, I_true, tspan, ...
    win_endpoints, horizon, pop_size, has_exo)
%LOCAL_BUILD_WINDOWS Build expanding-window forecast entries for one scenario.
n_wins   = numel(win_endpoints);
template = struct('forecast_origin', [], 'window_day_idx', [], ...
    'horizon_indices', [], 't_future', [], 'Rt_past', [], ...
    'truth_Rt', [], 'U_past', [], 'sirs_state', []);
window_data = repmat(template, n_wins, 1);
for k = 1:n_wins
    idx_T = find(tspan == win_endpoints(k), 1);
    if isempty(idx_T) || idx_T + horizon > numel(Rt)
        continue;
    end
    idx_future = (idx_T + 1 : idx_T + horizon)';
    t_future   = tspan(idx_future);
    window_data(k).forecast_origin = win_endpoints(k);
    window_data(k).window_day_idx  = idx_T;
    window_data(k).horizon_indices = idx_future;
    window_data(k).t_future        = t_future(:);   % documented H-by-1 layout
    window_data(k).Rt_past         = Rt(1:idx_T);
    window_data(k).truth_Rt        = Rt(idx_future);
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

function result = local_empty_window_result()
%LOCAL_EMPTY_WINDOW_RESULT Preallocate a single detailed forecast-result entry.
result = struct( ...
    'forecast_origin', [], 'window_day_idx', [], 'horizon_indices', [], ...
    't_future', [], 'Rt_true_future', [], 'Rt_pred', [], ...
    'lower_bounds', [], 'upper_bounds', [], 'ensemble_paths', [], ...
    'interval_alphas', [], 'aicc', [], 'resample_seed', [], ...
    'epidemic_base_seed', [], 'num_exo', []);
end

function local_shutdown_parallel_pool()
%LOCAL_SHUTDOWN_PARALLEL_POOL Close the local parallel pool before MATLAB exits.
pool = gcp('nocreate');
if ~isempty(pool)
    delete(pool);
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
