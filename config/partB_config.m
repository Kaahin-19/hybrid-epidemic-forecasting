function cfg = partB_config()
%PARTB_CONFIG Configure Part B robustness-dataset experiments.
%
%   Description:
%       Extends the Part A configuration with the Part B robustness design.
%       Part A supplies the shared time grid, effective-Rt bounds, SIRS
%       parameters, and analytic Rt scenarios. Part B adds the four
%       robustness cases (observation noise, process noise, structural
%       mismatch, and combined stress), the SEIR truth parameters used by
%       the structural-mismatch and combined-stress cases, the observation
%       model, the renewal-estimation settings, and the Part B output paths.
%
%   Outputs:
%       cfg - Structure inheriting all Part A fields plus:
%           .partB.experiment_id     : Short experiment identifier.
%           .partB.experiment_name   : Human-readable experiment name.
%           .partB.truth             : Base seed for truth simulation.
%           .partB.robustness_cases  : 1x4 robustness-case definitions.
%           .partB.observation_noise : Reporting and smoothing parameters.
%           .partB.process_noise     : Replicate count and seed stride.
%           .partB.seir              : SEIR truth parameters.
%           .partB.rt_estimation     : Renewal-estimator settings.
%           .partB.output            : Part B data and result paths.
%           .partB.snapshot          : Artifact provenance snapshot.
%
%   See also PARTA_CONFIG, PARTB_01_GENERATE_ROBUSTNESS_DATASETS, ESTIMATE_RT_RENEWAL.
%
% A. M. Kaahin 2026-06-30

%% 1. Inherit Part A Configuration
cfg = partA_config();

%% 2. Experiment Identity and Run Configuration
cfg.partB.experiment_id   = "partB";
cfg.partB.experiment_name = "Robustness Dataset Generation";
cfg.partB.run.model_types = ["AR", "ARX"];

%% 3. Truth Simulation Seed
cfg.partB.truth.seed = 90210;

%% 4. Robustness Case Definitions
case_template    = struct("case_id", "", "case_name", "", "truth_model", "", "solver", "", "observation_noise_enabled", false, "process_noise_enabled", false, "structural_mismatch_enabled", false);
robustness_cases = repmat(case_template, 1, 4);

robustness_cases(1).case_id                     = "observation_noise";
robustness_cases(1).case_name                   = "Observation Noise";
robustness_cases(1).truth_model                 = "SIRS";
robustness_cases(1).solver                      = "uds";
robustness_cases(1).observation_noise_enabled   = true;
robustness_cases(1).process_noise_enabled       = false;
robustness_cases(1).structural_mismatch_enabled = false;

robustness_cases(2).case_id                     = "process_noise";
robustness_cases(2).case_name                   = "Process Noise";
robustness_cases(2).truth_model                 = "SIRS";
robustness_cases(2).solver                      = "ssa";
robustness_cases(2).observation_noise_enabled   = false;
robustness_cases(2).process_noise_enabled       = true;
robustness_cases(2).structural_mismatch_enabled = false;

robustness_cases(3).case_id                     = "structural_mismatch";
robustness_cases(3).case_name                   = "Structural Mismatch";
robustness_cases(3).truth_model                 = "SEIR";
robustness_cases(3).solver                      = "uds";
robustness_cases(3).observation_noise_enabled   = false;
robustness_cases(3).process_noise_enabled       = false;
robustness_cases(3).structural_mismatch_enabled = true;

robustness_cases(4).case_id                     = "combined_stress";
robustness_cases(4).case_name                   = "Combined Stress";
robustness_cases(4).truth_model                 = "SEIR";
robustness_cases(4).solver                      = "ssa";
robustness_cases(4).observation_noise_enabled   = true;
robustness_cases(4).process_noise_enabled       = true;
robustness_cases(4).structural_mismatch_enabled = true;

cfg.partB.robustness_cases = robustness_cases;

%% 5. Observation Noise
cfg.partB.observation_noise.reporting_fraction    = 0.4;
cfg.partB.observation_noise.dispersion            = 10;
cfg.partB.observation_noise.smoothing_window_days = 7;
cfg.partB.observation_noise.num_replicates = 10;

%% 6. Process Noise
cfg.partB.process_noise.num_replicates        = 10;
cfg.partB.process_noise.replicate_seed_stride = 1000;

%% 7. SEIR Truth Parameters
cfg.partB.seir.gamma    = cfg.sirs.gamma;
cfg.partB.seir.sigma    = 1 / 3;
cfg.partB.seir.pop_size = cfg.sirs.pop_size;
cfg.partB.seir.I0       = cfg.sirs.I0;
cfg.partB.seir.E0       = round(0.5 * cfg.sirs.I0);
cfg.partB.seir.R0_init  = cfg.sirs.R0_init;

%% 8. Renewal Estimation
cfg.partB.rt_estimation.serial_interval_mean_days    = 5;
cfg.partB.rt_estimation.serial_interval_sd_days      = 2.5;
cfg.partB.rt_estimation.serial_interval_max_lag_days = 14;
cfg.partB.rt_estimation.min_denominator              = 1;

%% 9. Output Paths
thisDir  = fileparts(mfilename('fullpath'));
repoRoot = fileparts(thisDir);

cfg.partB.output.data_dir     = fullfile(repoRoot, "data", "partB");
cfg.partB.output.root_dir     = fullfile(repoRoot, "results", "partB");
cfg.partB.output.forecast_dir = fullfile(cfg.partB.output.root_dir, "forecasts");

%% 10. Artifact Provenance Snapshot
cfg.partB.snapshot = struct();
cfg.partB.snapshot.experiment_id     = cfg.partB.experiment_id;
cfg.partB.snapshot.experiment_name   = cfg.partB.experiment_name;
cfg.partB.snapshot.truth_seed        = cfg.partB.truth.seed;
cfg.partB.snapshot.Rt_bounds         = cfg.Rt.bounds;
cfg.partB.snapshot.sirs              = cfg.sirs;
cfg.partB.snapshot.seir              = cfg.partB.seir;
cfg.partB.snapshot.observation_noise = cfg.partB.observation_noise;
cfg.partB.snapshot.process_noise     = cfg.partB.process_noise;
cfg.partB.snapshot.rt_estimation     = cfg.partB.rt_estimation;

end
