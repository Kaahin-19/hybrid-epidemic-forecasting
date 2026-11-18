%PARTB_02_RUN_FORECASTS Generate persistence, oracle, and ARX infectious-population forecasts.
%
%   Description:
%       For every saved Part B dataset and every forecast origin T on the
%       fixed expanding-window grid, constructs three future-Rt driver
%       sequences and propagates each through the same SIRS forecasting
%       stepper from the same estimated state X_hat_T = [S; I; R_removed]
%       at T. The methods differ only in their drivers.
%
%       Time indexing: the SIRS stepper applies a driver to the interval
%       that starts at the current state. Rt_estimated(k) is the driver of
%       [t_k, t_{k+1}] and becomes available at index k + 1, so at origin
%       index iT the latest available estimate is Rt_estimated(iT - 1) and
%       the driver of [T, T+1] is not observed. For h = 1..H, column h of
%       every driver sequence drives [T+h-1, T+h]:
%           persistence : Rt_estimated(j) for all h, with j the most recent
%                         valid estimate index <= iT - 1;
%           oracle      : Rt_true(iT + h - 1), the prescribed synthetic
%                         driver (privileged reference; never true I or S);
%           ARX         : bootstrap median of the Part A-selected ARX/I
%                         model fitted to Rt_estimated(r0:iT-1) with
%                         covariate I_estimated(r0:iT-1) / N. FORECAST_CLOSED
%                         first replays [T-1, T] from X_hat_{T-1} with
%                         Rt_estimated(iT - 1) on the same stepper that
%                         produced X_hat_T, so its closed-loop covariate at T
%                         equals I_hat_T exactly, and its H outputs are the
%                         drivers of [T, T+1], ..., [T+H-1, T+H].
%       ARX requires a contiguous valid estimate run r0..iT-1 of at least
%       cfg.partB.arx.min_history values. No future observation enters
%       persistence or ARX. Unavailable or failed method forecasts are
%       recorded with an explicit status.
%
%   Workflow:
%       1. Initialize configuration, identity, and output paths.
%       2. Load and validate the Part A ARX/I selection artifact.
%       3. Load and validate the Part B generation status.
%       4. Initialize the forecast-execution status.
%       5. Forecast each saved dataset and checkpoint every attempt.
%       6. Verify completion and persist the final forecast status.
%
%   See also PARTB_CONFIG, PARTB_01_PREPARE_DATASETS,
%            PARTB_03_EVALUATE_FORECASTS, FORECAST_CLOSED, SIRS_INIT,
%            SIRS_STEP.
%
% A. M. Kaahin 2026-07-18
% Modified: 2026-11-18

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Infectious-Population Forecast Generation ===\n');

cfg          = partB_config();
pb           = cfg.partB;
data_dir     = pb.output.data_dir;
forecast_dir = pb.output.forecast_dir;
identity     = local_identity(cfg);

if ~exist(forecast_dir, 'dir')
    mkdir(forecast_dir);
end

status_path = fullfile(forecast_dir, 'partB_02_forecast_status.mat');

%% 2. Load Part A ARX Selection
selection = local_load_selection(cfg);
fprintf('Using %s / %s selected configuration %s from %s\n', selection.model_type, selection.exo_mode, mat2str(selection.selected_configuration), selection.artifact_name);

%% 3. Load Part B Generation Status
generation_path = fullfile(data_dir, 'partB_01_generation_status.mat');
if ~exist(generation_path, 'file')
    error('PARTB_02:MissingGenerationStatus', 'Missing Part B generation status: %s. Run partB_01 first.', generation_path);
end

generation = load(generation_path);
local_require_identity(generation.identity, identity, 'generation status');

if ~generation.run_completed
    error('PARTB_02:GenerationIncomplete', 'Part B dataset generation did not complete (run_completed is false).');
end

generation_status = generation.generation_status;
num_saved = sum([generation_status.status] == "saved");
fprintf('Forecasting %d saved datasets (%d generation attempts).\n', num_saved, numel(generation_status));

