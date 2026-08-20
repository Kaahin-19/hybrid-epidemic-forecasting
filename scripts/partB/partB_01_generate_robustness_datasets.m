%PARTB_01_GENERATE_ROBUSTNESS_DATASETS Generate Part B robustness datasets.
%
%   Description:
%       Generates synthetic robustness dataset artifacts by combining the
%       existing Part A analytic Rt scenarios with controlled measurement error
%       in the model-visible Rt input, stochastic process noise, structural
%       mismatch, and combined stress cases. Baseline truth follows the Part A
%       SIR/SIRS immunity-waning configuration, while structural-mismatch truth
%       adds an exposed compartment and therefore follows SEIR when xi = 0 or
%       SEIRS when xi > 0.
%
%   Workflow:
%       1. Load Part B configuration and resolve cases/scenarios.
%       2. Generate analytic Rt signals inline for each scenario.
%       3. Simulate latent SIR/SIRS or SEIR/SEIRS epidemic truth.
%       4. Build model-visible inputs.
%       5. Save successful dataset artifacts and record generation status.
%
%   See also PARTB_CONFIG, SIRS_INIT, SIRS_STEP, SEIRS_INIT, SEIRS_STEP.
%
% A. M. Kaahin 2026-06-30
% Modified: 2026-08-20

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Robustness Dataset Generation ===\n');

cfg      = partB_config();
tspan    = cfg.time.tspan;
rtBounds = cfg.Rt.bounds;
dataDir  = cfg.partB.output.data_dir;

if ~exist(dataDir, 'dir')
    mkdir(dataDir);
end

statusPath = fullfile(dataDir, 'partB_01_generation_status.mat');
known_domain_errors = "EPIDEMIC:SusceptibleBelowThreshold";
generation_status = local_initialize_generation_status(cfg);
run_completed = false;
save(statusPath, 'generation_status', 'run_completed');

%% 2. Dataset Generation
fprintf('Saving datasets to: %s\n', dataDir);

artifact_count       = 0;
domain_failure_count = 0;
status_index         = 0;

for ci = 1:numel(cfg.partB.robustness_cases)
    case_def = cfg.partB.robustness_cases(ci);

    for si = 1:numel(cfg.scenarios)
        scenario = cfg.scenarios(si);
        num_reps = local_num_replicates(case_def, cfg);

        sp = scenario.params;
        switch scenario.signal_type
            case "seasonal"
                Rt_true = sp.center + sp.amp * sin((2 * pi / sp.period) * tspan);
            case "sigmoid"
                Rt_true = sp.high + (sp.low - sp.high) ./ (1 + exp(-sp.k * (tspan - sp.t0)));
            case "multi_wave"
                peak1 = sp.A1 * exp(-((tspan - sp.mu1).^2) / sp.denom);
                peak2 = sp.A2 * exp(-((tspan - sp.mu2).^2) / sp.denom);
                peak3 = sp.A3 * exp(-((tspan - sp.mu3).^2) / sp.denom);
                peak4 = sp.A4 * exp(-((tspan - sp.mu4).^2) / sp.denom);

                Rt_true = sp.baseline + peak1 + peak2 + peak3 + peak4;
            otherwise
                error('PARTB:UnsupportedSignal', 'Unsupported Rt signal type: %s.', scenario.signal_type);
        end

        if any(Rt_true < rtBounds(1) | Rt_true > rtBounds(2), 'all')
            error('PARTB:RtOutOfBounds', 'Generated Rt signal for %s is outside cfg.Rt.bounds.', scenario.id);
        end

        Rt_true_col  = Rt_true(:);
        truth_solver = case_def.solver;

        for ri = 1:num_reps
            status_index = status_index + 1;
            process_seed = local_process_seed(cfg, ci, si, ri);
            noise_seed   = local_noise_seed(cfg, ci, si, ri);
            outPath      = fullfile(dataDir, char(generation_status(status_index).output_filename));

            fprintf('  - %s / %s / rep%03d ... ', case_def.case_id, scenario.id, ri);

            try
                switch case_def.truth_model
                    case {"SIR", "SIRS"}
                        pop_size = cfg.sirs.pop_size;
                        [S_true, I_true, R_true] = local_simulate_sirs_truth(cfg.sirs, Rt_true, case_def.solver, process_seed);
                        E_true = [];
                        local_validate_truth({S_true, I_true, R_true}, pop_size);
                    case {"SEIR", "SEIRS"}
                        pop_size = cfg.partB.seir.pop_size;
                        [S_true, E_true, I_true, R_true] = local_simulate_seir_truth(cfg.partB.seir, Rt_true, case_def.solver, process_seed);
                        local_validate_truth({S_true, E_true, I_true, R_true}, pop_size);
                    otherwise
                        error('PARTB:UnsupportedTruthModel', 'Unsupported truth model: %s.', case_def.truth_model);
                end

                [Rt_model_input, Rt_model_input_valid_mask] = local_create_rt_model_input(case_def, cfg, Rt_true_col, noise_seed);

                artifact = struct();
                artifact.case_id                   = case_def.case_id;
                artifact.case_name                 = case_def.case_name;
                artifact.scenario_id               = scenario.id;
                artifact.scenario_name             = scenario.name;
                artifact.replicate_id              = sprintf('rep%03d', ri);
                artifact.replicate_index           = ri;
                artifact.truth_model               = case_def.truth_model;
                artifact.requested_solver          = case_def.solver;
                artifact.truth_solver              = truth_solver;
                artifact.tspan                     = tspan(:);
                artifact.Rt_true                   = Rt_true_col;
                artifact.Rt_model_input            = Rt_model_input;
                artifact.Rt_model_input_valid_mask = Rt_model_input_valid_mask;
                artifact.S_true                    = S_true;
                artifact.I_true                    = I_true;
                artifact.R_true                    = R_true;
                artifact.E_true                    = E_true;
                artifact.S_model_input             = S_true;
                artifact.I_model_input             = I_true;
                artifact.E_model_input             = E_true;
                artifact.process_seed              = process_seed;
                artifact.noise_seed                = noise_seed;
                artifact.snapshot                  = local_cfg_snapshot(cfg, case_def, scenario);

                save(outPath, '-struct', 'artifact');

                generation_status(status_index).status = "saved";
                artifact_count = artifact_count + 1;
                fprintf('Saved\n');
            catch ME
                generation_status(status_index).error_id      = string(ME.identifier);
                generation_status(status_index).error_message = string(ME.message);

                if any(string(ME.identifier) == known_domain_errors)
                    if exist(outPath, 'file') == 2
                        delete(outPath);
                    end

                    generation_status(status_index).status = "domain_failure";
                    domain_failure_count = domain_failure_count + 1;
                    fprintf('Domain failure (%s): %s\n', ME.identifier, ME.message);
                else
                    save(statusPath, 'generation_status', 'run_completed');
                    rethrow(ME);
                end
            end

            save(statusPath, 'generation_status', 'run_completed');
        end
    end
