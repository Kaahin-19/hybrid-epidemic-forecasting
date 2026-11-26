%PARTA_01_GENERATE_TRUTH Generate the role-separated Part A synthetic datasets.
%
%   Description:
%       Generates the development, refinement, and assessment trajectories of
%       the Part A design. Each effective-Rt signal is evaluated from
%       canonical scenario parameters or from parameters drawn on the
%       trajectory's own random substream, simulated with the deterministic
%       SIRS stepper, checked for epidemiological feasibility, and saved in
%       its role directory together with a dataset manifest. An existing
%       dataset collection from the same design is reused; one from a
%       different design is an error.
%
%   Workflow:
%       1. Initialize the configured dataset design.
%       2. Reuse a compatible existing dataset collection.
%       3. Define the development, refinement, and assessment trajectories.
%       4. Simulate, check, and save every trajectory.
%       5. Save the dataset manifest.
%
%   See also PARTA_CONFIG, PARTA_02_SELECT_HYPERPARAMETERS,
%            GENERATE_RT_SIGNAL, SIRS_INIT, SIRS_STEP.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-11-26

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Synthetic Dataset Generation ===\n');

cfg             = partA_config();
tspan           = cfg.time.tspan;
num_time        = numel(tspan);
data_dir        = cfg.output.data_dir;
manifest_path   = cfg.output.dataset_manifest;
design_snapshot = cfg.snapshot.design;
design          = cfg.design;

%% 2. Existing Dataset Reuse
if exist(manifest_path, 'file') == 2
    existing = load(manifest_path, 'datasets', 'snapshot');

    if ~isequaln(existing.snapshot, design_snapshot)
        error('PARTA_01:DesignChanged', 'The dataset manifest %s was generated under a different Part A dataset design. Rerun with ./run_partA_pipeline.sh --fresh.', manifest_path);
    end

    missing_files = existing.datasets.File(~isfile(fullfile(data_dir, existing.datasets.File)));

    if ~isempty(missing_files)
        error('PARTA_01:MissingDatasets', 'The dataset manifest lists %d missing trajectory files, e.g. %s. Rerun with ./run_partA_pipeline.sh --fresh.', numel(missing_files), missing_files(1));
    end

    fprintf('Datasets: reused %d trajectories listed in %s\n', height(existing.datasets), manifest_path);
    fprintf('=== Part A Synthetic Dataset Generation Complete ===\n\n');
    return;
end

%% 3. Trajectory Definitions
template    = struct('dataset_id', "", 'role', "", 'family', "", 'stratum', "", 'is_canonical', false, 'seed_index', 0, 'signal_type', "", 'signal_params', struct(), 'design_draw', struct());
definitions = repmat(template, 0, 1);

for b = 1:numel(design.development.strata)
    stratum = design.development.strata(b);

    for j = 1:stratum.num_trajectories
        seed_index = design.seed_index_base.development + 10 * b + j;
        stream     = local_substream(design, seed_index);

        draw = struct();
        draw.trough_depth = local_uniform(stream, stratum.trough_depth);
        draw.peak_ratio   = local_uniform(stream, stratum.peak_ratio);
        draw.period       = local_uniform(stream, stratum.period);
        draw.phase        = local_uniform(stream, design.development.phase);

        center = design.development.center;
        params = struct('center', center, 'peak', center + draw.peak_ratio * draw.trough_depth, 'trough', center - draw.trough_depth, 'period', draw.period, 'phase', draw.phase);

        definitions(end + 1, 1) = struct('dataset_id', sprintf("dev_%s_%02d", stratum.id, j), 'role', "development", 'family', design.development.family, 'stratum', stratum.id, 'is_canonical', false, 'seed_index', seed_index, 'signal_type', "periodic", 'signal_params', params, 'design_draw', draw);
    end
end

