%PARTA_02_RUN_FORECASTS Execute expanding-window epidemic forecasts.
%
%   Description:
%       Executes an expanding-window forecasting pipeline over synthetic
%       ground truth data. Evaluates autoregressive and state-space models
%       and computes analytic predictive intervals. Future exogenous
%       covariates (Susceptible and Infected populations) are projected
%       dynamically using the deterministic compartmental solver ('uds') to
%       ensure causality.
%
%   Workflow:
%       1. Initialize experiment and model configurations.
%       2. Define the hyperparameter search grid.
%       3. Process synthetic ground truth datasets iteratively.
%       4. Perform parallelized expanding-window model evaluation.
%       5. Aggregate results and generate performance visualizations.
%
%   See also PARTA_CONFIG, GENDATA_SIRS, PLOT_RT_FORECAST_COMPARISON.

% A. M. Kaahin 2026-02-19
% Modified: 2026-03-26

%% 1. Initialization
clear; close all; clc;

fprintf('=== Forecast Pipeline Execution ===\n');

MODEL_TYPE = 'N4SID';
EXO_MODE   = 'I';

EXO_MODE = validate_configuration(MODEL_TYPE, EXO_MODE);
fprintf('Configuration: Model = %s | Exogenous Mode = %s\n', MODEL_TYPE, EXO_MODE);

%% 2. Configuration and Grid Setup
cfg      = partA_config(); 
dataDir  = cfg.output.data_dir;     
saveDir  = cfg.output.forecast_dir; 
fileList = dir(fullfile(dataDir, '*.mat'));
wis_alphas = cfg.forecast.wis_alphas;

switch MODEL_TYPE
    case 'AR'
        candidate_models = (0:cfg.forecast.max_ar_order)';
        table_headers    = {'p', 'Times_Selected'};

    case 'ARX'
        [P, NB, NK] = ndgrid( ...
            0:cfg.forecast.max_ar_order, ...
            1:cfg.forecast.max_exo_order, ...
            1:cfg.forecast.max_exo_delay);
        candidate_models = [P(:), NB(:), NK(:)];
        table_headers    = {'na', 'nb', 'nk', 'Times_Selected'};

    case {'N4SID', 'SSEST'}
        [N_order, D_order] = ndgrid( ...
            1:cfg.forecast.max_state_order, ...
            cfg.forecast.state_diff_orders);
        candidate_models = [N_order(:), D_order(:)];
        table_headers    = {'State_Order_n', 'Differencing_d', 'Times_Selected'};

    otherwise
        error('CFG:UnknownModel', 'Unsupported MODEL_TYPE: %s', MODEL_TYPE);
end

num_models = size(candidate_models, 1);

if isempty(gcp('nocreate'))
    parpool; 
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
    
    max_S = max(loaded.S_true(:));
    max_I = max(loaded.I_true(:));
    norm_S = loaded.S_true(:) / max_S;
    norm_I = loaded.I_true(:) / max_I;
    
    switch EXO_MODE
        case 'None', U_true = [];
        case 'S',    U_true = norm_S;
        case 'I',    U_true = norm_I;
        case 'Both', U_true = [norm_S, norm_I];
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
    selected_models_log = zeros(num_windows, size(candidate_models, 2));
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
            
            norm_S_fut = S_future_raw / max_S;
            norm_I_fut = I_future_raw / max_I;
            
            switch EXO_MODE
                case 'S',    U_future = norm_S_fut;
                case 'I',    U_future = norm_I_fut;
                case 'Both', U_future = [norm_S_fut, norm_I_fut];
            end
        end
        
        par_landscape = zeros(num_models, size(candidate_models, 2) + 1);
        par_forecasts = cell(num_models, 1);
        par_lowers    = cell(num_models, 1);
        par_uppers    = cell(num_models, 1);
        par_alphas    = cell(num_models, 1);
        
        parfor idx = 1:num_models
            params = candidate_models(idx, :);
            
            Rt_pred   = [];
            aicc      = [];
            Rt_lower  = [];
            Rt_upper  = [];
            wis_alpha = [];
            
            switch MODEL_TYPE
                case 'AR'
                    [Rt_pred, aicc, wis_alpha, Rt_lower, Rt_upper] = ...
                        fit_arima(Rt_past, params(1), 0, 0, horizon, wis_alphas);

                case 'ARX'
                    nb_vec = repmat(params(2), 1, num_exo);
                    nk_vec = repmat(params(3), 1, num_exo);
                    [Rt_pred, aicc, wis_alpha, Rt_lower, Rt_upper] = ...
                        fit_arimax(Rt_past, U_past, U_future, params(1), 0, 0, ...
                        nb_vec, nk_vec, horizon, wis_alphas);

                case 'N4SID'
                    [Rt_pred, aicc, wis_alpha, Rt_lower, Rt_upper] = ...
                        fit_n4sid(Rt_past, U_past, U_future, params(1), params(2), ...
                        horizon, wis_alphas);

                case 'SSEST'
                    [Rt_pred, aicc, wis_alpha, Rt_lower, Rt_upper] = ...
                        fit_ssest(Rt_past, U_past, U_future, params(1), params(2), ...
                        horizon, wis_alphas);
            end
            
            par_landscape(idx, :) = [params, aicc];
            par_forecasts{idx} = Rt_pred;
            par_lowers{idx}    = Rt_lower;
            par_uppers{idx}    = Rt_upper;
            par_alphas{idx}    = wis_alpha;
        end
        
        [~, sort_idx]    = sort(par_landscape(:, end));
        sorted_landscape = par_landscape(sort_idx, :);
        
        best_idx       = sort_idx(1);
        best_Rt_pred   = par_forecasts{best_idx};
        best_Rt_lower  = par_lowers{best_idx};
        best_Rt_upper  = par_uppers{best_idx};
        best_wis_alpha = par_alphas{best_idx};
        best_params    = sorted_landscape(1, 1:end-1);
        
        results(count).window_day      = T;
        results(count).window_day_idx  = idx_T;
        results(count).forecast_median = best_Rt_pred;
        results(count).forecast_interval_alphas = best_wis_alpha;
        results(count).forecast_lower  = best_Rt_lower;
        results(count).forecast_upper  = best_Rt_upper;
        results(count).best_model      = best_params;
        results(count).aic_landscape   = sorted_landscape;
        results(count).truth_Rt_window = Rt_true(idx_T+1 : idx_end);
        results(count).time_horizon    = tspan(idx_T+1 : idx_end);
        
        selected_models_log(count, :) = best_params;
        count = count + 1;
    end

    results = results(1:count-1);
    selected_models_log = selected_models_log(1:count-1, :);
    
    %% 4. Artifact Generation
    [uq_models, ~, uq_idx] = unique(selected_models_log, 'rows');
    model_counts           = accumarray(uq_idx, 1);
    [model_counts, sort_count_idx] = sort(model_counts, 'descend');
    uq_models              = uq_models(sort_count_idx, :);
    
    summary_table = array2table([uq_models, model_counts], 'VariableNames', table_headers);
    
    file_prefix = sprintf('partA_02_forecast_%s_%s_%s', scenario_id, MODEL_TYPE, EXO_MODE);
    
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
