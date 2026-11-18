%PARTB_01_PREPARE_DATASETS Generate synthetic truth, observations, and causal historical estimates.
%
%   Description:
%       Generates one synthetic dataset per robustness condition, scenario,
%       and replicate. Each dataset contains the latent epidemic truth
%       (S, E, I, removed compartment, prescribed effective Rt), the
%       model-visible daily observations, and the causally estimated
%       historical SIRS state and Rt used by every Part B forecast.
%
%       Truth: deterministic (uds) or stochastic (ssa) SIRS or SEIRS
%       simulation driven by the analytic Rt scenario, with an
%       incidence-tracking stepper that counts entries into I.
%
%       Observation: incidence_observed(k+1) is the number of entries into
%       the infectious compartment during [t_k, t_{k+1}]. Under SIRS these
%       are infection events (S to I); under SEIRS they are infectious-onset
%       events (E to I), and infection events (S to E) are not observed.
%       Noise-free conditions observe the count itself (the integrated flux
%       under uds, the realized event count under ssa); noisy conditions
%       observe an independent Poisson draw around it.
%
%       Estimation: ESTIMATE_SIRS_HISTORY_FROM_INCIDENCE inverts the SIRS
%       stepper day by day from the known initial state and known SIRS
%       parameters. Under SEIRS truth the SIRS estimator reads onsets as
%       infections: the I balance remains correct, the exposed compartment
%       is absorbed into the susceptible estimate, and the Rt estimate is a
%       latent-period-lagged proxy rather than the prescribed driver. Partial
%       estimation is preserved: estimates before the first genuine failure
%       are kept and the failure is recorded.
%
%   Workflow:
%       1. Initialize configuration, identity, and output paths.
%       2. Reject stale or incompatible Part B artifacts.
%       3. Initialize the generation status and configuration snapshot.
%       4. Simulate, observe, estimate, and save each dataset.
%       5. Verify completion and persist the final generation status.
%
%   See also PARTB_CONFIG, PARTB_02_RUN_FORECASTS, SIRS_INIT, SIRS_STEP,
%            SEIRS_INIT, SEIRS_STEP, ESTIMATE_SIRS_HISTORY_FROM_INCIDENCE.
%
% A. M. Kaahin 2026-06-30
% Modified: 2026-11-18

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Dataset and Estimate Preparation ===\n');

cfg      = partB_config();
pb       = cfg.partB;
tspan    = cfg.time.tspan;
rtBounds = cfg.Rt.bounds;
dataDir  = pb.output.data_dir;
identity = local_identity(cfg);

fprintf('Protocol: %s | config_id: %s | source_id: %s\n', identity.protocol_version, identity.config_id, identity.source_id);

if ~exist(dataDir, 'dir')
    mkdir(dataDir);
end

statusPath = fullfile(dataDir, 'partB_01_generation_status.mat');

%% 2. Stale-Artifact Guard
local_check_stale_outputs(pb.output, statusPath, identity);

%% 3. Status and Snapshot Initialization
generation_status = local_initialize_generation_status(cfg);
snapshot          = pb.snapshot;
run_completed     = false;
save(statusPath, 'generation_status', 'run_completed', 'identity', 'snapshot');

snapshotPath = fullfile(dataDir, 'partB_01_config_snapshot.json');
fid = fopen(snapshotPath, 'w');
fprintf(fid, '%s\n', jsonencode(struct('identity', identity, 'snapshot', snapshot), 'PrettyPrint', true));
fclose(fid);

known_domain_errors = "EPIDEMIC:SusceptibleBelowThreshold";
estimation_stepper  = sirs_init(cfg.sirs, struct('solver', 'uds', 'seed', cfg.run.seed), true);

%% 4. Dataset Generation Loop
fprintf('Saving datasets to: %s\n', dataDir);

artifact_count       = 0;
domain_failure_count = 0;
status_index         = 0;

for ci = 1:numel(pb.robustness_cases)
    case_def = pb.robustness_cases(ci);

    for si = 1:numel(cfg.scenarios)
        scenario = cfg.scenarios(si);
        Rt_true  = local_rt_signal(scenario, tspan);

        if any(Rt_true < rtBounds(1) | Rt_true > rtBounds(2), 'all')
            error('PARTB_01:RtOutOfBounds', 'Generated Rt signal for %s is outside cfg.Rt.bounds.', scenario.id);
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
                        error('PARTB_01:UnsupportedTruthModel', 'Unsupported truth model: %s.', case_def.truth_model);
                end
            catch ME
                if any(string(ME.identifier) == known_domain_errors)
                    if exist(outPath, 'file') == 2
                        delete(outPath);
                    end

                    generation_status(status_index).status        = "domain_failure";
                    generation_status(status_index).error_id      = string(ME.identifier);
                    generation_status(status_index).error_message = string(ME.message);
                    domain_failure_count = domain_failure_count + 1;
                    fprintf('Truth domain failure (%s): %s\n', ME.identifier, ME.message);
                    save(statusPath, 'generation_status', 'run_completed', 'identity', 'snapshot');
                    continue;
                end

                save(statusPath, 'generation_status', 'run_completed', 'identity', 'snapshot');
                rethrow(ME);
            end

            incidence_observed = local_observe(incidence_true, case_def, pb.observation, noise_seed);
            estimate = estimate_sirs_history_from_incidence(incidence_observed, pb.estimation.initial_state, estimation_stepper, pb.estimation);

            artifact = struct();
            artifact.identity                 = identity;
            artifact.dataset_id               = entry.dataset_id;
            artifact.case_id                  = case_def.case_id;
            artifact.case_name                = case_def.case_name;
            artifact.scenario_id              = scenario.id;
            artifact.scenario_name            = scenario.name;
            artifact.replicate_id             = entry.replicate_id;
            artifact.replicate_index          = ri;
            artifact.truth_model              = case_def.truth_model;
            artifact.truth_solver             = case_def.solver;
            artifact.observation_definition   = pb.observation.definition;
            artifact.observation_noise_enabled = case_def.observation_noise_enabled;
            artifact.tspan                    = tspan(:);
            artifact.Rt_true                  = Rt_true(:);
            artifact.S_true                   = S_true;
            artifact.E_true                   = E_true;
            artifact.I_true                   = I_true;
            artifact.R_removed_true           = R_removed_true;
            artifact.incidence_true           = incidence_true;
            artifact.incidence_observed       = incidence_observed;
            artifact.observation_valid_mask   = isfinite(incidence_observed);
            artifact.S_estimated              = estimate.S;
            artifact.I_estimated              = estimate.I;
            artifact.R_removed_estimated      = estimate.R_removed;
            artifact.Rt_estimated             = estimate.Rt;
            artifact.Rt_available_idx         = estimate.Rt_available_idx;
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

            save(statusPath, 'generation_status', 'run_completed', 'identity', 'snapshot');
        end
    end