end

%% 3. Completion Check
run_completed = true;
save(statusPath, 'generation_status', 'run_completed');

fprintf('Generated %d dataset artifacts.\n', artifact_count);
fprintf('Recorded %d domain failures.\n', domain_failure_count);
fprintf('Generation status saved to: %s\n', statusPath);
fprintf('=== Part B Robustness Dataset Generation Complete ===\n\n');

%% 4. Local Functions
function generation_status = local_initialize_generation_status(cfg)
%LOCAL_INITIALIZE_GENERATION_STATUS Preallocate one pending entry per expected attempt.
total_attempts = 0;
for ci = 1:numel(cfg.partB.robustness_cases)
    total_attempts = total_attempts + numel(cfg.scenarios) * local_num_replicates(cfg.partB.robustness_cases(ci), cfg);
end

entry = struct('case_id', "", 'scenario_id', "", 'replicate_id', "", 'status', "pending", 'error_id', "", 'error_message', "", 'output_filename', "");
generation_status = repmat(entry, total_attempts, 1);
index = 0;

for ci = 1:numel(cfg.partB.robustness_cases)
    case_def = cfg.partB.robustness_cases(ci);
    num_reps = local_num_replicates(case_def, cfg);

    for si = 1:numel(cfg.scenarios)
        scenario = cfg.scenarios(si);

        for ri = 1:num_reps
            index = index + 1;
            replicate_id = sprintf('rep%03d', ri);

            generation_status(index).case_id         = case_def.case_id;
            generation_status(index).scenario_id     = scenario.id;
            generation_status(index).replicate_id    = string(replicate_id);
            generation_status(index).output_filename = string(sprintf('partB_01_dataset_%s_%s_%s.mat', case_def.case_id, scenario.id, replicate_id));
        end
    end
end
end

function num_reps = local_num_replicates(case_def, cfg)
%LOCAL_NUM_REPLICATES Resolve replicate count for a case.
if case_def.observation_noise_enabled && case_def.process_noise_enabled
    if cfg.partB.observation_noise.num_replicates ~= cfg.partB.process_noise.num_replicates
        error('PARTB:ReplicateCountMismatch', 'Observation-noise and process-noise replicate counts must match for combined stress.');
    end

    num_reps = cfg.partB.process_noise.num_replicates;
