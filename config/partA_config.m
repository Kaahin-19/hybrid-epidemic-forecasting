function cfg = partA_config()

%PARTA_CONFIG Configure Part A synthetic-validation experiments.
%
%   Syntax:
%       cfg = partA_config()
%
%   Description:
%       Defines the synthetic-validation time grid, canonical effective-Rt
%       scenarios, SIRS parameters, the role-separated synthetic dataset
%       design, the active model configuration, the forecasting protocol and
%       candidate grids, the one-SE selection rule, predictive interval
%       settings, artifact snapshots, and output paths.
%
%   Inputs:
%       None.
%
%   Outputs:
%       cfg - Structure containing:
%           .time       : Simulation duration and time grid.
%           .Rt         : Effective reproduction-number bounds.
%           .sirs       : SIRS parameters and stepping guard.
%           .scenarios  : Canonical analytic effective-Rt scenarios A1-A4.
%           .design     : Development, refinement, and assessment datasets.
%           .run        : Active model, exogenous-input mode, valid
%                         model/input configurations, seed, and workers.
%           .forecast   : Forecast windows, candidate grids, WIS levels,
%                         recognised infeasibility identifiers, and plot
%                         settings.
%           .selection  : One-SE threshold multipliers.
%           .intervals  : Predictive interval simulation settings.
%           .snapshot   : Artifact compatibility snapshots.
%           .output     : Data, result, figure, and table paths.
%
%   See also PARTA_01_GENERATE_TRUTH, PARTA_02_SELECT_HYPERPARAMETERS,
%            GENERATE_RT_SIGNAL, PARTB_CONFIG, PARTC_CONFIG.
%
% A. M. Kaahin 2026-02-18
% Modified: 2026-11-26

%% 1. Configuration Initialization
cfg = struct();

%% 2. Time Grid
cfg.time.T_end = 365;
cfg.time.dt    = 1;
cfg.time.tspan = 0:cfg.time.dt:cfg.time.T_end;

%% 3. Effective-Reproduction-Number Bounds
cfg.Rt.bounds = [0.5, 2.0];

%% 4. SIRS Simulation Parameters
cfg.sirs.gamma    = 1/7;
cfg.sirs.xi       = 1/90;
cfg.sirs.pop_size = 100000;
cfg.sirs.I0       = 500;
cfg.sirs.R0_init  = 0;

cfg.sirs.min_susceptible_fraction = 0.05;
cfg.sirs.min_susceptible = cfg.sirs.min_susceptible_fraction * cfg.sirs.pop_size;

%% 5. Canonical Scenario Definitions
cfg.scenarios = repmat(struct("id", "", "name", "", "signal_type", "", "params", struct()), 1, 4);

T_end      = cfg.time.T_end;
wave_space = T_end / 5;
wave_denom = (wave_space^2) / 8;
wave_scale = 0.27;

cfg.scenarios(1).id          = "A1";
cfg.scenarios(1).name        = "Seasonal Forcing";
cfg.scenarios(1).signal_type = "seasonal";
cfg.scenarios(1).params      = struct("center", 1, "amp", 0.18, "period", T_end, "phase", 0);

cfg.scenarios(2).id          = "A2";
cfg.scenarios(2).name        = "Policy Intervention";
cfg.scenarios(2).signal_type = "sigmoid";
cfg.scenarios(2).params      = struct("high", 1.30, "low", 0.65, "t0", 51, "k", 4 / 14);

cfg.scenarios(3).id          = "A3";
cfg.scenarios(3).name        = "Damped Recurrent Waves";
cfg.scenarios(3).signal_type = "multi_wave";
cfg.scenarios(3).params      = struct("baseline", 0.90, "mu1", 1 * wave_space, "A1", wave_scale * 1.00, "mu2", 2 * wave_space, "A2", wave_scale * 0.95, "mu3", 3 * wave_space, "A3", wave_scale * 0.95^2, "mu4", 4 * wave_space, "A4", wave_scale * 0.95^3, "denom", wave_denom);

cfg.scenarios(4).id          = "A4";
cfg.scenarios(4).name        = "Amplifying Recurrent Waves";
cfg.scenarios(4).signal_type = "multi_wave";
cfg.scenarios(4).params      = struct("baseline", 0.90, "mu1", 1 * wave_space, "A1", wave_scale * 1.00, "mu2", 2 * wave_space, "A2", wave_scale * 1.05, "mu3", 3 * wave_space, "A3", wave_scale * 1.05^2, "mu4", 4 * wave_space, "A4", wave_scale * 1.05^3, "denom", wave_denom);

