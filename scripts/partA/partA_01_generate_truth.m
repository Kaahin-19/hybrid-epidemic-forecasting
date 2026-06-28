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
%   See also PARTA_CONFIG, SIRS_INIT, SIRS_STEP.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-28

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Synthetic Truth Generation ===\n');

cfg      = partA_config();
tspan    = cfg.time.tspan;
numTime  = numel(tspan);
rtBounds = cfg.Rt.bounds;
dataDir  = cfg.output.data_dir;

if ~exist(dataDir, 'dir')
    mkdir(dataDir);
end

%% 2. Simulation and Persistence Loop
fprintf('Saving trajectories to: %s\n', dataDir);

for i = 1:numel(cfg.scenarios)
    scenario = cfg.scenarios(i);
    params   = cfg.sirs;

    fprintf('  - Processing %s (%s)... ', scenario.id, scenario.name);

    sp = scenario.params;
    switch scenario.signal_type
        case "seasonal"
            Rt_true = sp.center + sp.amp * sin((2 * pi / sp.period) * tspan);
        case "sigmoid"
            Rt_true = sp.high + (sp.low - sp.high) ./ (1 + exp(-sp.k * (tspan - sp.t0)));
        case "multi_wave"
            Rt_true = sp.baseline + sp.A1*exp(-((tspan-sp.mu1).^2)/sp.denom) + sp.A2*exp(-((tspan-sp.mu2).^2)/sp.denom) + sp.A3*exp(-((tspan-sp.mu3).^2)/sp.denom) + sp.A4*exp(-((tspan-sp.mu4).^2)/sp.denom);
        otherwise
            error('PARTA:UnsupportedSignal', 'Unsupported Rt signal type: %s.', scenario.signal_type);
    end

    if any(Rt_true < rtBounds(1) | Rt_true > rtBounds(2), 'all')
        error('PARTA:RtOutOfBounds', 'Generated Rt signal for %s is outside cfg.Rt.bounds.', scenario.id);
    end

    step_options         = struct('solver', 'uds', 'seed', 1234);
    stepper              = sirs_init(params, step_options);

    U = zeros(3, numTime);
    U(:, 1) = [params.pop_size - params.I0 - params.R0_init; params.I0; params.R0_init];

    for k = 1:(numTime - 1)
        [next_state, stepper] = sirs_step(stepper, U(:, k), Rt_true(k));
        U(:, k + 1) = next_state;
    end

    snapshot = cfg.snapshot.truth;
    snapshot.scenario = scenario;

    artifact = struct('scenario_id', scenario.id, 'scenario_name', scenario.name, 'Rt_true', Rt_true(:), 'S_true', U(1, :)', 'I_true', U(2, :)', 'tspan', tspan(:), 'model_params', params, 'snapshot', snapshot);

    outPath = fullfile(dataDir, sprintf('partA_01_truth_%s.mat', scenario.id));
    save(outPath, '-struct', 'artifact');

    fprintf('Saved\n');
end
fprintf('=== Part A Synthetic Truth Generation Complete ===\n\n');