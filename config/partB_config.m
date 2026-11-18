function cfg = partB_config(fixture)

%PARTB_CONFIG Configure Part B infectious-population forecasting experiments.
%
%   Syntax:
%       cfg = partB_config()
%       cfg = partB_config(fixture)
%
%   Description:
%       Extends the shared synthetic-validation configuration with five
%       robustness conditions (clean baseline, observation noise, process
%       noise, structural mismatch, combined stress), the SIRS-inversion
%       estimation settings, the persistence/oracle/ARX forecast methods, and
%       the Part B output paths. Structural-mismatch truth preserves the
%       shared immunity-waning assumption: SIR baselines use SEIR truth and
%       SIRS baselines use SEIRS truth. Every forecast uses the SIRS model.
%
%   Inputs:
%       fixture - Optional verification fixture with T_end, scenario_ids,
%                 and num_replicates (used only by
%                 PARTB_VERIFY_IMPLEMENTATION).
%
%   Outputs:
%       cfg - Structure inheriting all Part A fields plus:
%           .partB.experiment_id     : Short experiment identifier.
%           .partB.experiment_name   : Human-readable experiment name.
%           .partB.truth             : Base seed for truth simulation.
%           .partB.robustness_cases  : 1x5 robustness-case definitions.
%           .partB.process_noise     : Replicate seed stride.
%           .partB.seir              : SEIR/SEIRS truth parameters.
%           .partB.estimation        : SIRS-inversion settings.
%           .partB.method_ids        : Forecast-method identifiers.
%           .partB.arx               : Part A ARX/I selection reference.
%           .partB.visualization     : Figure settings.
%           .partB.output            : Part B data and result paths.
%           .partB.snapshot          : Artifact provenance snapshot.
%
%   See also PARTA_CONFIG, PARTB_01_PREPARE_DATASETS,
%            ESTIMATE_SIRS_HISTORY_FROM_INCIDENCE.
%
% A. M. Kaahin 2026-06-30
% Modified: 2026-11-18

%% 1. Inherit Part A Configuration
cfg = partA_config();
stochastic_replicates = 10;

%% 2. Verification Fixture
if nargin == 1
    cfg.time.T_end        = fixture.T_end;
    cfg.time.tspan        = 0:cfg.time.dt:cfg.time.T_end;
    cfg.scenarios         = cfg.scenarios(ismember([cfg.scenarios.id], fixture.scenario_ids));
    stochastic_replicates = fixture.num_replicates;
end

%% 3. Experiment Identity
cfg.partB.experiment_id   = "partB";
cfg.partB.experiment_name = "Infectious-Population Forecasting Robustness";

%% 4. Truth Simulation Seed
cfg.partB.truth.seed = 90210;

%% 5. Robustness Conditions
if cfg.sirs.xi < 0
    error('PARTB:InvalidWaningRate', 'cfg.sirs.xi must be nonnegative.');
elseif cfg.sirs.xi == 0
    baseline_truth_model   = "SIR";
    structural_truth_model = "SEIR";
else
    baseline_truth_model   = "SIRS";
    structural_truth_model = "SEIRS";
end

case_template    = struct("case_id", "", "case_name", "", "truth_model", "", "solver", "", "observation_noise_enabled", false, "process_noise_enabled", false, "structural_mismatch_enabled", false, "num_replicates", 1);
robustness_cases = repmat(case_template, 1, 5);

robustness_cases(1).case_id                     = "clean_baseline";
robustness_cases(1).case_name                   = "Clean Baseline";
robustness_cases(1).truth_model                 = baseline_truth_model;
robustness_cases(1).solver                      = "uds";
robustness_cases(1).observation_noise_enabled   = false;
robustness_cases(1).process_noise_enabled       = false;
robustness_cases(1).structural_mismatch_enabled = false;
robustness_cases(1).num_replicates              = 1;

robustness_cases(2).case_id                     = "observation_noise";
robustness_cases(2).case_name                   = "Observation Noise";
robustness_cases(2).truth_model                 = baseline_truth_model;
robustness_cases(2).solver                      = "uds";
robustness_cases(2).observation_noise_enabled   = true;
robustness_cases(2).process_noise_enabled       = false;
robustness_cases(2).structural_mismatch_enabled = false;
robustness_cases(2).num_replicates              = stochastic_replicates;

robustness_cases(3).case_id                     = "process_noise";
robustness_cases(3).case_name                   = "Process Noise";
robustness_cases(3).truth_model                 = baseline_truth_model;
robustness_cases(3).solver                      = "ssa";
robustness_cases(3).observation_noise_enabled   = false;
robustness_cases(3).process_noise_enabled       = true;
robustness_cases(3).structural_mismatch_enabled = false;
robustness_cases(3).num_replicates              = stochastic_replicates;

robustness_cases(4).case_id                     = "structural_mismatch";
robustness_cases(4).case_name                   = "Structural Mismatch";
robustness_cases(4).truth_model                 = structural_truth_model;
robustness_cases(4).solver                      = "uds";
robustness_cases(4).observation_noise_enabled   = false;
robustness_cases(4).process_noise_enabled       = false;
robustness_cases(4).structural_mismatch_enabled = true;
robustness_cases(4).num_replicates              = 1;

