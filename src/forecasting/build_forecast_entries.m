function scenario_data = build_forecast_entries(cfg, exo_mode, source_spec)
%BUILD_FORECAST_ENTRIES Build expanding-window forecast entries.
%
%   Syntax:
%       scenario_data = build_forecast_entries(cfg, exo_mode)
%       scenario_entry = build_forecast_entries(cfg, exo_mode, source_spec)
%
%   Description:
%       Builds the normalized scenario-entry structure consumed by the shared
%       expanding-window forecast dispatcher. The default call loads Part A
%       synthetic truth artifacts. Optional source specifications adapt Part B
%       robustness artifacts and Part C processed real-data artifacts into the
%       same forecast-entry format.
%
%   Inputs:
%       cfg         - Part A, Part B, or Part C configuration structure.
%       exo_mode    - Exogenous mode for the forecast model.
%       source_spec - Optional structure with mode ("partA", "partB", or
%                     "partC") and source data for single-entry modes.
%
%   Outputs:
%       scenario_data - Structure array for Part A, or a single scenario-entry
%                       structure for Part B/Part C source specifications.
%
%   See also RUN_EXPANDING_WINDOW_FORECAST, PARTA_CONFIG, PARTB_CONFIG,
%            PARTC_CONFIG.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-11

    %% 1. Source Dispatch
    if nargin < 3 || isempty(source_spec)
        source_spec = struct('mode', "partA");
    end

    switch local_source_mode(source_spec)
        case "partA"
            scenario_data = local_build_partA_dataset(cfg, exo_mode);
        case "partB"
            scenario_data = local_build_partB_entry(cfg, exo_mode, ...
                local_source_data(source_spec));
        case "partC"
            scenario_data = local_build_partC_entry(cfg, exo_mode, ...
                local_source_data(source_spec));
        otherwise
            error('FORECAST:UnknownDatasetMode', ...
                'Unsupported forecast dataset mode: %s.', source_spec.mode);
    end
end

function scenario_data = local_build_partA_dataset(cfg, exo_mode)
%LOCAL_BUILD_PARTA_DATASET Load Part A synthetic forecast entries.
    data_dir = cfg.output.data_dir;
    file_list = dir(fullfile(data_dir, 'partA_01_truth_*.mat'));

    if isempty(file_list)
        error('FORECAST:NoData', ...
            'No synthetic truth files found in %s. Run partA_01 first.', data_dir);
    end

    scenario_data = repmat(local_empty_scenario_entry(), length(file_list), 1);
    for i = 1:length(file_list)
        loaded = load(fullfile(data_dir, file_list(i).name));
        scenario_data(i) = local_build_entry_from_signals( ...
            local_partA_signals(loaded, cfg, exo_mode));

        fprintf('Prepared scenario %d/%d (%s)\n', ...
            i, length(file_list), loaded.scenario_id);
    end
end

function scenario_entry = local_build_partB_entry(cfg, exo_mode, loaded)
%LOCAL_BUILD_PARTB_ENTRY Adapt one Part B truth artifact.
    scenario_entry = local_build_entry_from_signals( ...
        local_partB_signals(loaded, cfg, exo_mode));
end

function scenario_entry = local_build_partC_entry(cfg, exo_mode, processed)
%LOCAL_BUILD_PARTC_ENTRY Adapt one Part C processed real-data artifact.
    scenario_entry = local_build_entry_from_signals( ...
        local_partC_signals(processed, cfg, exo_mode));
end

function signals = local_partA_signals(loaded, cfg, exo_mode)
%LOCAL_PARTA_SIGNALS Map Part A truth fields into forecast signals.
    Rt_model_input = double(loaded.Rt_true(:));
    [S_model_input, I_model_input, U_true] = ...
        local_partA_state_and_covariates(loaded, cfg, exo_mode);
    horizon = cfg.forecast.horizon;
    windows = cfg.forecast.min_window : cfg.forecast.step_size : ...
        (length(loaded.Rt_true) - horizon);

    signals = local_empty_signals();
    signals.scenario_id = string(loaded.scenario_id);
    signals.scenario_name = string(loaded.scenario_name);
    signals.Rt_model_input = Rt_model_input;
    signals.Rt_evaluation_target = Rt_model_input;
    signals.tspan = double(loaded.tspan(:));
    signals.S_model_input = S_model_input;
    signals.I_model_input = I_model_input;
    signals.U_true = U_true;
    signals.sirs_cfg = cfg.sirs;
    signals.horizon = horizon;
    signals.windows = windows;
