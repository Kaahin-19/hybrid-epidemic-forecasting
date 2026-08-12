%PARTB_02_RUN_FORECASTS Run Part A models on successful Part B datasets.
%
%   Description:
%       Runs the frozen Part A selected model configurations on the successful
%       Part B robustness datasets. The requested model families are chosen
%       through cfg.partB.run.model_types. For every requested model and
%       exogenous-input combination the script loads the Part A model-selection
%       artifact and reuses its selected_configuration without any further
%       model-order selection. Each dataset is forecast with the same
%       expanding-window protocol as Part A: the model is trained on the
%       model-visible Rt_model_input (respecting its dataset validity mask)
%       while the saved truth windows are taken from the latent Rt_true.
%
%   Workflow:
%       1. Resolve the requested model/exogenous combinations.
%       2. Load the available Part A selected configurations and report gaps.
%       3. Load the Part B generation status and select successful datasets.
%       4. Forecast each dataset with every available combination.
%       5. Save one forecast artifact per dataset/combination and checkpoint
%          a forecast-execution status artifact after every attempt.
%
%   See also PARTB_CONFIG, PARTA_03_RUN_FORECASTS, BUILD_FORECAST_WINDOWS, ...
%            FORECAST_OPEN, FORECAST_CLOSED.
%
% A. M. Kaahin 2026-07-18
% Modified: 2026-08-12

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Forecast Generation ===\n');

cfg = partB_config();

model_types  = cfg.partB.run.model_types;
data_dir     = cfg.partB.output.data_dir;
forecast_dir = cfg.partB.output.forecast_dir;
base_seed    = cfg.run.seed;
num_draws    = cfg.intervals.num_draws;
horizon      = cfg.forecast.horizon;
wis_alphas   = cfg.forecast.wis_alphas;
vary         = cfg.intervals.include_epidemic_seed_variation;

if ~exist(forecast_dir, 'dir')
    mkdir(forecast_dir);
end

status_path = fullfile(forecast_dir, 'partB_02_forecast_status.mat');

%% 2. Resolve Requested Combinations
combos = local_resolve_combinations(model_types);

%% 3. Load Part A Selected Configurations
[available, availability_report] = local_load_selections(cfg, combos);

fprintf('Requested %d model/exogenous combinations:\n', numel(availability_report));
for r = 1:numel(availability_report)
    rep = availability_report(r);
    if rep.available
        fprintf('  [available]   %s / %s -> selected configuration %s\n', rep.model_type, rep.exo_mode, mat2str(rep.selected_configuration));
    else
        fprintf('  [unavailable] %s / %s -> %s\n', rep.model_type, rep.exo_mode, rep.reason);
    end
end

if isempty(available)
    error('PARTB_02:NoAvailableSelection', 'None of the requested model/exogenous combinations have a compatible Part A selection artifact.');
end

%% 4. Load Part B Generation Status
status_file = fullfile(data_dir, 'partB_01_generation_status.mat');
if ~exist(status_file, 'file')
    error('PARTB_02:MissingGenerationStatus', 'Missing Part B generation status: %s. Run partB_01 first.', status_file);
end

generation = load(status_file);
if ~isfield(generation, 'run_completed') || ~generation.run_completed
    error('PARTB_02:GenerationIncomplete', 'Part B dataset generation did not complete (run_completed is not true).');
end

saved = local_saved_datasets(generation.generation_status);
if isempty(saved)
    error('PARTB_02:NoSavedDatasets', 'No Part B generation-status entries are marked "saved".');
end

fprintf('Forecasting %d successful datasets x %d available combinations.\n', numel(saved), numel(available));

%% 5. Preinitialize Forecast Status
forecast_status = local_init_forecast_status(saved, available);
local_save_status(status_path, forecast_status, availability_report, false);

%% 6. Forecast Execution Loop
base_stepper = sirs_init(cfg.sirs, struct('solver', 'uds', 'seed', base_seed));