%% 4. Initialize Forecast Status
forecast_status = local_init_forecast_status(generation_status);
run_completed   = false;
save(status_path, 'forecast_status', 'run_completed', 'identity', 'selection');

forecast_stepper = sirs_init(cfg.sirs, struct('solver', 'uds', 'seed', cfg.run.seed), true);
scenario_ids     = [cfg.scenarios.id];

%% 5. Forecast Execution Loop
saved_index = 0;
for di = 1:numel(generation_status)
    entry = generation_status(di);

    if entry.status ~= "saved"
        continue;
    end

    saved_index = saved_index + 1;
    fprintf('Dataset %d/%d (%s)\n', saved_index, num_saved, entry.dataset_id);

    dataset = load(fullfile(data_dir, entry.output_filename));
    local_require_identity(dataset.identity, identity, entry.output_filename);

    scenario_index = find(scenario_ids == dataset.scenario_id);
    windows = local_forecast_dataset(dataset, cfg, selection, forecast_stepper, scenario_index);

    artifact = struct();
    artifact.identity       = identity;
    artifact.dataset_id     = dataset.dataset_id;
    artifact.case_id        = dataset.case_id;
    artifact.scenario_id    = dataset.scenario_id;
    artifact.replicate_id   = dataset.replicate_id;
    artifact.source_dataset = entry.output_filename;
    artifact.method_ids     = pb.method_ids;
    artifact.selection      = selection;
    artifact.seed_policy    = "window_seed = run_seed + 10000*scenario_index + window_index; ARX resample seed = window_seed; epidemic seed = window_seed + 1e6";
    artifact.windows        = windows;
    artifact.snapshot       = pb.snapshot;

    out_name = "partB_02_forecast_" + dataset.dataset_id + ".mat";
    save(fullfile(forecast_dir, out_name), '-struct', 'artifact');

    method_status = [windows.status];
    forecast_status(di).status          = "saved";
    forecast_status(di).output_filename = out_name;
    forecast_status(di).num_windows     = numel(windows);
    forecast_status(di).num_ok          = sum(method_status == "ok", 2);
    forecast_status(di).num_matched     = sum(all(method_status == "ok", 1));

    fprintf('  %d windows | ok persistence/oracle/arx = %d/%d/%d | matched = %d\n', numel(windows), forecast_status(di).num_ok, forecast_status(di).num_matched);
    save(status_path, 'forecast_status', 'run_completed', 'identity', 'selection');
end

%% 6. Completion Check
run_completed = true;
save(status_path, 'forecast_status', 'run_completed', 'identity', 'selection');

fprintf('Saved forecast status to: %s\n', status_path);
fprintf('=== Part B Infectious-Population Forecast Generation Complete ===\n\n');

%% 7. Local Functions
function identity = local_identity(cfg)
%LOCAL_IDENTITY Experiment, configuration, and source identity shared by all Part B artifacts.
identity = struct('experiment_id', cfg.partB.experiment_id, 'protocol_version', cfg.partB.protocol_version, 'config_id', cfg.partB.config_id, 'source_id', cfg.partB.provenance.source_id);
end

function local_require_identity(found, expected, label)
%LOCAL_REQUIRE_IDENTITY Reject inputs produced under a different protocol, configuration, or source.
if ~isequal(found, expected)
    error('PARTB_02:IncompatibleArtifact', ['%s was produced under protocol %s, config_id %s, source_id %s; the current run expects protocol %s, ' ...
        'config_id %s, source_id %s. Rerun with ./run_partB_pipeline.sh --fresh.'], label, found.protocol_version, found.config_id, found.source_id, expected.protocol_version, expected.config_id, expected.source_id);
end
end

function selection = local_load_selection(cfg)
%LOCAL_LOAD_SELECTION Load the Part A ARX/I selection and require a compatible selection protocol.
artifact_path = cfg.partB.arx.selection_artifact;
if ~exist(artifact_path, 'file')
    error('PARTB_02:MissingSelectionArtifact', 'Missing Part A selection artifact: %s.', artifact_path);
