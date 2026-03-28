%PARTA_03_RUN_FORECASTS Execute expanding-window epidemic forecasts.
%
%   Description:
%       Executes an expanding-window forecasting pipeline over synthetic
%       ground truth data using a globally selected hyperparameter
%       configuration for the active model family and exogenous-input
%       setting. Each forecast window is refit on its own local history and
%       produces analytic predictive intervals. Future exogenous covariates
%       (Susceptible and Infected populations) are projected dynamically
%       using the deterministic compartmental solver ('uds') to ensure
%       causality.
%
%   Workflow:
%       1. Initialize experiment and model configurations.
%       2. Load the globally selected hyperparameter artifact.
%       3. Process synthetic ground truth datasets iteratively.
%       4. Perform expanding-window forecast estimation.
%       5. Aggregate results and generate performance visualizations.
%
%   See also PARTA_CONFIG, GENDATA_SIRS, PLOT_RT_FORECAST_COMPARISON, ... 
%            PARTA_01_GENERATE_TRUTH, ... 
%            PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS.

% A. M. Kaahin 2026-02-19
% Modified: 2026-03-28

%% 1. Initialization
clear; close all; clc;

fprintf('=== Forecast Pipeline Execution ===\n');

cfg = partA_config();
MODEL_TYPE = char(cfg.run.model_type);
EXO_MODE   = char(cfg.run.exo_mode);

EXO_MODE = validate_configuration(MODEL_TYPE, EXO_MODE);
fprintf('Configuration: Model = %s | Exogenous Mode = %s\n', MODEL_TYPE, EXO_MODE);

%% 2. Configuration and Grid Setup
dataDir  = cfg.output.data_dir;     
saveDir  = cfg.output.forecast_dir; 
tuningDir = cfg.output.tuning_dir;
fileList = dir(fullfile(dataDir, '*.mat'));
wis_alphas = cfg.forecast.wis_alphas;

[selected_model, table_headers] = load_selected_hyperparameters( ...
    tuningDir, MODEL_TYPE, EXO_MODE, cfg);
fprintf('Using global hyperparameters: %s\n', mat2str(selected_model));

if isempty(fileList)
    error('FORECAST:NoData', 'No synthetic truth files found. Run partA_01_generate_truth.m first.');
end

if ~exist(saveDir, 'dir')
    mkdir(saveDir);
end

