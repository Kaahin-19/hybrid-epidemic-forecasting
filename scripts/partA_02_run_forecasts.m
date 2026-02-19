%PARTA_02_RUN_FORECASTS Unified Execution Pipeline for Epidemic Forecasting
%
%   Description:
%       Executes expanding-window forecasts over synthetic ground truth data. 
%       Supports pure statistical (ARIMA), hybrid statistical (ARIMAX), and 
%       State-Space (N4SID, SSEST) model configurations.
%
%   Workflow:
%       1. Define the experiment configuration
%       2. Generate the parameter search grid
%       3. Iterate through synthetic truth datasets
%       4. Perform parallelized expanding-window model evaluation
%       5. Persist results and generate comparative plots

% A. M. Kaahin 2026-02-19

%% 1. Experiment Configuration
clear; clc; close all;

% Model Configuration
%   MODEL_TYPE: 'ARIMA', 'ARIMAX', 'N4SID', 'SSEST'
%   EXO_MODE:   'None', 'S', 'I', 'Both'
MODEL_TYPE = 'SSEST'; 
EXO_MODE   = 'Both';    

% Validate configuration compatibility
EXO_MODE = validate_configuration(MODEL_TYPE, EXO_MODE);

fprintf('=== Starting %s Forecast Pipeline (Exogenous Mode: %s) ===\n', MODEL_TYPE, EXO_MODE);

%% 2. Initialization & Grid Setup
cfg      = partA_config(); 
dataDir  = cfg.output.data_dir;     
saveDir  = cfg.output.forecast_dir; 
fileList = dir(fullfile(dataDir, '*.mat'));

% Define model-specific parameter search space
switch MODEL_TYPE
    case 'ARIMA'
        [P, D, Q] = ndgrid(0:14, [0, 1], 0:2);
        candidate_models = [P(:), D(:), Q(:)];
        table_headers    = {'p', 'd', 'q', 'Times_Selected'};
        
    case 'ARIMAX'
        [P, D, Q, NB, NK] = ndgrid(0:14, [0, 1], 0:2, 1:2, 1);
        candidate_models  = [P(:), D(:), Q(:), NB(:), NK(:)];
        table_headers     = {'p', 'd', 'q', 'nb', 'nk', 'Times_Selected'};
        
    case {'N4SID', 'SSEST'}
        [N_order, D_order] = ndgrid(1:8, [0, 1]);
        candidate_models   = [N_order(:), D_order(:)];
        table_headers      = {'State_Order_n', 'Differencing_d', 'Times_Selected'};
end

num_models = size(candidate_models, 1);
fprintf('Evaluating %d unique parameter configurations per window.\n', num_models);

if isempty(gcp('nocreate'))
    parpool; 
end

