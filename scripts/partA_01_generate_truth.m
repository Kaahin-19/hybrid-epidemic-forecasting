%PARTA_01_GENERATE_TRUTH Generate and persist stochastic ground truth data.
%
%   Description:
%       Executes the stochastic SIRS simulation for all scenarios defined
%       in the configuration. It dynamically calculates the transmission
%       rate from the synthetic Rt signals and saves the resulting
%       epidemic trajectories to disk.
%
%   Workflow:
%       1. Initialization
%       2. Simulation Loop (Rt generation and stochastic modeling)
%
%   See also PARTA_CONFIG, PARTA_00_MAKE_SCENARIOS.

% A. M. Kaahin 2026-02-18

%% 1. Initialization
clear; close all; clc;

cfg = partA_config();
t   = cfg.time.tspan;

fprintf("=== Generating Synthetic Truth ===\n");

%% 2. Simulation Loop
for i = 1:numel(cfg.scenarios)
    slot = cfg.scenarios(i);
    fprintf("Processing: %s (%s)... ", slot.id, slot.name);

    params = cfg.sirs;

    Rt_true = slot.generator(t, slot.params);

    % Fundamental SIRS relationship: Beta(t) = Rt(t) * Gamma
    params.beta = Rt_true .* params.gamma;

    if isfield(slot.params, "I0")
        params.I0 = slot.params.I0;
    end

    if isfield(slot.params, "R0_init")
        params.R0_init = slot.params.R0_init;
    end

    try
        umod = genData_SIRS(t, params, cfg.sim.seed);
    catch ME
        fprintf("FAILED.\n");
        warning("Simulation failed for %s: %s", slot.id, ME.message);
        continue;
    end

    % 3. Persistence
    S_true = umod.U(1, :);
    I_true = umod.U(2, :);
    tspan  = t;

    outPath = fullfile(cfg.output.data_dir, sprintf("partA_01_truth_%s.mat", slot.id));
    save(outPath, "umod", "Rt_true", "I_true", "S_true", "tspan", "params", "cfg");

    fprintf("Saved to %s\n", outPath);
end

fprintf("=== Generation Complete ===\n");