function cfg = partA_config()
%PARTA_CONFIG Configuration for Part A: Synthetic Validation.
%
%   Syntax:
%       cfg = partA_config()
%
%   Description:
%       Serves as the central configuration for Part A experiments. It
%       defines the simulation environment, ground truth parameters, and
%       forecasting hyperparameters. The active model family and
%       exogenous-input setting can be overridden externally through
%       environment variables.
%
%   Outputs:
%       cfg - Structure containing:
%           .time       : Simulation duration and step size.
%           .Rt         : Effective reproduction-number constraints for checks.
%           .scenarios  : Array of structs defining the signal slots.
%           .sirs       : Biological parameters (gamma, xi, pop_size).
%           .sim        : Reproducibility settings.
%           .run        : Active execution settings for Part A scripts.
%           .forecast   : Hyperparameters for the hybrid model.
%           .output     : Absolute paths for data and figure storage.
%
%   See also PARTA_00_MAKE_SCENARIOS, PARTA_01_GENERATE_TRUTH, ...
%            PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS, ...
%            PARTA_03_RUN_FORECASTS, PARTA_04_EVALUATE_MODELS.

% A. M. Kaahin 2026-02-18
% Modified: 2026-03-29

    cfg = struct();

    %% 1. Time Grid
    cfg.time.T_end = 365;
    cfg.time.dt    = 1;
    cfg.time.tspan = 0:cfg.time.dt:cfg.time.T_end;

    %% 2. Effective-Reproduction-Number Admissibility Constraints
    cfg.Rt.bounds = [0.5, 2.0];

    %% 3. Scenario Slots
    cfg.scenarios = repmat(struct( ...
        "id", "", ...
        "name", "", ...
        "generator", [], ...
        "params", struct() ...
    ), 1, 4);

    T_end      = cfg.time.T_end;
    wave_space = T_end / 5;
    wave_denom = (wave_space^2) / 8;

    % Slot A1
    cfg.scenarios(1).id        = "A1"; 
    cfg.scenarios(1).name      = "Seasonal Forcing";
    cfg.scenarios(1).generator = @rt_seasonal;
    cfg.scenarios(1).params    = struct( ...
        "center", 1.2, ...
        "amp",    0.3, ...
        "period", T_end / 2 ... 
    );

    % Slot A2
    cfg.scenarios(2).id        = "A2";
    cfg.scenarios(2).name      = "Policy Intervention";
    cfg.scenarios(2).generator = @rt_sigmoid;
    cfg.scenarios(2).params    = struct( ...
        "high", 1.8, ...
        "low",  0.7, ...
        "t0",   T_end / 3, ... 
        "k",    0.5, ...
        "I0",   5000 ...
    );

    % Slot A3
    cfg.scenarios(3).id        = "A3";
    cfg.scenarios(3).name      = "Damping Resurgence"; 
    cfg.scenarios(3).generator = @rt_multi_wave;
    cfg.scenarios(3).params    = struct( ...
        "baseline", 0.6, ...  
        "mu1",      1 * wave_space, ...
        "A1",       1.100, ... 
        "mu2",      2 * wave_space, ...
        "A2",       1.045, ... 
        "mu3",      3 * wave_space, ...
        "A3",       0.993, ... 
        "mu4",      4 * wave_space, ...
        "A4",       0.943, ... 
        "denom",    wave_denom ...
    );

    % Slot A4
    cfg.scenarios(4).id        = "A4";
    cfg.scenarios(4).name      = "Amplifying Resurgence";
    cfg.scenarios(4).generator = @rt_multi_wave;
    cfg.scenarios(4).params    = struct( ...
        "baseline", 0.6, ...  
        "mu1",      1 * wave_space, ...
        "A1",       0.943, ... 
        "mu2",      2 * wave_space, ...
        "A2",       0.993, ... 
        "mu3",      3 * wave_space, ...
        "A3",       1.045, ... 
        "mu4",      4 * wave_space, ...
        "A4",       1.100, ... 
        "denom",    wave_denom, ...
        "R0_init",  40000 ...
    );

    %% 4. Simulation Parameters (SIRS)
    cfg.sirs.gamma    = 1/7;
    cfg.sirs.xi       = 1/90;
    cfg.sirs.pop_size = 100000;
    cfg.sirs.I0       = 500;
    cfg.sirs.R0_init  = 0;

    %% 5. Reproducibility
    cfg.sim.seed = 1234;

    %% 6. Active Run Configuration
    cfg.run.model_type = string(local_env_or_default('PARTA_MODEL_TYPE', 'N4SID'));
    cfg.run.exo_mode   = string(local_env_or_default('PARTA_EXO_MODE', 'I'));
    local_validate_run_configuration(cfg.run.model_type, cfg.run.exo_mode);

    %% 7. Forecasting Hyperparameters
    cfg.forecast.min_window = 49;
    cfg.forecast.step_size  = 7;
    cfg.forecast.horizon    = 14;
    cfg.forecast.max_ar_order  = 10;
    cfg.forecast.max_exo_order = 4;
    cfg.forecast.max_exo_delay = 4;
    cfg.forecast.max_state_order = 4;
    cfg.forecast.state_diff_orders = 0;
    cfg.forecast.wis_alphas    = [0.05, 0.10, 0.20, 0.50];
    cfg.forecast.plot_alphas   = [0.10, 0.50];
    cfg.forecast.plot_lead_time = 7;

    %% 8. Output Artifacts
    thisDir  = fileparts(mfilename('fullpath'));
    repoRoot = fileparts(thisDir);

    cfg.output.data_dir     = fullfile(repoRoot, "data", "partA");
    cfg.output.root_dir     = fullfile(repoRoot, "results", "partA");
    cfg.output.fig_dir      = fullfile(cfg.output.root_dir, "figures");
    cfg.output.forecast_dir = fullfile(cfg.output.root_dir, "forecasts");
    cfg.output.score_dir    = fullfile(cfg.output.root_dir, "scores");
    cfg.output.tuning_dir   = fullfile(cfg.output.root_dir, "tuning");

end

function value = local_env_or_default(env_name, default_value)
    value = getenv(env_name);
    if isempty(value)
        value = default_value;
    end
end

function local_validate_run_configuration(model_type, exo_mode)
    valid_models = ["AR", "ARX", "N4SID", "SSEST"];
    valid_exo_modes = ["None", "S", "I", "Both"];

    if ~any(strcmp(model_type, valid_models))
        error('CFG:InvalidRunModel', ...
            'Unsupported PARTA_MODEL_TYPE value: %s.', string(model_type));
    end

    if ~any(strcmp(exo_mode, valid_exo_modes))
        error('CFG:InvalidRunExo', ...
            'Unsupported PARTA_EXO_MODE value: %s.', string(exo_mode));
    end
end
