%PARTA_03_RUN_FORECASTS Run the independent Part A assessment forecasts.
%
%   Description:
%       Forecasts the final selected configuration of the active model/input
%       configuration on the assessment trajectories, which no selection
%       stage uses. Coefficients are re-estimated at every forecast origin,
%       and recognised forecast infeasibility is recorded per origin. Each
%       median Rt forecast and an origin-only Rt persistence driver are
%       propagated through the deterministic SIRS model from the true origin
%       state as an idealised infectious-population projection. When
%       selection recorded that no candidate is feasible, the assessment is
%       not applicable and no assessment artifact is produced.
%
%   Workflow:
%       1. Initialize the configured assessment run.
%       2. Load the final selected configuration, or stop when the
%          assessment is not applicable.
%       3. Load the assessment trajectories.
%       4. Forecast, project, and save the assessment results.
%
%   See also PARTA_CONFIG, PARTA_02_SELECT_HYPERPARAMETERS,
%            PARTA_04_EVALUATE_FORECASTS, BUILD_FORECAST_WINDOWS,
%            FORECAST_OPEN, FORECAST_CLOSED, SIRS_INIT, SIRS_STEP.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-11-27

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Independent Assessment Forecasts ===\n');

cfg        = partA_config();
model_type = cfg.run.model_type;
exo_mode   = cfg.run.exo_mode;

fprintf('Configuration: Model = %s | Exogenous Mode = %s\n', model_type, exo_mode);

forecast_dir = cfg.output.forecast_dir;
if ~exist(forecast_dir, 'dir')
    mkdir(forecast_dir);
end

file_suffix = model_type + "_" + exo_mode;
pop_size    = cfg.sirs.pop_size;

protocol = struct('model_type', model_type, 'exo_mode', exo_mode, 'horizon', cfg.forecast.horizon, 'num_draws', cfg.intervals.num_draws, 'wis_alphas', cfg.forecast.wis_alphas, 'base_seed', cfg.run.seed, 'vary_epidemic_seed', cfg.intervals.include_epidemic_seed_variation, 'infeasibility_ids', cfg.forecast.infeasibility_ids);

%% 2. Final Configuration
handover_path    = fullfile(cfg.output.model_selection_dir, "partA_02_global_hyperparameters_" + file_suffix + ".mat");
no_feasible_path = fullfile(cfg.output.model_selection_dir, "partA_02_no_feasible_candidate_" + file_suffix + ".mat");

if isfile(no_feasible_path) && ~isfile(handover_path)
    record = load(no_feasible_path);

    if ~isequaln(record.snapshot, cfg.snapshot.selection)
        error('PARTA_03:SelectionConfigMismatch', 'The no-feasible-candidate record %s does not match the current Part A selection protocol.', no_feasible_path);
    end

    fprintf('Assessment not applicable: selection %s found no feasible candidate in %s.\n', record.selection_id, record.failed_stage);
    fprintf('=== Part A Independent Assessment Forecasts Complete ===\n\n');
    return;
end

if ~isfile(handover_path) || isfile(no_feasible_path)
    error('PARTA_03:MissingSelectionArtifact', 'No unique selection outcome for %s: expected either the final configuration artifact %s or the no-feasible-candidate record %s. Run partA_02 first.', file_suffix, handover_path, no_feasible_path);
end

handover = load(handover_path);

if ~isequaln(handover.snapshot, cfg.snapshot.selection)
    error('PARTA_03:SelectionConfigMismatch', 'The final configuration artifact %s does not match the current Part A selection protocol.', handover_path);
end

final_configuration = handover.selected_configuration;

fprintf('Using final configuration %s (selection %s)\n', mat2str(final_configuration), handover.selection_id);

%% 3. Assessment Dataset Preparation
if exist(cfg.output.dataset_manifest, 'file') ~= 2
    error('PARTA_03:MissingDatasets', 'Missing dataset manifest %s. Run partA_01 first.', cfg.output.dataset_manifest);
end

manifest = load(cfg.output.dataset_manifest);

if ~isequaln(manifest.snapshot, cfg.snapshot.design)
    error('PARTA_03:DatasetDesignMismatch', 'The Part A datasets were generated under a different dataset design. Rerun with ./run_partA_pipeline.sh --fresh.');
end

assessment_rows = manifest.datasets(manifest.datasets.Role == "assessment", :);
num_assessment  = height(assessment_rows);

if exo_mode == "None"
    base_stepper = [];
else
    base_stepper = sirs_init(cfg.sirs, struct('solver', 'uds', 'seed', cfg.run.seed));
end

projection_stepper = sirs_init(cfg.sirs, struct('solver', 'uds', 'seed', cfg.run.seed));

%% 4. Assessment Forecast Loop
forecast_cells = cell(num_assessment, 1);

for j = 1:num_assessment
    loaded = load(fullfile(cfg.output.data_dir, assessment_rows.File(j)));

    fprintf('Processing trajectory %d/%d (%s)\n', j, num_assessment, loaded.dataset_id);

    window_data = build_forecast_windows(loaded.Rt_true, loaded.S_true, loaded.I_true, loaded.tspan, exo_mode, pop_size, cfg.forecast.min_window, cfg.forecast.step_size, cfg.forecast.horizon);

    if isempty(window_data)
        error('PARTA_03:NoForecastWindows', 'Trajectory %s has no forecast windows; check min_window, step_size, and horizon against the truth length.', loaded.dataset_id);
    end

    forecast_cells{j} = local_forecast_trajectory(final_configuration, loaded, window_data, base_stepper, projection_stepper, protocol, pop_size);
end

forecasts = vertcat(forecast_cells{:});