end

function signals = local_partB_signals(loaded, cfg, exo_mode)
%LOCAL_PARTB_SIGNALS Map Part B model/evaluation fields into forecast signals.
    horizon = local_effective_horizon(cfg);
    Rt_model_input = double(loaded.Rt_model_input(:));
    Rt_target = double(loaded.Rt_evaluation_target(:));
    pop_size = local_population_size(loaded, cfg);
    I_model_input = double(loaded.I_model_input(:));
    S_model_input = double(loaded.S_model_input(:));
    U_true = local_partB_covariates(I_model_input, pop_size, exo_mode);

    windows = cfg.forecast.min_window : cfg.forecast.step_size : ...
        (numel(Rt_model_input) - horizon);
    if local_smoke_enabled(cfg)
        windows = windows(1:min(numel(windows), cfg.smoke_test.max_windows));
    end

    signals = local_empty_signals();
    signals.scenario_id = string(loaded.scenario_id);
    signals.scenario_name = string(loaded.scenario_name);
    signals.Rt_model_input = Rt_model_input;
    signals.Rt_evaluation_target = Rt_target;
    signals.tspan = double(loaded.tspan(:));
    signals.S_model_input = S_model_input;
    signals.I_model_input = I_model_input;
    signals.U_true = U_true;
    signals.sirs_cfg = cfg.sirs_projection;
    signals.horizon = horizon;
    signals.windows = windows;
end

function signals = local_partC_signals(processed, cfg, exo_mode)
%LOCAL_PARTC_SIGNALS Map Part C real-data fields into forecast signals.
    horizon = cfg.forecast.horizon;
    Rt_model_input = double(processed.Rt_est(:));
    Rt_target = Rt_model_input;
    tspan = double(processed.t(:));

    [S_model_input, I_model_input, U_true, compatibility_metadata] = ...
        local_partC_compatibility_state(processed.I_scaled, cfg, exo_mode);
    windows = cfg.forecast.min_window : cfg.forecast.step_size : ...
        (tspan(end) - horizon);

    signals = local_empty_signals();
    signals.scenario_id = "real";
    signals.scenario_name = "WHO-derived Sweden Rt estimate";
    signals.Rt_model_input = Rt_model_input;
    signals.Rt_evaluation_target = Rt_target;
    signals.tspan = tspan;
    signals.S_model_input = S_model_input;
    signals.I_model_input = I_model_input;
    signals.U_true = U_true;
    signals.sirs_cfg = cfg.sirs_projection;
    signals.horizon = horizon;
    signals.windows = windows(:);
    signals.compatibility_metadata = compatibility_metadata;
end

function scenario_entry = local_build_entry_from_signals(signals)
%LOCAL_BUILD_ENTRY_FROM_SIGNALS Assemble the shared scenario-entry structure.
    % Forecast history (Rt_past) is drawn from the model-visible Rt_history_input
    % (Rt_model_input). The future scoring truth is the separate evaluation
    % target signals.Rt_evaluation_target, applied to truth_Rt below. For Part B
    % observation-noise cases these two differ: history is incidence-estimated,
    % evaluation is latent Rt_true.
    scenario_inputs = struct( ...
        'Rt_history_input', signals.Rt_model_input, ...
        'tspan', signals.tspan, ...
        'S_true', signals.S_model_input, ...
        'I_true', signals.I_model_input, ...
        'U_true', signals.U_true);

    scenario_entry = local_empty_scenario_entry();
    scenario_entry.scenario_id = signals.scenario_id;
    scenario_entry.scenario_name = signals.scenario_name;
    scenario_entry.num_exo = size(signals.U_true, 2);
    scenario_entry.windows = signals.windows;
    scenario_entry.window_data = local_build_window_data(scenario_inputs, ...
        signals.Rt_evaluation_target, signals.windows, signals.horizon, ...
        signals.sirs_cfg);
    scenario_entry.Rt_true = signals.Rt_evaluation_target;
    scenario_entry.Rt_model_input = signals.Rt_model_input;
    scenario_entry.tspan = signals.tspan;
    scenario_entry.U_true = signals.U_true;
    scenario_entry.S_model_input = signals.S_model_input;
    scenario_entry.I_model_input = signals.I_model_input;
    scenario_entry.compatibility_metadata = signals.compatibility_metadata;
