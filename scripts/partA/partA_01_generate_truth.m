%PARTA_01_GENERATE_TRUTH Generate and persist deterministic ground truth data.
%
%   Description:
%       Executes the deterministic SIRS simulation for all scenarios defined
%       in the configuration. The scenario generators prescribe desired
%       effective reproduction-number trajectories; genData_SIRS converts them
%       to state-consistent internal transmission rates and returns the implied
%       beta curve for metadata persistence.
%
%   Workflow:
%       1. Initialization
%       2. Simulation and persistence loop
%       3. Completion check
%
%   See also PARTA_CONFIG, GENDATA_SIRS.
%
% A. M. Kaahin 2026-02-18
% Modified: 2026-05-04

%% 1. Initialization
clear; close all; clc;

fprintf('=== Synthetic Truth Generation ===\n');

cfg = partA_config();
t   = cfg.time.tspan;

%% 2. Simulation and Persistence Loop
fprintf('Saving trajectories to: %s\n', cfg.output.data_dir);
failed_scenarios = strings(0, 1);

for i = 1:numel(cfg.scenarios)
    slot = cfg.scenarios(i);
    fprintf('  - Processing %s (%s)... ', slot.id, slot.name);

    params      = cfg.sirs;
    Rt_true     = slot.generator(t, slot.params);
    params.solver  = 'uds';

    if isfield(slot.params, 'I0')
        params.I0 = slot.params.I0;
    end

    if isfield(slot.params, 'R0_init')
        params.R0_init = slot.params.R0_init;
    end

    sim_params = params;
    sim_params.Rt = Rt_true;

    try
        [umod, beta_curve] = genData_SIRS(t, sim_params, cfg.sim.seed);
    catch ME
        fprintf('FAILED.\n');
        warning('SIM:Failure', 'Simulation failed for %s: %s', slot.id, ME.message);
        failed_scenarios(end + 1, 1) = string(slot.id);
        continue;
    end

    S_true = umod.U(1, :);
    I_true = umod.U(2, :);
    tspan  = t;

    params.beta = beta_curve;
    umod.private.epiid.dynrates = params;

    outPath = fullfile(cfg.output.data_dir, sprintf('partA_01_truth_%s.mat', slot.id));
    save(outPath, 'umod', 'Rt_true', 'I_true', 'S_true', 'tspan', 'params', 'cfg');

    fprintf('Saved\n');
end

%% 3. Completion Check
if ~isempty(failed_scenarios)
    error('SIM:ScenarioFailures', ...
        'Synthetic truth generation failed for scenarios: %s.', ...
        char(strjoin(failed_scenarios, ', ')));
end

fprintf('=== Truth Generation Complete ===\n\n');