%% 6. Synthetic Dataset Design
% Development trajectories are zero-mean periodic signals with exact
% extrema: trough = center - trough_depth and peak = center + peak_ratio *
% trough_depth. A peak_ratio within [1, 5/3] keeps one trough per cycle, and
% trough_depth <= 0.5 with peak_ratio <= 5/3 keeps Rt within [0.5, 1.84].
% Refinement trajectories are the canonical scenarios plus random variants;
% assessment trajectories are further random variants. Variants keep the
% canonical family's net transmission budget: A1 keeps center 1, A2 keeps
% its pre-intervention growth (high - 1) * t0 below the canonical value,
% and A3/A4 derive their baseline so that the mean Rt over the time grid
% equals the canonical mean. Each random trajectory draws its parameters, in
% a fixed order, from its own substream with index equal to its seed index.
cfg.design.seed        = 20261126;
cfg.design.stream_type = "mrg32k3a";

cfg.design.seed_index_base = struct("refinement", 100, "development", 200, "assessment", 300);

cfg.design.min_susceptible_margin = 3;
cfg.design.conservation_tolerance = 1e-6 * cfg.sirs.pop_size;

cfg.design.development.family = "P";
cfg.design.development.center = 1;
cfg.design.development.phase  = [0, 2 * pi];
cfg.design.development.strata = struct( ...
    "id",               {"PH"; "PL"}, ...
    "name",             {"Strong fast periodic"; "Mild slow periodic"}, ...
    "num_trajectories", {4; 4}, ...
    "trough_depth",     {[0.35, 0.50]; [0.15, 0.30]}, ...
    "peak_ratio",       {[1, 5/3]; [1, 5/3]}, ...
    "period",           {[35, 56]; [60, 105]});

cfg.design.refinement.num_variants = 3;
cfg.design.assessment.num_variants = 3;

cfg.design.variants.A1 = struct("amp", [0.12, 0.18], "phase", [0, 2 * pi]);
cfg.design.variants.A2 = struct("t0", [49, 63], "k", [3, 5] / 14, "low", [0.65, 0.85], "growth_fraction", [0.7, 1.0]);
cfg.design.variants.A3 = struct("spacing", [70, 80], "scale", [0.24, 0.30], "ratio", [0.92, 0.97]);
cfg.design.variants.A4 = struct("spacing", [70, 80], "scale", [0.22, 0.27], "ratio", [1.03, 1.06]);

%% 7. Active Run Configuration
cfg.run.seed        = 23487;
cfg.run.num_workers = 4;

cfg.run.valid_configurations = [
    "AR",    "None";
    "ARX",   "S";
    "ARX",   "I";
    "ARX",   "Both";
    "N4SID", "None";
    "N4SID", "S";
    "N4SID", "I";
    "N4SID", "Both";
    "SSEST", "None";
    "SSEST", "S";
    "SSEST", "I";
    "SSEST", "Both"];

cfg.run.model_type = string(local_env_or_default('PARTA_MODEL_TYPE', 'ARX'));
cfg.run.exo_mode   = string(local_env_or_default('PARTA_EXO_MODE', 'I'));
cfg.run.exo_mode   = local_resolve_run_configuration(cfg.run.model_type, cfg.run.exo_mode, cfg.run.valid_configurations);

%% 8. Forecasting Protocol and Candidate Grids
cfg.forecast.min_window = 49;
cfg.forecast.step_size  = 7;
cfg.forecast.horizon    = 14;

cfg.forecast.max_ar_order    = 7;
cfg.forecast.max_exo_order   = 4;
cfg.forecast.max_exo_delay   = 4;
cfg.forecast.max_state_order = 4;

cfg.forecast.wis_alphas     = [0.05; 0.10; 0.20; 0.50];
cfg.forecast.plot_alphas    = [0.10, 0.50];
cfg.forecast.plot_lead_time = 7;

cfg.forecast.seed_policy = "Origin w of the trajectory with seed index k uses seed run.seed + 10000*k + w for residual resampling and that seed + 1e6 as the SIRS epidemic seed, which is inert under the deterministic uds solver.";

% Forecast failures recorded as experimental infeasibility; any other error
% terminates the run.
cfg.forecast.infeasibility_ids = [
    "FORECAST_OPEN:InvalidForecastDraw";
    "FORECAST_CLOSED:InvalidForecastDraw";
    "EPIDEMIC:SusceptibleBelowThreshold";
    "FORECAST_OPEN:ConstantSeries";
    "FORECAST_CLOSED:ConstantSeries";
    "FORECAST_OPEN:InsufficientHistory";
    "FORECAST_CLOSED:InsufficientHistory";
    "FORECAST_OPEN:InsufficientResiduals";
    "FORECAST_CLOSED:InsufficientResiduals"];

