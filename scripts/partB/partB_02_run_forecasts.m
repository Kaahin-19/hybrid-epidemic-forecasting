%PARTB_02_RUN_FORECASTS Generate persistence, oracle, AR, and ARX infectious-population forecasts.
%
%   Description:
%       For every saved Part B dataset and every forecast origin T on the
%       expanding-window grid, builds four future-Rt driver sequences and
%       propagates each through the same SIRS stepper from the same
%       estimated state X_hat_T. Rt_estimated(k) drives [t_k, t_{k+1}] and
%       is available at index k+1, so at origin index iT the driver of
%       [T, T+1] is unobserved and all H drivers are forecasts:
%           persistence : last valid Rt_estimated at or before iT-1, held;
%           oracle      : Rt_true(iT:iT+H-1), the prescribed driver (never
%                         true S or I);
%           AR          : bootstrap median of the Part A-selected AR/None
%                         model (FORECAST_OPEN) refitted to the contiguous
%                         valid estimates r0..iT-1 (at least min_window
%                         values);
%           ARX         : bootstrap median of the Part A-selected ARX/I model
%                         refitted to the same estimates r0..iT-1.
%                         FORECAST_CLOSED replays [T-1, T] from X_hat_{T-1},
%                         which reproduces X_hat_T exactly.
%       AR and ARX share the fit range, the window seed, and the number of
%       bootstrap draws; their selected orders stay fixed. Unavailable or
%       failed method forecasts are recorded per window and never replaced by
%       another method.
%
%   Workflow:
%       1. Initialize the forecast run and output paths.
%       2. Load the Part A AR/None and ARX/I selected configurations.
%       3. Load the Part B generation status.
%       4. Forecast each saved dataset and checkpoint every attempt.
%       5. Verify completion and persist the final forecast status.
%
%   See also PARTB_CONFIG, PARTB_01_PREPARE_DATASETS,
%            PARTB_03_EVALUATE_FORECASTS, FORECAST_OPEN, FORECAST_CLOSED,
%            SIRS_STEP.
%
% A. M. Kaahin 2026-07-18
% Modified: 2026-11-25

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Forecast Generation ===\n');

cfg          = partB_config();
pb           = cfg.partB;
data_dir     = pb.output.data_dir;
forecast_dir = pb.output.forecast_dir;
snapshot     = pb.snapshot;

if ~exist(forecast_dir, 'dir')
    mkdir(forecast_dir);
end

status_path = fullfile(forecast_dir, 'partB_02_forecast_status.mat');

%% 2. Load Part A AR/None and ARX/I Selections
selection = struct('ar', local_load_selection(cfg, pb.ar), 'arx', local_load_selection(cfg, pb.arx));
for ref = [selection.ar, selection.arx]
    fprintf('Using %s / %s selected configuration %s from %s\n', ref.model_type, ref.exo_mode, mat2str(ref.selected_configuration), ref.artifact_name);
end

%% 3. Load Part B Generation Status
generation_path = fullfile(data_dir, 'partB_01_generation_status.mat');
if ~exist(generation_path, 'file')
    error('PARTB_02:MissingGenerationStatus', 'Missing Part B generation status: %s. Run partB_01 first.', generation_path);
end

generation = load(generation_path);
local_require_snapshot(generation.snapshot, snapshot, generation_path);

if ~generation.run_completed
    error('PARTB_02:GenerationIncomplete', 'Part B dataset generation did not complete (run_completed is false).');
end

generation_status = generation.generation_status;
num_saved = sum([generation_status.status] == "saved");
fprintf('Forecasting %d saved datasets (%d generation attempts).\n', num_saved, numel(generation_status));

forecast_status = local_init_forecast_status(generation_status);
run_completed   = false;
save(status_path, 'forecast_status', 'run_completed', 'snapshot', 'selection');

%% 4. Forecast Execution Loop
forecast_stepper = sirs_init(cfg.sirs, struct('solver', 'uds', 'seed', cfg.run.seed), true);
scenario_ids     = [cfg.scenarios.id];

