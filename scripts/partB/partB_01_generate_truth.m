%PARTB_01_GENERATE_TRUTH Generate structural-mismatch SEIR truth data.
%
%   Description:
%       Executes the Part B structural-mismatch truth stage. The script uses
%       the same four analytic effective-Rt scenarios as Part A, generates
%       ground-truth trajectories from an SEIR compartment model, and saves
%       one MATLAB artifact per scenario for fixed Part A forecast testing.
%
%   Workflow:
%       1. Load configuration and ensure the structural-mismatch data folder.
%       2. Generate each configured effective-Rt signal.
%       3. Simulate and save one deterministic SEIR truth artifact per scenario.
%
%   See also PARTB_CONFIG, GENERATE_RT_SIGNAL, SIMULATE_GROUND_TRUTH_EPIDEMIC.
%
% A. M. Kaahin 2026-05-18
% Modified: 2026-06-02

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Structural-Mismatch SEIR Truth Generation ===\n');

cfg = partB_config();
tspan = cfg.time.tspan;
data_dir = cfg.output.data_dir;

if ~exist(data_dir, 'dir')
    mkdir(data_dir);
end

scenarios = local_active_scenarios(cfg);

%% 2. Simulation and Persistence Loop
fprintf('Experiment: %s\n', cfg.experiment_id);
fprintf('Saving trajectories to: %s\n', data_dir);
failed_mask = false(numel(scenarios), 1);

for i = 1:numel(scenarios)
    scenario = scenarios(i);
    fprintf('  - Processing %s (%s)... ', scenario.id, scenario.name);

    try
        Rt_true = generate_rt_signal(tspan, scenario);
        model_params = local_model_params_for_scenario(cfg, scenario);
        sim_options = local_sim_options_from_cfg(cfg);
        truth = simulate_ground_truth_epidemic( ...
            cfg.truth_model, tspan, Rt_true, model_params, sim_options);

        local_validate_truth_state(truth, scenario.id);

        artifact = struct();
        artifact.experiment_id = string(cfg.experiment_id);
        artifact.experiment_name = string(cfg.experiment_name);
        artifact.truth_model = string(cfg.truth_model);
        artifact.forecast_assumption = string(cfg.forecast_assumption);
        artifact.scenario_id = string(scenario.id);
        artifact.scenario_name = string(scenario.name);
        artifact.Rt_true = truth.Rt_true;
        artifact.S_true = truth.S_true;
        artifact.E_true = truth.E_true;
        artifact.I_true = truth.I_true;
        artifact.R_true = truth.R_true;
        artifact.tspan = truth.tspan;
        artifact.seir_parameters = model_params;
        artifact.cfg_snapshot = local_cfg_snapshot(cfg, scenario, ...
            model_params, sim_options);
        artifact.truth = truth;
        artifact.beta_curve = truth.beta_curve;
        artifact.sim_options = sim_options;

        out_path = fullfile(data_dir, sprintf('%s_truth_%s.mat', ...
            char(cfg.experiment_id), char(scenario.id)));
        save(out_path, '-struct', 'artifact');
    catch ME
        fprintf('FAILED.\n');
        warning('SIM:Failure', 'SEIR simulation failed for %s: %s', ...
            scenario.id, ME.message);
        failed_mask(i) = true;
        continue;
    end

    fprintf('Saved\n');
end

%% 3. Completion Check
if any(failed_mask)
    failed_scenarios = arrayfun(@(s) string(s.id), scenarios(failed_mask));
    error('SIM:ScenarioFailures', ...
        'Structural-mismatch SEIR truth generation failed for scenarios: %s.', ...
        char(strjoin(failed_scenarios, ', ')));
end

fprintf('=== Part B Structural-Mismatch SEIR Truth Generation Complete ===\n\n');

%% 4. Local Functions
function scenarios = local_active_scenarios(cfg)
%LOCAL_ACTIVE_SCENARIOS Apply optional smoke-test scenario limiting.
    scenarios = cfg.scenarios;
    if cfg.smoke_test.enabled
        n = min(numel(scenarios), cfg.smoke_test.num_scenarios);
        scenarios = scenarios(1:n);
        fprintf('Smoke test enabled: using %d scenario(s).\n', n);
    end
end

function model_params = local_model_params_for_scenario(cfg, scenario)
%LOCAL_MODEL_PARAMS_FOR_SCENARIO Apply scenario-specific SEIR overrides.
    model_params = cfg.seir;

    if isfield(scenario.params, 'I0')
        model_params.I0 = scenario.params.I0;
        model_params.E0 = round((model_params.gamma / model_params.sigma) * ...
            model_params.I0);
    end

    if isfield(scenario.params, 'R0_init')
        model_params.R0_init = scenario.params.R0_init;
    end
end

function sim_options = local_sim_options_from_cfg(cfg)
%LOCAL_SIM_OPTIONS_FROM_CFG Build SEIR truth simulation options.
    sim_options = cfg.truth;
    sim_options.seed = cfg.sim.seed;
end

function local_validate_truth_state(truth, scenario_id)
%LOCAL_VALIDATE_TRUTH_STATE Verify SEIR truth integrity before persistence.
    pop_size = truth.model_params.pop_size;
    population_error = max(abs((truth.S_true + truth.E_true + ...
        truth.I_true + truth.R_true) - pop_size));
    if population_error > max(1e-6 * pop_size, 1e-6)
        error('SIM:PopulationConservation', ...
            'SEIR population conservation failed for %s.', scenario_id);
    end

    values = [truth.S_true(:); truth.E_true(:); truth.I_true(:); ...
        truth.R_true(:); truth.Rt_true(:); truth.beta_curve(:)];
    if any(~isfinite(values)) || any(values < 0)
        error('SIM:InvalidTruthState', ...
            'SEIR truth generation produced invalid values for %s.', scenario_id);
    end
end

function cfg_snapshot = local_cfg_snapshot(cfg, scenario, model_params, sim_options)
%LOCAL_CFG_SNAPSHOT Capture the scientific inputs used for one artifact.
    cfg_snapshot = struct();
    cfg_snapshot.experiment_id = cfg.experiment_id;
    cfg_snapshot.experiment_name = cfg.experiment_name;
    cfg_snapshot.truth_model = cfg.truth_model;
    cfg_snapshot.forecast_assumption = cfg.forecast_assumption;
    cfg_snapshot.time = cfg.time;
    cfg_snapshot.Rt = cfg.Rt;
    cfg_snapshot.scenario = scenario;
    cfg_snapshot.truth = cfg.truth;
    cfg_snapshot.seir = cfg.seir;
    cfg_snapshot.model_params = model_params;
    cfg_snapshot.sim_options = sim_options;
    cfg_snapshot.sim = cfg.sim;
    cfg_snapshot.smoke_test = cfg.smoke_test;
end
