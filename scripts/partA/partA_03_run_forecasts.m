%PARTA_03_RUN_FORECASTS Run final Part A expanding-window forecasts.
%
%   Description:
%       Generates the final Part A forecasts using the globally selected model
%       configuration for the active model family and exogenous-input setting.
%       The forecast dataset, expanding-window protocol, and model dispatch
%       reproduce the corrected Part A model-selection behaviour so that final
%       forecasts and selection share identical model logic. The script is a
%       thin orchestration layer over the reusable forecasting helpers and
%       saves only MATLAB forecast artifacts.
%
%   Workflow:
%       1. Load configuration and resolve the active model/exogenous setting.
%       2. Load and validate the global model-selection artifact.
%       3. Build the expanding-window forecast dataset and run forecasts.
%       4. Save one MATLAB forecast artifact per scenario.
%
%   See also PARTA_CONFIG, BUILD_FORECASTING_DATASET, ...
%            RUN_EXPANDING_WINDOW_FORECAST, RUN_MODEL_FORECAST, ...
%            PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS, PARTA_04_EVALUATE_FORECASTS.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-06-04

%% 1. Initialization
clear; close all; clc;

fprintf('=== Forecast Pipeline Execution ===\n');

cfg = partA_config();
MODEL_TYPE = char(cfg.run.model_type);
EXO_MODE   = char(cfg.run.exo_mode);

fprintf('Configuration: Model = %s | Exogenous Mode = %s\n', MODEL_TYPE, EXO_MODE);

saveDir = cfg.output.forecast_dir;
if ~exist(saveDir, 'dir')
    mkdir(saveDir);
end

%% 2. Load Selected Configuration
selected_configuration = local_load_selected_configuration( ...
    cfg.output.model_selection_dir, MODEL_TYPE, EXO_MODE, cfg);
fprintf('Using global configuration: %s\n', mat2str(selected_configuration));

%% 3. Build Dataset and Run Forecasts
scenario_data = build_forecasting_dataset(cfg, EXO_MODE);

forecast_options = struct( ...
    'horizon', cfg.forecast.horizon, ...
    'wis_alphas', cfg.forecast.wis_alphas, ...
    'sirs_cfg', cfg.sirs, ...
    'exo_mode', EXO_MODE, ...
    'sim_seed', cfg.sim.seed, ...
    'num_exo', 0, ...
    'intervals', cfg.intervals);

cfg_snapshot = cfg.run_snapshot;

model_type = MODEL_TYPE;
exo_mode = EXO_MODE;

fprintf('Saving forecast artifacts to: %s\n', saveDir);

for i = 1:numel(scenario_data)
    scenario_entry = scenario_data(i);
    scenario_id   = char(scenario_entry.scenario_id);
    scenario_name = scenario_entry.scenario_name;
    fprintf('  - Forecasting Scenario: %s...\n', scenario_id);

    forecast_results = run_expanding_window_forecast(scenario_entry, ...
        MODEL_TYPE, selected_configuration, forecast_options);

    if isempty(forecast_results)
        warning('FORECAST:NoWindows', ...
            'No valid forecast windows for scenario %s.', scenario_id);
    end

    %% 4. Persist Forecast Artifact
    file_prefix = sprintf('partA_03_forecast_%s_%s_%s', scenario_id, MODEL_TYPE, EXO_MODE);
    outName = fullfile(saveDir, [file_prefix, '.mat']);

    save(outName, ...
        'model_type', 'exo_mode', ...
        'scenario_id', 'scenario_name', ...
        'selected_configuration', 'forecast_results', 'cfg_snapshot');
    fprintf('    saved %s\n', [file_prefix, '.mat']);
end

fprintf('=== Forecast Pipeline Complete ===\n\n');

%% 5. Local Functions
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

selected_configuration = reshape(double(selection.selected_configuration), 1, []);
end