elseif case_def.observation_noise_enabled
    num_reps = cfg.partB.observation_noise.num_replicates;
elseif case_def.process_noise_enabled
    num_reps = cfg.partB.process_noise.num_replicates;
else
    num_reps = 1;
end
end

function process_seed = local_process_seed(cfg, case_index, scenario_index, replicate_index)
%LOCAL_PROCESS_SEED Deterministic per-replicate process seed.
stride = cfg.partB.process_noise.replicate_seed_stride;
process_seed = cfg.partB.truth.seed + case_index * 1e7 + scenario_index * 1e5 + (replicate_index - 1) * stride;
end

function noise_seed = local_noise_seed(cfg, case_index, scenario_index, replicate_index)
%LOCAL_NOISE_SEED Deterministic per-replicate observation-noise seed disjoint from process seeds.
stride = cfg.partB.process_noise.replicate_seed_stride;
noise_seed = cfg.partB.truth.seed + 5e8 + case_index * 1e7 + scenario_index * 1e5 + (replicate_index - 1) * stride;
end

function [S, I, R] = local_simulate_sirs_truth(model_params, Rt_true, solver, seed)
%LOCAL_SIMULATE_SIRS_TRUTH Simulate latent SIR/SIRS truth via the URDME stepper.
num_time = numel(Rt_true);

initial_state = [model_params.pop_size - model_params.I0 - model_params.R0_init; model_params.I0; model_params.R0_init];
if any(initial_state < 0)
    error('PARTB:InvalidInitialState', 'SIR/SIRS initial state has a negative compartment.');
end

step_options = struct('solver', char(solver), 'seed', seed);
stepper      = sirs_init(model_params, step_options);

U = zeros(3, num_time);
U(:, 1) = initial_state;

for k = 1:(num_time - 1)
    [next_state, stepper] = sirs_step(stepper, U(:, k), Rt_true(k));
    U(:, k + 1) = next_state;
end

S = U(1, :)';
I = U(2, :)';
R = U(3, :)';
end

function [S, E, I, R] = local_simulate_seir_truth(seir, Rt_true, solver, seed)
%LOCAL_SIMULATE_SEIR_TRUTH Simulate latent SEIR/SEIRS truth via the URDME stepper.
num_time = numel(Rt_true);

initial_state = [seir.pop_size - seir.E0 - seir.I0 - seir.R0_init; seir.E0; seir.I0; seir.R0_init];
if any(initial_state < 0)
    error('PARTB:InvalidInitialState', 'SEIR/SEIRS initial state has a negative compartment.');
end

step_options = struct('solver', char(solver), 'seed', seed);
stepper      = seirs_init(seir, step_options);

U = zeros(4, num_time);
U(:, 1) = initial_state;

for k = 1:(num_time - 1)
    [next_state, stepper] = seirs_step(stepper, U(:, k), Rt_true(k));
    U(:, k + 1) = next_state;
end

S = U(1, :)';
E = U(2, :)';
I = U(3, :)';
R = U(4, :)';
end

function local_validate_truth(states, pop_size)
%LOCAL_VALIDATE_TRUTH Check simulated compartment states are finite, nonnegative, and conserved.
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
end

function [Rt_model_input, Rt_model_input_valid_mask] = local_create_rt_model_input(case_def, cfg, Rt_true_col, noise_seed)
%LOCAL_CREATE_RT_MODEL_INPUT Create the model-visible Rt input with optional measurement error.
if case_def.observation_noise_enabled
    rng(noise_seed, 'twister');
    sigma_log = cfg.partB.observation_noise.sigma_log;
    z = randn(size(Rt_true_col));
    Rt_model_input = Rt_true_col .* exp(sigma_log .* z - 0.5 .* sigma_log.^2);
else
    Rt_model_input = Rt_true_col;
end

if any(~isfinite(Rt_model_input)) || any(Rt_model_input <= 0)
    error('PARTB:InvalidRtModelInput', 'Rt_model_input must be finite and strictly positive.');
end

Rt_model_input_valid_mask = true(size(Rt_model_input));
end

function snapshot = local_cfg_snapshot(cfg, case_def, scenario)
%LOCAL_CFG_SNAPSHOT Build the per-artifact provenance snapshot.
snapshot          = cfg.partB.snapshot;
snapshot.case     = case_def;
snapshot.scenario = scenario;
end