%% 9. One-SE Selection Rule
cfg.selection.se_multiplier           = 1;
cfg.selection.sensitivity_multipliers = [0; 0.5; 2];

%% 10. Predictive Interval Settings
cfg.intervals.num_draws = 60;
cfg.intervals.include_epidemic_seed_variation = true;

%% 11. Artifact Compatibility Snapshots
cfg.snapshot.design = struct("T_end", cfg.time.T_end, "dt", cfg.time.dt, "Rt_bounds", cfg.Rt.bounds, "sirs", cfg.sirs, "scenarios", cfg.scenarios, "design", cfg.design);

cfg.snapshot.selection = struct("model_type", cfg.run.model_type, "exo_mode", cfg.run.exo_mode, "seed", cfg.run.seed, "min_window", cfg.forecast.min_window, "step_size", cfg.forecast.step_size, "horizon", cfg.forecast.horizon, "max_ar_order", cfg.forecast.max_ar_order, "max_exo_order", cfg.forecast.max_exo_order, "max_exo_delay", cfg.forecast.max_exo_delay, "max_state_order", cfg.forecast.max_state_order, "wis_alphas", cfg.forecast.wis_alphas, "infeasibility_ids", cfg.forecast.infeasibility_ids, "num_draws", cfg.intervals.num_draws, "include_epidemic_seed_variation", cfg.intervals.include_epidemic_seed_variation, "sirs", cfg.sirs, "selection", cfg.selection, "design", cfg.snapshot.design);

cfg.snapshot.forecast = struct("model_type", cfg.run.model_type, "exo_mode", cfg.run.exo_mode, "seed", cfg.run.seed, "min_window", cfg.forecast.min_window, "step_size", cfg.forecast.step_size, "horizon", cfg.forecast.horizon, "wis_alphas", cfg.forecast.wis_alphas, "infeasibility_ids", cfg.forecast.infeasibility_ids, "num_draws", cfg.intervals.num_draws, "include_epidemic_seed_variation", cfg.intervals.include_epidemic_seed_variation, "sirs", cfg.sirs, "design", cfg.snapshot.design);

%% 12. Output Paths
thisDir  = fileparts(mfilename('fullpath'));
repoRoot = fileparts(thisDir);

cfg.output.data_dir            = fullfile(repoRoot, "data", "partA");
cfg.output.dataset_manifest    = fullfile(cfg.output.data_dir, "partA_01_dataset_manifest.mat");
cfg.output.root_dir            = fullfile(repoRoot, "results", "partA");
cfg.output.model_selection_dir = fullfile(cfg.output.root_dir, "model_selection");
cfg.output.forecast_dir        = fullfile(cfg.output.root_dir, "forecasts");
cfg.output.score_dir           = fullfile(cfg.output.root_dir, "evaluation");
cfg.output.fig_dir             = fullfile(cfg.output.root_dir, "figures");
cfg.output.table_dir           = fullfile(cfg.output.root_dir, "tables");

end

%% 13. Local Functions
function value = local_env_or_default(env_name, default_value)
%LOCAL_ENV_OR_DEFAULT Return environment value or default string.
value = getenv(env_name);

if isempty(value)
    value = default_value;
end
end

function exo_mode = local_resolve_run_configuration(model_type, exo_mode, valid_configurations)
%LOCAL_RESOLVE_RUN_CONFIGURATION Resolve active model and exogenous-input mode.
valid_exo_modes = ["None", "S", "I", "Both"];

if ~any(model_type == valid_configurations(:, 1))
    error('CFG:InvalidRunModel', 'Unsupported PARTA_MODEL_TYPE value: %s.', model_type);
end

if ~any(exo_mode == valid_exo_modes)
    error('CFG:InvalidRunExo', 'Unsupported PARTA_EXO_MODE value: %s.', exo_mode);
end

if model_type == "AR" && exo_mode ~= "None"
    warning('CFG:ArExo', 'AR is strictly autoregressive. Forcing EXO_MODE to None.');
    exo_mode = "None";
end

if ~any(valid_configurations(:, 1) == model_type & valid_configurations(:, 2) == exo_mode)
    error('CFG:InvalidRunCombination', '%s does not support EXO_MODE %s.', model_type, exo_mode);
end
end
