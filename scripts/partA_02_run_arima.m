%PARTA_02_RUN_ARIMA Track 1: Pure Statistical Rt Forecasting (AR vs ARIMA).
%
%   Description:
%       Executes Track 1 using an adaptive, parallelized ARIMA pipeline.
%       Implements an exhaustive grid search using AICc to prevent overfitting.
%       Evaluates models concurrently using parfor for maximum efficiency.

%% 1. Initialization
clear; clc;

cfg = partA_config(); 
dataDir = cfg.output.data_dir;     
saveDir = cfg.output.forecast_dir; 
fileList = dir(fullfile(dataDir, '*.mat'));

fprintf('=== Starting Track 1: Parallelized Statistical Forecasts ===\n');

% EXHAUSTIVE GRIDS (No Inductive Bias)
grid_p = 0:14;              % Contiguous search up to 2 weeks
grid_d = [0, 1];            % Stationary vs. Constant Trend
grid_q = 0:2;               % Short-term shock absorption limit

% Flatten grids into a matrix of all possible combinations
[P, D, Q] = ndgrid(grid_p, grid_d, grid_q);
candidate_models = [P(:), D(:), Q(:)];
num_models = size(candidate_models, 1);

fprintf('Testing %d unique ARIMA configurations per window.\n', num_models);

% Initialize Parallel Pool (Starts if not already running)
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
        
        Rt_past = Rt_true(1:idx_T);
        horizon = cfg.forecast.horizon;
        
        % Pre-allocate arrays for parallel loop
        par_landscape = zeros(num_models, 4); % [p, d, q, aicc]
        par_forecasts = cell(num_models, 1);
        
        % --- PARALLEL MODEL EVALUATION ---
        parfor idx = 1:num_models
            p = candidate_models(idx, 1);
            d = candidate_models(idx, 2);
            q = candidate_models(idx, 3);
            
            [Rt_pred, aicc] = fit_predict_arima(Rt_past, p, d, q, horizon);
            
            par_landscape(idx, :) = [p, d, q, aicc];
            par_forecasts{idx} = Rt_pred;
        end
        
        % Sort landscape by AICc (Lowest is best)
        [~, sort_idx] = sort(par_landscape(:, 4));
        sorted_landscape = par_landscape(sort_idx, :);
        
        % Extract Best and Runner-Up
        best_idx = sort_idx(1);
        best_Rt_pred = par_forecasts{best_idx};
        best_pdq = sorted_landscape(1, 1:3);
        
        runner_up_pdq = sorted_landscape(2, 1:3);
        delta_aicc = sorted_landscape(2, 4) - sorted_landscape(1, 4);
        
        % Log to Struct
        results(count).window_day     = T;
        results(count).window_day_idx = idx_T;
        results(count).forecast_Rt    = best_Rt_pred;
        results(count).best_pdq       = best_pdq;
        results(count).runner_up_pdq  = runner_up_pdq;
        results(count).delta_aicc     = delta_aicc;
        results(count).aic_landscape  = sorted_landscape; 
        
        idx_end = idx_T + horizon;
        results(count).truth_Rt_window = Rt_true(idx_T+1 : idx_end);
        results(count).time_horizon    = tspan(idx_T+1 : idx_end);
        
        selected_models_log = [selected_models_log; best_pdq]; %#ok<AGROW>
        count = count + 1;
    end
    
    % --- End of Scenario: Generate Model Selection Summary ---
    [uq_models, ~, uq_idx] = unique(selected_models_log, 'rows');
    model_counts = accumarray(uq_idx, 1);
    
    [model_counts, sort_count_idx] = sort(model_counts, 'descend');
    uq_models = uq_models(sort_count_idx, :);
    
    summary_table = table(uq_models(:,1), uq_models(:,2), uq_models(:,3), model_counts, ...
        'VariableNames', {'p', 'd', 'q', 'Times_Selected'});
    
    fprintf('  Model Selection Summary for %s:\n', name_core);
    disp(summary_table);
    
    % Save Results & Summary
    outName = fullfile(saveDir, ['track1_results_' filename]);
    save_mat_atomic(outName, 'results', results, 'cfg', cfg);
    
    csvName = fullfile(saveDir, ['track1_model_summary_' name_core '.csv']);
    writetable(summary_table, csvName);
    
    plot_rt_forecast_comparison(results, Rt_true, tspan, name_core, cfg);
end

fprintf('\n=== Track 1 Forecasts Complete ===\n');

%% ========================================================================
%  LOCAL FUNCTIONS: ARIMA Modeling with AICc
%  ========================================================================

function [Rt_curve, aicc] = fit_predict_arima(Rt_hist, p, d, q, horizon)
    epsilon = 1e-6;
    y = log(Rt_hist(:) + epsilon);
    
    if d == 1
        fit_data = diff(y);
    else
        fit_data = y;
    end
    
    n = length(fit_data);
    k = p + q; 
    
    if n <= k + 1
        Rt_curve = repmat(Rt_hist(end), horizon, 1); 
        aicc = inf; 
        return;
    end
    
    data = iddata(fit_data, [], 1);
    
    try
        if q == 0
            sys = ar(data, p, 'ls');
        else
            sys = armax(data, [p, q], 'Display', 'off');
        end
        
        aic = sys.Report.Fit.AIC;
        
        % Calculate AICc
        aicc = aic + (2 * k * (k + 1)) / (n - k - 1);
        
        opt = forecastOptions('InitialCondition', 'z');
        f_obj = forecast(sys, data, horizon, opt);
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