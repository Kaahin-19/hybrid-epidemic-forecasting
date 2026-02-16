%PARTA_02_RUN_ARIMAX Hybrid Baseline: Statistical Forecasting with Exogenous Data
%
%   Description:
%       Executes an adaptive, parallelized ARIMAX pipeline.
%       Uses exogenous data (e.g., Susceptible population) to guide Rt forecasts.
%       Automatically routes to fast ARX (if q=0) or heavy ARMAX (if q>0).
%% 1. Initialization
clear; clc;
cfg = partA_config(); 
dataDir = cfg.output.data_dir;     
saveDir = cfg.output.forecast_dir; 
fileList = dir(fullfile(dataDir, '*.mat'));
fprintf('=== Starting ARIMAX (Hybrid Baseline) Forecasts ===\n');

% EXHAUSTIVE GRIDS 
grid_p  = 0:14;             % Autoregressive order (past Rt)
grid_d  = [0, 1];           % Integrated order (Stationary vs Trend)
grid_q  = 0:2;              % Moving Average order (Error shock absorption)
grid_nb = 1:2;              % Exogenous order (past S or I data)
grid_nk = 1;                % Delay (usually 1 day)

% Flatten grids into a matrix of all possible combinations
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
    
    % --- EXOGENOUS DATA ---
    % Assume S_true (Susceptible) or I_true (Infected) is saved in the mat file.
    % We will use S_true as our exogenous variable (U) for this example.
    U_true  = loaded.S_true; 
    tspan   = loaded.tspan;
    
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
        
        % 1. Target Data (Y)
        Rt_past = Rt_true(1:idx_T);
        
        % 2. Exogenous Data (U)
        U_past   = U_true(1:idx_T);
        
        % IMPORTANT FOR PART B: 
        % In this standalone script, we feed the "true" future U to the forecast.
        % When you build the final hybrid ODE loop, this U_future will come 
        % directly from your URDME 'uds' solver predictions, not the ground truth!
        U_future = U_true(idx_T+1 : idx_end); 
        
        % Pre-allocate arrays for parallel loop
        par_landscape = zeros(num_models, 6); % [p, d, q, nb, nk, aicc]
        par_forecasts = cell(num_models, 1);
        
        % --- PARALLEL MODEL EVALUATION ---
        parfor idx = 1:num_models
            p  = candidate_models(idx, 1);
            d  = candidate_models(idx, 2);
            q  = candidate_models(idx, 3);
            nb = candidate_models(idx, 4);
            nk = candidate_models(idx, 5);
            
            [Rt_pred, aicc] = fit_predict_arimax(Rt_past, U_past, U_future, p, d, q, nb, nk, horizon);
            
            par_landscape(idx, :) = [p, d, q, nb, nk, aicc];
            par_forecasts{idx} = Rt_pred;
        end
        
        % Sort landscape by AICc (Lowest is best)
        [~, sort_idx] = sort(par_landscape(:, 6));
        sorted_landscape = par_landscape(sort_idx, :);
        
        % Extract Best 
        best_idx = sort_idx(1);
        best_Rt_pred = par_forecasts{best_idx};
        best_pdq_nb_nk = sorted_landscape(1, 1:5);
        
        % Log to Struct
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
    
    % --- End of Scenario: Generate Model Selection Summary ---
    [uq_models, ~, uq_idx] = unique(selected_models_log, 'rows');
    model_counts = accumarray(uq_idx, 1);
    [model_counts, sort_count_idx] = sort(model_counts, 'descend');
    uq_models = uq_models(sort_count_idx, :);
    
    summary_table = table(uq_models(:,1), uq_models(:,2), uq_models(:,3), uq_models(:,4), model_counts, ...
        'VariableNames', {'p', 'd', 'q', 'nb', 'Times_Selected'});
    
    fprintf('  Model Selection Summary for %s:\n', name_core);
    disp(summary_table);
    
    % Save Results
    outName = fullfile(saveDir, ['track2_results_' filename]);
    save_mat_atomic(outName, 'results', results, 'cfg', cfg);

    
    plot_name = [name_core, '_ARIMAX'];
    plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg);
end
fprintf('\n=== ARIMAX Forecasts Complete ===\n');

%% ========================================================================
%  LOCAL FUNCTIONS: ARIMAX Modeling with AICc
%  ========================================================================
function [Rt_curve, aicc] = fit_predict_arimax(Rt_hist, U_hist, U_future, p, d, q, nb, nk, horizon)
    epsilon = 1e-6;
    
    % Prepare Target (Y) and Exogenous (U) Data
    y = log(Rt_hist(:) + epsilon);
    u = U_hist(:);
    u_fut = U_future(:);
    
    % Normalize Exogenous data (Crucial for matrix conditioning in ARIMAX)
    u_scale = max(u);
    if u_scale > 0
        u = u / u_scale;
        u_fut = u_fut / u_scale;
    end
    
    % THE "I" IN ARIMAX: Difference BOTH signals synchronously
    if d == 1
        fit_y = diff(y);
        fit_u = diff(u);
        % To difference the future U, we must subtract the last known historical U
        fit_u_fut = diff([u(end); u_fut]);
    else
        fit_y = y;
        fit_u = u;
        fit_u_fut = u_fut;
    end
    
    % Dithering (Prevent singular matrix crashes on synthetic flatlines)
    if std(fit_y) < 1e-8
        fit_y = fit_y + (randn(size(fit_y)) * 1e-6);
    end
    
    % Structural Safeguard
    n = length(fit_y);
    k = p + q + nb; 
    if n <= k + 1
        Rt_curve = repmat(Rt_hist(end), horizon, 1); 
        aicc = inf; 
        return;
    end
    
    % Create iddata object for training
    data = iddata(fit_y, fit_u, 1);
    
    try
        % --- THE ROUTING LOGIC ---
        if q == 0
            % Pure ARX: Fast Linear Least Squares
            sys = arx(data, [p, nb, nk]);
        else
            % ARMAX: Heavy Non-Linear Iterative Solver
            sys = armax(data, [p, nb, q, nk], 'Display', 'off');
        end
        
        aic = sys.Report.Fit.AIC;
        aicc = aic + (2 * k * (k + 1)) / (n - k - 1);
        
        % --- FORECASTING WITH EXOGENOUS DATA ---
        % Create an iddata object for the future Exogenous data
        fut_data = iddata([], fit_u_fut, 1);
        
        % Forecast future Y using future U
        opt = forecastOptions('InitialCondition', 'z');
        f_obj = forecast(sys, data, horizon, fut_data, opt);
        pred_fit = f_obj.OutputData;
        
        % Re-integrate if differenced
        if d == 1
            pred_y = y(end) + cumsum(pred_fit);
        else
            pred_y = pred_fit;
        end
        
        % Inverse Log Transform and Clamp
        Rt_curve = exp(pred_y) - epsilon;
        Rt_curve = max(0, min(10, Rt_curve));
    catch
        Rt_curve = repmat(Rt_hist(end), horizon, 1);
        aicc = inf;
    end
end