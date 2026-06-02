%PARTB_01_GENERATE_TRUTH Generate Part B robustness-ladder truth data.
%
%   Description:
%       Executes the Part B truth stage for all active robustness cases. Each
%       case uses the configured compartment model and solver, then applies
%       observation noise only when requested. The saved artifacts separate
%       latent truth, observed/model-input signals, and evaluation targets.
%
%   Workflow:
%       1. Load configuration and resolve active cases, scenarios, replicates.
%       2. Generate analytic Rt, simulate latent epidemic truth, and apply
%          observation noise when enabled.
%       3. Save one MATLAB truth artifact per case/scenario/replicate.
%
%   See also PARTB_CONFIG, GENERATE_RT_SIGNAL, SIMULATE_GROUND_TRUTH_EPIDEMIC,
%            APPLY_OBSERVATION_NOISE.
%
% A. M. Kaahin 2026-05-18
% Modified: 2026-06-03

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Robustness-Ladder Truth Generation ===\n');

cfg = partB_config();
tspan = cfg.time.tspan;
cases = local_active_cases(cfg);
scenarios = local_active_scenarios(cfg);

fprintf('Experiment: %s\n', cfg.experiment_id);
fprintf('Active cases: %d | scenarios: %d\n', numel(cases), numel(scenarios));

failed_runs = strings(0, 1);
generated_artifacts = strings(0, 1);

%% 2. Simulation and Persistence Loop
for c = 1:numel(cases)
    case_cfg = cases(c);
    case_dir = local_case_data_dir(cfg, case_cfg.case_id);
    if ~exist(case_dir, 'dir'), mkdir(case_dir); end

    num_replicates = local_active_replicates(cfg, case_cfg);
    fprintf('Case %s: %s (%d replicate(s))\n', ...
        case_cfg.case_id, case_cfg.case_name, num_replicates);

    for i = 1:numel(scenarios)
        scenario = scenarios(i);
        Rt_signal = generate_rt_signal(tspan, scenario);

        for r = 1:num_replicates
            replicate_id = r;
            run_label = sprintf('%s/%s/rep%03d', char(case_cfg.case_id), ...
                char(scenario.id), replicate_id);
            fprintf('  - Processing %s... ', run_label);

            try
                model_params = local_model_params_for_case(cfg, case_cfg, scenario);
                sim_options = local_sim_options_for_case(cfg, case_cfg, ...
                    i, replicate_id);
                latent_truth = simulate_ground_truth_epidemic( ...
                    case_cfg.truth_model, tspan, Rt_signal, ...
                    model_params, sim_options);
                local_validate_truth_state(latent_truth, case_cfg, scenario.id);

                noise_seed = local_noise_seed(cfg, c, i, replicate_id);
                observed = apply_observation_noise(latent_truth, ...
                    case_cfg.observation_noise, noise_seed, cfg.Rt.bounds);

                artifact = local_truth_artifact(cfg, case_cfg, scenario, ...
                    replicate_id, latent_truth, observed, model_params, ...
                    sim_options);

                out_path = fullfile(case_dir, sprintf('partB_%s_truth_%s_rep%03d.mat', ...
                    char(case_cfg.case_id), char(scenario.id), replicate_id));
                save(out_path, '-struct', 'artifact');
                generated_artifacts(end + 1, 1) = string(out_path); %#ok<SAGROW>
            catch ME
                fprintf('FAILED.\n');
                warning('SIM:Failure', 'Part B truth generation failed for %s: %s', ...
                    run_label, ME.message);
                failed_runs(end + 1, 1) = string(run_label); %#ok<SAGROW>
                continue;
            end

            fprintf('Saved\n');
        end
    end
end

%% 3. Completion Check
if ~isempty(failed_runs)
    error('SIM:ScenarioFailures', ...
        'Part B truth generation failed for: %s.', ...
        char(strjoin(failed_runs, ', ')));
end

fprintf('Generated %d truth artifacts.\n', numel(generated_artifacts));
fprintf('=== Part B Robustness-Ladder Truth Generation Complete ===\n\n');