for di = 1:numel(saved)
    entry        = saved(di);
    dataset_path = fullfile(data_dir, char(entry.output_filename));

    fprintf('Dataset %d/%d (%s)\n', di, numel(saved), entry.output_filename);

    if ~exist(dataset_path, 'file')
        local_save_status(status_path, forecast_status, availability_report, false);
        error('PARTB_02:MissingDataset', 'Generation status marks %s as "saved" but the dataset file is missing: %s.', entry.output_filename, dataset_path);
    end

    dataset = load(dataset_path);
    scenario_index = find(string({cfg.scenarios.id}) == string(dataset.scenario_id));

    if ~isfield(dataset, 'snapshot') || ~isfield(dataset.snapshot, 'observation_noise') || ~isequal(dataset.snapshot.observation_noise, cfg.partB.snapshot.observation_noise) || ~isequal(dataset.snapshot.seir, cfg.partB.snapshot.seir)
        local_save_status(status_path, forecast_status, availability_report, false);
        error('PARTB_02:IncompatibleDatasetSnapshot', 'Dataset %s does not match the current Part B dataset configuration. Regenerate Part B datasets with partB_01.', entry.output_filename);
    end

    [v0, v1] = local_longest_valid_run(dataset.Rt_model_input_valid_mask);

    for ci = 1:numel(available)
        k     = (di - 1) * numel(available) + ci;
        combo = available(ci);

        try
            window_data = local_build_windows(dataset, combo.exo_mode, v0, v1, cfg);

            if isempty(window_data)
                forecast_status(k).status = "no_windows";
                fprintf('  %s / %s ... no valid forecast windows\n', combo.model_type, combo.exo_mode);
            else
                results = local_run_forecasts(combo.model_type, combo.exo_mode, combo.selected_configuration, window_data, base_stepper, base_seed, num_draws, horizon, wis_alphas, vary, scenario_index);
                artifact = local_build_artifact(dataset, entry, combo, [v0, v1], wis_alphas, results, cfg);

                out_name = sprintf('partB_02_forecast_%s_%s_%s_%s_%s.mat', entry.case_id, entry.scenario_id, entry.replicate_id, combo.model_type, combo.exo_mode);
                save(fullfile(forecast_dir, out_name), '-struct', 'artifact');

                forecast_status(k).status          = "saved";
                forecast_status(k).output_filename = string(out_name);
                fprintf('  %s / %s ... saved (%d windows)\n', combo.model_type, combo.exo_mode, numel(results));
            end
        catch ME
            if strcmp(ME.identifier, 'EPIDEMIC:SusceptibleBelowThreshold')
                forecast_status(k).status        = "domain_failure";
                forecast_status(k).error_id      = string(ME.identifier);
                forecast_status(k).error_message = string(ME.message);
                fprintf('  %s / %s ... domain failure\n', combo.model_type, combo.exo_mode);
            else
                local_save_status(status_path, forecast_status, availability_report, false);
                rethrow(ME);
            end
        end

        local_save_status(status_path, forecast_status, availability_report, false);
    end
end

%% 7. Completion Check
local_save_status(status_path, forecast_status, availability_report, true);

fprintf('Saved forecast status to: %s\n', status_path);
fprintf('=== Part B Forecast Generation Complete ===\n\n');

%% 8. Local Functions
function combos = local_resolve_combinations(model_types)
%LOCAL_RESOLVE_COMBINATIONS Expand requested model families into model/exogenous combinations.
valid_models = ["AR", "ARX", "N4SID", "SSEST"];
template     = struct('model_type', "", 'exo_mode', "");
combos       = repmat(template, 0, 1);

for i = 1:numel(model_types)
    model = model_types(i);
    if ~any(model == valid_models)
        error('PARTB_02:InvalidModelType', 'Unsupported model type in cfg.partB.run.model_types: %s.', model);
    end

    exo_modes = local_valid_exo_modes(model);
    for j = 1:numel(exo_modes)
        combos(end + 1, 1) = struct('model_type', model, 'exo_mode', exo_modes(j)); %#ok<AGROW>
    end
end
end

function exo_modes = local_valid_exo_modes(model_type)
%LOCAL_VALID_EXO_MODES Valid exogenous-input modes for a model family (matches Part A).
switch model_type
    case "AR"
        exo_modes = "None";
    case "ARX"
        exo_modes = ["S", "I", "Both"];
    case {"N4SID", "SSEST"}
        exo_modes = ["None", "S", "I", "Both"];
