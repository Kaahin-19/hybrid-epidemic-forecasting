function cfg = partA_config()
%PARTA_CONFIG Configuration for Part A: Synthetic Validation.
%
%   Syntax:
%       cfg = partA_config()
%
%   Description:
%       Serves as the "Single Source of Truth" for Part A experiments. It
%       defines the simulation environment, ground truth parameters, and
%       forecasting hyperparameters.
%
%       This configuration uses a "Slot" system (A1-A4). Downstream scripts
%       iterate through 'cfg.scenarios' agnostic to the content, executing
%       whatever generator function handle is provided in the slot.
%
%   Outputs:
%       cfg - Structure containing:
%           .time       : Simulation duration and step size.
%           .Rt         : Constraints for validity checks.
%           .scenarios  : Array of structs defining the 4 signal slots.
%           .sirs       : Biological parameters (Gamma, Xi).
%           .sim        : Reproducibility settings.
%           .forecast   : Hyperparameters for the Hybrid Model.
%           .output     : Absolute paths for data and figure storage.
%
%   See also PARTA_00_MAKE_SCENARIOS, PARTA_01_GENERATE_TRUTH, 
%            PARTA_02_RUN_FORECASTS, PARTA_03_EVALUATE.

    cfg = struct();

    %% 1. Time Grid
    cfg.time.T_end = 140;                       % Duration [days]
    cfg.time.dt    = 1;                         % Step size [days]
    cfg.time.tspan = 0:cfg.time.dt:cfg.time.T_end;

    %% 2. Rt Admissibility Constraints
    cfg.Rt.bounds       = [0.5, 2.0];           % [Min, Max] allowable Rt

    %% 3. Scenario Slots
    % Initialize container for 4 slots.
    cfg.scenarios = repmat(struct( ...
        "id", "", ...
        "class", "", ...
        "name", "", ...
        "generator", [], ...
        "params", struct() ...
    ), 1, 4);

    % --- Slot A1 ---
    cfg.scenarios(1).id        = "A1";
    cfg.scenarios(1).class     = "seasonal";
    cfg.scenarios(1).name      = "Seasonality";
    cfg.scenarios(1).generator = @rt_seasonal;
    cfg.scenarios(1).params    = struct( ...
        "center", 1.1, ...
        "amp",    0.4, ...
        "period", 60 ...
    );

    % --- Slot A2 ---
    cfg.scenarios(2).id        = "A2";
    cfg.scenarios(2).class     = "transient";
    cfg.scenarios(2).name      = "Intervention";
    cfg.scenarios(2).generator = @rt_transient;
    cfg.scenarios(2).params    = struct( ...
        "kind", "sigmoid_step", ...
        "high", 1.5, ...
        "low",  0.7, ...
        "t0",   50, ...
        "k",    0.3 ...
    );

    % --- Slot A3 ---
    cfg.scenarios(3).id        = "A3";
    cfg.scenarios(3).class     = "transient";
    cfg.scenarios(3).name      = "Damping Resurgence"; 
    cfg.scenarios(3).generator = @rt_transient;
    cfg.scenarios(3).params    = struct( ...
        "kind",     "multi_wave", ... 
        "baseline", 0.6, ...  
        "mu1",      40, ...
        "A1",       1.100, ... 
        "mu2",      80, ...
        "A2",       1.045, ... 
        "mu3",      120, ...
        "A3",       0.993, ... 
        "mu4",      160, ...
        "A4",       0.943, ... 
        "denom",    200 ...      
    );

    % --- Slot A4 ---
    cfg.scenarios(4).id        = "A4";
    cfg.scenarios(4).class     = "transient";
    cfg.scenarios(4).name      = "Amplifying Resurgence";
    cfg.scenarios(4).generator = @rt_transient;
    cfg.scenarios(4).params    = struct( ...
        "kind",     "multi_wave", ...
        "baseline", 0.6, ...  
        "mu1",      40, ...
        "A1",       0.943, ... 
        "mu2",      80, ...
        "A2",       0.993, ... 
        "mu3",      120, ...
        "A3",       1.045, ... 
        "mu4",      160, ...
        "A4",       1.100, ... 
        "denom",    200 ...   
    );

    %% 4. Simulation Parameters (SIRS)
    cfg.sirs.gamma = 1/7;       % Recovery rate [1/days]
    cfg.sirs.xi    = 0;         % Waning immunity rate [1/days]
    cfg.sirs.pop_size = 100000;  % Total population size

    %% 5. Reproducibility
    cfg.sim.seed = 1234;     % Fixed seed

    %% 6. Forecasting Hyperparameters
    cfg.forecast.min_window = 28;   % Initial training window [days]
    cfg.forecast.step_size  = 7;    % Window expansion step [days]
    cfg.forecast.horizon    = 14;   % Prediction horizon [days]

    %% 7. Output Artifacts
    thisDir  = fileparts(mfilename('fullpath')); % .../config
    repoRoot = fileparts(thisDir);               % .../ (Project Root)

    cfg.output.data_dir     = fullfile(repoRoot, "data", "ground_truth");
    cfg.output.fig_dir      = fullfile(repoRoot, "results", "figures");
    cfg.output.forecast_dir = fullfile(repoRoot, "results", "forecasts");
    cfg.output.score_dir    = fullfile(repoRoot, "results", "scores");
    
    cfg.output.fig_name     = "input_Rt_scenarios.png";

end