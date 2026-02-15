%PARTA_02_RUN_FORECASTS Orchestrate the hybrid forecasting experiment.
%
%   Description:
%       Executes the core "Hybrid Inference" experiment for Part A.
%
%       The "Hybrid" approach uses a Day-by-Day Closed Feedback Loop:
%       1. Statistical Step: An ARX model (in logspace) predicts the next 
%          day's Rt using past Rt and past Infected (I) counts.
%       2. Mechanistic Step: The SIRS ODE model projects the next day's 
%          Infected (I) count using the newly predicted Rt.
%       3. Feedback: The new state feeds back into the statistical model.

%% 1. Initialization
clear; clc;

cfg = partA_config(); 

dataDir = cfg.output.data_dir;     
saveDir = cfg.output.forecast_dir; 

fileList = dir(fullfile(dataDir, 'synthetic_*.mat'));

fprintf('=== Starting Part A: Hybrid Forecasts (ARX Closed-Loop) ===\n');
fprintf('Found %d scenarios in %s\n', length(fileList), dataDir);

%% 2. Main Experiment Loop
for i = 1:length(fileList)
    filename = fileList(i).name;
    fullPath = fullfile(dataDir, filename);
    [~, name_core] = fileparts(filename);
    
    fprintf('\nProcessing: %s\n', name_core);
    
    loaded = load_mat_safe(fullPath);
    Rt_true   = loaded.Rt_true;
    tspan     = loaded.tspan;
    umod_true = loaded.umod;
    dynrates  = loaded.dynrates;
    
    results = struct();
    count = 1;
    
    T_end = length(Rt_true);
    max_T = T_end - cfg.forecast.horizon;
    windows = cfg.forecast.min_window : cfg.forecast.step_size : max_T;
    
    % --- A. Expanding Window Loop ---
    for T = windows
        idx_T = find(tspan == T, 1);
        if isempty(idx_T), continue; end
        
        % 1. Extract Historical Data
        Rt_past = Rt_true(1:idx_T);
        I_past  = umod_true.U(2, 1:idx_T)'; % Exogenous variable
        
        % 2. Train ARX Model (in logspace)
        sys = train_arx_logspace(Rt_past, I_past, cfg.forecast.ar_order);
        
        % 3. The Mechanistic Step (Day-by-Day Closed Loop)
        Rt_pred_curve = zeros(cfg.forecast.horizon, 1);
        I_pred_curve  = zeros(1, cfg.forecast.horizon);
        
        % Initialize simulation states
        u_curr      = umod_true.U(:, idx_T);
        Rt_sim_hist = Rt_past(:);
        I_sim_hist  = I_past(:);
        
        for k = 1:cfg.forecast.horizon
            % a. Predict Rt(t+k) using ARX
            Rt_next = predict_arx_1step(sys, Rt_sim_hist, I_sim_hist);
            Rt_pred_curve(k) = Rt_next;
            
            % b. Run ODE for 1 step using the new Rt
            Rt_traj_step = [Rt_sim_hist(end); Rt_next];
            [~, I_step_curve, u_full_step] = hybrid_forecast_ode(u_curr, Rt_traj_step, dynrates);
            
            % c. Extract new State
            I_next = I_step_curve(end);
            u_curr = u_full_step(:, end);
            I_pred_curve(k) = I_next;
            
            % d. Append to simulated history for the next step
            Rt_sim_hist = [Rt_sim_hist; Rt_next];
            I_sim_hist  = [I_sim_hist; I_next];
        end
        
        % 4. Store Results
        results(count).window_day     = T;
        results(count).window_day_idx = idx_T;
        results(count).forecast_Rt    = Rt_pred_curve;
        results(count).forecast_I     = I_pred_curve;
        
        idx_end = idx_T + cfg.forecast.horizon;
        results(count).truth_Rt_window = Rt_true(idx_T+1 : idx_end);
        results(count).truth_I_window  = umod_true.U(2, idx_T : idx_end); 
        results(count).time_horizon    = tspan(idx_T+1 : idx_end);
        
        count = count + 1;
    end
    
    % --- B. Save & Visualize ---
    outName = fullfile(saveDir, ['results_' filename]);
    save_mat_atomic(outName, 'results', results, 'cfg', cfg);
    fprintf('  -> Saved results to: %s\n', outName);
    
    plot_truth_vs_forecast(results, umod_true, tspan, name_core, cfg);
end

fprintf('\n=== All Forecasts Complete ===\n');

%% ========================================================================
%  LOCAL FUNCTIONS: ARX Statistical Modeling
%  ========================================================================

function sys = train_arx_logspace(Rt_hist, I_hist, order)
    % Trains an ARX model using Log(Rt) as output and I as exogenous input
    epsilon = 1e-6;
    y = log(Rt_hist(:) + epsilon);
    u = I_hist(:);
    
    if length(y) <= order
        order = max(1, length(y) - 1);
    end
    
    data = iddata(y, u, 1);
    
    try
        % na: past y, nb: past u, nk: input delay
        sys = arx(data, [order, order, 1]); 
    catch
        sys = [];
    end
end

function Rt_next = predict_arx_1step(sys, Rt_hist, I_hist)
    % Predicts exactly 1 day ahead using the trained ARX model
    epsilon = 1e-6;
    if isempty(sys)
        Rt_next = Rt_hist(end);
        return;
    end
    
    y = log(Rt_hist(:) + epsilon);
    u = I_hist(:);
    data = iddata(y, u, 1);
    
    opt = forecastOptions('InitialCondition', 'z');
    p = forecast(sys, data, 1, opt);
    
    % Inverse Log-Transform
    Rt_next = exp(p.OutputData) - epsilon;
    
    % Final stability safeguard to prevent ODE numerical crashing 
    Rt_next = max(0, min(10, Rt_next)); 
end