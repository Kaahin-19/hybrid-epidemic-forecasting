%PARTB_01_GENERATE_TRUTH Generate and persist deterministic SEIR truth data.
%
%   Description:
%       Executes deterministic SEIR simulation for all Part A analytic Rt
%       scenarios under the Part B robustness design. The desired effective
%       reproduction-number trajectory is converted to a state-consistent
%       internal transmission curve by genData_SEIR.
%
%   Workflow:
%       1. Initialization
%       2. Simulation and persistence loop
%       3. Completion check
%
%   See also PARTB_CONFIG, GENDATA_SEIR.

% A. M. Kaahin 2026-05-18

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B SEIR Truth Generation ===\n');

cfg = partB_config();
t   = cfg.time.tspan;

if ~exist(cfg.output.data_dir, 'dir')
    mkdir(cfg.output.data_dir);
end

%% 2. Simulation and Persistence Loop
fprintf('Saving trajectories to: %s\n', cfg.output.data_dir);
failed_scenarios = strings(0, 1);

for i = 1:numel(cfg.scenarios)
    slot = cfg.scenarios(i);
    fprintf('  - Processing %s (%s)... ', slot.id, slot.name);

    params      = cfg.seir;
    Rt_true     = slot.generator(t, slot.params);
    params.solver = 'uds';

    if isfield(slot.params, 'I0')
        params.I0 = slot.params.I0;
        params.E0 = round((params.gamma / params.sigma) * params.I0);
    end

    if isfield(slot.params, 'R0_init')
        params.R0_init = slot.params.R0_init;
    end

    sim_params = params;
    sim_params.Rt = Rt_true;

    try
        [umod, beta_curve] = genData_SEIR(t, sim_params, cfg.sim.seed);
    catch ME
        fprintf('FAILED.\n');
        warning('SIM:Failure', 'Simulation failed for %s: %s', slot.id, ME.message);
        failed_scenarios(end + 1, 1) = string(slot.id);
        continue;
    end

    S_true = umod.U(1, :);
    E_true = umod.U(2, :);
    I_true = umod.U(3, :);
    R_true = umod.U(4, :);
    tspan  = t;

    params.beta = beta_curve;
    umod.private.epiid.dynrates = params;

    local_validate_truth_state(S_true, E_true, I_true, R_true, ...
        Rt_true, beta_curve, params.pop_size, slot.id);

    outPath = fullfile(cfg.output.data_dir, ...
        sprintf('partB_01_truth_%s.mat', slot.id));
    save(outPath, 'umod', 'Rt_true', 'S_true', 'E_true', 'I_true', ...
        'R_true', 'tspan', 'params', 'cfg', 'beta_curve');

    fprintf('Saved\n');
end

%% 3. Completion Check
if ~isempty(failed_scenarios)
    error('SIM:ScenarioFailures', ...
        'SEIR truth generation failed for scenarios: %s.', ...
        char(strjoin(failed_scenarios, ', ')));
end

fprintf('=== Part B SEIR Truth Generation Complete ===\n\n');

%% 4. Local Functions
function local_validate_truth_state(S_true, E_true, I_true, R_true, ...
    Rt_true, beta_curve, pop_size, scenario_id)
%LOCAL_VALIDATE_TRUTH_STATE Verify SEIR truth integrity before persistence.
    population_error = max(abs((S_true + E_true + I_true + R_true) - pop_size));
    if population_error > max(1e-6 * pop_size, 1e-6)
        error('SIM:PopulationConservation', ...
            'SEIR population conservation failed for %s.', scenario_id);
    end

    values = [S_true(:); E_true(:); I_true(:); R_true(:); ...
        Rt_true(:); beta_curve(:)];
    if any(~isfinite(values)) || any(values < 0)
        error('SIM:InvalidTruthState', ...
            'SEIR truth generation produced invalid values for %s.', scenario_id);
    end
end
