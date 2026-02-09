%PARTA_02_RUN_FORECASTS Orchestrate the hybrid forecasting experiment.
%
%   Description:
%       Executes the core "Hybrid Inference" experiment for Part A. It applies
%       an Expanding Window Cross-Validation strategy to evaluate forecast
%       performance.
%
%       The "Hybrid" approach consists of two distinct steps per window:
%       1. Statistical Step: Fit an Auto-Regressive (AR) model 
%          to past Rt data to predict future Rt.
%       2. Mechanistic Step: Plug the predicted Rt into the 
%          SIRS ODE model to project future Infection (I) counts.
%
%   Workflow:
%       1. Setup: Load configuration and identify ground truth files.
%       2. Scenario Loop: Iterate through every synthetic dataset.
%       3. Window Loop: For each time point T (e.g., day 28, 35, 42...):
%          a. Truncate data to time T (simulate "real-time").
%          b. Forecast Rt (AR Model).
%          c. Forecast I (ODE Model).
%       4. Persistence: Save results and generate validation plots.
%
%   See also PARTA_CONFIG, FIT_AR_MODEL, HYBRID_FORECAST_ODE, PLOT_TRUTH_VS_FORECAST.

%% 1. Initialization
clear; clc;

% Load the Single Source of Truth configuration
cfg = partA_config(); 

% Define Input/Output Directories
dataDir = cfg.output.data_dir;     % Source: Ground Truth
saveDir = cfg.output.forecast_dir; % Dest: Forecast Results

ensure_dirs(saveDir);

% Get list of scenarios to process
fileList = dir(fullfile(dataDir, 'synthetic_*.mat'));

fprintf('=== Starting Part A: Hybrid Forecasts ===\n');
fprintf('Found %d scenarios in %s\n', length(fileList), dataDir);
fprintf('Forecast Config: MinWindow=%d, Step=%d, Horizon=%d\n', ...
    cfg.forecast.min_window, cfg.forecast.step_size, cfg.forecast.horizon);

%% 2. Main Experiment Loop
for i = 1:length(fileList)
    filename = fileList(i).name;
    fullPath = fullfile(dataDir, filename);
    [~, name_core] = fileparts(filename);
    
    fprintf('\nProcessing: %s\n', name_core);
    
    % --- A. Load Ground Truth ---
    % We need the full truth (Rt and Umod) to simulate "past" knowledge
    % and to evaluate "future" accuracy.
    loaded = load_mat_safe(fullPath);
    Rt_true   = loaded.Rt_true;
    tspan     = loaded.tspan;
    umod_true = loaded.umod;
    dynrates  = loaded.dynrates;
    
    % Initialize Results Container
    results = struct();
    count = 1;
    
    % Determine Validation Windows
    % We stop when the forecast horizon would exceed the simulation end.
    T_end = length(Rt_true);
    max_T = T_end - cfg.forecast.horizon;
    windows = cfg.forecast.min_window : cfg.forecast.step_size : max_T;
    
    % --- B. Expanding Window Loop ---
    for T = windows
        % 1. Prepare Training Data
        % Find index for "Today" (T).
        idx_T = find(tspan == T, 1);
        if isempty(idx_T), continue; end
        
        % Truncate history (Simulate having data only up to day T)
        Rt_past = Rt_true(1:idx_T);
        
        % 2. The Statistical Step
        % Fit AR model to past Rt and project forward.
        [Rt_pred_curve, ~] = fit_ar_model(Rt_past, cfg.forecast.horizon, cfg.forecast.ar_order);
        
        % 3. The Mechanistic Step
        % Use the ODE solver to translate Rt prediction into Case counts.
        
        % a. Get Initial Condition (State at day T)
        u0 = umod_true.U(:, idx_T);
        
        % b. Construct trajectory (Current Day + Forecast)
        Rt_current    = Rt_past(end);
        Rt_trajectory = [Rt_current; Rt_pred_curve];
        
        % c. Run Simulation (Model Agnostic ODE Solver)
        [~, I_pred_curve, ~] = hybrid_forecast_ode(u0, Rt_trajectory, dynrates);
        
        % 4. Store Results
        results(count).window_day     = T;
        results(count).window_day_idx = idx_T;
        results(count).forecast_Rt    = Rt_pred_curve;
        results(count).forecast_I     = I_pred_curve;
        
        % Store Truth segment for easier scoring later
        idx_end = idx_T + cfg.forecast.horizon;
        results(count).truth_Rt_window = Rt_true(idx_T+1 : idx_end);
        results(count).truth_I_window  = umod_true.U(2, idx_T : idx_end); 
        results(count).time_horizon    = tspan(idx_T+1 : idx_end);
        
        count = count + 1;
    end
    
    % --- C. Save & Visualize ---
    outName = fullfile(saveDir, ['results_' filename]);
    
    % Save 'cfg' with results to ensure reproducibility of settings
    save_mat_atomic(outName, 'results', results, 'cfg', cfg);
    fprintf('  -> Saved results to: %s\n', outName);
    
    % Generate summary plot
    plot_truth_vs_forecast(results, umod_true, tspan, name_core, cfg);
end

fprintf('\n=== All Forecasts Complete ===\n');