%PARTA_02_RUN_ARIMAX Hybrid Baseline: Statistical Forecasting with Exogenous Data
%
%   Description:
%       Executes an adaptive, parallelized ARIMAX pipeline.
%       Features selectable Exogenous inputs (S, I, or Both) to test what
%       biological data best informs Rt prediction.
%% 1. Initialization
clear; clc;
cfg = partA_config(); 
dataDir = cfg.output.data_dir;     
saveDir = cfg.output.forecast_dir; 
fileList = dir(fullfile(dataDir, '*.mat'));

% =========================================================================
% CONFIGURATION: SELECT YOUR EXOGENOUS VARIABLE(S)
% Options: 'S' (Susceptible), 'I' (Infected), or 'Both'
exo_mode = 'Both'; 
% =========================================================================

fprintf('=== Starting ARIMAX Forecasts (Exogenous Mode: %s) ===\n', exo_mode);

% EXHAUSTIVE GRIDS 
grid_p  = 0:14;             % Autoregressive order (past Rt)
grid_d  = [0, 1];           % Integrated order (Stationary vs Trend)
grid_q  = 0:2;              % Moving Average order (Error shock absorption)
grid_nb = 1:2;              % Exogenous memory (Applies to all inputs)
grid_nk = 1;                % Delay (usually 1 day)

% Flatten grids into a matrix
[P, D, Q, NB, NK] = ndgrid(grid_p, grid_d, grid_q, grid_nb, grid_nk);
candidate_models = [P(:), D(:), Q(:), NB(:), NK(:)];
num_models = size(candidate_models, 1);
fprintf('Testing %d unique ARIMAX configurations per window.\n', num_models);

% Initialize Parallel Pool
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
    
    % --- DYNAMIC EXOGENOUS DATA CONSTRUCTION ---
    raw_S = loaded.S_true(:);
    raw_I = loaded.I_true(:);
    
    % Normalize to [0, 1] to prevent matrix scaling collapse
    norm_S = raw_S / max(raw_S);
    norm_I = raw_I / max(raw_I);
    
    switch exo_mode
        case 'S'
            U_true = norm_S;
        case 'I'
            U_true = norm_I;
        case 'Both'
            U_true = [norm_S, norm_I]; % Matrix [Time x 2]
        otherwise
            error('Invalid exo_mode. Choose ''S'', ''I'', or ''Both''.');
    end
    
    num_exo = size(U_true, 2);
    
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
        
        Rt_past  = Rt_true(1:idx_T);
        U_past   = U_true(1:idx_T, :);
        U_future = U_true(idx_T+1 : idx_end, :); 
        
        par_landscape = zeros(num_models, 6); 
        par_forecasts = cell(num_models, 1);
        
        % --- PARALLEL MODEL EVALUATION ---
        parfor idx = 1:num_models
            p  = candidate_models(idx, 1);
            d  = candidate_models(idx, 2);
            q  = candidate_models(idx, 3);
            nb_scalar = candidate_models(idx, 4);
            nk_scalar = candidate_models(idx, 5);
            
            % Expand exogenous orders for multiple inputs
            nb_vec = repmat(nb_scalar, 1, num_exo);
            nk_vec = repmat(nk_scalar, 1, num_exo);
            
            [Rt_pred, aicc] = fit_predict_arimax_dynamic(Rt_past, U_past, U_future, p, d, q, nb_vec, nk_vec, horizon);
            
            par_landscape(idx, :) = [p, d, q, nb_scalar, nk_scalar, aicc];
            par_forecasts{idx} = Rt_pred;
        end
        
        % Sort landscape by AICc (Lowest is best)
        [~, sort_idx] = sort(par_landscape(:, 6));
        sorted_landscape = par_landscape(sort_idx, :);
        
        best_idx = sort_idx(1);
        best_Rt_pred = par_forecasts{best_idx};
        best_pdq_nb_nk = sorted_landscape(1, 1:5);
        
        % Log Results
        results(count).window_day     = T;
        results(count).window_day_idx = idx_T;
        results(count).forecast_Rt    = best_Rt_pred;
        results(count).best_model     = best_pdq_nb_nk;
        results(count).aic_landscape  = sorted_landscape; 
        results(count).truth_Rt_window = Rt_true(idx_T+1 : idx_end);
        results(count).time_horizon    = tspan(idx_T+1 : idx_end);
        
        selected_models_log = [selected_models_log; best_pdq_nb_nk]; %#ok<AGROW>
        count = count + 1;
    end
    
    % --- End of Scenario: Generate Summary ---
    [uq_models, ~, uq_idx] = unique(selected_models_log, 'rows');
    model_counts = accumarray(uq_idx, 1);
    [model_counts, sort_count_idx] = sort(model_counts, 'descend');
    uq_models = uq_models(sort_count_idx, :);
    
    summary_table = table(uq_models(:,1), uq_models(:,2), uq_models(:,3), uq_models(:,4), model_counts, ...
        'VariableNames', {'p', 'd', 'q', 'nb', 'Times_Selected'});
    
    fprintf('  Model Selection Summary for %s:\n', name_core);
    disp(summary_table);
    
    % Output Naming (Appends _S, _I, or _Both)
    run_tag = ['_', exo_mode];
    
    % Save CSV
    csvName = fullfile(saveDir, ['track2_model_summary_', name_core, run_tag, '.csv']);
    writetable(summary_table, csvName);
    
    % Save MAT
    outName = fullfile(saveDir, ['track2_results_', name_core, run_tag, '.mat']);
    save_mat_atomic(outName, 'results', results, 'cfg', cfg);
    
    % Save Plot 
    plot_name = [name_core, '_ARIMAX', run_tag];
    plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg);
end
fprintf('\n=== ARIMAX Forecasts Complete ===\n');

%% ========================================================================
%  LOCAL FUNCTIONS: DYNAMIC ARIMAX Modeling
%  ========================================================================
function [Rt_curve, aicc] = fit_predict_arimax_dynamic(Rt_hist, U_hist, U_future, p, d, q, nb_vec, nk_vec, horizon)
    epsilon = 1e-6;
    y = log(Rt_hist(:) + epsilon);
    
    % THE "I" IN ARIMAX: Difference Matrix column-by-column
    if d == 1
        fit_y = diff(y);
        fit_u = diff(U_hist, 1, 1); 
        
        % Difference future U connecting to last historical row
        combined_fut = [U_hist(end, :); U_future];
        fit_u_fut = diff(combined_fut, 1, 1);
    else
        fit_y = y;
        fit_u = U_hist;
        fit_u_fut = U_future;
    end
    
    if std(fit_y) < 1e-8
        fit_y = fit_y + (randn(size(fit_y)) * 1e-6);
    end
    
    % Parameter counting penalty (sum of nb array for multiple inputs)
    n = length(fit_y);
    k = p + q + sum(nb_vec); 
    if n <= k + 1
        Rt_curve = repmat(Rt_hist(end), horizon, 1); 
        aicc = inf; 
        return;
    end
    
    data = iddata(fit_y, fit_u, 1);
    
    try
        % Dynamic Routing
        if q == 0
            % arx format: [na, nb_vec, nk_vec]
            sys = arx(data, [p, nb_vec, nk_vec]);
        else
            % armax format: [na, nb_vec, nc, nk_vec]
            sys = armax(data, [p, nb_vec, q, nk_vec], 'Display', 'off');
        end
        
        aic = sys.Report.Fit.AIC;
        aicc = aic + (2 * k * (k + 1)) / (n - k - 1);
        
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