artifact = struct('stage', "assessment", 'model_type', model_type, 'exo_mode', exo_mode, 'configuration', final_configuration, 'configuration_role', "final", 'selection_id', handover.selection_id, 'wis_alphas', cfg.forecast.wis_alphas, 'horizon', cfg.forecast.horizon, 'seed_policy', cfg.forecast.seed_policy, 'dataset_ids', assessment_rows.DatasetId, 'forecasts', forecasts, 'snapshot', cfg.snapshot.forecast, 'created', string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));

artifact_path = fullfile(forecast_dir, "partA_03_forecast_assessment_" + file_suffix + ".mat");
save(artifact_path, '-struct', 'artifact');

status = vertcat(forecasts.status);
fprintf('Final configuration forecast at %d of %d assessment origins\n', sum(status == "ok"), numel(status));
fprintf('Assessment artifact saved to: %s\n', artifact_path);
fprintf('=== Part A Independent Assessment Forecasts Complete ===\n\n');

%% 5. Local Functions
function forecasts = local_forecast_trajectory(params, trajectory, window_data, base_stepper, projection_stepper, protocol, pop_size)
%LOCAL_FORECAST_TRAJECTORY Forecast and project one fixed configuration at every origin of one trajectory.
num_windows = numel(window_data);
H           = protocol.horizon;
K           = numel(protocol.wis_alphas);
S_true      = trajectory.S_true;
I_true      = trajectory.I_true;

forecasts = struct('dataset_id', trajectory.dataset_id, 'family', trajectory.family, 'stratum', trajectory.stratum, 'is_canonical', trajectory.is_canonical, 'seed_index', trajectory.seed_index, 'tspan', trajectory.tspan, 'Rt_true', trajectory.Rt_true, 'window_day', [window_data.window_day].', 'window_idx', [window_data.window_day_idx].', 'status', repmat("not_evaluated", num_windows, 1), 'error_id', strings(num_windows, 1), 'error_message', strings(num_windows, 1), 'origin_Rt', arrayfun(@(win) win.Rt_past(end), window_data), 'truth_Rt', [window_data.truth_Rt], 'forecast_median', nan(H, num_windows), 'forecast_lower', nan(H, K, num_windows), 'forecast_upper', nan(H, K, num_windows), 'aicc', nan(num_windows, 1), 'spectral_radius', nan(num_windows, 1), 'termination', strings(num_windows, 1), 'iteration_limit_reached', false(num_windows, 1), 'truth_S', nan(H, num_windows), 'truth_I', nan(H, num_windows), 'projected_S', nan(H, num_windows), 'projected_I', nan(H, num_windows), 'persistence_S', nan(H, num_windows), 'persistence_I', nan(H, num_windows));

for w = 1:num_windows
    win         = window_data(w);
    window_seed = protocol.base_seed + 10000 * trajectory.seed_index + w;
    idx_T       = win.window_day_idx;

    initial_state      = [S_true(idx_T); I_true(idx_T); pop_size - S_true(idx_T) - I_true(idx_T)];
    persistence_states = local_project_sirs_trajectory(projection_stepper, initial_state, repmat(win.Rt_past(end), H, 1));

    forecasts.truth_S(:, w)       = S_true(idx_T + 1 : idx_T + H);
    forecasts.truth_I(:, w)       = I_true(idx_T + 1 : idx_T + H);
    forecasts.persistence_S(:, w) = persistence_states(:, 1);
    forecasts.persistence_I(:, w) = persistence_states(:, 2);

    try
        if isempty(win.U_past)
            [ensemble, fit_info] = forecast_open(protocol.model_type, params, win.Rt_past, protocol.num_draws, H, window_seed);
        else
            [ensemble, fit_info] = forecast_closed(protocol.model_type, params, win.Rt_past, win.U_past, win.sirs_state, size(win.U_past, 2), protocol.num_draws, H, protocol.exo_mode, base_stepper, window_seed, window_seed + 1000000, protocol.vary_epidemic_seed);
        end
    catch ME
        if ~any(ME.identifier == protocol.infeasibility_ids)
            rethrow(ME);
        end

        forecasts.status(w)        = "infeasible";
        forecasts.error_id(w)      = ME.identifier;
        forecasts.error_message(w) = ME.message;
        continue;
    end

    median_Rt = median(ensemble, 2);

    projected_states = local_project_sirs_trajectory(projection_stepper, initial_state, [win.Rt_past(end); median_Rt(1:H - 1)]);

    forecasts.status(w)                  = "ok";
    forecasts.forecast_median(:, w)      = median_Rt;
    forecasts.forecast_lower(:, :, w)    = quantile(ensemble, protocol.wis_alphas.' / 2, 2);
    forecasts.forecast_upper(:, :, w)    = quantile(ensemble, 1 - protocol.wis_alphas.' / 2, 2);
    forecasts.aicc(w)                    = fit_info.AICc;
    forecasts.spectral_radius(w)         = fit_info.spectral_radius;
    forecasts.termination(w)             = fit_info.termination;
    forecasts.iteration_limit_reached(w) = fit_info.iteration_limit_reached;
    forecasts.projected_S(:, w)          = projected_states(:, 1);
    forecasts.projected_I(:, w)          = projected_states(:, 2);
end
end

function projected_states = local_project_sirs_trajectory(stepper, initial_state, Rt_drivers)
%LOCAL_PROJECT_SIRS_TRAJECTORY Propagate a SIRS state along an Rt trajectory.
projected_states = zeros(numel(Rt_drivers), 3);
state = initial_state;

for h = 1:numel(Rt_drivers)
    [state, stepper] = sirs_step(stepper, state, Rt_drivers(h));
    projected_states(h, :) = state.';
end
end