saved_index = 0;
for di = 1:numel(generation_status)
    entry = generation_status(di);

    if entry.status ~= "saved"
        continue;
    end

    saved_index = saved_index + 1;
    fprintf('Dataset %d/%d (%s)\n', saved_index, num_saved, entry.dataset_id);

    dataset = load(fullfile(data_dir, entry.output_filename));
    local_require_snapshot(dataset.snapshot, snapshot, entry.output_filename);

    scenario_index = find(scenario_ids == dataset.scenario_id);
    windows = local_forecast_dataset(dataset, cfg, selection, forecast_stepper, scenario_index);

    artifact = struct();
    artifact.dataset_id     = dataset.dataset_id;
    artifact.case_id        = dataset.case_id;
    artifact.scenario_id    = dataset.scenario_id;
    artifact.replicate_id   = dataset.replicate_id;
    artifact.source_dataset = entry.output_filename;
    artifact.method_ids     = pb.method_ids;
    artifact.selection      = selection;
    artifact.seed_policy    = "window_seed = run_seed + 10000*scenario_index + window_index; AR and ARX resample seed = window_seed; ARX epidemic seed = window_seed + 1e6";
    artifact.windows        = windows;
    artifact.snapshot       = snapshot;

    out_name = "partB_02_forecast_" + dataset.dataset_id + ".mat";
    save(fullfile(forecast_dir, out_name), '-struct', 'artifact');

    forecast_status(di).status          = "saved";
    forecast_status(di).output_filename = out_name;

    method_ok = [windows.status] == "ok";
    fprintf('  %d windows | ok %s = %s', numel(windows), strjoin(pb.method_ids', '/'), strjoin(string(sum(method_ok, 2))', '/'));
    for k = 1:numel(pb.matched_sets)
        fprintf(' | %s matched = %d', pb.matched_sets(k).set_id, sum(all(method_ok(ismember(pb.method_ids, pb.matched_sets(k).method_ids), :), 1)));
    end
    fprintf('\n');
    save(status_path, 'forecast_status', 'run_completed', 'snapshot', 'selection');
end

%% 5. Completion Check
run_completed = true;
save(status_path, 'forecast_status', 'run_completed', 'snapshot', 'selection');

fprintf('Saved forecast status to: %s\n', status_path);
fprintf('=== Part B Forecast Generation Complete ===\n\n');

%% 6. Local Functions
function local_require_snapshot(found, expected, label)
%LOCAL_REQUIRE_SNAPSHOT Reject an input produced under a different Part B configuration.
if ~isequal(found, expected)
    error('PARTB_02:IncompatibleArtifact', '%s was produced under a different Part B configuration. Rerun with ./run_partB_pipeline.sh --fresh.', label);
end
end

function selection = local_load_selection(cfg, reference)
%LOCAL_LOAD_SELECTION Load one Part A global selection and require a compatible selection protocol.
artifact_path = reference.selection_artifact;
loaded   = load(artifact_path);
expected = cfg.snapshot.selection;
expected.model_type = reference.model_type;
expected.exo_mode   = reference.exo_mode;

if ~local_selection_snapshot_compatible(loaded.snapshot, expected)
    error('PARTB_02:IncompatibleSelection', 'Part A selection artifact %s does not match the current %s/%s selection protocol.', artifact_path, expected.model_type, expected.exo_mode);
end

[~, name, ext] = fileparts(artifact_path);
selection = struct('model_type', reference.model_type, 'exo_mode', reference.exo_mode, 'selected_configuration', loaded.selected_configuration, 'artifact_name', string(name) + string(ext));
end

function compatible = local_selection_snapshot_compatible(saved, expected)
%LOCAL_SELECTION_SNAPSHOT_COMPATIBLE Compare the selection settings relevant to the model type only.
irrelevant_fields = {'max_state_order', 'state_diff_orders'};
if expected.model_type == "AR"
    irrelevant_fields = [irrelevant_fields, {'max_exo_order', 'max_exo_delay'}];
end
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
template = struct('case_id', "", 'scenario_id', "", 'replicate_id', "", 'dataset_id', "", 'status', "pending", 'output_filename', "");
forecast_status = repmat(template, numel(generation_status), 1);

for i = 1:numel(generation_status)
    forecast_status(i).case_id           = generation_status(i).case_id;
    forecast_status(i).scenario_id       = generation_status(i).scenario_id;
    forecast_status(i).replicate_id      = generation_status(i).replicate_id;
    forecast_status(i).dataset_id        = generation_status(i).dataset_id;

    if generation_status(i).status ~= "saved"
        forecast_status(i).status = "dataset_unavailable";
    end
end
end

function windows = local_forecast_dataset(dataset, cfg, selection, stepper, scenario_index)
%LOCAL_FORECAST_DATASET Persistence, oracle, AR, and ARX forecasts at every origin of one dataset.
%   drivers and I_pred are H-by-M and status and error_id are M-by-1, with
%   columns ordered as cfg.partB.method_ids.
method_ids  = cfg.partB.method_ids;
M           = numel(method_ids);
i_pers      = find(method_ids == "persistence");
i_oracle    = find(method_ids == "oracle");
i_ar        = find(method_ids == "ar");
i_arx       = find(method_ids == "arx");
H           = cfg.forecast.horizon;
pop_size    = cfg.sirs.pop_size;
min_history = cfg.forecast.min_window;
origin_days = cfg.forecast.min_window:cfg.forecast.step_size:(cfg.time.T_end - H);
rt_valid    = dataset.estimation_valid_mask;
state_valid = dataset.state_valid_mask;
X_hat       = [dataset.S_estimated, dataset.I_estimated, dataset.R_removed_estimated]';