end

function window_data = local_build_window_data(scenario_inputs, target_Rt, ...
    windows, horizon, sirs_cfg)
%LOCAL_BUILD_WINDOW_DATA Build all expanding-window entries.
    if isempty(windows)
        window_data = struct([]);
        return;
    end

    window_data = repmat(local_prepare_window_data(scenario_inputs, ...
        windows(1), horizon, sirs_cfg), numel(windows), 1);
    for w = 1:numel(windows)
        window_data(w) = local_prepare_window_data(scenario_inputs, ...
            windows(w), horizon, sirs_cfg);
        if window_data(w).is_valid_window
            idx = window_data(w).horizon_indices;
            if max(idx) <= numel(target_Rt)
                window_data(w).truth_Rt = target_Rt(idx);
            else
                window_data(w).is_valid_window = false;
            end
        end
    end
end

function window_entry = local_prepare_window_data(scenario_inputs, ...
    window_endpoint, horizon, sirs_cfg)
%LOCAL_PREPARE_WINDOW_DATA Build one expanding-window forecast input.
    window_entry = struct( ...
        'window_day', window_endpoint, ...
        'window_day_idx', [], ...
        'horizon_indices', [], ...
        't_future', [], ...
        'Rt_past', [], ...
        'truth_Rt', [], ...
        'U_past', [], ...
        'sirs_state', [], ...
        'is_valid_window', false);

    idx_T = find(scenario_inputs.tspan == window_endpoint, 1);
    if isempty(idx_T)
        return;
    end

    idx_end = idx_T + horizon;
    window_entry.window_day_idx  = idx_T;
    window_entry.horizon_indices = (idx_T + 1 : idx_end)';
    window_entry.t_future        = scenario_inputs.tspan(idx_T + 1 : idx_end);
    window_entry.Rt_past         = scenario_inputs.Rt_history_input(1:idx_T);
    % Placeholder future truth; overwritten with the evaluation target in
    % local_build_window_data for valid windows.
    window_entry.truth_Rt        = scenario_inputs.Rt_history_input(idx_T + 1 : idx_end);

    [window_entry.U_past, window_entry.sirs_state] = ...
        local_prepare_exogenous_inputs(scenario_inputs, idx_T, sirs_cfg);

    window_entry.is_valid_window = ...
        ~isempty(window_entry.Rt_past) && ~isempty(window_entry.truth_Rt);
end

function [U_past, sirs_state] = local_prepare_exogenous_inputs(data, idx_T, sirs_cfg)
%LOCAL_PREPARE_EXOGENOUS_INPUTS Build historical covariates and current state.
    if isempty(data.U_true)
        U_past = [];
        sirs_state = [];
        return;
    end

    U_past = data.U_true(1:idx_T, :);

    current_I = data.I_true(idx_T);
    current_S = data.S_true(idx_T);
    current_R = sirs_cfg.pop_size - current_S - current_I;
    sirs_state = [current_S, current_I, current_R];
end

function [S_model_input, I_model_input, U_true] = ...
    local_partA_state_and_covariates(loaded, cfg, exo_mode)
%LOCAL_PARTA_STATE_AND_COVARIATES Build Part A covariate inputs.
    S_model_input = double(loaded.S_true(:));
    I_model_input = double(loaded.I_true(:));
    scaled_S = S_model_input / cfg.sirs.pop_size;
    scaled_I = I_model_input / cfg.sirs.pop_size;

    switch string(exo_mode)
        case "None"
            U_true = [];
        case "S"
            U_true = scaled_S;
        case "I"
            U_true = scaled_I;
        case "Both"
            U_true = [scaled_S, scaled_I];
        otherwise
            error('FORECAST:UnknownExoMode', ...
                'Unsupported EXO_MODE: %s', exo_mode);
    end
end

function U_true = local_partB_covariates(I_model_input, pop_size, exo_mode)
%LOCAL_PARTB_COVARIATES Build Part B covariate inputs.
    switch char(string(exo_mode))
        case 'None'
            U_true = [];
        case 'I'
            U_true = I_model_input / pop_size;
        otherwise
            error('FORECAST:UnsupportedExoMode', ...
                'Part B robustness ladder evaluates only None and I exogenous modes.');
    end
end