for f = 1:numel(cfg.scenarios)
    scenario = cfg.scenarios(f);

    definitions(end + 1, 1) = struct('dataset_id', "ref_" + scenario.id + "_c", 'role', "refinement", 'family', scenario.id, 'stratum', scenario.id, 'is_canonical', true, 'seed_index', f, 'signal_type', scenario.signal_type, 'signal_params', scenario.params, 'design_draw', struct());

    for j = 1:design.refinement.num_variants
        seed_index = design.seed_index_base.refinement + 10 * f + j;
        [params, draw] = local_draw_variant(scenario, design.variants.(scenario.id), local_substream(design, seed_index), tspan);

        definitions(end + 1, 1) = struct('dataset_id', sprintf("ref_%s_v%02d", scenario.id, j), 'role', "refinement", 'family', scenario.id, 'stratum', scenario.id, 'is_canonical', false, 'seed_index', seed_index, 'signal_type', scenario.signal_type, 'signal_params', params, 'design_draw', draw);
    end
end

for f = 1:numel(cfg.scenarios)
    scenario = cfg.scenarios(f);

    for j = 1:design.assessment.num_variants
        seed_index = design.seed_index_base.assessment + 10 * f + j;
        [params, draw] = local_draw_variant(scenario, design.variants.(scenario.id), local_substream(design, seed_index), tspan);

        definitions(end + 1, 1) = struct('dataset_id', sprintf("asm_%s_v%02d", scenario.id, j), 'role', "assessment", 'family', scenario.id, 'stratum', scenario.id, 'is_canonical', false, 'seed_index', seed_index, 'signal_type', scenario.signal_type, 'signal_params', params, 'design_draw', draw);
    end
end

num_datasets = numel(definitions);
roles        = ["development"; "refinement"; "assessment"];

fprintf('Generating %d trajectories (%d development, %d refinement, %d assessment) in %s\n', num_datasets, sum([definitions.role] == "development"), sum([definitions.role] == "refinement"), sum([definitions.role] == "assessment"), data_dir);

%% 4. Simulation and Feasibility Checks
for r = 1:numel(roles)
    if ~exist(fullfile(data_dir, roles(r)), 'dir')
        mkdir(fullfile(data_dir, roles(r)));
    end
end

base_stepper  = sirs_init(cfg.sirs, struct('solver', 'uds', 'seed', 1234));
initial_state = [cfg.sirs.pop_size - cfg.sirs.I0 - cfg.sirs.R0_init; cfg.sirs.I0; cfg.sirs.R0_init];
files         = strings(num_datasets, 1);

for i = 1:num_datasets
    def = definitions(i);

    fprintf('  - Generating %s (%s, %s)... ', def.dataset_id, def.role, def.family);

    Rt_true = generate_rt_signal(def.signal_type, def.signal_params, tspan);

    if any(Rt_true < cfg.Rt.bounds(1) | Rt_true > cfg.Rt.bounds(2))
        error('PARTA_01:RtOutOfBounds', 'Generated Rt signal for %s lies outside cfg.Rt.bounds.', def.dataset_id);
    end

    stepper = base_stepper;
    states  = zeros(3, num_time);
    states(:, 1) = initial_state;

    for k = 1:(num_time - 1)
        [states(:, k + 1), stepper] = sirs_step(stepper, states(:, k), Rt_true(k));
    end

    acceptance = local_check_feasibility(def.dataset_id, states, Rt_true, cfg);

    if def.is_canonical
        stream_info = struct('type', design.stream_type, 'seed', design.seed, 'substream', NaN);
    else
        stream_info = struct('type', design.stream_type, 'seed', design.seed, 'substream', def.seed_index);
    end

    artifact = struct('dataset_id', def.dataset_id, 'role', def.role, 'family', def.family, 'stratum', def.stratum, 'is_canonical', def.is_canonical, 'seed_index', def.seed_index, 'stream', stream_info, 'signal_type', def.signal_type, 'signal_params', def.signal_params, 'design_draw', def.design_draw, 'tspan', tspan.', 'Rt_true', Rt_true, 'S_true', states(1, :).', 'I_true', states(2, :).', 'R_true', states(3, :).', 'model_params', cfg.sirs, 'acceptance', acceptance, 'snapshot', design_snapshot);

    files(i) = fullfile(def.role, "partA_01_truth_" + def.dataset_id + ".mat");
    save(fullfile(data_dir, files(i)), '-struct', 'artifact');

    fprintf('Saved (min S/N %.3f, max I/N %.4f)\n', acceptance.min_susceptible_fraction, acceptance.max_infectious_fraction);
end