template = struct('window_day', [], 'window_day_idx', [], 'X_hat_T', [], 'persistence_source_idx', NaN, 'fit_range', [NaN; NaN], ...
    'drivers', [], 'I_pred', [], 'status', [], 'error_id', [], 'truth_I', [], 'truth_Rt_drivers', []);
windows = repmat(template, numel(origin_days), 1);

for w = 1:numel(origin_days)
    iT = find(dataset.tspan == origin_days(w));

    drivers  = NaN(H, M);
    status   = repmat("ok", M, 1);
    error_id = repmat("", M, 1);

    windows(w).window_day       = origin_days(w);
    windows(w).window_day_idx   = iT;
    windows(w).X_hat_T          = X_hat(:, iT);
    windows(w).truth_I          = dataset.I_true(iT + 1:iT + H);
    windows(w).truth_Rt_drivers = dataset.Rt_true(iT:iT + H - 1);

    if ~state_valid(iT)
        windows(w).drivers  = drivers;
        windows(w).I_pred   = NaN(H, M);
        windows(w).status   = repmat("estimation_unavailable", M, 1);
        windows(w).error_id = error_id;
        continue;
    end

    persistence_idx = find(rt_valid(1:iT - 1), 1, 'last');
    if ~isempty(persistence_idx)
        windows(w).persistence_source_idx = persistence_idx;
        drivers(:, i_pers) = repmat(dataset.Rt_estimated(persistence_idx), H, 1);
    else
        status(i_pers) = "estimation_unavailable";
    end

    drivers(:, i_oracle) = dataset.Rt_true(iT:iT + H - 1);

    if ~rt_valid(iT - 1)
        status([i_ar, i_arx]) = "estimation_unavailable";
    else
        r0 = find(~rt_valid(1:iT - 1), 1, 'last') + 1;
        if isempty(r0)
            r0 = 1;
        end
        windows(w).fit_range = [r0; iT - 1];

        if iT - r0 < min_history
            status([i_ar, i_arx]) = "insufficient_history";
        else
            window_seed = cfg.run.seed + 10000 * scenario_index + w;
            try
                ensemble = forecast_open(selection.ar.model_type, selection.ar.selected_configuration, dataset.Rt_estimated(r0:iT - 1), cfg.intervals.num_draws, H, window_seed);
                drivers(:, i_ar) = median(ensemble, 2);
            catch ME
                [status(i_ar), error_id(i_ar)] = local_classify_failure(ME);
            end
            try
                ensemble = forecast_closed(selection.arx.model_type, selection.arx.selected_configuration, dataset.Rt_estimated(r0:iT - 1), dataset.I_estimated(r0:iT - 1) / pop_size, X_hat(:, iT - 1), 1, cfg.intervals.num_draws, H, selection.arx.exo_mode, stepper, window_seed, window_seed + 1000000, cfg.intervals.include_epidemic_seed_variation);
                drivers(:, i_arx) = median(ensemble, 2);
            catch ME
                [status(i_arx), error_id(i_arx)] = local_classify_failure(ME);
            end
        end
    end

    I_pred = NaN(H, M);
    for m = 1:M
        if status(m) ~= "ok"
            drivers(:, m) = NaN;
            continue;
        end

        try
            I_pred(:, m) = local_project_infectious(stepper, X_hat(:, iT), drivers(:, m));
        catch ME
            [status(m), error_id(m)] = local_classify_failure(ME);
        end
    end

    windows(w).drivers  = drivers;
    windows(w).I_pred   = I_pred;
    windows(w).status   = status;
    windows(w).error_id = error_id;
end
end

function [status, error_id] = local_classify_failure(ME)
%LOCAL_CLASSIFY_FAILURE Map documented forecasting failures to statuses; rethrow anything else.
error_id = string(ME.identifier);
if startsWith(error_id, "EPIDEMIC:")
    status = "domain_failure";
elseif startsWith(error_id, "FORECAST_OPEN:") || startsWith(error_id, "FORECAST_CLOSED:")
    status = "forecast_failure";
else
    rethrow(ME);
end
end

function I_pred = local_project_infectious(stepper, initial_state, Rt_drivers)
%LOCAL_PROJECT_INFECTIOUS Propagate a SIRS state along an H-by-1 driver sequence and return I.
I_pred = zeros(numel(Rt_drivers), 1);
state  = initial_state;

for h = 1:numel(Rt_drivers)
    [state, stepper] = sirs_step(stepper, state, Rt_drivers(h));
    I_pred(h) = state(2);
end
end
