%PARTA_01_GENERATE_SYNTHETIC_TRUTH Generate and persist Part A synthetic truth data.
%
%   Description:
%       Executes the Part A SIRS synthetic truth stage. The script loads the
%       configured analytic effective-Rt scenarios, generates each Rt signal,
%       simulates the corresponding SIRS ground truth, and saves one MATLAB
%       artifact per scenario for downstream model-selection and forecasting
%       stages.
%
%   Workflow:
%       1. Load configuration and ensure the Part A data directory exists.
%       2. Generate each configured effective-Rt signal.
%       3. Simulate and save one SIRS truth artifact per scenario.
%
%   See also PARTA_CONFIG, GENERATE_RT_SIGNAL, SIMULATE_GROUND_TRUTH_EPIDEMIC.
%
% A. M. Kaahin 2026-05-31

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Synthetic Truth Generation ===\n');

cfg = partA_config();
tspan = cfg.time.tspan;
dataDir = cfg.output.data_dir;

if ~exist(dataDir, 'dir')
    mkdir(dataDir);
end

%% 2. Simulation and Persistence Loop
fprintf('Saving trajectories to: %s\n', dataDir);
failed_mask = false(numel(cfg.scenarios), 1);

for i = 1:numel(cfg.scenarios)
    scenario = cfg.scenarios(i);
    fprintf('  - Processing %s (%s)... ', scenario.id, scenario.name);

    try
        Rt_true = generate_rt_signal(tspan, scenario);
        model_params = local_model_params_for_scenario(cfg, scenario);
        sim_options = local_sim_options_from_cfg(cfg);
        truth = simulate_ground_truth_epidemic( ...
            cfg.truth.model_type, tspan, Rt_true, model_params, sim_options);

        artifact = struct();
        artifact.scenario_id = string(scenario.id);
        artifact.scenario_name = string(scenario.name);
        artifact.Rt_true = truth.Rt_true;
        artifact.S_true = truth.S_true;
        artifact.I_true = truth.I_true;
        artifact.R_true = truth.R_true;
        artifact.tspan = truth.tspan;
        artifact.truth = truth;
        artifact.cfg_snapshot = local_cfg_snapshot(cfg, scenario, model_params, sim_options);
        artifact.beta_curve = truth.beta_curve;
        artifact.model_params = model_params;
        artifact.sim_options = sim_options;

        outPath = fullfile(dataDir, sprintf('partA_01_truth_%s.mat', scenario.id));
        save(outPath, '-struct', 'artifact');
    catch ME
        fprintf('FAILED.\n');
        warning('SIM:Failure', 'Simulation failed for %s: %s', scenario.id, ME.message);
        failed_mask(i) = true;
        continue;
    end

    fprintf('Saved\n');
end

%% 3. Completion Check
if any(failed_mask)
    failed_scenarios = arrayfun(@(s) string(s.id), cfg.scenarios(failed_mask));
    error('SIM:ScenarioFailures', ...
        'Synthetic truth generation failed for scenarios: %s.', ...
        char(strjoin(failed_scenarios, ', ')));
end

fprintf('=== Part A Synthetic Truth Generation Complete ===\n\n');

%% 4. Local Functions
function model_params = local_model_params_for_scenario(cfg, scenario)
%LOCAL_MODEL_PARAMS_FOR_SCENARIO Apply scenario-specific SIRS overrides.
    model_params = cfg.sirs;

    if isfield(scenario.params, 'I0')
        model_params.I0 = scenario.params.I0;
    end

    if isfield(scenario.params, 'R0_init')
        model_params.R0_init = scenario.params.R0_init;
    end
end

function sim_options = local_sim_options_from_cfg(cfg)
%LOCAL_SIM_OPTIONS_FROM_CFG Build ground-truth simulation options.
    sim_options = cfg.truth;
    sim_options.seed = cfg.sim.seed;
end

function cfg_snapshot = local_cfg_snapshot(cfg, scenario, model_params, sim_options)
%LOCAL_CFG_SNAPSHOT Capture the scientific inputs used for one artifact.
    cfg_snapshot = struct();
    cfg_snapshot.time = cfg.time;
    cfg_snapshot.Rt = cfg.Rt;
    cfg_snapshot.scenario = scenario;
    cfg_snapshot.truth = cfg.truth;
    cfg_snapshot.sirs = cfg.sirs;
    cfg_snapshot.model_params = model_params;
    cfg_snapshot.sim_options = sim_options;
    cfg_snapshot.sim = cfg.sim;
end