robustness_cases(5).case_id                     = "combined_stress";
robustness_cases(5).case_name                   = "Combined Stress";
robustness_cases(5).truth_model                 = structural_truth_model;
robustness_cases(5).solver                      = "ssa";
robustness_cases(5).observation_noise_enabled   = true;
robustness_cases(5).process_noise_enabled       = true;
robustness_cases(5).structural_mismatch_enabled = true;
robustness_cases(5).num_replicates              = stochastic_replicates;

cfg.partB.robustness_cases = robustness_cases;

%% 6. Process Noise
cfg.partB.process_noise.replicate_seed_stride = 1000;

%% 7. SEIR/SEIRS Truth Parameters
cfg.partB.seir.gamma    = cfg.sirs.gamma;
cfg.partB.seir.xi       = cfg.sirs.xi;
cfg.partB.seir.sigma    = 1 / 3;
cfg.partB.seir.pop_size = cfg.sirs.pop_size;
cfg.partB.seir.I0       = cfg.sirs.I0;
cfg.partB.seir.E0       = round(0.5 * cfg.sirs.I0);
cfg.partB.seir.R0_init  = cfg.sirs.R0_init;
cfg.partB.seir.min_susceptible_fraction = cfg.sirs.min_susceptible_fraction;
cfg.partB.seir.min_susceptible          = cfg.sirs.min_susceptible;

%% 8. Historical Estimation
cfg.partB.estimation.initial_state = [cfg.sirs.pop_size - cfg.sirs.I0 - cfg.sirs.R0_init; cfg.sirs.I0; cfg.sirs.R0_init];
cfg.partB.estimation.rel_tol       = 1e-4;
cfg.partB.estimation.abs_tol       = 0.1;
cfg.partB.estimation.max_fixed_point_iterations = 25;
cfg.partB.estimation.max_bracket_expansions     = 60;
cfg.partB.estimation.conservation_tolerance     = 1e-8 * cfg.sirs.pop_size;

%% 9. Forecast Methods and ARX Reference
cfg.partB.method_ids = ["persistence"; "oracle"; "arx"];

cfg.partB.arx.model_type         = "ARX";
cfg.partB.arx.exo_mode           = "I";
cfg.partB.arx.selection_artifact = fullfile(cfg.output.model_selection_dir, "partA_02_global_hyperparameters_ARX_I.mat");

%% 10. Visualization
cfg.partB.visualization.trajectory_origin_day = 147;
cfg.partB.visualization.trajectory_cases      = ["clean_baseline"; "combined_stress"];
cfg.partB.visualization.trajectory_replicate  = "rep001";
cfg.partB.visualization.history_days          = 28;

%% 11. Output Paths
thisDir  = fileparts(mfilename('fullpath'));
repoRoot = fileparts(thisDir);

cfg.partB.output.data_dir       = fullfile(repoRoot, "data", "partB");
cfg.partB.output.root_dir       = fullfile(repoRoot, "results", "partB");
cfg.partB.output.forecast_dir   = fullfile(cfg.partB.output.root_dir, "forecasts");
cfg.partB.output.evaluation_dir = fullfile(cfg.partB.output.root_dir, "evaluation");
cfg.partB.output.table_dir      = fullfile(cfg.partB.output.root_dir, "tables");
cfg.partB.output.fig_dir        = fullfile(cfg.partB.output.root_dir, "figures");

%% 12. Artifact Provenance Snapshot
cfg.partB.snapshot = struct();
cfg.partB.snapshot.experiment_id    = cfg.partB.experiment_id;
cfg.partB.snapshot.experiment_name  = cfg.partB.experiment_name;
cfg.partB.snapshot.time             = struct("T_end", cfg.time.T_end, "dt", cfg.time.dt);
cfg.partB.snapshot.Rt_bounds        = cfg.Rt.bounds;
cfg.partB.snapshot.scenarios        = cfg.scenarios;
cfg.partB.snapshot.truth_seed       = cfg.partB.truth.seed;
cfg.partB.snapshot.sirs             = cfg.sirs;
cfg.partB.snapshot.seir             = cfg.partB.seir;
cfg.partB.snapshot.robustness_cases = cfg.partB.robustness_cases;
cfg.partB.snapshot.process_noise    = cfg.partB.process_noise;
cfg.partB.snapshot.estimation       = cfg.partB.estimation;
cfg.partB.snapshot.forecast         = struct("min_window", cfg.forecast.min_window, "step_size", cfg.forecast.step_size, "horizon", cfg.forecast.horizon, "num_draws", cfg.intervals.num_draws, "include_epidemic_seed_variation", cfg.intervals.include_epidemic_seed_variation, "run_seed", cfg.run.seed);
cfg.partB.snapshot.method_ids       = cfg.partB.method_ids;
cfg.partB.snapshot.arx              = struct("model_type", cfg.partB.arx.model_type, "exo_mode", cfg.partB.arx.exo_mode, "selection_snapshot", cfg.snapshot.selection);

end
