%PARTA_01_GENERATE_TRUTH Generate and persist Part A synthetic truth data.
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
% Modified: 2026-06-04

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Synthetic Truth Generation ===\n');

cfg     = partA_config();
tspan   = cfg.time.tspan;
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
        Rt_true      = generate_rt_signal(tspan, scenario);
        model_params = scenario.model_params;

        sim_options      = cfg.truth;
        sim_options.seed = cfg.sim.seed;

        truth = simulate_ground_truth_epidemic( ...
            cfg.truth.model_type, tspan, Rt_true, model_params, sim_options);

        artifact = struct( ...
            'scenario_id',  scenario.id, ...
            'scenario_name', scenario.name, ...
            'Rt_true',       truth.Rt_true, ...
            'S_true',        truth.S_true, ...
            'I_true',        truth.I_true, ...
            'R_true',        truth.R_true, ...
            'beta_curve',    truth.beta_curve, ...
            'tspan',         truth.tspan ...
            );
        artifact.cfg_snapshot = struct( ...
            'time',         cfg.time, ...
            'Rt',           cfg.Rt, ...
            'scenario',     scenario, ...
            'truth',        cfg.truth, ...
            'sirs',         cfg.sirs, ...
            'model_params', model_params, ...
            'sim_options',  sim_options, ...
            'sim',          cfg.sim);

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