%% 3. Main Experiment Loop
for i = 1:length(fileList)
    filename = fileList(i).name;
    fullPath = fullfile(dataDir, filename);
    [~, name_core] = fileparts(filename);
    
    scenario_id = strrep(name_core, 'partA_01_truth_', '');
    fprintf('\nProcessing Scenario: %s\n', scenario_id);
    
    loaded  = load(fullPath);
    Rt_true = loaded.Rt_true;
    tspan   = loaded.tspan;
    
    % Normalize exogenous variables to [0, 1] to ensure numerical stability during estimation
    norm_S = loaded.S_true(:) / max(loaded.S_true(:));
    norm_I = loaded.I_true(:) / max(loaded.I_true(:));
    
    switch EXO_MODE
        case 'None', U_true = [];
        case 'S',    U_true = norm_S;
        case 'I',    U_true = norm_I;
        case 'Both', U_true = [norm_S, norm_I];
    end
    
    num_exo = size(U_true, 2);
    results = struct();
    count   = 1;
    
    T_end   = length(Rt_true);
    max_T   = T_end - cfg.forecast.horizon;
    windows = cfg.forecast.min_window : cfg.forecast.step_size : max_T;
    
    selected_models_log = []; 
    
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
            U_past   = U_true(1:idx_T, :);
            U_future = U_true(idx_T+1 : idx_end, :); 
        end
        
        par_landscape = zeros(num_models, size(candidate_models, 2) + 1); 
        par_forecasts = cell(num_models, 1);
        
        parfor idx = 1:num_models
            params = candidate_models(idx, :);
            
            Rt_pred = [];
            aicc    = [];
            
            switch MODEL_TYPE
                case 'ARIMA'
                    [Rt_pred, aicc] = fit_arima(Rt_past, params(1), params(2), params(3), horizon);
                    
                case 'ARIMAX'
                    nb_vec = repmat(params(4), 1, num_exo);
                    nk_vec = repmat(params(5), 1, num_exo);
                    [Rt_pred, aicc] = fit_arimax(Rt_past, U_past, U_future, params(1), params(2), params(3), nb_vec, nk_vec, horizon);
                    
                case 'N4SID'
                    [Rt_pred, aicc] = fit_n4sid(Rt_past, U_past, U_future, params(1), params(2), horizon);
                    
                case 'SSEST'
                    [Rt_pred, aicc] = fit_ssest(Rt_past, U_past, U_future, params(1), params(2), horizon);
            end
            
            par_landscape(idx, :) = [params, aicc];
            par_forecasts{idx}    = Rt_pred;
        end
        
        % Isolate the optimal model according to AICc score
        [~, sort_idx]    = sort(par_landscape(:, end));
        sorted_landscape = par_landscape(sort_idx, :);
        
        best_idx     = sort_idx(1);
        best_Rt_pred = par_forecasts{best_idx};
        best_params  = sorted_landscape(1, 1:end-1);
        
        results(count).window_day      = T;
        results(count).window_day_idx  = idx_T;
        results(count).forecast_Rt     = best_Rt_pred;
        results(count).best_model      = best_params;
        results(count).aic_landscape   = sorted_landscape; 
        results(count).truth_Rt_window = Rt_true(idx_T+1 : idx_end);
        results(count).time_horizon    = tspan(idx_T+1 : idx_end);
        
        selected_models_log = [selected_models_log; best_params]; %#ok<AGROW>
        count = count + 1;
    end
    
    %% 4. Artifact Generation
    [uq_models, ~, uq_idx] = unique(selected_models_log, 'rows');
    model_counts           = accumarray(uq_idx, 1);
    [model_counts, sort_count_idx] = sort(model_counts, 'descend');
    uq_models              = uq_models(sort_count_idx, :);
    
    summary_table = array2table([uq_models, model_counts], 'VariableNames', table_headers);
    fprintf('  Model Selection Summary:\n');
    disp(summary_table);
    
    file_prefix = sprintf('partA_02_forecast_%s_%s_%s', scenario_id, MODEL_TYPE, EXO_MODE);
    
    csvName = fullfile(saveDir, [file_prefix, '_summary.csv']);
    writetable(summary_table, csvName);
    
    outName = fullfile(saveDir, [file_prefix, '.mat']);
    save(outName, 'results', 'cfg');
    
    plot_name = sprintf('%s_%s_%s', scenario_id, MODEL_TYPE, EXO_MODE);
    plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg);
end

fprintf('\n=== %s Forecast Pipeline Complete ===\n', MODEL_TYPE);


function valid_exo_mode = validate_configuration(model_type, exo_mode)
%VALIDATE_CONFIGURATION Check for logical conflicts in user settings.
    
    valid_exo_mode = exo_mode;

    if strcmp(model_type, 'ARIMA') && ~strcmp(exo_mode, 'None')
        warning('ARIMA is strictly autoregressive. Forcing EXO_MODE to ''None''.');
        valid_exo_mode = 'None';
        
    elseif strcmp(model_type, 'ARIMAX') && strcmp(exo_mode, 'None')
        error('ARIMAX requires exogenous covariates. Change EXO_MODE to ''S'', ''I'', or ''Both''.');
    end
end