end
end

function [available, report] = local_load_selections(cfg, combos)
%LOCAL_LOAD_SELECTIONS Load Part A selected configurations and build an availability report.
report_template = struct('model_type', "", 'exo_mode', "", 'available', false, 'reason', "", 'artifact_name', "", 'selected_configuration', []);
report          = repmat(report_template, numel(combos), 1);

for i = 1:numel(combos)
    model = combos(i).model_type;
    exo   = combos(i).exo_mode;

    artifact_name = sprintf('partA_02_global_hyperparameters_%s_%s.mat', model, exo);
    artifact_path = fullfile(cfg.output.model_selection_dir, artifact_name);

    report(i).model_type    = model;
    report(i).exo_mode      = exo;
    report(i).artifact_name = string(artifact_name);

    if ~exist(artifact_path, 'file')
        report(i).reason = "missing selection artifact";
        continue;
    end

    selection = load(artifact_path);
    if ~isfield(selection, 'selected_configuration') || ~isfield(selection, 'snapshot')
        report(i).reason = "invalid selection artifact";
        continue;
    end

    expected            = cfg.snapshot.selection;
    expected.model_type = model;
    expected.exo_mode   = exo;
    if ~isequaln(selection.snapshot, expected)
        report(i).reason = "incompatible selection snapshot";
        continue;
    end

    report(i).available              = true;
    report(i).reason                 = "available";
    report(i).selected_configuration = selection.selected_configuration;
end

available = report([report.available]);
end

function saved = local_saved_datasets(generation_status)
%LOCAL_SAVED_DATASETS Successful datasets in deterministic filename order.
is_saved = arrayfun(@(e) string(e.status) == "saved", generation_status);
saved    = generation_status(is_saved);

names = strings(numel(saved), 1);
for i = 1:numel(saved)
    names(i) = string(saved(i).output_filename);
end
[~, order] = sort(names);
saved = saved(order);
end

function forecast_status = local_init_forecast_status(saved, available)
%LOCAL_INIT_FORECAST_STATUS Preinitialize one pending attempt per dataset/combination.
template        = struct('case_id', "", 'scenario_id', "", 'replicate_id', "", 'model_type', "", 'exo_mode', "", 'status', "pending", 'output_filename', "", 'error_id', "", 'error_message', "");
forecast_status = repmat(template, numel(saved) * numel(available), 1);

for di = 1:numel(saved)
    for ci = 1:numel(available)
        k = (di - 1) * numel(available) + ci;
        forecast_status(k).case_id      = string(saved(di).case_id);
        forecast_status(k).scenario_id  = string(saved(di).scenario_id);
        forecast_status(k).replicate_id = string(saved(di).replicate_id);
        forecast_status(k).model_type   = available(ci).model_type;
        forecast_status(k).exo_mode     = available(ci).exo_mode;
    end
end
end

function [v0, v1] = local_longest_valid_run(valid_mask)
%LOCAL_LONGEST_VALID_RUN First and last index of the longest contiguous valid run.
mask   = logical(valid_mask(:));
edges  = diff([false; mask; false]);
starts = find(edges == 1);
stops  = find(edges == -1) - 1;

if isempty(starts)
    v0 = [];
    v1 = [];
    return;
end

[~, longest] = max(stops - starts);
v0 = starts(longest);
v1 = stops(longest);
end

function window_data = local_build_windows(dataset, exo_mode, v0, v1, cfg)
%LOCAL_BUILD_WINDOWS Expanding windows over the valid model-input range with Rt_true truth.
if isempty(v0)
    window_data = [];
    return;
end

horizon     = cfg.forecast.horizon;
tspan_full  = dataset.tspan;
tspan_valid = tspan_full(v0:v1);
tspan_local = tspan_valid - tspan_valid(1);

window_data = build_forecast_windows(dataset.Rt_model_input(v0:v1), dataset.S_model_input(v0:v1), dataset.I_model_input(v0:v1), tspan_local, exo_mode, cfg.sirs.pop_size, cfg.forecast.min_window, cfg.forecast.step_size, horizon);

