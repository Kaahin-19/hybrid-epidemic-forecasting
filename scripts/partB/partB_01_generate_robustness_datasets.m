%PARTB_01_GENERATE_ROBUSTNESS_DATASETS Generate Part B robustness datasets.
%
%   Description:
%       Generates synthetic robustness dataset artifacts by combining the
%       existing Part A analytic Rt scenarios with controlled observation noise,
%       stochastic process noise, structural mismatch, and combined stress cases.
%
%   Workflow:
%       1. Load Part B configuration and resolve cases/scenarios.
%       2. Generate analytic Rt signals inline for each scenario.
%       3. Simulate latent SIRS or SEIR epidemic truth.
%       4. Build model-visible inputs.
%       5. Save successful dataset artifacts and record generation status.
%
%   See also PARTB_CONFIG, ESTIMATE_RT_RENEWAL, SIRS_INIT, SIRS_STEP.
%
% A. M. Kaahin 2026-06-30

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Robustness Dataset Generation ===\n');

cfg      = partB_config();
tspan    = cfg.time.tspan;
rtBounds = cfg.Rt.bounds;
dataDir  = cfg.partB.output.data_dir;

if exist('binornd', 'file') ~= 2 || exist('nbinrnd', 'file') ~= 2
    error('PARTB:MissingStatsToolbox', 'Part B stochastic transitions and negative-binomial observation noise require binornd and nbinrnd.');
end

if ~exist(dataDir, 'dir')
    mkdir(dataDir);
end

statusPath = fullfile(dataDir, 'partB_01_generation_status.mat');
known_domain_errors = ["EPIDEMIC:SusceptibleBelowThreshold", "PARTB:SusceptibleDepleted"];
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
        truth_solver = local_truth_solver(case_def);

        for ri = 1:num_reps
            status_index = status_index + 1;
            process_seed = local_process_seed(cfg, ci, si, ri);
            noise_seed   = local_noise_seed(cfg, ci, si, ri);
            outPath      = fullfile(dataDir, char(generation_status(status_index).output_filename));

            fprintf('  - %s / %s / rep%03d ... ', case_def.case_id, scenario.id, ri);

            try
                switch case_def.truth_model
                    case "SIRS"
                        pop_size = cfg.sirs.pop_size;
                        [S_true, I_true, R_true] = local_simulate_sirs_truth(cfg.sirs, Rt_true, case_def.solver, process_seed);
                        E_true         = [];
                        incidence_true = local_derive_incidence(Rt_true_col, I_true, cfg.sirs.gamma);
                        local_validate_truth({S_true, I_true, R_true}, incidence_true, pop_size);
                    case "SEIR"
                        pop_size = cfg.partB.seir.pop_size;
                        [S_true, E_true, I_true, R_true, incidence_true] = local_simulate_seir_truth(cfg.partB.seir, Rt_true, case_def.solver, process_seed);
                        local_validate_truth({S_true, E_true, I_true, R_true}, incidence_true, pop_size);
                    otherwise
                        error('PARTB:UnsupportedTruthModel', 'Unsupported truth model: %s.', case_def.truth_model);
                end

                [Rt_model_input, Rt_model_input_valid_mask, incidence_observed, incidence_model_input] = local_apply_observation_model(case_def, cfg, incidence_true, Rt_true_col, noise_seed);

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
                artifact.incidence_true            = incidence_true;
                artifact.incidence_observed        = incidence_observed;
                artifact.incidence_model_input     = incidence_model_input;
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

function truth_solver = local_truth_solver(case_def)
%LOCAL_TRUTH_SOLVER Honest label for the simulation method actually used.
if case_def.truth_model == "SIRS"
    truth_solver = case_def.solver;
elseif strcmp(char(case_def.solver), 'uds')
    truth_solver = "local_discrete_deterministic";
else
    truth_solver = "local_chain_binomial";
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
%LOCAL_SIMULATE_SIRS_TRUTH Simulate latent SIRS truth via the URDME stepper.
num_time = numel(Rt_true);

initial_state = [model_params.pop_size - model_params.I0 - model_params.R0_init; model_params.I0; model_params.R0_init];
if any(initial_state < 0)
    error('PARTB:InvalidInitialState', 'SIRS initial state has a negative compartment.');
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

function [S, E, I, R, incidence] = local_simulate_seir_truth(seir, Rt_true, solver, seed)
%LOCAL_SIMULATE_SEIR_TRUTH Simulate latent SEIR truth by daily discrete S->E->I->R transitions.
is_stochastic = ~strcmp(char(solver), 'uds');
if is_stochastic
    rng(seed, 'twister');