%% 4. Local Functions
function cases = local_active_cases(cfg)
%LOCAL_ACTIVE_CASES Apply optional smoke-test case limiting.
    cases = cfg.robustness_cases;
    if cfg.smoke_test.enabled
        n = min(numel(cases), cfg.smoke_test.num_cases);
        cases = cases(1:n);
        fprintf('Smoke test enabled: using %d robustness case(s).\n', n);
    end
end

function scenarios = local_active_scenarios(cfg)
%LOCAL_ACTIVE_SCENARIOS Apply optional smoke-test scenario limiting.
    scenarios = cfg.scenarios;
    if cfg.smoke_test.enabled
        n = min(numel(scenarios), cfg.smoke_test.num_scenarios);
        scenarios = scenarios(1:n);
        fprintf('Smoke test enabled: using %d scenario(s).\n', n);
    end
end

function n = local_active_replicates(cfg, case_cfg)
%LOCAL_ACTIVE_REPLICATES Apply optional smoke-test replicate limiting.
    n = double(case_cfg.num_replicates);
    if cfg.smoke_test.enabled
        n = min(n, cfg.smoke_test.num_replicates);
    end
    n = max(1, floor(n));
end

function data_dir = local_case_data_dir(cfg, case_id)
%LOCAL_CASE_DATA_DIR Return one case-specific data directory.
    data_dir = fullfile(cfg.output.data_root_dir, char(case_id));
end

function model_params = local_model_params_for_case(cfg, case_cfg, scenario)
%LOCAL_MODEL_PARAMS_FOR_CASE Apply scenario overrides to truth parameters.
    switch char(case_cfg.truth_model)
        case 'SIRS'
            model_params = cfg.sirs;
        case 'SEIR'
            model_params = cfg.seir;
        otherwise
            error('SIM:UnsupportedTruthModel', ...
                'Unsupported Part B truth model: %s.', case_cfg.truth_model);
    end

    if isfield(scenario.params, 'I0')
        model_params.I0 = scenario.params.I0;
        if strcmp(char(case_cfg.truth_model), 'SEIR')
            model_params.E0 = round((model_params.gamma / model_params.sigma) * ...
                model_params.I0);
        end
    end

    if isfield(scenario.params, 'R0_init')
        model_params.R0_init = scenario.params.R0_init;
    end
end

function sim_options = local_sim_options_for_case(cfg, case_cfg, scenario_idx, replicate_id)
%LOCAL_SIM_OPTIONS_FOR_CASE Build deterministic or stochastic simulation options.
    sim_options = struct();
    sim_options.model_type = case_cfg.truth_model;
    sim_options.solver = case_cfg.solver;
    sim_options.compile = cfg.truth.compile;
    if logical(case_cfg.process_noise.enabled)
        sim_options.seed = local_process_seed(cfg, case_cfg, scenario_idx, replicate_id);
    else
        sim_options.seed = cfg.sim.seed;
    end
end

function seed = local_process_seed(cfg, case_cfg, scenario_idx, replicate_id)
%LOCAL_PROCESS_SEED Generate reproducible process-noise seeds.
    case_offset = local_case_seed_offset(case_cfg.case_id);
    seed = cfg.sim.seed + case_offset + 1000 * scenario_idx + 37 * replicate_id;
end

function seed = local_noise_seed(cfg, case_idx, scenario_idx, replicate_id)
%LOCAL_NOISE_SEED Generate reproducible observation-noise seeds.
    seed = cfg.sim.seed + 500000 + 10000 * case_idx + 1000 * scenario_idx + ...
        53 * replicate_id;
end

function offset = local_case_seed_offset(case_id)
%LOCAL_CASE_SEED_OFFSET Stable case-specific seed offset.
    ids = ["observation_noise", "process_noise", "structural_mismatch", ...
        "combined_stress"];
    idx = find(ids == string(case_id), 1);
    if isempty(idx)
        idx = 0;
    end
    offset = 100000 * idx;
end

