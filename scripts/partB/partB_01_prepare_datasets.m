%PARTB_01_PREPARE_DATASETS Generate synthetic truth, observations, and historical estimates.
%
%   Description:
%       Generates one dataset per robustness condition, scenario, and
%       replicate. Truth is simulated with the SIRS or SEIRS URDME stepper
%       (uds or ssa) driven by the analytic Rt scenario. The observation
%       incidence_observed(k+1) is the number of entries into I during
%       [t_k, t_{k+1}]: infections (S to I) under SIRS and infectious onsets
%       (E to I) under SEIRS. Noisy conditions observe an independent
%       Poisson draw around that count. ESTIMATE_SIRS_HISTORY_FROM_INCIDENCE
%       then reconstructs the historical SIRS state and Rt from the
%       observations alone. Under SEIRS truth the SIRS estimator absorbs E
%       into S and its Rt is a latent-period-lagged proxy for the driver.
%
%   Workflow:
%       1. Initialize configuration, output paths, and generation status.
%       2. Simulate truth, observe, estimate, and save each dataset.
%       3. Verify completion and persist the final generation status.
%
%   See also PARTB_CONFIG, PARTB_02_RUN_FORECASTS, GENERATE_RT_SIGNAL,
%            SIRS_INIT, SIRS_STEP, SEIRS_INIT, SEIRS_STEP,
%            ESTIMATE_SIRS_HISTORY_FROM_INCIDENCE.
%
% A. M. Kaahin 2026-06-30
% Modified: 2026-11-26

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Dataset and Estimate Preparation ===\n');

cfg      = partB_config();
pb       = cfg.partB;
tspan    = cfg.time.tspan;
rtBounds = cfg.Rt.bounds;
dataDir  = pb.output.data_dir;
snapshot = pb.snapshot;

if ~exist(dataDir, 'dir')
    mkdir(dataDir);
end

statusPath = fullfile(dataDir, 'partB_01_generation_status.mat');
generation_status = local_initialize_generation_status(cfg);
run_completed = false;
save(statusPath, 'generation_status', 'run_completed', 'snapshot');

estimation_stepper = sirs_init(cfg.sirs, struct('solver', 'uds', 'seed', cfg.run.seed), true);

%% 2. Dataset Generation
fprintf('Saving datasets to: %s\n', dataDir);

artifact_count       = 0;
domain_failure_count = 0;
status_index         = 0;

