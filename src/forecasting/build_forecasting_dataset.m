function scenario_data = build_forecasting_dataset(cfg, exo_mode)
%BUILD_FORECASTING_DATASET Assemble Part A expanding-window forecast inputs.
%
%   Syntax:
%       scenario_data = build_forecasting_dataset(cfg, exo_mode)
%
%   Description:
%       Loads the Part A synthetic truth artifacts and precomputes the
%       expanding-window forecast inputs for every scenario. The window grid,
%       exogenous-covariate scaling, and current-state construction reproduce
%       the Part A model-selection protocol so that final forecasts are built
%       on an identical dataset.
%
%   Inputs:
%       cfg      - Part A configuration structure.
%       exo_mode - Exogenous mode: None, S, I, or Both.
%
%   Outputs:
%       scenario_data - Structure array, one entry per scenario, with
%                       scenario identifiers, the expanding-window grid, and
%                       prepared per-window inputs.
%
%   See also PREPARE_WINDOW_DATA, RUN_EXPANDING_WINDOW_FORECAST, PARTA_CONFIG.
%
% A. M. Kaahin 2026-06-01

    %% 1. Locate Truth Artifacts
    data_dir = cfg.output.data_dir;
    file_list = dir(fullfile(data_dir, '*.mat'));

    if isempty(file_list)
        error('FORECAST:NoData', ...
            'No synthetic truth files found in %s. Run partA_01 first.', data_dir);
    end

    horizon = cfg.forecast.horizon;
    sirs_cfg = cfg.sirs;

    scenario_data = repmat(struct( ...
        'scenario_id', "", ...
        'scenario_name', "", ...
        'num_exo', 0, ...
        'windows', [], ...
        'window_data', [], ...
        'Rt_true', [], ...
        'tspan', []), length(file_list), 1);

    %% 2. Per-Scenario Window Construction
    for i = 1:length(file_list)
        full_path = fullfile(data_dir, file_list(i).name);
        [~, name_core] = fileparts(file_list(i).name);

        loaded = load(full_path);
        local_validate_truth_artifact(loaded, full_path);

        scenario_id = string(strrep(name_core, 'partA_01_truth_', ''));
        scenario_name = local_resolve_scenario_name(loaded, scenario_id);

        scaled_S = loaded.S_true(:) / cfg.sirs.pop_size;
        scaled_I = loaded.I_true(:) / cfg.sirs.pop_size;

        switch char(exo_mode)
            case 'None', U_true = [];
            case 'S',    U_true = scaled_S;
            case 'I',    U_true = scaled_I;
            case 'Both', U_true = [scaled_S, scaled_I];
            otherwise
                error('FORECAST:UnknownExoMode', ...
                    'Unsupported EXO_MODE: %s', string(exo_mode));
        end

        scenario_inputs = struct( ...
            'Rt_true', loaded.Rt_true(:), ...
            'tspan', loaded.tspan(:), ...
            'S_true', loaded.S_true(:), ...
            'I_true', loaded.I_true(:), ...
            'U_true', U_true);

        T_end = length(loaded.Rt_true);
        max_T = T_end - horizon;
        windows = cfg.forecast.min_window : cfg.forecast.step_size : max_T;

        window_data = repmat(prepare_window_data(scenario_inputs, ...
            windows(1), horizon, sirs_cfg), numel(windows), 1);
        for w = 2:numel(windows)
            window_data(w) = prepare_window_data(scenario_inputs, ...
                windows(w), horizon, sirs_cfg);
        end

        scenario_data(i).scenario_id   = scenario_id;
        scenario_data(i).scenario_name = scenario_name;
        scenario_data(i).num_exo       = size(U_true, 2);
        scenario_data(i).windows       = windows;
        scenario_data(i).window_data   = window_data;
        scenario_data(i).Rt_true       = scenario_inputs.Rt_true;
        scenario_data(i).tspan         = scenario_inputs.tspan;

        fprintf('Prepared scenario %d/%d (%s)\n', ...
            i, length(file_list), char(scenario_id));
    end
end

function local_validate_truth_artifact(loaded, artifact_path)
%LOCAL_VALIDATE_TRUTH_ARTIFACT Verify required truth fields are present.
    required_fields = {'Rt_true', 'S_true', 'I_true', 'tspan'};
    if ~all(isfield(loaded, required_fields))
        error('FORECAST:InvalidTruthArtifact', ...
            'Synthetic truth artifact is missing required fields: %s.', artifact_path);
    end
end

function scenario_name = local_resolve_scenario_name(loaded, scenario_id)
%LOCAL_RESOLVE_SCENARIO_NAME Use the stored scenario name when available.
    if isfield(loaded, 'scenario_name') && ~isempty(loaded.scenario_name)
        scenario_name = string(loaded.scenario_name);
    else
        scenario_name = scenario_id;
    end
end
