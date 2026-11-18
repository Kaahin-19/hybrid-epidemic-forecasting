function cfg = partB_config(fixture)

%PARTB_CONFIG Configure Part B infectious-population forecasting experiments.
%
%   Syntax:
%       cfg = partB_config()
%       cfg = partB_config(fixture)
%
%   Description:
%       Extends the shared synthetic-validation configuration with the Part B
%       experiment: five robustness conditions (clean baseline, observation
%       noise, process noise, structural mismatch, combined stress), the
%       daily I-entry observation model, causal SIRS-inversion estimation of
%       the historical state and Rt, the three future-Rt drivers
%       (persistence, oracle, Part A-selected ARX/I), and the output paths.
%
%       Structural-mismatch truth preserves the shared immunity-waning
%       assumption: SIR baselines use SEIR truth and SIRS baselines use
%       SEIRS truth. Every forecast uses the SIRS model.
%
%       The configuration identity consists of protocol_version, a complete
%       machine-readable snapshot of all scientific settings, its JSON
%       encoding, and config_id (SHA-256 of that JSON). Implementation
%       provenance is recorded separately in provenance.source_id, a
%       SHA-256 fingerprint of the repository source-code content.
%
%       The optional fixture input is used only by the verification
%       script. It shortens the time grid, restricts the scenarios, and sets
%       the stochastic replicate count before any derived setting is
%       computed, so the snapshot and config_id describe the fixture.
%
%   Inputs:
%       fixture - Optional structure with T_end, scenario_ids (string
%                 array), and num_replicates.
%
%   Outputs:
%       cfg - Structure inheriting all Part A fields plus:
%           .partB.experiment_id, .experiment_name, .protocol_version
%           .partB.truth             : Truth-simulation seed.
%           .partB.robustness_cases  : 1x5 condition definitions.
%           .partB.observation       : I-entry observation model.
%           .partB.process_noise     : Replicate count and seed stride.
%           .partB.seir              : SEIR/SEIRS truth parameters.
%           .partB.estimation        : SIRS-inversion settings.
%           .partB.arx               : Part A ARX selection reference.
%           .partB.method_ids        : Forecast-method identifiers.
%           .partB.visualization     : Figure settings (not in snapshot).
%           .partB.output            : Part B data and result paths.
%           .partB.snapshot, .config_json, .config_id, .provenance
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
    unknown_ids = setdiff(fixture.scenario_ids, [cfg.scenarios.id]);
    if ~isempty(unknown_ids)
        error('PARTB_CONFIG:UnknownFixtureScenario', 'Unknown fixture scenario id(s): %s.', strjoin(unknown_ids, ', '));
    end

    cfg.time.T_end        = fixture.T_end;
    cfg.time.tspan        = 0:cfg.time.dt:cfg.time.T_end;
    cfg.scenarios         = cfg.scenarios(ismember([cfg.scenarios.id], fixture.scenario_ids));
    stochastic_replicates = fixture.num_replicates;
end

%% 3. Experiment Identity
cfg.partB.experiment_id    = "partB";
cfg.partB.experiment_name  = "Infectious-population forecasting under robustness conditions";
cfg.partB.protocol_version = "partB_infectious_forecast_v1";

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

%% 6. Observation Model
cfg.partB.observation.definition   = "entries_into_I";
cfg.partB.observation.noise_model  = "poisson";
cfg.partB.observation.seed_offset  = 5e8;

%% 7. Process Noise
cfg.partB.process_noise.replicate_seed_stride = 1000;

%% 8. SEIR/SEIRS Truth Parameters
cfg.partB.seir.gamma    = cfg.sirs.gamma;
cfg.partB.seir.xi       = cfg.sirs.xi;
cfg.partB.seir.sigma    = 1 / 3;
cfg.partB.seir.pop_size = cfg.sirs.pop_size;
cfg.partB.seir.I0       = cfg.sirs.I0;
cfg.partB.seir.E0       = round(0.5 * cfg.sirs.I0);
cfg.partB.seir.R0_init  = cfg.sirs.R0_init;
cfg.partB.seir.min_susceptible_fraction = cfg.sirs.min_susceptible_fraction;
cfg.partB.seir.min_susceptible          = cfg.sirs.min_susceptible;

%% 9. Historical Estimation
cfg.partB.estimation.method        = "sirs_inversion";
cfg.partB.estimation.initial_state = [cfg.sirs.pop_size - cfg.sirs.I0 - cfg.sirs.R0_init; cfg.sirs.I0; cfg.sirs.R0_init];
cfg.partB.estimation.rel_tol       = 1e-4;
cfg.partB.estimation.abs_tol       = 0.1;
cfg.partB.estimation.max_fixed_point_iterations = 25;
cfg.partB.estimation.max_bracket_expansions     = 60;
cfg.partB.estimation.conservation_tolerance     = 1e-8 * cfg.sirs.pop_size;

%% 10. Forecast Methods and ARX Reference
cfg.partB.method_ids = ["persistence"; "oracle"; "arx"];

cfg.partB.arx.model_type         = "ARX";
cfg.partB.arx.exo_mode           = "I";
cfg.partB.arx.selection_artifact = fullfile(cfg.output.model_selection_dir, "partA_02_global_hyperparameters_ARX_I.mat");
cfg.partB.arx.min_history        = cfg.forecast.min_window;