%% 5. Dataset Manifest
datasets = table([definitions.dataset_id]', [definitions.role]', [definitions.family]', [definitions.stratum]', [definitions.is_canonical]', [definitions.seed_index]', [definitions.signal_type]', files, 'VariableNames', {'DatasetId', 'Role', 'Family', 'Stratum', 'IsCanonical', 'SeedIndex', 'SignalType', 'File'});

snapshot = design_snapshot;
created  = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

save(manifest_path, 'datasets', 'snapshot', 'created');

fprintf('Datasets: generated %d trajectories; manifest saved to %s\n', num_datasets, manifest_path);
fprintf('=== Part A Synthetic Dataset Generation Complete ===\n\n');

%% 6. Local Functions
function stream = local_substream(design, seed_index)
%LOCAL_SUBSTREAM Independent parameter-draw substream of one trajectory.
stream = RandStream(design.stream_type, 'Seed', design.seed);
stream.Substream = seed_index;
end

function value = local_uniform(stream, range)
%LOCAL_UNIFORM Draw one value uniformly from a [lower, upper] range.
value = range(1) + (range(2) - range(1)) * rand(stream);
end

function [params, draw] = local_draw_variant(scenario, ranges, stream, tspan)
%LOCAL_DRAW_VARIANT Draw one family variant that keeps the canonical net transmission budget.
canonical = scenario.params;
draw      = struct();

switch scenario.signal_type
    case "seasonal"
        draw.amp   = local_uniform(stream, ranges.amp);
        draw.phase = local_uniform(stream, ranges.phase);

        params = struct('center', canonical.center, 'amp', draw.amp, 'period', canonical.period, 'phase', draw.phase);
    case "sigmoid"
        draw.t0              = local_uniform(stream, ranges.t0);
        draw.k               = local_uniform(stream, ranges.k);
        draw.low             = local_uniform(stream, ranges.low);
        draw.growth_fraction = local_uniform(stream, ranges.growth_fraction);

        growth_budget = (canonical.high - 1) * canonical.t0;
        params = struct('high', 1 + draw.growth_fraction * growth_budget / draw.t0, 'low', draw.low, 't0', draw.t0, 'k', draw.k);
    case "multi_wave"
        draw.spacing = local_uniform(stream, ranges.spacing);
        draw.scale   = local_uniform(stream, ranges.scale);
        draw.ratio   = local_uniform(stream, ranges.ratio);

        params = struct('baseline', 0, 'mu1', 1 * draw.spacing, 'A1', draw.scale, 'mu2', 2 * draw.spacing, 'A2', draw.scale * draw.ratio, 'mu3', 3 * draw.spacing, 'A3', draw.scale * draw.ratio^2, 'mu4', 4 * draw.spacing, 'A4', draw.scale * draw.ratio^3, 'denom', draw.spacing^2 / 8);

        canonical_mean  = mean(generate_rt_signal(scenario.signal_type, canonical, tspan));
        params.baseline = canonical_mean - mean(generate_rt_signal(scenario.signal_type, params, tspan));
end
end

function acceptance = local_check_feasibility(dataset_id, states, Rt_true, cfg)
%LOCAL_CHECK_FEASIBILITY Reject trajectories that violate the design's epidemiological limits.
pop_size           = cfg.sirs.pop_size;
S                  = states(1, :).';
I                  = states(2, :).';
min_S_allowed      = cfg.design.min_susceptible_margin * cfg.sirs.min_susceptible;
conservation_error = max(abs(sum(states, 1) - pop_size));

if any(states(:) < 0)
    error('PARTA_01:NegativeState', 'Simulated SIRS states of %s contain negative values.', dataset_id);
end

if conservation_error > cfg.design.conservation_tolerance
    error('PARTA_01:PopulationNotConserved', 'Simulated SIRS states of %s violate population conservation by %.3g.', dataset_id, conservation_error);
end

if min(S) < min_S_allowed
    error('PARTA_01:SusceptibleMargin', 'Trajectory %s reaches S = %.1f, below the design margin %.1f (%g times the forecasting guard).', dataset_id, min(S), min_S_allowed, cfg.design.min_susceptible_margin);
end

acceptance = struct('min_susceptible_fraction', min(S) / pop_size, 'max_infectious_fraction', max(I) / pop_size, 'min_infectious', min(I), 'max_implied_basic_rt', max(Rt_true .* pop_size ./ S), 'conservation_error', conservation_error);
end
