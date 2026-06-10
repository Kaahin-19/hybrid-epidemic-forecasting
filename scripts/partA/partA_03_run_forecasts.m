%PARTA_03_RUN_FORECASTS Run final Part A expanding-window forecasts.
%
%   Description:
%       Generates the final Part A forecasts using the globally selected model
%       configuration for the active model family and exogenous-input setting.
%       The forecast dataset, expanding-window protocol, and model dispatch
%       reproduce the current Part A model-selection behaviour so that final
%       forecasts and selection share identical model logic. The script is a
%       thin orchestration layer over the reusable forecasting helpers and
%       saves only MATLAB forecast artifacts.
%
%   Workflow:
%       1. Load configuration and resolve the active model/exogenous setting.
%       2. Load and validate the global model-selection artifact.
%       3. Build the expanding-window forecast dataset and run scenario
%          forecasts in parallel when multiple workers are configured.
%       4. Save one MATLAB forecast artifact per scenario.
%
%   See also PARTA_CONFIG, BUILD_FORECASTING_DATASET, ...
%            RUN_EXPANDING_WINDOW_FORECAST, RUN_MODEL_FORECAST, ...
%            PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS, PARTA_04_EVALUATE_FORECASTS.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-06-11

%% 1. Initialization
clear; close all; clc;

fprintf('=== Forecast Pipeline Execution ===\n');

cfg = partA_config();
model_type = cfg.run.model_type;
exo_mode   = cfg.run.exo_mode;

fprintf('Configuration: Model = %s | Exogenous Mode = %s\n', model_type, exo_mode);

saveDir = cfg.output.forecast_dir;
if ~exist(saveDir, 'dir')
    mkdir(saveDir);
end

%% 2. Load Selected Configuration
selected_configuration = local_load_selected_configuration( ...
    cfg.output.model_selection_dir, model_type, exo_mode, cfg);
fprintf('Using global configuration: %s\n', mat2str(selected_configuration));

%% 3. Build Dataset and Run Forecasts
scenario_data = build_forecasting_dataset(cfg, exo_mode);
num_scenarios = numel(scenario_data);

forecast_options = struct( ...
    'horizon', cfg.forecast.horizon, ...
    'wis_alphas', cfg.forecast.wis_alphas, ...
    'sirs_cfg', cfg.sirs, ...
    'exo_mode', exo_mode, ...
    'sim_seed', cfg.sim.seed, ...
    'intervals', cfg.intervals);

cfg_snapshot = cfg.run_snapshot;

pool_cleanup = local_start_parallel_pool(cfg.run.num_workers, num_scenarios); %#ok<NASGU>

forecast_results_by_scenario = cell(num_scenarios, 1);
scenario_ids = strings(num_scenarios, 1);
scenario_names = strings(num_scenarios, 1);

fprintf('Running forecasts for %d scenarios.\n', num_scenarios);

parfor i = 1:num_scenarios
    scenario_entry = scenario_data(i);
    scenario_ids(i) = scenario_entry.scenario_id;
    scenario_names(i) = scenario_entry.scenario_name;

    forecast_results_by_scenario{i} = run_expanding_window_forecast(scenario_entry, ...
        model_type, selected_configuration, forecast_options);
end

clear pool_cleanup

fprintf('Saving forecast artifacts to: %s\n', saveDir);

for i = 1:num_scenarios
    scenario_id = scenario_ids(i);
    scenario_name = scenario_names(i);
    forecast_results = forecast_results_by_scenario{i};

    if isempty(forecast_results)
        warning('FORECAST:NoWindows', ...
            'No valid forecast windows for scenario %s.', scenario_id);
    end

    %% 4. Persist Forecast Artifact
    file_prefix = sprintf('partA_03_forecast_%s_%s_%s', scenario_id, model_type, exo_mode);
    outName = fullfile(saveDir, [file_prefix, '.mat']);

    save(outName, ...
        'model_type', 'exo_mode', ...
        'scenario_id', 'scenario_name', ...
        'selected_configuration', 'forecast_results', 'cfg_snapshot');
    fprintf('    saved %s\n', [file_prefix, '.mat']);
end

fprintf('=== Forecast Pipeline Complete ===\n\n');

%% 5. Local Functions
function pool_cleanup = local_start_parallel_pool(num_workers, num_tasks)
%LOCAL_START_PARALLEL_POOL Start a process pool for scenario forecasts.
pool_cleanup = [];
worker_count = min(max(1, round(double(num_workers))), max(1, double(num_tasks)));
if worker_count <= 1
    return;
end

pool = gcp('nocreate');
if isempty(pool)
    fprintf('Starting parallel pool with %d workers.\n', worker_count);
    parpool('Processes', worker_count);
    pool_cleanup = onCleanup(@local_shutdown_parallel_pool);
else
    fprintf('Using existing parallel pool with %d workers.\n', pool.NumWorkers);
end
end

function local_shutdown_parallel_pool()
%LOCAL_SHUTDOWN_PARALLEL_POOL Close the local parallel pool before MATLAB exits.
pool = gcp('nocreate');
if ~isempty(pool)
    delete(pool);
end
end

function selected_configuration = local_load_selected_configuration( ...
    selection_dir, model_type, exo_mode, cfg)
%LOCAL_LOAD_SELECTED_CONFIGURATION Load and screen the partA_02 selection artifact.
file_prefix = sprintf('partA_02_global_hyperparameters_%s_%s', model_type, exo_mode);
artifact_path = fullfile(selection_dir, [file_prefix, '.mat']);

if ~exist(artifact_path, 'file')
    error('FORECAST:MissingSelectionArtifact', ...
        ['Missing global model-selection artifact: %s. ', ...
        'Run partA_02_select_global_hyperparameters.m first.'], artifact_path);
end

selection = load(artifact_path);

if ~isfield(selection, 'selected_configuration') || isempty(selection.selected_configuration)
    error('FORECAST:InvalidSelectionArtifact', ...
        'Selection artifact has no selected_configuration: %s.', artifact_path);
end

if ~isfield(selection, 'cfg_snapshot') || ~isequal(selection.cfg_snapshot, cfg.run_snapshot)
    error('FORECAST:SelectionConfigMismatch', ...
        'Selection artifact is incompatible with the current configuration: %s.', ...
        artifact_path);
end

selected_configuration = selection.selected_configuration;
end
