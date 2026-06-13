%PARTA_01_GENERATE_TRUTH Generate and persist Part A synthetic truth data.
%
%   Description:
%       Executes the Part A SIRS synthetic truth stage. The script loads the
%       configured analytic effective-Rt scenarios, generates each Rt signal,
%       simulates the corresponding SIRS ground truth via sirs_init/sirs_step,
%       and saves one MATLAB artifact per scenario for downstream
%       model-selection and forecasting stages.
%
%   Workflow:
%       1. Load configuration and ensure the Part A data directory exists.
%       2. Generate each configured effective-Rt signal and check bounds.
%       3. Simulate and save one SIRS truth artifact per scenario.
%
%   See also PARTA_CONFIG, GENERATE_RT_SIGNAL, SIRS_INIT, SIRS_STEP.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-13

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Synthetic Truth Generation ===\n');

cfg      = partA_config();
tspan    = cfg.time.tspan;
rtBounds = cfg.Rt.bounds;
dataDir  = cfg.output.data_dir;

if ~exist(dataDir, 'dir')
    mkdir(dataDir);
end

sim_options = struct( ...
    'solver',  cfg.truth.solver, ...
    'compile', cfg.truth.compile, ...
    'seed',    cfg.sim.seed);

%% 2. Simulation and Persistence Loop
fprintf('Saving trajectories to: %s\n', dataDir);

for i = 1:numel(cfg.scenarios)
    scenario = cfg.scenarios(i);
    fprintf('  - Processing %s (%s)... ', scenario.id, scenario.name);

    Rt_true = generate_rt_signal(tspan, scenario);
    if ~all(Rt_true >= rtBounds(1) & Rt_true <= rtBounds(2), 'all')
        error('PARTA:RtOutOfBounds', ...
            'Generated Rt signal for %s is outside cfg.Rt.bounds.', scenario.id);
    end

    params               = scenario.model_params;
    step_options         = sim_options;
    step_options.compile = sim_options.compile && (i == 1);
    stepper              = sirs_init(params, step_options);

    U = zeros(3, numel(tspan));
    U(:, 1) = [params.pop_size - params.I0 - params.R0_init; params.I0; params.R0_init];

    beta_curve = nan(1, numel(tspan));

    for k = 1:(numel(tspan) - 1)
        [next_state, stepper] = sirs_step(stepper, U(:, k), Rt_true(k));
        U(:, k + 1)   = reshape(next_state, 3, 1);
        beta_curve(k) = stepper.last_beta;
    end

    beta_curve(end) = Rt_true(end) * params.gamma * params.pop_size / ...
        max(U(1, end), 1);

    artifact = struct( ...
        'scenario_id',   scenario.id, ...
        'scenario_name', scenario.name, ...
        'Rt_true',       Rt_true, ...
        'S_true',        U(1, :), ...
        'I_true',        U(2, :), ...
        'R_true',        U(3, :), ...
        'beta_curve',    beta_curve, ...
        'tspan',         tspan ...
        );

    artifact.cfg_snapshot = struct( ...
        'time',        cfg.time, ...
        'Rt',          cfg.Rt, ...
        'scenario',    scenario, ...
        'sirs',        cfg.sirs, ...
        'sim_options', step_options);

    outPath = fullfile(dataDir, sprintf('partA_01_truth_%s.mat', scenario.id));
    save(outPath, '-struct', 'artifact');

    fprintf('Saved\n');
end

%% 3. Completion
fprintf('=== Part A Synthetic Truth Generation Complete ===\n\n');