end

loaded   = load(artifact_path);
expected = cfg.snapshot.selection;
expected.model_type = cfg.partB.arx.model_type;
expected.exo_mode   = cfg.partB.arx.exo_mode;

if ~local_selection_snapshot_compatible(loaded.snapshot, expected)
    error('PARTB_02:IncompatibleSelection', 'Part A selection artifact %s does not match the current %s/%s selection protocol.', artifact_path, expected.model_type, expected.exo_mode);
end

[~, name, ext] = fileparts(artifact_path);
selection = struct('model_type', cfg.partB.arx.model_type, 'exo_mode', cfg.partB.arx.exo_mode, 'selected_configuration', loaded.selected_configuration, 'artifact_name', string(name) + string(ext));
end

function compatible = local_selection_snapshot_compatible(saved, expected)
%LOCAL_SELECTION_SNAPSHOT_COMPATIBLE Compare ARX-relevant selection settings only.
irrelevant_fields = {'max_state_order', 'state_diff_orders'};
for i = 1:numel(irrelevant_fields)
    if isfield(saved, irrelevant_fields{i})
        saved = rmfield(saved, irrelevant_fields{i});
    end
    if isfield(expected, irrelevant_fields{i})
        expected = rmfield(expected, irrelevant_fields{i});
    end
end
compatible = isequaln(saved, expected);
end

function forecast_status = local_init_forecast_status(generation_status)
%LOCAL_INIT_FORECAST_STATUS One forecast-status entry per generation attempt.
template = struct('case_id', "", 'scenario_id', "", 'replicate_id', "", 'dataset_id', "", 'generation_status', "", 'status', "pending", 'output_filename', "", 'num_windows', 0, 'num_ok', zeros(3, 1), 'num_matched', 0);
forecast_status = repmat(template, numel(generation_status), 1);

for i = 1:numel(generation_status)
    forecast_status(i).case_id           = generation_status(i).case_id;
    forecast_status(i).scenario_id       = generation_status(i).scenario_id;
    forecast_status(i).replicate_id      = generation_status(i).replicate_id;
    forecast_status(i).dataset_id        = generation_status(i).dataset_id;
    forecast_status(i).generation_status = generation_status(i).status;

    if generation_status(i).status ~= "saved"
        forecast_status(i).status = "dataset_unavailable";
    end
end
end

function windows = local_forecast_dataset(dataset, cfg, selection, stepper, scenario_index)
%LOCAL_FORECAST_DATASET Persistence, oracle, and ARX forecasts at every origin of one dataset.
H           = cfg.forecast.horizon;
pop_size    = cfg.sirs.pop_size;
min_history = cfg.partB.arx.min_history;
origin_days = cfg.forecast.min_window:cfg.forecast.step_size:(cfg.time.T_end - H);
rt_valid    = dataset.estimation_valid_mask;
state_valid = dataset.state_valid_mask;
X_hat       = [dataset.S_estimated, dataset.I_estimated, dataset.R_removed_estimated]';

template = struct('window_day', [], 'window_day_idx', [], 'time_horizon', [], 'X_hat_T', [], 'last_estimate_idx', [], 'persistence_source_idx', NaN, 'arx_fit_range', [NaN; NaN], ...
    'drivers', [], 'I_pred', [], 'S_pred', [], 'R_removed_pred', [], 'status', [], 'error_id', [], 'truth_I', [], 'truth_Rt_drivers', []);
windows = repmat(template, numel(origin_days), 1);