function [S_model_input, I_model_input, U_true, metadata] = ...
    local_partC_compatibility_state(I_scaled, cfg, exo_mode)
%LOCAL_PARTC_COMPATIBILITY_STATE Build the explicit Part C ARX state proxy.
    I_scaled = double(I_scaled(:));
    pop_size = double(cfg.sirs_projection.pop_size);
    max_fraction = 1 - (1 / pop_size);
    I_fraction = min(max(I_scaled, 0), max_fraction);
    I_model_input = I_fraction * pop_size;
    S_model_input = pop_size - I_model_input;
    S_model_input = max(S_model_input, 1);
    total_si = S_model_input + I_model_input;
    S_model_input = S_model_input .* (pop_size ./ total_si);
    I_model_input = I_model_input .* (pop_size ./ total_si);

    switch char(string(exo_mode))
        case 'None'
            U_true = [];
        case 'I'
            U_true = I_scaled;
        otherwise
            error('FORECAST:UnsupportedExoMode', ...
                'Part C supports only None and I exogenous modes.');
    end

    metadata = struct();
    metadata.Rt_model_input = "Rt_est";
    metadata.Rt_evaluation_target = "Rt_est";
    metadata.I_model_input = ...
        "I_scaled mapped to a normalized compatibility state";
    metadata.S_model_input = ...
        "Neutral complement to I_scaled for closed-loop ARX compatibility only";
    metadata.U_true = "I_scaled for ARX/I; empty for AR/None";
    metadata.pop_size = pop_size;
    metadata.max_state_fraction = max_fraction;
    metadata.biological_interpretation = ...
        "The Part C S/I state is not an observed Swedish susceptible trajectory.";
end

function horizon = local_effective_horizon(cfg)
%LOCAL_EFFECTIVE_HORIZON Resolve full or smoke-test horizon.
    horizon = cfg.forecast.horizon;
    if local_smoke_enabled(cfg)
        horizon = min(horizon, cfg.smoke_test.horizon);
    end
end

function pop_size = local_population_size(loaded, cfg)
%LOCAL_POPULATION_SIZE Resolve scaling population for model inputs.
    if isfield(loaded, 'model_params') && isfield(loaded.model_params, 'pop_size')
        pop_size = double(loaded.model_params.pop_size);
    else
        pop_size = double(cfg.sirs_projection.pop_size);
    end
end

function enabled = local_smoke_enabled(cfg)
%LOCAL_SMOKE_ENABLED Check optional Part B smoke-test state.
    enabled = isfield(cfg, 'smoke_test') && isfield(cfg.smoke_test, 'enabled') && ...
        logical(cfg.smoke_test.enabled);
end

function mode = local_source_mode(source_spec)
%LOCAL_SOURCE_MODE Resolve source-spec mode with Part A default.
    if ~isstruct(source_spec) || ~isfield(source_spec, 'mode')
        mode = "partA";
    else
        mode = string(source_spec.mode);
    end
end

function data = local_source_data(source_spec)
%LOCAL_SOURCE_DATA Read source data from a source specification.
    if ~isstruct(source_spec) || ~isfield(source_spec, 'data')
        error('FORECAST:MissingSourceData', ...
            'Part B and Part C forecast dataset modes require source_spec.data.');
    end
    data = source_spec.data;
end

function signals = local_empty_signals()
%LOCAL_EMPTY_SIGNALS Build an empty normalized signal container.
    signals = struct( ...
        'scenario_id', "", ...
        'scenario_name', "", ...
        'Rt_model_input', [], ...
        'Rt_evaluation_target', [], ...
        'tspan', [], ...
        'S_model_input', [], ...
        'I_model_input', [], ...
        'U_true', [], ...
        'sirs_cfg', struct(), ...
        'horizon', [], ...
        'windows', [], ...
        'compatibility_metadata', struct());
end

function scenario_entry = local_empty_scenario_entry()
%LOCAL_EMPTY_SCENARIO_ENTRY Build an empty forecast scenario entry.
    scenario_entry = struct( ...
        'scenario_id', "", ...
        'scenario_name', "", ...
        'num_exo', 0, ...
        'windows', [], ...
        'window_data', [], ...
        'Rt_true', [], ...
        'Rt_model_input', [], ...
        'tspan', [], ...
        'U_true', [], ...
        'S_model_input', [], ...
        'I_model_input', [], ...
        'compatibility_metadata', struct());
end
