%PARTB_01_GENERATE_TRUTH Generate Part B robustness-ladder truth data.
%
%   Description:
%       Executes the Part B truth stage for all active robustness cases. Each
%       case uses the configured compartment model and solver. Process-noise
%       cases are replicated over multiple independent SSA realizations per
%       scenario so robustness conclusions do not depend on a single random
%       path; deterministic cases use one replicate. Latent Rt_true is
%       preserved as each replicate's evaluation target. Under observation noise
%       the model-visible Rt is not perturbed from Rt_true directly: latent
%       incidence is observed under a count model, smoothed, and re-estimated
%       with the shared renewal estimator. The saved artifacts separate latent
%       truth, observed incidence, model-input signals, and evaluation targets,
%       and carry replicate identity and seeds.
%
%   Workflow:
%       1. Load configuration and resolve active cases and scenarios.
%       2. For each case/scenario/replicate, generate analytic Rt and simulate
%          latent epidemic truth with a unique reproducible process seed.
%       3. Derive latent incidence, observed incidence, smoothed model-input
%          incidence, and the renewal-estimated Rt_model_input when observation
%          noise is enabled; validate the observation design.
%       4. Save one MATLAB truth artifact per case/scenario/replicate.
%
%   See also PARTB_CONFIG, GENERATE_RT_SIGNAL, SIMULATE_GROUND_TRUTH_EPIDEMIC,
%            APPLY_OBSERVATION_NOISE, ESTIMATE_RT_RENEWAL.
%
% A. M. Kaahin 2026-05-18
% Modified: 2026-06-11

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

    num_reps = local_num_replicates(cfg, case_cfg);
    local_validate_replicate_plan(cfg, case_cfg, num_reps);
    fprintf('Case %s: %s (%d replicate(s))\n', case_cfg.case_id, ...
        case_cfg.case_name, num_reps);

    for i = 1:numel(scenarios)
        scenario = scenarios(i);
        Rt_signal = generate_rt_signal(tspan, scenario);
        scenario_process_seeds = nan(num_reps, 1);

        for r = 1:num_reps
            replicate_id = sprintf('rep%03d', r);
            run_label = sprintf('%s/%s/%s', char(case_cfg.case_id), ...
                char(scenario.id), replicate_id);
            fprintf('  - Processing %s... ', run_label);

            try
                model_params = local_model_params_for_case(cfg, case_cfg, scenario);
                sim_options = local_sim_options_for_case(cfg, case_cfg, i, r);
                process_seed = sim_options.seed;
                scenario_process_seeds(r) = process_seed;
                latent_truth = simulate_ground_truth_epidemic( ...
                    case_cfg.truth_model, tspan, Rt_signal, ...
                    model_params, sim_options);
                local_validate_truth_state(latent_truth, case_cfg, scenario.id);

                noise_seed = local_noise_seed(cfg, case_cfg, i, r);
                observed = apply_observation_noise(latent_truth, ...
                    case_cfg.observation_noise, noise_seed, cfg.Rt.bounds);

                artifact = local_truth_artifact(cfg, case_cfg, scenario, ...
                    latent_truth, observed, model_params, sim_options, ...
                    replicate_id, r, num_reps, process_seed);
                local_validate_observation_model(artifact, case_cfg, scenario.id);

                out_path = fullfile(case_dir, sprintf('partB_%s_truth_%s_%s.mat', ...
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

        local_validate_unique_process_seeds(scenario_process_seeds, ...
            case_cfg, scenario.id, num_reps);
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

function data_dir = local_case_data_dir(cfg, ~)
%LOCAL_CASE_DATA_DIR Return the shared Part B data directory.
    data_dir = cfg.output.data_root_dir;
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

function num_reps = local_num_replicates(cfg, case_cfg)
%LOCAL_NUM_REPLICATES Resolve replicate count for a case (smoke-aware).
    if logical(case_cfg.process_noise.enabled)
        num_reps = cfg.process_noise.num_replicates;
        if cfg.smoke_test.enabled
            num_reps = min(num_reps, cfg.smoke_test.num_process_replicates);
        end
    else
        num_reps = 1;
    end
    num_reps = max(1, round(double(num_reps)));
end

function local_validate_replicate_plan(cfg, case_cfg, num_reps)
%LOCAL_VALIDATE_REPLICATE_PLAN Require >1 replicate for process noise (full run).
    if logical(case_cfg.process_noise.enabled) && ~cfg.smoke_test.enabled && ...
            num_reps < 2
        error('SIM:InsufficientReplicates', ...
            ['Process-noise case %s must use at least 2 independent SSA ' ...
            'replicates in a full run.'], case_cfg.case_id);
    end
end

function local_validate_unique_process_seeds(seeds, case_cfg, scenario_id, num_reps)
%LOCAL_VALIDATE_UNIQUE_PROCESS_SEEDS Ensure replicate process seeds are unique.
    seeds = seeds(isfinite(seeds));
    if numel(unique(seeds)) ~= num_reps
        error('SIM:DuplicateProcessSeed', ...
            'Process seeds for %s/%s are not unique across %d replicate(s).', ...
            case_cfg.case_id, scenario_id, num_reps);
    end
end

function sim_options = local_sim_options_for_case(cfg, case_cfg, scenario_idx, replicate_idx)
%LOCAL_SIM_OPTIONS_FOR_CASE Build deterministic or stochastic simulation options.
    sim_options = struct();
    sim_options.model_type = case_cfg.truth_model;
    sim_options.solver = case_cfg.solver;
    sim_options.compile = cfg.truth.compile;
    if logical(case_cfg.process_noise.enabled)
        sim_options.seed = local_process_seed(cfg, case_cfg, scenario_idx, replicate_idx);
    else
        sim_options.seed = cfg.truth.seed;
    end
end

function seed = local_process_seed(cfg, case_cfg, scenario_idx, replicate_idx)
%LOCAL_PROCESS_SEED Reproducible, order-independent process-noise seed.
%   seed = base + case_block*case_index + scenario_block*(scenario-1)
%               + replicate_stride*(replicate-1).
%   Block sizes are nested so distinct case/scenario/replicate seeds never
%   collide and are separated by more than the number of latent time steps,
%   keeping each replicate's per-interval SSA seed stream disjoint.
    case_block = 100000000;
    scenario_block = 1000000;
    replicate_stride = cfg.process_noise.replicate_seed_stride;
    seed = cfg.truth.seed + case_block * local_case_seed_index(case_cfg.case_id) + ...
        scenario_block * (scenario_idx - 1) + replicate_stride * (replicate_idx - 1);
end

function seed = local_noise_seed(cfg, case_cfg, scenario_idx, replicate_idx)
%LOCAL_NOISE_SEED Reproducible, replicate-varying observation-noise seed.
    noise_space = 500000000;
    case_block = 100000000;
    scenario_block = 1000000;
    replicate_stride = cfg.process_noise.replicate_seed_stride;
    seed = cfg.truth.seed + noise_space + ...
        case_block * local_case_seed_index(case_cfg.case_id) + ...
        scenario_block * (scenario_idx - 1) + replicate_stride * (replicate_idx - 1);
end

function idx = local_case_seed_index(case_id)
%LOCAL_CASE_SEED_INDEX Stable case-specific seed index, independent of order.
    ids = ["observation_noise", "process_noise", "structural_mismatch", ...
        "combined_stress"];
    idx = find(ids == string(case_id), 1);
    if isempty(idx)
        idx = 0;
    end
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

function local_validate_observation_model(artifact, case_cfg, scenario_id)
%LOCAL_VALIDATE_OBSERVATION_MODEL Verify the incidence-based observation design.
    incidence_fields = {'incidence_true', 'incidence_observed', ...
        'incidence_model_input', 'renewal_lambda_model_input', ...
        'serial_interval_weights'};
    if ~all(isfield(artifact, incidence_fields))
        error('SIM:MissingIncidenceFields', ...
            'Truth artifact for %s/%s is missing incidence observation fields.', ...
            case_cfg.case_id, scenario_id);
    end

    if ~isfield(artifact, 'observation_metadata') || ...
            ~isfield(artifact.observation_metadata, 'direct_Rt_noise_used') || ...
            logical(artifact.observation_metadata.direct_Rt_noise_used)
        error('SIM:DirectRtNoise', ...
            'direct_Rt_noise_used must be false for %s/%s.', ...
            case_cfg.case_id, scenario_id);
    end

    if any(~isfinite(artifact.Rt_evaluation_target(:))) || ...
            ~isequal(artifact.Rt_evaluation_target(:), artifact.Rt_true(:))
        error('SIM:EvaluationTargetDrift', ...
            'Rt_evaluation_target must equal latent Rt_true for %s/%s.', ...
            case_cfg.case_id, scenario_id);
    end

    incidence_true = artifact.incidence_true(:);
    if any(~isfinite(incidence_true)) || any(incidence_true < 0)
        error('SIM:InvalidIncidence', ...
            'incidence_true must be finite and nonnegative for %s/%s.', ...
            case_cfg.case_id, scenario_id);
    end

    if logical(case_cfg.observation_noise.enabled)
        Rt_model_input = artifact.Rt_model_input(:);
        if any(~isfinite(Rt_model_input)) || any(Rt_model_input <= 0)
            error('SIM:InvalidRtModelInput', ...
                'Rt_model_input must be finite and strictly positive for %s/%s.', ...
                case_cfg.case_id, scenario_id);
        end
        if isequal(Rt_model_input, artifact.Rt_true(:))
            error('SIM:RtModelInputNotEstimated', ...
                ['Rt_model_input equals latent Rt_true for observation-noise ' ...
                'case %s/%s; it must be estimated from observed incidence.'], ...
                case_cfg.case_id, scenario_id);
        end
    end
end

function artifact = local_truth_artifact(cfg, case_cfg, scenario, ...
    latent_truth, observed, model_params, sim_options, ...
    replicate_id, replicate_index, num_replicates_for_case, process_seed)
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
    artifact.scenario_id = string(scenario.id);
    artifact.scenario_name = string(scenario.name);

    artifact.replicate_id = string(replicate_id);
    artifact.replicate_index = double(replicate_index);
    artifact.num_replicates_for_case = double(num_replicates_for_case);
    artifact.process_seed = double(process_seed);

    artifact.Rt_true = observed.Rt_true;
    artifact.Rt_observed = observed.Rt_observed;
    artifact.Rt_model_input = observed.Rt_model_input;
    artifact.Rt_evaluation_target = observed.Rt_evaluation_target;

    artifact.incidence_true = observed.incidence_true;
    artifact.incidence_observed = observed.incidence_observed;
    artifact.incidence_model_input = observed.incidence_model_input;
    artifact.renewal_lambda_model_input = observed.renewal_lambda_model_input;
    artifact.serial_interval_weights = observed.serial_interval_weights;

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
    artifact.observation_metadata = observed.observation_metadata;
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
