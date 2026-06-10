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
%           .truth      : Ground-truth simulator model and solver settings.
%           .sim        : Reproducibility settings.
%           .run        : Active execution settings for Part A scripts.
%           .forecast   : Hyperparameters for the hybrid model.
%           .output     : Absolute paths for data and artifact storage.
%
%   See also PARTA_01_GENERATE_TRUTH, ...
%            PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS, ...
%            PARTA_03_RUN_FORECASTS, PARTA_04_EVALUATE_FORECASTS.

% A. M. Kaahin 2026-02-18
% Modified: 2026-06-10

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
    "signal_type", "", ...
    "params", struct(), ...
    "init", struct() ...
    ), 1, 4);

T_end      = cfg.time.T_end;
wave_space = T_end / 5;
wave_denom = (wave_space^2) / 8;

% Slot A1
cfg.scenarios(1).id        = "A1";
cfg.scenarios(1).name      = "Seasonal Forcing";
cfg.scenarios(1).signal_type = "seasonal";
cfg.scenarios(1).params    = struct( ...
    "center", 1.2, ...
    "amp",    0.3, ...
    "period", T_end / 2 ...
    );

% Slot A2
cfg.scenarios(2).id        = "A2";
cfg.scenarios(2).name      = "Policy Intervention";
cfg.scenarios(2).signal_type = "sigmoid";
cfg.scenarios(2).params    = struct( ...
    "high", 1.8, ...
    "low",  0.7, ...
    "t0",   T_end / 3, ...
    "k",    0.5 ...
    );
cfg.scenarios(2).init      = struct("I0", 5000);

% Slot A3
cfg.scenarios(3).id        = "A3";
cfg.scenarios(3).name      = "Damping Resurgence";
cfg.scenarios(3).signal_type = "multi_wave";
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
cfg.scenarios(4).signal_type = "multi_wave";
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
    "denom",    wave_denom ...
    );
cfg.scenarios(4).init      = struct("R0_init", 40000);

%% 4. Simulation Parameters (SIRS)
cfg.sirs.gamma    = 1/7;
cfg.sirs.xi       = 1/90;
cfg.sirs.pop_size = 100000;
cfg.sirs.I0       = 500;
cfg.sirs.R0_init  = 0;

for s = 1:numel(cfg.scenarios)
    model_params = cfg.sirs;
    overrides = cfg.scenarios(s).init;
    for field = string(fieldnames(overrides))'
        model_params.(field) = overrides.(field);
    end
    cfg.scenarios(s).model_params = model_params;
end

%% 5. Ground-Truth Simulation
cfg.truth.model_type = "SIRS";
cfg.truth.solver     = "uds";
cfg.truth.compile    = true;

%% 6. Reproducibility
cfg.sim.seed = 1234;

%% 7. Active Run Configuration
cfg.run.model_type = string(local_env_or_default('PARTA_MODEL_TYPE', 'ARX'));
cfg.run.exo_mode   = string(local_env_or_default('PARTA_EXO_MODE', 'I'));
cfg.run.num_workers = 4;
cfg.run.exo_mode   = local_resolve_run_configuration(cfg.run.model_type, cfg.run.exo_mode);

%% 8. Forecasting Hyperparameters
cfg.forecast.min_window = 49;
cfg.forecast.step_size  = 7;
cfg.forecast.horizon    = 14;
cfg.forecast.max_ar_order  = 2;
cfg.forecast.max_exo_order = 2;
cfg.forecast.max_exo_delay = 2;
cfg.forecast.max_state_order = 2;
cfg.forecast.state_diff_orders = 0;
cfg.forecast.wis_alphas    = [0.05, 0.10, 0.20, 0.50];
cfg.forecast.plot_alphas   = [0.10, 0.50];
cfg.forecast.plot_lead_time = 7;

cfg.run_snapshot = struct( ...
    'min_window', cfg.forecast.min_window, ...
    'step_size',  cfg.forecast.step_size, ...
    'horizon',    cfg.forecast.horizon, ...
    'wis_alphas', cfg.forecast.wis_alphas, ...
    'pop_size',   cfg.sirs.pop_size, ...
    'gamma',      cfg.sirs.gamma, ...
    'xi',         cfg.sirs.xi, ...
    'sim_seed',   cfg.sim.seed);

%% 9. Predictive Interval Settings
cfg.intervals.seed = 1234;
cfg.intervals.method = "closed_loop_monte_carlo";
cfg.intervals.num_draws = 60;
cfg.intervals.min_residual_std = 1e-6;
cfg.intervals.use_common_random_numbers = true;
cfg.intervals.include_epidemic_seed_variation = true;
cfg.intervals.final_num_draws = cfg.intervals.num_draws;

%% 10. Output Artifacts
thisDir  = fileparts(mfilename('fullpath'));
repoRoot = fileparts(thisDir);

cfg.output.data_dir     = fullfile(repoRoot, "data", "partA");
cfg.output.root_dir     = fullfile(repoRoot, "results", "partA");
cfg.output.model_selection_dir = fullfile(cfg.output.root_dir, "model_selection");
cfg.output.forecast_dir = fullfile(cfg.output.root_dir, "forecasts");
cfg.output.score_dir    = fullfile(cfg.output.root_dir, "evaluation");
cfg.output.fig_dir      = fullfile(cfg.output.root_dir, "figures");
cfg.output.table_dir    = fullfile(cfg.output.root_dir, "tables");
cfg.output.log_dir      = fullfile(cfg.output.root_dir, "logs");

end

function value = local_env_or_default(env_name, default_value)
value = getenv(env_name);
if isempty(value)
    value = default_value;
end
end

function exo_mode = local_resolve_run_configuration(model_type, exo_mode)
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

if model_type == "AR" && exo_mode ~= "None"
    warning('CFG:ArExo', 'AR is strictly autoregressive. Forcing EXO_MODE to None.');
    exo_mode = "None";
elseif model_type == "ARX" && exo_mode == "None"
    error('CFG:ArxExo', ...
        'ARX requires exogenous covariates. Set EXO_MODE to S, I, or Both.');
end
end