for ci = 1:numel(pb.robustness_cases)
    case_def = pb.robustness_cases(ci);

    for si = 1:numel(cfg.scenarios)
        scenario = cfg.scenarios(si);

        Rt_true = generate_rt_signal(scenario.signal_type, scenario.params, tspan);

        if any(Rt_true < rtBounds(1) | Rt_true > rtBounds(2), 'all')
            error('PARTB:RtOutOfBounds', 'Generated Rt signal for %s is outside cfg.Rt.bounds.', scenario.id);
        end

        for ri = 1:case_def.num_replicates
            status_index = status_index + 1;
            entry        = generation_status(status_index);
            process_seed = local_process_seed(pb, ci, si, ri);
            noise_seed   = local_noise_seed(pb, ci, si, ri);
            outPath      = fullfile(dataDir, entry.output_filename);

            fprintf('  - %s / %s / %s ... ', case_def.case_id, scenario.id, entry.replicate_id);

            try
                switch case_def.truth_model
                    case {"SIR", "SIRS"}
                        [S_true, I_true, R_removed_true, incidence_true] = local_simulate_sirs_truth(cfg.sirs, Rt_true, case_def.solver, process_seed);
                        E_true = [];
                        local_validate_truth({S_true, I_true, R_removed_true}, incidence_true, cfg.sirs.pop_size);
                    case {"SEIR", "SEIRS"}
                        [S_true, E_true, I_true, R_removed_true, incidence_true] = local_simulate_seir_truth(pb.seir, Rt_true, case_def.solver, process_seed);
                        local_validate_truth({S_true, E_true, I_true, R_removed_true}, incidence_true, pb.seir.pop_size);
                    otherwise
                        error('PARTB:UnsupportedTruthModel', 'Unsupported truth model: %s.', case_def.truth_model);
                end
            catch ME
                if strcmp(ME.identifier, 'EPIDEMIC:SusceptibleBelowThreshold')
                    if exist(outPath, 'file') == 2
                        delete(outPath);
                    end

                    generation_status(status_index).status        = "domain_failure";
                    generation_status(status_index).error_id      = string(ME.identifier);
                    generation_status(status_index).error_message = string(ME.message);
                    domain_failure_count = domain_failure_count + 1;
                    fprintf('Truth domain failure (%s): %s\n', ME.identifier, ME.message);
                    save(statusPath, 'generation_status', 'run_completed', 'snapshot');
                    continue;
                end

                save(statusPath, 'generation_status', 'run_completed', 'snapshot');
                rethrow(ME);
            end

            incidence_observed = local_observe(incidence_true, case_def, noise_seed);
            estimate = estimate_sirs_history_from_incidence(incidence_observed, pb.estimation.initial_state, estimation_stepper, pb.estimation);

            artifact = struct();
            artifact.dataset_id               = entry.dataset_id;
            artifact.case_id                  = case_def.case_id;
            artifact.case_name                = case_def.case_name;
            artifact.scenario_id              = scenario.id;
            artifact.scenario_name            = scenario.name;
            artifact.replicate_id             = entry.replicate_id;
            artifact.replicate_index          = ri;
            artifact.truth_model              = case_def.truth_model;
            artifact.truth_solver             = case_def.solver;
            artifact.observation_noise_enabled = case_def.observation_noise_enabled;
            artifact.tspan                    = tspan(:);
            artifact.Rt_true                  = Rt_true(:);
            artifact.S_true                   = S_true;
            artifact.E_true                   = E_true;
            artifact.I_true                   = I_true;
            artifact.R_removed_true           = R_removed_true;
            artifact.incidence_true           = incidence_true;
            artifact.incidence_observed       = incidence_observed;
            artifact.S_estimated              = estimate.S;
            artifact.I_estimated              = estimate.I;
            artifact.R_removed_estimated      = estimate.R_removed;
            artifact.Rt_estimated             = estimate.Rt;
            artifact.state_valid_mask         = estimate.state_valid_mask;
            artifact.estimation_valid_mask    = estimate.rt_valid_mask;
            artifact.estimation_reason        = estimate.reason;
            artifact.estimation_diagnostics   = struct('method', estimate.inversion_method, 'evaluations', estimate.inversion_evaluations, 'residual', estimate.inversion_residual);
            artifact.estimation_failure_idx   = estimate.failure_idx;
            artifact.estimation_failure_id    = estimate.failure_id;
            artifact.estimation_failure_message = estimate.failure_message;
            artifact.process_seed             = process_seed;
            artifact.noise_seed               = noise_seed;
            artifact.snapshot                 = snapshot;

            save(outPath, '-struct', 'artifact');

            generation_status(status_index).status                 = "saved";
            generation_status(status_index).estimation_failure_idx = estimate.failure_idx;
            generation_status(status_index).zero_incidence_days    = sum(estimate.reason == "unidentifiable_zero_incidence");
            generation_status(status_index).valid_rt_estimates     = sum(estimate.rt_valid_mask);
            artifact_count = artifact_count + 1;

            if isnan(estimate.failure_idx)
                fprintf('Saved (%d valid Rt estimates, %d zero-incidence days)\n', generation_status(status_index).valid_rt_estimates, generation_status(status_index).zero_incidence_days);
            else
                fprintf('Saved with estimation stopped at index %d (%s)\n', estimate.failure_idx, estimate.failure_id);
            end

            save(statusPath, 'generation_status', 'run_completed', 'snapshot');
        end
    end
end

%% 3. Completion Check
run_completed = true;
save(statusPath, 'generation_status', 'run_completed', 'snapshot');

fprintf('Generated %d dataset artifacts.\n', artifact_count);
fprintf('Recorded %d truth domain failures.\n', domain_failure_count);
fprintf('Datasets with a genuine estimation failure: %d.\n', sum(~isnan([generation_status.estimation_failure_idx])));
fprintf('Generation status saved to: %s\n', statusPath);
fprintf('=== Part B Dataset and Estimate Preparation Complete ===\n\n');

%% 4. Local Functions
function generation_status = local_initialize_generation_status(cfg)
%LOCAL_INITIALIZE_GENERATION_STATUS Preallocate one pending entry per expected dataset.
cases = cfg.partB.robustness_cases;
total = sum([cases.num_replicates]) * numel(cfg.scenarios);

entry = struct('case_id', "", 'scenario_id', "", 'replicate_id', "", 'dataset_id', "", 'status', "pending", 'error_id', "", 'error_message', "", 'output_filename', "", 'estimation_failure_idx', NaN, 'zero_incidence_days', NaN, 'valid_rt_estimates', NaN);
generation_status = repmat(entry, total, 1);
index = 0;