end

%% 5. Completion Check
run_completed = true;
save(statusPath, 'generation_status', 'run_completed', 'identity', 'snapshot');

fprintf('Generated %d dataset artifacts.\n', artifact_count);
fprintf('Recorded %d truth domain failures.\n', domain_failure_count);
fprintf('Datasets with a genuine estimation failure: %d.\n', sum(~isnan([generation_status.estimation_failure_idx])));
fprintf('Generation status saved to: %s\n', statusPath);
fprintf('=== Part B Dataset and Estimate Preparation Complete ===\n\n');

%% 6. Local Functions
function identity = local_identity(cfg)
%LOCAL_IDENTITY Experiment, configuration, and source identity shared by all Part B artifacts.
identity = struct('experiment_id', cfg.partB.experiment_id, 'protocol_version', cfg.partB.protocol_version, 'config_id', cfg.partB.config_id, 'source_id', cfg.partB.provenance.source_id);
end

function local_check_stale_outputs(output, status_path, identity)
%LOCAL_CHECK_STALE_OUTPUTS Reject existing Part B outputs not produced under the current identity.
output_dirs = {output.data_dir, output.forecast_dir, output.evaluation_dir, output.table_dir, output.fig_dir};
existing = 0;
for i = 1:numel(output_dirs)
    listing = dir(output_dirs{i});
    existing = existing + sum(~[listing.isdir]);
end

if existing == 0
    return;
end

if exist(status_path, 'file') == 2
    previous = load(status_path);
    if isfield(previous, 'identity') && isequal(previous.identity, identity)
        return;
    end
end

error('PARTB_01:StaleArtifacts', ['%d existing Part B artifact file(s) were not produced under the current protocol, configuration, ' ...
    'and source identity (or are legacy artifacts). Rerun with ./run_partB_pipeline.sh --fresh.'], existing);
end

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

function Rt_true = local_rt_signal(scenario, tspan)
%LOCAL_RT_SIGNAL Analytic effective-Rt scenario signal on the time grid (row vector).
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
        error('PARTB_01:UnsupportedSignal', 'Unsupported Rt signal type: %s.', scenario.signal_type);
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
noise_seed = pb.truth.seed + pb.observation.seed_offset + case_index * 1e7 + scenario_index * 1e5 + (replicate_index - 1) * stride;
end

function [S, I, R_removed, incidence] = local_simulate_sirs_truth(model_params, Rt_true, solver, seed)
%LOCAL_SIMULATE_SIRS_TRUTH Simulate latent SIR/SIRS truth and daily entries into I.
num_time = numel(Rt_true);

initial_state = [model_params.pop_size - model_params.I0 - model_params.R0_init; model_params.I0; model_params.R0_init];
if any(initial_state < 0)
    error('PARTB_01:InvalidInitialState', 'SIR/SIRS initial state has a negative compartment.');
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
    error('PARTB_01:InvalidInitialState', 'SEIR/SEIRS initial state has a negative compartment.');
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
        error('PARTB_01:InvalidState', 'Simulated epidemic state is nonfinite or negative.');
    end
    total = total + state_k;
end

if any(abs(total - pop_size) > 1e-6 * pop_size)
    error('PARTB_01:PopulationNotConserved', 'Simulated population is not conserved.');
end

if any(~isfinite(incidence(2:end))) || any(incidence(2:end) < 0)
    error('PARTB_01:InvalidTruthIncidence', 'Simulated daily entries into I are nonfinite or negative.');
end
end

function incidence_observed = local_observe(incidence_true, case_def, observation, noise_seed)
%LOCAL_OBSERVE Model-visible daily entries into I, with independent Poisson noise when enabled.
if case_def.observation_noise_enabled
    if observation.noise_model ~= "poisson"
        error('PARTB_01:UnsupportedNoiseModel', 'Unsupported observation noise model: %s.', observation.noise_model);
    end

    rng(noise_seed, 'twister');
    incidence_observed = [NaN; poissrnd(incidence_true(2:end))];
else
    incidence_observed = incidence_true;
end
end
