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
%            PARTA_02_SELECT_GLOBAL_MODEL_CONFIGURATIONS, PARTA_04_EVALUATE_FORECASTS.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-06-02

%% 1. Initialization
clear; close all; clc;

fprintf('=== Forecast Pipeline Execution ===\n');

cfg = partA_config();
MODEL_TYPE = char(cfg.run.model_type);
EXO_MODE   = char(cfg.run.exo_mode);

EXO_MODE = local_validate_configuration(MODEL_TYPE, EXO_MODE);
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

cfg_snapshot = struct( ...
    'min_window', cfg.forecast.min_window, ...
    'step_size', cfg.forecast.step_size, ...
    'horizon', cfg.forecast.horizon, ...
    'wis_alphas', cfg.forecast.wis_alphas, ...
    'pop_size', cfg.sirs.pop_size, ...
    'gamma', cfg.sirs.gamma, ...
    'xi', cfg.sirs.xi, ...
    'sim_seed', cfg.sim.seed);

model_type = MODEL_TYPE;
exo_mode = EXO_MODE;

for i = 1:numel(scenario_data)
    scenario_entry = scenario_data(i);
    scenario_id   = char(scenario_entry.scenario_id);
    scenario_name = scenario_entry.scenario_name; %#ok<NASGU>
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
    fprintf('Forecast artifact saved to: %s\n', outName);
end

fprintf('=== Forecast Pipeline Complete ===\n\n');

%% 5. Local Functions
function valid_exo_mode = local_validate_configuration(model_type, exo_mode)
%LOCAL_VALIDATE_CONFIGURATION Resolve logical conflicts in run configuration.
    valid_exo_mode = exo_mode;
    if strcmp(model_type, 'AR') && ~strcmp(exo_mode, 'None')
        warning('CFG:ArExo', 'AR is strictly autoregressive. Forcing EXO_MODE to None.');
        valid_exo_mode = 'None';
    elseif strcmp(model_type, 'ARX') && strcmp(exo_mode, 'None')
        error('CFG:ArxExo', 'ARX requires exogenous covariates. Set EXO_MODE to S, I, or Both.');
    elseif ~any(strcmp(model_type, {'AR', 'ARX', 'N4SID', 'SSEST'}))
        error('CFG:UnknownModel', 'Unsupported MODEL_TYPE: %s', model_type);
    end
end

function selected_configuration = local_load_selected_configuration( ...
    selection_dir, model_type, exo_mode, cfg)
%LOCAL_LOAD_SELECTED_CONFIGURATION Load and validate the selection artifact.
    expected_num_params = local_expected_param_count(model_type);

    file_prefix = sprintf('partA_02_global_hyperparameters_%s_%s', model_type, exo_mode);
    artifact_path = fullfile(selection_dir, [file_prefix, '.mat']);

    if ~exist(artifact_path, 'file')
        error('FORECAST:MissingSelectionArtifact', ...
            ['Missing global model-selection artifact: %s. ', ...
            'Run partA_02_select_global_model_configurations.m first.'], artifact_path);
    end

    selection = load(artifact_path);
    local_validate_selection_artifact(selection, artifact_path, ...
        model_type, exo_mode, cfg, expected_num_params);
    selected_configuration = local_extract_selected_configuration(selection);
end

function local_validate_selection_artifact(selection, artifact_path, ...
    model_type, exo_mode, cfg, expected_num_params)
%LOCAL_VALIDATE_SELECTION_ARTIFACT Validate a loaded model-selection artifact.
    required_fields = {'model_type', 'exo_mode', 'cfg_snapshot'};
    if ~all(isfield(selection, required_fields))
        error('FORECAST:InvalidSelectionArtifact', ...
            'Model-selection artifact is missing required fields: %s.', artifact_path);
    end

    if ~isfield(selection, 'selected_configuration')
        error('FORECAST:InvalidSelectionArtifact', ...
            'Model-selection artifact is missing selected_configuration: %s.', ...
            artifact_path);
    end

    if ~strcmp(string(selection.model_type), string(model_type))
        error('FORECAST:SelectionModelMismatch', ...
            'Selection artifact model mismatch. Expected %s, found %s.', ...
            model_type, string(selection.model_type));
    end

    if ~strcmp(string(selection.exo_mode), string(exo_mode))
        error('FORECAST:SelectionExoMismatch', ...
            'Selection artifact exogenous-mode mismatch. Expected %s, found %s.', ...
            exo_mode, string(selection.exo_mode));
    end

    selected_configuration = local_extract_selected_configuration(selection);
    if numel(selected_configuration) ~= expected_num_params
        error('FORECAST:SelectionDimensionMismatch', ...
            'Selected configuration dimensionality is invalid in artifact: %s.', ...
            artifact_path);
    end

    snapshot = selection.cfg_snapshot;
    if ~isfield(snapshot, 'min_window') || snapshot.min_window ~= cfg.forecast.min_window || ...
            ~isfield(snapshot, 'step_size') || snapshot.step_size ~= cfg.forecast.step_size || ...
            ~isfield(snapshot, 'horizon') || snapshot.horizon ~= cfg.forecast.horizon || ...
            ~isfield(snapshot, 'wis_alphas') || ...
            ~isequal(double(snapshot.wis_alphas(:)), double(cfg.forecast.wis_alphas(:))) || ...
            ~isfield(snapshot, 'pop_size') || snapshot.pop_size ~= cfg.sirs.pop_size || ...
            ~isfield(snapshot, 'gamma') || snapshot.gamma ~= cfg.sirs.gamma || ...
            ~isfield(snapshot, 'xi') || snapshot.xi ~= cfg.sirs.xi || ...
            ~isfield(snapshot, 'sim_seed') || snapshot.sim_seed ~= cfg.sim.seed
        error('FORECAST:SelectionConfigMismatch', ...
            'Model-selection artifact is incompatible with the current configuration: %s.', ...
            artifact_path);
    end

    if isfield(selection, 'wis_alphas') && ...
            ~isequal(double(selection.wis_alphas(:)), double(cfg.forecast.wis_alphas(:)))
        error('FORECAST:SelectionAlphaMismatch', ...
            'Model-selection artifact uses different WIS alphas: %s.', artifact_path);
    end
end

function selected_configuration = local_extract_selected_configuration(selection)
%LOCAL_EXTRACT_SELECTED_CONFIGURATION Read the canonical selected configuration.
    selected_configuration = reshape(double(selection.selected_configuration), 1, []);
end

function expected_num_params = local_expected_param_count(model_type)
%LOCAL_EXPECTED_PARAM_COUNT Return the parameter count for a model family.
    switch model_type
        case 'AR'
            expected_num_params = 1;
        case 'ARX'
            expected_num_params = 3;
        case {'N4SID', 'SSEST'}
            expected_num_params = 2;
        otherwise
            error('CFG:UnknownModel', 'Unsupported MODEL_TYPE: %s', model_type);
    end
end