for ci = 1:numel(cases)
    for si = 1:numel(cfg.scenarios)
        for ri = 1:cases(ci).num_replicates
            index = index + 1;
            replicate_id = string(sprintf('rep%03d', ri));
            dataset_id   = cases(ci).case_id + "_" + cfg.scenarios(si).id + "_" + replicate_id;

            generation_status(index).case_id         = cases(ci).case_id;
            generation_status(index).scenario_id     = cfg.scenarios(si).id;
            generation_status(index).replicate_id    = replicate_id;
            generation_status(index).dataset_id      = dataset_id;
            generation_status(index).output_filename = "partB_01_dataset_" + dataset_id + ".mat";
        end
    end
end
end

function process_seed = local_process_seed(pb, case_index, scenario_index, replicate_index)
%LOCAL_PROCESS_SEED Deterministic per-replicate process seed.
stride = pb.process_noise.replicate_seed_stride;
process_seed = pb.truth.seed + case_index * 1e7 + scenario_index * 1e5 + (replicate_index - 1) * stride;
end

function noise_seed = local_noise_seed(pb, case_index, scenario_index, replicate_index)
%LOCAL_NOISE_SEED Deterministic per-replicate observation-noise seed disjoint from process seeds.
stride = pb.process_noise.replicate_seed_stride;
noise_seed = pb.truth.seed + 5e8 + case_index * 1e7 + scenario_index * 1e5 + (replicate_index - 1) * stride;
end

function [S, I, R_removed, incidence] = local_simulate_sirs_truth(model_params, Rt_true, solver, seed)
%LOCAL_SIMULATE_SIRS_TRUTH Simulate latent SIR/SIRS truth and daily entries into I.
num_time = numel(Rt_true);

initial_state = [model_params.pop_size - model_params.I0 - model_params.R0_init; model_params.I0; model_params.R0_init];
if any(initial_state < 0)
    error('PARTB:InvalidInitialState', 'SIR/SIRS initial state has a negative compartment.');
end

stepper = sirs_init(model_params, struct('solver', solver, 'seed', seed), true);

U = zeros(3, num_time);
U(:, 1) = initial_state;
incidence = NaN(num_time, 1);

for k = 1:(num_time - 1)
    [U(:, k + 1), stepper, incidence(k + 1)] = sirs_step(stepper, U(:, k), Rt_true(k));
end

S         = U(1, :)';
I         = U(2, :)';
R_removed = U(3, :)';
end

function [S, E, I, R_removed, incidence] = local_simulate_seir_truth(seir, Rt_true, solver, seed)
%LOCAL_SIMULATE_SEIR_TRUTH Simulate latent SEIR/SEIRS truth and daily entries into I (onsets).
num_time = numel(Rt_true);

initial_state = [seir.pop_size - seir.E0 - seir.I0 - seir.R0_init; seir.E0; seir.I0; seir.R0_init];
if any(initial_state < 0)
    error('PARTB:InvalidInitialState', 'SEIR/SEIRS initial state has a negative compartment.');
end

stepper = seirs_init(seir, struct('solver', solver, 'seed', seed), true);

U = zeros(4, num_time);
U(:, 1) = initial_state;
incidence = NaN(num_time, 1);

for k = 1:(num_time - 1)
    [U(:, k + 1), stepper, incidence(k + 1)] = seirs_step(stepper, U(:, k), Rt_true(k));
end

S         = U(1, :)';
E         = U(2, :)';
I         = U(3, :)';
R_removed = U(4, :)';
end

function local_validate_truth(states, incidence, pop_size)
%LOCAL_VALIDATE_TRUTH Check simulated states and entries are finite, nonnegative, and conserved.
total = zeros(size(states{1}));
for k = 1:numel(states)
    state_k = states{k};
    if any(~isfinite(state_k)) || any(state_k < 0)
        error('PARTB:InvalidState', 'Simulated epidemic state is nonfinite or negative.');
    end
    total = total + state_k;
end

if any(abs(total - pop_size) > 1e-6 * pop_size)
    error('PARTB:PopulationNotConserved', 'Simulated population is not conserved.');
end

if any(~isfinite(incidence(2:end))) || any(incidence(2:end) < 0)
    error('PARTB:InvalidTruthIncidence', 'Simulated daily entries into I are nonfinite or negative.');
end
end

function incidence_observed = local_observe(incidence_true, case_def, noise_seed)
%LOCAL_OBSERVE Model-visible daily entries into I, with independent Poisson noise when enabled.
if case_def.observation_noise_enabled
    rng(noise_seed, 'twister');
    incidence_observed = [NaN; poissrnd(incidence_true(2:end))];
else
    incidence_observed = incidence_true;
end
end
