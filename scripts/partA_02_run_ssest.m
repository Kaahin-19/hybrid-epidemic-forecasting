%PARTA_02_RUN_SSEST Track 4: Optimized State-Space Forecasting (ssest)
%
%   Description:
%       Executes a State-Space forecasting pipeline using the iterative
%       Prediction Error optimizer (ssest). 
%       Can run as a pure time-series ('None') or with Exogenous inputs.

%% 1. Initialization
clear; clc;
cfg = partA_config(); 
dataDir = cfg.output.data_dir;     
saveDir = cfg.output.forecast_dir; 
fileList = dir(fullfile(dataDir, '*.mat'));

% =========================================================================
% CONFIGURATION: EXOGENOUS VARIABLE
% =========================================================================
exo_mode = 'Both';    % Options: 'None', 'S', 'I', or 'Both'
% =========================================================================

fprintf('=== Starting TRACK 4 Forecasts (SSEST | Exo: %s) ===\n', exo_mode);

% EXHAUSTIVE GRIDS FOR STATE-SPACE
grid_n = 1:8;               % Number of hidden states (Differential Equations)
grid_d = [0, 1];            % Integrated order (Stationary vs Trend)

[N_order, D_order] = ndgrid(grid_n, grid_d);
candidate_models = [N_order(:), D_order(:)];
num_models = size(candidate_models, 1);
fprintf('Testing %d unique SSEST configurations per window.\n', num_models);

if isempty(gcp('nocreate'))
    parpool; 
end

%% 2. Main Experiment Loop
for i = 1:length(fileList)
    filename = fileList(i).name;
    fullPath = fullfile(dataDir, filename);
    [~, name_core] = fileparts(filename);
    
    fprintf('\nProcessing Scenario: %s\n', name_core);
    
    loaded = load_mat_safe(fullPath);
    Rt_true = loaded.Rt_true;
    tspan   = loaded.tspan;
    
    % --- DYNAMIC EXOGENOUS DATA ---
    raw_S = loaded.S_true(:);
    raw_I = loaded.I_true(:);
    
    norm_S = raw_S / max(raw_S);
    norm_I = raw_I / max(raw_I);
    
    switch exo_mode
        case 'None'
            U_true = [];
        case 'S'
            U_true = norm_S;
        case 'I'
            U_true = norm_I;
        case 'Both'
            U_true = [norm_S, norm_I];
        otherwise
            error('Invalid exo_mode. Choose ''None'', ''S'', ''I'', or ''Both''.');
    end
    
    results = struct();
    count = 1;
    
    T_end = length(Rt_true);
    max_T = T_end - cfg.forecast.horizon;
    windows = cfg.forecast.min_window : cfg.forecast.step_size : max_T;
    
    selected_models_log = []; 
    
    % --- Expanding Window Loop ---
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
        
        par_landscape = zeros(num_models, 3); 
        par_forecasts = cell(num_models, 1);
        
        parfor idx = 1:num_models
            n = candidate_models(idx, 1);
            d = candidate_models(idx, 2);
            
            [Rt_pred, aicc] = fit_predict_ssest(Rt_past, U_past, U_future, n, d, horizon);
            
            par_landscape(idx, :) = [n, d, aicc];
            par_forecasts{idx} = Rt_pred;
        end
        
        [~, sort_idx] = sort(par_landscape(:, 3));
        sorted_landscape = par_landscape(sort_idx, :);
        
        best_idx = sort_idx(1);
        best_Rt_pred = par_forecasts{best_idx};
        best_n_d = sorted_landscape(1, 1:2);
        
        results(count).window_day     = T;
        results(count).window_day_idx = idx_T;
        results(count).forecast_Rt    = best_Rt_pred;
        results(count).best_model     = best_n_d;
        results(count).aic_landscape  = sorted_landscape; 
        results(count).truth_Rt_window = Rt_true(idx_T+1 : idx_end);
        results(count).time_horizon    = tspan(idx_T+1 : idx_end);
        
        selected_models_log = [selected_models_log; best_n_d]; %#ok<AGROW>
        count = count + 1;
    end
    
    % --- Generate Summary ---
    [uq_models, ~, uq_idx] = unique(selected_models_log, 'rows');
    model_counts = accumarray(uq_idx, 1);
    [model_counts, sort_count_idx] = sort(model_counts, 'descend');
    uq_models = uq_models(sort_count_idx, :);
    
    summary_table = table(uq_models(:,1), uq_models(:,2), model_counts, ...
        'VariableNames', {'State_Order_n', 'Differencing_d', 'Times_Selected'});
    
    fprintf('  Model Selection Summary for %s:\n', name_core);
    disp(summary_table);
    
    run_tag = ['_', exo_mode];
    
    csvName = fullfile(saveDir, sprintf('track4_model_summary_%s%s.csv', name_core, run_tag));
    writetable(summary_table, csvName);
    
    outName = fullfile(saveDir, sprintf('track4_results_%s%s.mat', name_core, run_tag));
    save_mat_atomic(outName, 'results', results, 'cfg', cfg);
    
    plot_name = sprintf('%s_SSEST%s', name_core, run_tag);
    plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg);
end
fprintf('\n=== TRACK 4 Forecasts Complete ===\n');

function [Rt_curve, aicc] = fit_predict_ssest(Rt_hist, U_hist, U_future, n, d, horizon)
    epsilon = 1e-6;
    y = log(Rt_hist(:) + epsilon);
    
    if d == 1
        fit_y = diff(y);
        if isempty(U_hist)
            fit_u = [];
            fit_u_fut = [];
        else
            fit_u = diff(U_hist, 1, 1); 
            combined_fut = [U_hist(end, :); U_future];
            fit_u_fut = diff(combined_fut, 1, 1);
        end
    else
        fit_y = y;
        fit_u = U_hist;
        fit_u_fut = U_future;
    end
    
    if std(fit_y) < 1e-8
        fit_y = fit_y + (randn(size(fit_y)) * 1e-6);
    end
    
    N_samples = length(fit_y);
    data = iddata(fit_y, fit_u, 1);
    
    try
        opt_est = ssestOptions('Display', 'off');
        sys = ssest(data, n, opt_est);
        
        n_params = length(getpvec(sys)); 
        aic = sys.Report.Fit.AIC;
        
        if N_samples > n_params + 1
            aicc = aic + (2 * n_params * (n_params + 1)) / (N_samples - n_params - 1);
        else
            aicc = inf;
        end
        
        fut_data = iddata([], fit_u_fut, 1);
        opt = forecastOptions('InitialCondition', 'z');
        f_obj = forecast(sys, data, horizon, fut_data, opt);
        pred_fit = f_obj.OutputData;
        
        if d == 1
            pred_y = y(end) + cumsum(pred_fit);
        else
            pred_y = pred_fit;
        end
        
        Rt_curve = exp(pred_y) - epsilon;
        Rt_curve = max(0, min(10, Rt_curve));
    catch
        Rt_curve = repmat(Rt_hist(end), horizon, 1);
        aicc = inf;
    end
end