%% 11. Visualization
cfg.partB.visualization.trajectory_origin_day = 147;
cfg.partB.visualization.trajectory_cases      = ["clean_baseline"; "combined_stress"];
cfg.partB.visualization.trajectory_replicate  = "rep001";
cfg.partB.visualization.history_days          = 28;

%% 12. Output Paths
thisDir  = fileparts(mfilename('fullpath'));
repoRoot = fileparts(thisDir);

cfg.partB.output.data_dir       = fullfile(repoRoot, "data", "partB");
cfg.partB.output.root_dir       = fullfile(repoRoot, "results", "partB");
cfg.partB.output.forecast_dir   = fullfile(cfg.partB.output.root_dir, "forecasts");
cfg.partB.output.evaluation_dir = fullfile(cfg.partB.output.root_dir, "evaluation");
cfg.partB.output.table_dir      = fullfile(cfg.partB.output.root_dir, "tables");
cfg.partB.output.fig_dir        = fullfile(cfg.partB.output.root_dir, "figures");

%% 13. Configuration Identity
[~, selection_name, selection_ext] = fileparts(cfg.partB.arx.selection_artifact);

snapshot = struct();
snapshot.protocol_version = cfg.partB.protocol_version;
snapshot.experiment_id    = cfg.partB.experiment_id;
snapshot.time             = struct("T_end", cfg.time.T_end, "dt", cfg.time.dt);
snapshot.Rt_bounds        = cfg.Rt.bounds;
snapshot.scenarios        = cfg.scenarios;
snapshot.sirs             = cfg.sirs;
snapshot.seir             = cfg.partB.seir;
snapshot.truth_seed       = cfg.partB.truth.seed;
snapshot.robustness_cases = cfg.partB.robustness_cases;
snapshot.observation      = cfg.partB.observation;
snapshot.process_noise    = cfg.partB.process_noise;
snapshot.estimation       = cfg.partB.estimation;
snapshot.forecast         = struct("min_window", cfg.forecast.min_window, "step_size", cfg.forecast.step_size, "horizon", cfg.forecast.horizon, "num_draws", cfg.intervals.num_draws, "include_epidemic_seed_variation", cfg.intervals.include_epidemic_seed_variation, "run_seed", cfg.run.seed);
snapshot.method_ids       = cfg.partB.method_ids;
snapshot.arx              = struct("model_type", cfg.partB.arx.model_type, "exo_mode", cfg.partB.arx.exo_mode, "selection_artifact", string(selection_name) + string(selection_ext), "min_history", cfg.partB.arx.min_history, "selection_snapshot", cfg.snapshot.selection);

cfg.partB.snapshot    = snapshot;
cfg.partB.config_json = string(jsonencode(snapshot));
cfg.partB.config_id   = local_sha256_hex(unicode2native(char(cfg.partB.config_json), 'UTF-8'));

%% 14. Implementation Provenance
cfg.partB.provenance = local_source_provenance();

end

%% 15. Local Functions
function provenance = local_source_provenance()
%LOCAL_SOURCE_PROVENANCE Content fingerprint of the repository source code that executes Part B.
stage_path = which('partB_01_prepare_datasets');
if isempty(stage_path)
    error('PARTB_CONFIG:SourceRootUnavailable', 'partB_01_prepare_datasets is not on the MATLAB path; run startup first.');
end

source_root = fileparts(fileparts(fileparts(stage_path)));

files = [dir(fullfile(source_root, 'src', '**', '*.m')); dir(fullfile(source_root, 'scripts', '**', '*.m')); dir(fullfile(source_root, 'config', '**', '*.m')); dir(fullfile(source_root, 'startup.m')); dir(fullfile(source_root, 'run_partB_pipeline.sh'))];
relative_paths = strings(numel(files), 1);
for i = 1:numel(files)
    relative_paths(i) = string(erase(fullfile(files(i).folder, files(i).name), [source_root filesep]));
end
[relative_paths, order] = sort(relative_paths);
files = files(order);

manifest = strings(numel(files), 1);
for i = 1:numel(files)
    fid = fopen(fullfile(files(i).folder, files(i).name), 'r');
    content = fread(fid, Inf, '*uint8');
    fclose(fid);
    manifest(i) = relative_paths(i) + "  " + local_sha256_hex(content);
end

[git_status, git_head] = system(sprintf('git -C "%s" rev-parse HEAD', source_root));
if git_status ~= 0
    git_head = "unavailable";
end
[dirty_status, dirty_output] = system(sprintf('git -C "%s" status --porcelain -- src scripts config startup.m run_partB_pipeline.sh', source_root));

provenance = struct();
provenance.source_root     = string(source_root);
provenance.source_id       = local_sha256_hex(unicode2native(char(strjoin(manifest, newline)), 'UTF-8'));
provenance.source_manifest = manifest;
provenance.git_head        = strtrim(string(git_head));
provenance.git_source_dirty = dirty_status == 0 && strlength(strtrim(string(dirty_output))) > 0;
end

function hex = local_sha256_hex(bytes)
%LOCAL_SHA256_HEX SHA-256 digest of a byte vector as a lowercase hex string.
digest = java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(bytes(:), 'int8'));
hex = string(lower(reshape(dec2hex(typecast(digest.digest(), 'uint8'), 2)', 1, [])));
end