end

num_time = numel(Rt_true);
N        = seir.pop_size;
gamma    = seir.gamma;
sigma    = seir.sigma;

S = zeros(num_time, 1);
E = zeros(num_time, 1);
I = zeros(num_time, 1);
R = zeros(num_time, 1);
incidence = zeros(num_time, 1);

S(1) = N - seir.I0 - seir.E0 - seir.R0_init;
E(1) = seir.E0;
I(1) = seir.I0;
R(1) = seir.R0_init;

if any([S(1), E(1), I(1), R(1)] < 0)
    error('PARTB:InvalidInitialState', 'SEIR initial state has a negative compartment.');
end

p_EI = 1 - exp(-sigma);
p_IR = 1 - exp(-gamma);

for t = 1:num_time
    if S(t) <= 0
        error('PARTB:SusceptibleDepleted', 'SEIR susceptible state reached zero at step %d.', t);
    end

    beta = Rt_true(t) * gamma * N / S(t);
    p_SE = 1 - exp(-beta * I(t) / N);

    if t < num_time
        [next_state, new_exposed] = local_seir_step([S(t); E(t); I(t); R(t)], p_SE, p_EI, p_IR, is_stochastic);
        S(t + 1)     = next_state(1);
        E(t + 1)     = next_state(2);
        I(t + 1)     = next_state(3);
        R(t + 1)     = next_state(4);
        incidence(t) = new_exposed;
    else
        incidence(t) = S(t) * p_SE;
    end
end
end

function [next_state, new_exposed] = local_seir_step(state, p_SE, p_EI, p_IR, is_stochastic)
%LOCAL_SEIR_STEP Advance one SEIR day using expected or chain-binomial transition flows.
S = state(1);
E = state(2);
I = state(3);
R = state(4);

if is_stochastic
    new_exposed    = binornd(S, p_SE);
    new_infectious = binornd(E, p_EI);
    new_recovered  = binornd(I, p_IR);
else
    new_exposed    = S * p_SE;
    new_infectious = E * p_EI;
    new_recovered  = I * p_IR;
end

next_state = [S - new_exposed; E + new_exposed - new_infectious; I + new_infectious - new_recovered; R + new_recovered];
end

function incidence = local_derive_incidence(Rt_true, I_true, gamma)
%LOCAL_DERIVE_INCIDENCE SIRS latent incidence as the expected S->I infection flow Rt*gamma*I.
incidence = Rt_true .* gamma .* I_true;
end

function local_validate_truth(states, incidence, pop_size)
%LOCAL_VALIDATE_TRUTH Check simulated states are finite, nonnegative, conserved, and incidence is valid.
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

if any(~isfinite(incidence)) || any(incidence < 0)
    error('PARTB:InvalidIncidence', 'incidence_true is nonfinite or negative.');
end
end

function [Rt_model_input, Rt_model_input_valid_mask, incidence_observed, incidence_model_input] = local_apply_observation_model(case_def, cfg, incidence_true, Rt_true_col, noise_seed)
%LOCAL_APPLY_OBSERVATION_MODEL Build model-visible Rt input through the incidence-observation-renewal path.
if case_def.observation_noise_enabled
    obs = cfg.partB.observation_noise;

    rng(noise_seed, 'twister');
    mu   = obs.reporting_fraction .* incidence_true;
    p_nb = obs.dispersion ./ (obs.dispersion + mu);
    incidence_observed = nbinrnd(obs.dispersion, p_nb);

    incidence_model_input = local_smooth_incidence(incidence_observed, obs.smoothing_window_days);

    [Rt_model_input, renewal_info] = estimate_rt_renewal(incidence_model_input(:), cfg.partB.rt_estimation);
    Rt_model_input_valid_mask = renewal_info.valid_mask;
else
    Rt_model_input            = Rt_true_col;
    Rt_model_input_valid_mask = true(size(Rt_true_col));
    incidence_observed        = incidence_true;
    incidence_model_input     = incidence_true;
end
end

function smoothed = local_smooth_incidence(incidence, window_days)
%LOCAL_SMOOTH_INCIDENCE Trailing moving average over past and current days only.
smoothed = movmean(incidence, [window_days - 1, 0]);
end

function snapshot = local_cfg_snapshot(cfg, case_def, scenario)
%LOCAL_CFG_SNAPSHOT Build the per-artifact provenance snapshot.
snapshot          = cfg.partB.snapshot;
snapshot.case     = case_def;
snapshot.scenario = scenario;
end