%% 3. Evaluation Loop
for i = 1:length(fileList)
    filename = fileList(i).name;
    fullPath = fullfile(dataDir, filename);
    [~, name_core] = fileparts(filename);
    
    scenario_id = strrep(name_core, 'partA_01_truth_', '');
    fprintf('  - Processing Scenario: %s...\n', scenario_id);
    
    loaded  = load(fullPath);
    Rt_true = loaded.Rt_true;
    tspan   = loaded.tspan;
    
    scaled_S = loaded.S_true(:) / cfg.sirs.pop_size;
    scaled_I = loaded.I_true(:) / cfg.sirs.pop_size;
    
    switch EXO_MODE
        case 'None', U_true = [];
        case 'S',    U_true = scaled_S;
        case 'I',    U_true = scaled_I;
        case 'Both', U_true = [scaled_S, scaled_I];
    end
    
    num_exo = size(U_true, 2);
    
    T_end   = length(Rt_true);
    max_T   = T_end - cfg.forecast.horizon;
    windows = cfg.forecast.min_window : cfg.forecast.step_size : max_T;
    num_windows = numel(windows);
    
    results = repmat(struct( ...
        'window_day', [], ...
        'window_day_idx', [], ...
        'forecast_median', [], ...
        'forecast_interval_alphas', [], ...
        'forecast_lower', [], ...
        'forecast_upper', [], ...
        'best_model', [], ...
        'aic_landscape', [], ...
        'truth_Rt_window', [], ...
        'time_horizon', []), num_windows, 1);
    selected_models_log = zeros(num_windows, numel(selected_model));
    count = 1;
    
    for T = windows
        idx_T = find(tspan == T, 1);
        if isempty(idx_T), continue; end
        
        horizon = cfg.forecast.horizon;
        idx_end = idx_T + horizon;
        
        Rt_past = Rt_true(1:idx_T);
        
        if isempty(U_true)
            U_past   = [];
            U_future = [];
        else
            U_past = U_true(1:idx_T, :);
            
            current_Rt = Rt_true(idx_T);
            current_I  = loaded.I_true(idx_T);
            current_S  = loaded.S_true(idx_T);
            current_R  = cfg.sirs.pop_size - current_S - current_I;
            
            future_tspan = 0:horizon; 
            flat_beta    = repmat(current_Rt * cfg.sirs.gamma, 1, length(future_tspan));
            
            uds_params = cfg.sirs;
            uds_params.beta    = flat_beta;
            uds_params.I0      = current_I;
            uds_params.R0_init = current_R;
            uds_params.solver  = 'uds'; 
            uds_params.compile = 0; 
            
            uds_mod = genData_SIRS(future_tspan, uds_params, cfg.sim.seed);
            
            S_future_raw = uds_mod.U(1, 2:end)';
            I_future_raw = uds_mod.U(2, 2:end)';
            
            scaled_S_fut = S_future_raw / cfg.sirs.pop_size;
            scaled_I_fut = I_future_raw / cfg.sirs.pop_size;
            
            switch EXO_MODE
                case 'S',    U_future = scaled_S_fut;
                case 'I',    U_future = scaled_I_fut;
                case 'Both', U_future = [scaled_S_fut, scaled_I_fut];
            end
        end
        
        [best_Rt_pred, aicc, best_wis_alpha, best_Rt_lower, best_Rt_upper] = ...
            fit_selected_model(MODEL_TYPE, selected_model, Rt_past, U_past, ...
            U_future, num_exo, horizon, wis_alphas);
        
        results(count).window_day      = T;
        results(count).window_day_idx  = idx_T;
        results(count).forecast_median = best_Rt_pred;
        results(count).forecast_interval_alphas = best_wis_alpha;
        results(count).forecast_lower  = best_Rt_lower;
        results(count).forecast_upper  = best_Rt_upper;
        results(count).best_model      = selected_model;
        results(count).aic_landscape   = [selected_model, aicc];
        results(count).truth_Rt_window = Rt_true(idx_T+1 : idx_end);
        results(count).time_horizon    = tspan(idx_T+1 : idx_end);
        
        selected_models_log(count, :) = selected_model;
        count = count + 1;
    end

    results = results(1:count-1);
    selected_models_log = selected_models_log(1:count-1, :);
    
    %% 4. Artifact Generation
    summary_table = array2table([selected_model, size(selected_models_log, 1)], ...
        'VariableNames', table_headers);
    
    file_prefix = sprintf('partA_03_forecast_%s_%s_%s', scenario_id, MODEL_TYPE, EXO_MODE);
    
    csvName = fullfile(saveDir, [file_prefix, '_summary.csv']);
    writetable(summary_table, csvName);
    
    outName = fullfile(saveDir, [file_prefix, '.mat']);
    save(outName, 'results', 'cfg');
    
    plot_name = sprintf('%s_%s_%s', scenario_id, MODEL_TYPE, EXO_MODE);
    plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg);
end

fprintf('=== Forecast Pipeline Complete ===\n\n');

%% 5. Local Functions
function valid_exo_mode = validate_configuration(model_type, exo_mode)
%VALIDATE_CONFIGURATION Resolve logical conflicts in configuration.
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

function [selected_model, table_headers] = load_selected_hyperparameters(tuning_dir, model_type, exo_mode, cfg)
%LOAD_SELECTED_HYPERPARAMETERS Load and validate a global tuning artifact.
    [parameter_headers, expected_num_params] = get_parameter_headers(model_type);
    table_headers = [parameter_headers, {'Times_Selected'}];

    file_prefix = sprintf('partA_02_global_hyperparameters_%s_%s', model_type, exo_mode);
    tuning_path = fullfile(tuning_dir, [file_prefix, '.mat']);

    if ~exist(tuning_path, 'file')
        error('FORECAST:MissingTuningArtifact', ...
            'Missing global hyperparameter artifact: %s. Run partA_02_select_global_hyperparameters.m first.', ...
            tuning_path);
    end

    tuning = load(tuning_path);
    validate_tuning_artifact(tuning, tuning_path, model_type, exo_mode, cfg, expected_num_params);
    selected_model = reshape(double(tuning.selected_model), 1, []);
end