function local_validate_truth_state(truth, case_cfg, scenario_id)
%LOCAL_VALIDATE_TRUTH_STATE Verify epidemic truth integrity before persistence.
    pop_size = truth.model_params.pop_size;
    if isfield(truth, 'E_true') && ~isempty(truth.E_true)
        population = truth.S_true + truth.E_true + truth.I_true + truth.R_true;
        values = [truth.S_true(:); truth.E_true(:); truth.I_true(:); ...
            truth.R_true(:); truth.Rt_true(:); truth.beta_curve(:)];
    else
        population = truth.S_true + truth.I_true + truth.R_true;
        values = [truth.S_true(:); truth.I_true(:); truth.R_true(:); ...
            truth.Rt_true(:); truth.beta_curve(:)];
    end

    population_error = max(abs(population - pop_size));
    if population_error > max(1e-6 * pop_size, 1e-6)
        error('SIM:PopulationConservation', ...
            'Population conservation failed for %s/%s.', ...
            case_cfg.case_id, scenario_id);
    end

    if any(~isfinite(values)) || any(values < 0)
        error('SIM:InvalidTruthState', ...
            'Truth generation produced invalid values for %s/%s.', ...
            case_cfg.case_id, scenario_id);
    end
end

function artifact = local_truth_artifact(cfg, case_cfg, scenario, replicate_id, ...
    latent_truth, observed, model_params, sim_options)
%LOCAL_TRUTH_ARTIFACT Assemble one case/scenario/replicate artifact.
    artifact = struct();
    artifact.experiment_id = string(cfg.experiment_id);
    artifact.experiment_name = string(cfg.experiment_name);
    artifact.case_id = string(case_cfg.case_id);
    artifact.case_name = string(case_cfg.case_name);
    artifact.truth_model = string(case_cfg.truth_model);
    artifact.solver = string(case_cfg.solver);
    artifact.forecast_assumption = string(case_cfg.forecast_assumption);
    artifact.structural_mismatch_enabled = logical(case_cfg.structural_mismatch_enabled);
    artifact.observation_noise_enabled = logical(case_cfg.observation_noise.enabled);
    artifact.process_noise_enabled = logical(case_cfg.process_noise.enabled);
    artifact.replicate_id = double(replicate_id);
    artifact.scenario_id = string(scenario.id);
    artifact.scenario_name = string(scenario.name);

    artifact.Rt_true = observed.Rt_true;
    artifact.Rt_observed = observed.Rt_observed;
    artifact.Rt_model_input = observed.Rt_model_input;
    artifact.Rt_evaluation_target = observed.Rt_evaluation_target;

    artifact.S_true = observed.S_true;
    artifact.I_true = observed.I_true;
    artifact.R_true = observed.R_true;
    artifact.S_observed = observed.S_observed;
    artifact.I_observed = observed.I_observed;
    artifact.R_observed = observed.R_observed;
    artifact.S_model_input = observed.S_model_input;
    artifact.I_model_input = observed.I_model_input;

    artifact.E_true = observed.E_true;
    artifact.E_observed = observed.E_observed;

    artifact.tspan = latent_truth.tspan;
    artifact.beta_curve = latent_truth.beta_curve;
    artifact.model_params = model_params;
    artifact.noise_parameters = observed.noise_parameters;
    artifact.noise_seed = observed.noise_seed;
    artifact.sim_options = sim_options;
    artifact.source_case_config = case_cfg;
    artifact.cfg_snapshot = local_cfg_snapshot(cfg, case_cfg, scenario, ...
        model_params, sim_options);
    artifact.truth = latent_truth;
end

function cfg_snapshot = local_cfg_snapshot(cfg, case_cfg, scenario, ...
    model_params, sim_options)
%LOCAL_CFG_SNAPSHOT Capture scientific inputs used for one artifact.
    cfg_snapshot = struct();
    cfg_snapshot.experiment_id = cfg.experiment_id;
    cfg_snapshot.experiment_name = cfg.experiment_name;
    cfg_snapshot.case_config = case_cfg;
    cfg_snapshot.time = cfg.time;
    cfg_snapshot.Rt = cfg.Rt;
    cfg_snapshot.scenario = scenario;
    cfg_snapshot.truth = cfg.truth;
    cfg_snapshot.sirs = cfg.sirs;
    cfg_snapshot.seir = cfg.seir;
    cfg_snapshot.model_params = model_params;
    cfg_snapshot.sim_options = sim_options;
    cfg_snapshot.sim = cfg.sim;
    cfg_snapshot.smoke_test = cfg.smoke_test;
end