for w = 1:numel(window_data)
    local_origin_idx = window_data(w).window_day_idx;
    origin_idx = v0 + local_origin_idx - 1;

    window_data(w).window_day     = tspan_full(origin_idx);
    window_data(w).window_day_idx = origin_idx;
    window_data(w).time_horizon   = tspan_full(origin_idx + 1 : origin_idx + horizon);
    window_data(w).truth_Rt       = dataset.Rt_true(origin_idx + 1 : origin_idx + horizon);
end
end

function results = local_run_forecasts(model_type, exo_mode, params, window_data, base_stepper, base_seed, num_draws, horizon, wis_alphas, vary, scenario_index)
%LOCAL_RUN_FORECASTS Frozen-configuration forecasts for one dataset/combination.
template = struct('window_day', [], 'window_day_idx', [], 'time_horizon', [], 'truth_Rt_window', [], 'forecast_median', [], 'forecast_lower', [], 'forecast_upper', []);
results  = repmat(template, numel(window_data), 1);

for w = 1:numel(window_data)
    win = window_data(w);

    window_seed = base_seed + 10000 * scenario_index + w;
    r_seed      = window_seed;

    if isempty(win.U_past)
        ens = forecast_open(model_type, params, win.Rt_past, num_draws, horizon, r_seed);
    else
        e_seed = window_seed + 1000000;
        ens = forecast_closed(model_type, params, win.Rt_past, win.U_past, win.sirs_state, size(win.U_past, 2), num_draws, horizon, exo_mode, base_stepper, r_seed, e_seed, vary);
    end

    Rt_pred = median(ens, 2);
    lower   = quantile(ens, wis_alphas(:).' / 2, 2);
    upper   = quantile(ens, 1 - wis_alphas(:).' / 2, 2);

    valid = numel(Rt_pred) == horizon && all(isfinite(Rt_pred)) && all(Rt_pred > 0) && all(isfinite(lower(:))) && all(isfinite(upper(:))) && all(lower(:) <= upper(:));

    if ~valid
        error('PARTB_02:UnscoreableWindow', 'Forecast window produced invalid intervals.');
    end

    results(w).window_day      = win.window_day;
    results(w).window_day_idx  = win.window_day_idx;
    results(w).time_horizon    = win.time_horizon;
    results(w).truth_Rt_window = win.truth_Rt;
    results(w).forecast_median = Rt_pred;
    results(w).forecast_lower  = lower;
    results(w).forecast_upper  = upper;
end
end

function artifact = local_build_artifact(dataset, entry, combo, valid_range, wis_alphas, results, cfg)
%LOCAL_BUILD_ARTIFACT Assemble one Part B forecast artifact.
snapshot            = cfg.snapshot.forecast;
snapshot.model_type = combo.model_type;
snapshot.exo_mode   = combo.exo_mode;

artifact                           = struct();
artifact.case_id                   = dataset.case_id;
artifact.case_name                 = dataset.case_name;
artifact.scenario_id               = dataset.scenario_id;
artifact.scenario_name             = dataset.scenario_name;
artifact.replicate_id              = dataset.replicate_id;
artifact.replicate_index           = dataset.replicate_index;
artifact.model_type                = combo.model_type;
artifact.exo_mode                  = combo.exo_mode;
artifact.selected_configuration    = combo.selected_configuration;
artifact.selection_artifact        = combo.artifact_name;
artifact.source_dataset            = string(entry.output_filename);
artifact.model_input_valid_range   = valid_range;
artifact.wis_alphas                = wis_alphas;
artifact.tspan                     = dataset.tspan;
artifact.Rt_true                   = dataset.Rt_true;
artifact.Rt_model_input            = dataset.Rt_model_input;
artifact.Rt_model_input_valid_mask = dataset.Rt_model_input_valid_mask;
artifact.snapshot                  = snapshot;
artifact.results                   = results;
end

function local_save_status(status_path, forecast_status, availability_report, run_completed)
%LOCAL_SAVE_STATUS Checkpoint the forecast-execution status artifact.
status_out = struct('forecast_status', {forecast_status}, 'availability_report', {availability_report}, 'run_completed', run_completed);
save(status_path, '-struct', 'status_out');
end