function validate_tuning_artifact(tuning, tuning_path, model_type, exo_mode, cfg, expected_num_params)
%VALIDATE_TUNING_ARTIFACT Validate a loaded global tuning artifact.
    required_fields = {'model_type', 'exo_mode', 'selected_model', 'cfg_snapshot', 'wis_alphas'};
    if ~all(isfield(tuning, required_fields))
        error('FORECAST:InvalidTuningArtifact', ...
            'Global hyperparameter artifact is missing required fields: %s.', ...
            tuning_path);
    end

    if ~strcmp(string(tuning.model_type), string(model_type))
        error('FORECAST:TuningModelMismatch', ...
            'Tuning artifact model mismatch. Expected %s, found %s.', ...
            model_type, string(tuning.model_type));
    end

    if ~strcmp(string(tuning.exo_mode), string(exo_mode))
        error('FORECAST:TuningExoMismatch', ...
            'Tuning artifact exogenous-mode mismatch. Expected %s, found %s.', ...
            exo_mode, string(tuning.exo_mode));
    end

    selected_model = reshape(double(tuning.selected_model), 1, []);
    if numel(selected_model) ~= expected_num_params
        error('FORECAST:TuningDimensionMismatch', ...
            'Selected hyperparameter dimensionality is invalid in tuning artifact: %s.', ...
            tuning_path);
    end

    if ~isfield(tuning.cfg_snapshot, 'min_window') || ...
            tuning.cfg_snapshot.min_window ~= cfg.forecast.min_window || ...
            ~isfield(tuning.cfg_snapshot, 'step_size') || ...
            tuning.cfg_snapshot.step_size ~= cfg.forecast.step_size || ...
            ~isfield(tuning.cfg_snapshot, 'horizon') || ...
            tuning.cfg_snapshot.horizon ~= cfg.forecast.horizon || ...
            ~isfield(tuning.cfg_snapshot, 'wis_alphas') || ...
            ~isequal(double(tuning.cfg_snapshot.wis_alphas(:)), double(cfg.forecast.wis_alphas(:)))
        error('FORECAST:TuningConfigMismatch', ...
            'Global hyperparameter artifact is incompatible with the current forecast configuration: %s.', ...
            tuning_path);
    end

    if ~isequal(double(tuning.wis_alphas(:)), double(cfg.forecast.wis_alphas(:)))
        error('FORECAST:TuningAlphaMismatch', ...
            'Global hyperparameter artifact uses different WIS alphas: %s.', ...
            tuning_path);
    end
end

function [parameter_headers, expected_num_params] = get_parameter_headers(model_type)
%GET_PARAMETER_HEADERS Return parameter labels for the active model family.
    switch model_type
        case 'AR'
            parameter_headers = {'p'};
            expected_num_params = 1;

        case 'ARX'
            parameter_headers = {'na', 'nb', 'nk'};
            expected_num_params = 3;

        case {'N4SID', 'SSEST'}
            parameter_headers = {'State_Order_n', 'Differencing_d'};
            expected_num_params = 2;

        otherwise
            error('CFG:UnknownModel', 'Unsupported MODEL_TYPE: %s', model_type);
    end
end

function [Rt_pred, aicc, wis_alpha, Rt_lower, Rt_upper] = fit_selected_model( ...
    model_type, selected_model, Rt_past, U_past, U_future, num_exo, horizon, wis_alphas)
%FIT_SELECTED_MODEL Fit and forecast the selected global hyperparameter configuration.
    switch model_type
        case 'AR'
            [Rt_pred, aicc, wis_alpha, Rt_lower, Rt_upper] = ...
                fit_arima(Rt_past, selected_model(1), 0, 0, horizon, wis_alphas);

        case 'ARX'
            nb_vec = repmat(selected_model(2), 1, num_exo);
            nk_vec = repmat(selected_model(3), 1, num_exo);
            [Rt_pred, aicc, wis_alpha, Rt_lower, Rt_upper] = ...
                fit_arimax(Rt_past, U_past, U_future, selected_model(1), 0, 0, ...
                nb_vec, nk_vec, horizon, wis_alphas);

        case 'N4SID'
            [Rt_pred, aicc, wis_alpha, Rt_lower, Rt_upper] = ...
                fit_n4sid(Rt_past, U_past, U_future, selected_model(1), selected_model(2), ...
                horizon, wis_alphas);

        case 'SSEST'
            [Rt_pred, aicc, wis_alpha, Rt_lower, Rt_upper] = ...
                fit_ssest(Rt_past, U_past, U_future, selected_model(1), selected_model(2), ...
                horizon, wis_alphas);

        otherwise
            error('CFG:UnknownModel', 'Unsupported MODEL_TYPE: %s', model_type);
    end
end