for w = 1:numel(origin_days)
    iT = find(dataset.tspan == origin_days(w));

    drivers  = NaN(H, 3);
    status   = repmat("ok", 3, 1);
    error_id = repmat("", 3, 1);

    windows(w).window_day        = origin_days(w);
    windows(w).window_day_idx    = iT;
    windows(w).time_horizon      = dataset.tspan(iT + 1:iT + H)';
    windows(w).X_hat_T           = X_hat(:, iT);
    windows(w).last_estimate_idx = iT - 1;
    windows(w).truth_I           = dataset.I_true(iT + 1:iT + H);
    windows(w).truth_Rt_drivers  = dataset.Rt_true(iT:iT + H - 1);

    if ~state_valid(iT)
        windows(w).drivers        = drivers;
        windows(w).I_pred         = NaN(H, 3);
        windows(w).S_pred         = NaN(H, 3);
        windows(w).R_removed_pred = NaN(H, 3);
        windows(w).status         = repmat("estimation_unavailable", 3, 1);
        windows(w).error_id       = error_id;
        continue;
    end

    persistence_idx = find(rt_valid(1:iT - 1), 1, 'last');
    if ~isempty(persistence_idx)
        windows(w).persistence_source_idx = persistence_idx;
        drivers(:, 1) = repmat(dataset.Rt_estimated(persistence_idx), H, 1);
    else
        status(1) = "estimation_unavailable";
    end

    drivers(:, 2) = dataset.Rt_true(iT:iT + H - 1);

    if ~rt_valid(iT - 1) || ~state_valid(iT - 1)
        status(3) = "estimation_unavailable";
    else
        r0 = find(~rt_valid(1:iT - 1), 1, 'last') + 1;
        if isempty(r0)
            r0 = 1;
        end
        windows(w).arx_fit_range = [r0; iT - 1];

        if iT - r0 < min_history
            status(3) = "insufficient_history";
        else
            window_seed = cfg.run.seed + 10000 * scenario_index + w;
            try
                ensemble = forecast_closed(selection.model_type, selection.selected_configuration, dataset.Rt_estimated(r0:iT - 1), dataset.I_estimated(r0:iT - 1) / pop_size, X_hat(:, iT - 1), 1, cfg.intervals.num_draws, H, selection.exo_mode, stepper, window_seed, window_seed + 1000000, cfg.intervals.include_epidemic_seed_variation);
                drivers(:, 3) = median(ensemble, 2);
            catch ME
                [status(3), error_id(3)] = local_classify_failure(ME);
            end
        end
    end

    I_pred = NaN(H, 3);
    S_pred = NaN(H, 3);
    R_pred = NaN(H, 3);

    for m = 1:3
        if status(m) ~= "ok"
            drivers(:, m) = NaN;
            continue;
        end

        try
            projected = local_project_sirs_trajectory(stepper, X_hat(:, iT), drivers(:, m));
            S_pred(:, m) = projected(:, 1);
            I_pred(:, m) = projected(:, 2);
            R_pred(:, m) = projected(:, 3);
        catch ME
            [status(m), error_id(m)] = local_classify_failure(ME);
        end
    end

    windows(w).drivers        = drivers;
    windows(w).I_pred         = I_pred;
    windows(w).S_pred         = S_pred;
    windows(w).R_removed_pred = R_pred;
    windows(w).status         = status;
    windows(w).error_id       = error_id;
end
end

function [status, error_id] = local_classify_failure(ME)
%LOCAL_CLASSIFY_FAILURE Map documented forecasting failures to statuses; rethrow anything else.
error_id = string(ME.identifier);
if startsWith(error_id, "EPIDEMIC:")
    status = "domain_failure";
elseif startsWith(error_id, "FORECAST_CLOSED:")
    status = "forecast_failure";
else
    rethrow(ME);
end
end

function projected_states = local_project_sirs_trajectory(stepper, initial_state, Rt_drivers)
%LOCAL_PROJECT_SIRS_TRAJECTORY Propagate a SIRS state along an H-by-1 driver sequence.
projected_states = zeros(numel(Rt_drivers), 3);
state = initial_state;

for h = 1:numel(Rt_drivers)
    [state, stepper] = sirs_step(stepper, state, Rt_drivers(h));
    projected_states(h, :) = state.';
end
end
