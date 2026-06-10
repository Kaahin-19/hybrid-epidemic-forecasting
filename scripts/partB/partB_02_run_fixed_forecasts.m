%PARTB_02_RUN_FIXED_FORECASTS Run fixed Part A forecasts across Part B cases.
%
%   Description:
%       Loads Part B robustness-ladder truth artifacts and evaluates only the
%       fixed Part A-selected AR/None and ARX/I configurations. Forecast
%       histories use Rt_model_input and I_model_input, while stored future
%       truth for evaluation uses Rt_evaluation_target.
%
%   Workflow:
%       1. Load configuration, truth artifacts, and fixed Part A choices.
%       2. Build generic expanding-window forecast inputs for each artifact.
%       3. Run forecasts through the reusable Part A forecasting dispatcher.
%       4. Save one MATLAB forecast artifact per case/scenario/model.
%
%   See also PARTB_CONFIG, PREPARE_WINDOW_DATA, RUN_EXPANDING_WINDOW_FORECAST.
%
% A. M. Kaahin 2026-05-18
% Modified: 2026-06-11

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Robustness-Ladder Fixed Forecast Execution ===\n');

cfg = partB_config();
truth_paths = local_truth_artifact_paths(cfg);
if isempty(truth_paths)
    error('FORECAST:NoTruthArtifacts', ...
        'No Part B truth artifacts found under %s. Run Part B 01 first.', ...
        cfg.output.data_root_dir);
end

fixed_configs = local_load_fixed_partA_configs(cfg);

fprintf('Experiment: %s\n', cfg.experiment_id);
fprintf('Found %d truth artifact(s).\n', numel(truth_paths));

%% 2. Forecast Loop
for i = 1:numel(truth_paths)
    truth_path = truth_paths(i);
    loaded = load(truth_path);
    local_validate_truth_artifact(loaded, truth_path);

    case_id = string(loaded.case_id);
    case_forecast_dir = local_case_forecast_dir(cfg, case_id);
    if ~exist(case_forecast_dir, 'dir'), mkdir(case_forecast_dir); end

    fprintf('  - Forecasting %s / %s\n', ...
        loaded.case_id, loaded.scenario_id);

    for c = 1:numel(fixed_configs)
        model_cfg = fixed_configs(c);
        fprintf('    * Fixed model %s / %s using %s configuration %s\n', ...
            model_cfg.model_type, model_cfg.exo_mode, ...
            model_cfg.selected_configuration_source, ...
            mat2str(model_cfg.selected_configuration));

        scenario_entry = local_build_scenario_entry(loaded, cfg, ...
            model_cfg.exo_mode);
        forecast_options = local_forecast_options(cfg, model_cfg.exo_mode, ...
            scenario_entry);

        forecast_results = run_expanding_window_forecast(scenario_entry, ...
            model_cfg.model_type, model_cfg.selected_configuration, ...
            forecast_options);

        if isempty(forecast_results)
            warning('FORECAST:NoWindows', ...
                'No valid forecast windows for %s / %s / %s / %s.', ...
                loaded.case_id, loaded.scenario_id, ...
                model_cfg.model_type, model_cfg.exo_mode);
        end

        %% 3. Persist Forecast Artifact
        experiment_id = string(cfg.experiment_id);
        experiment_name = string(cfg.experiment_name);
        case_id = string(loaded.case_id);
        case_name = string(loaded.case_name);
        truth_model = string(loaded.truth_model);
        solver = string(loaded.solver);
        forecast_assumption = string(loaded.forecast_assumption);
        structural_mismatch_enabled = logical(loaded.structural_mismatch_enabled);
        observation_noise_enabled = logical(loaded.observation_noise_enabled);
        process_noise_enabled = logical(loaded.process_noise_enabled);
        scenario_id = string(loaded.scenario_id);
        scenario_name = string(loaded.scenario_name);
        model_type = string(model_cfg.model_type);
        exo_mode = string(model_cfg.exo_mode);
        selected_configuration = model_cfg.selected_configuration;
        selected_configuration_source = string(model_cfg.selected_configuration_source);
        selected_configuration_artifact = string(model_cfg.selected_configuration_artifact);
        selection_metadata = model_cfg.selection_metadata;
        source_truth_artifact = string(truth_path);
        cfg_snapshot = local_cfg_snapshot(cfg, loaded, forecast_options);

        file_prefix = sprintf('partB_%s_forecast_%s_%s_%s', ...
            char(case_id), char(scenario_id), ...
            char(model_type), char(exo_mode));
        out_path = fullfile(case_forecast_dir, [file_prefix, '.mat']);

        save(out_path, ...
            'experiment_id', 'experiment_name', 'case_id', 'case_name', ...
            'truth_model', 'solver', 'forecast_assumption', ...
            'structural_mismatch_enabled', 'observation_noise_enabled', ...
            'process_noise_enabled', 'scenario_id', ...
            'scenario_name', 'model_type', 'exo_mode', ...
            'selected_configuration', 'selected_configuration_source', ...
            'selected_configuration_artifact', 'selection_metadata', ...
            'forecast_results', 'source_truth_artifact', 'cfg_snapshot');
        fprintf('      Forecast artifact saved to: %s\n', out_path);
    end
end

fprintf('=== Part B Robustness-Ladder Fixed Forecast Execution Complete ===\n\n');

%% 4. Local Functions
function paths = local_truth_artifact_paths(cfg)
%LOCAL_TRUTH_ARTIFACT_PATHS Return active truth artifact paths.
    cases = local_active_cases(cfg);
    active_scenarios = local_active_scenario_ids(cfg);
    paths = strings(0, 1);
    for i = 1:numel(cases)
        for j = 1:numel(active_scenarios)
            artifact_path = fullfile(cfg.output.data_root_dir, ...
                sprintf('partB_%s_truth_%s.mat', ...
                char(cases(i).case_id), char(active_scenarios(j))));
            if exist(artifact_path, 'file') == 2
                paths(end + 1, 1) = artifact_path; %#ok<AGROW>
            end
        end
    end
end

function cases = local_active_cases(cfg)
%LOCAL_ACTIVE_CASES Apply optional smoke-test case limiting.
    cases = cfg.robustness_cases;
    if cfg.smoke_test.enabled
        cases = cases(1:min(numel(cases), cfg.smoke_test.num_cases));
    end
end

function scenario_ids = local_active_scenario_ids(cfg)
%LOCAL_ACTIVE_SCENARIO_IDS Return active scenario ids.
    scenarios = cfg.scenarios;
    if cfg.smoke_test.enabled
        scenarios = scenarios(1:min(numel(scenarios), cfg.smoke_test.num_scenarios));
    end
    scenario_ids = strings(numel(scenarios), 1);
    for i = 1:numel(scenarios)
        scenario_ids(i) = string(scenarios(i).id);
    end
end

function forecast_dir = local_case_forecast_dir(cfg, ~)
%LOCAL_CASE_FORECAST_DIR Return the shared Part B forecast directory.
    forecast_dir = cfg.output.forecast_dir;
end

function fixed_configs = local_load_fixed_partA_configs(cfg)
%LOCAL_LOAD_FIXED_PARTA_CONFIGS Load or fall back to frozen Part A selections.
    cases = cfg.fixed_forecast_cases;
    if cfg.smoke_test.enabled
        n = min(numel(cases), cfg.smoke_test.num_forecast_cases);
        cases = cases(1:n);
        fprintf('Smoke test enabled: using %d fixed forecast case(s).\n', n);
    end

    fixed_configs = repmat(local_empty_fixed_config(), 1, numel(cases));
    for i = 1:numel(cases)
        fixed_configs(i) = local_load_one_fixed_config(cfg, cases(i));
    end
end

function model_cfg = local_load_one_fixed_config(cfg, fixed_case)
%LOCAL_LOAD_ONE_FIXED_CONFIG Load one Part A selection artifact or fallback.
    model_type = string(fixed_case.model_type);
    exo_mode = string(fixed_case.exo_mode);
    artifact_path = fullfile(cfg.output.partA_model_selection_dir, ...
        sprintf('partA_02_global_hyperparameters_%s_%s.mat', ...
        char(model_type), char(exo_mode)));

    if exist(artifact_path, 'file') == 2
        selection = load(artifact_path);
        local_validate_selection_artifact(selection, artifact_path, ...
            model_type, exo_mode);
        selected_configuration = reshape(double(selection.selected_configuration), 1, []);
        source = "partA_model_selection";
        selection_artifact = string(artifact_path);
        selection_metadata = local_selection_metadata(selection);
    else
        selected_configuration = reshape(double(fixed_case.fallback_configuration), 1, []);
        source = "partB_config_fallback";
        selection_artifact = "";
        selection_metadata = struct('selected_index', nan, 'best_global_wis', nan);
        warning('FORECAST:PartASelectionFallback', ...
            ['Missing Part A selection artifact for %s / %s: %s. ', ...
            'Using documented Part B config fallback %s.'], ...
            model_type, exo_mode, artifact_path, mat2str(selected_configuration));
    end

    local_validate_configuration_shape(model_type, selected_configuration);

    model_cfg = local_empty_fixed_config();
    model_cfg.model_type = model_type;
    model_cfg.exo_mode = exo_mode;
    model_cfg.selected_configuration = selected_configuration;
    model_cfg.selected_configuration_source = source;
    model_cfg.selected_configuration_artifact = selection_artifact;
    model_cfg.selection_metadata = selection_metadata;
end

function local_validate_selection_artifact(selection, artifact_path, model_type, exo_mode)
%LOCAL_VALIDATE_SELECTION_ARTIFACT Validate a Part A selection artifact.
    required_fields = {'model_type', 'exo_mode', 'selected_configuration'};
    if ~all(isfield(selection, required_fields))
        error('FORECAST:InvalidSelectionArtifact', ...
            'Selection artifact is missing required fields: %s.', artifact_path);
    end

    if string(selection.model_type) ~= model_type || string(selection.exo_mode) ~= exo_mode
        error('FORECAST:SelectionIdentityMismatch', ...
            'Selection artifact identity mismatch: %s.', artifact_path);
    end
end

function local_validate_configuration_shape(model_type, selected_configuration)
%LOCAL_VALIDATE_CONFIGURATION_SHAPE Check expected parameter counts.
    switch char(model_type)
        case 'AR'
            expected_count = 1;
        case 'ARX'
            expected_count = 3;
        otherwise
            error('FORECAST:UnsupportedModel', ...
                'Part B robustness ladder supports only AR and ARX.');
    end

    if numel(selected_configuration) ~= expected_count
        error('FORECAST:InvalidSelectedConfiguration', ...
            'Selected configuration for %s has invalid size: %s.', ...
            model_type, mat2str(selected_configuration));
    end
end

function metadata = local_selection_metadata(selection)
%LOCAL_SELECTION_METADATA Capture optional Part A selection metadata.
    metadata = struct();
    metadata.selected_index = local_numeric_field(selection, 'selected_index');
    metadata.best_global_wis = local_numeric_field(selection, 'best_global_wis');
    if isnan(metadata.best_global_wis) && isfield(selection, 'global_mean_wis') && ...
            isfield(selection, 'selected_index') && ...
            selection.selected_index >= 1 && ...
            selection.selected_index <= numel(selection.global_mean_wis)
        metadata.best_global_wis = double(selection.global_mean_wis(selection.selected_index));
    end
end

function value = local_numeric_field(s, field_name)
%LOCAL_NUMERIC_FIELD Read a scalar numeric field or NaN.
    value = nan;
    if isfield(s, field_name) && ~isempty(s.(field_name)) && isnumeric(s.(field_name))
        raw = double(s.(field_name));
        if isscalar(raw)
            value = raw;
        end
    end
end

function model_cfg = local_empty_fixed_config()
%LOCAL_EMPTY_FIXED_CONFIG Build a fixed configuration placeholder.
    model_cfg = struct( ...
        'model_type', "", ...
        'exo_mode', "", ...
        'selected_configuration', [], ...
        'selected_configuration_source', "", ...
        'selected_configuration_artifact', "", ...
        'selection_metadata', struct());
end

function local_validate_truth_artifact(loaded, artifact_path)
%LOCAL_VALIDATE_TRUTH_ARTIFACT Verify required Part B truth fields.
    required_fields = {'case_id', 'case_name', 'truth_model', 'solver', ...
        'forecast_assumption', 'structural_mismatch_enabled', ...
        'observation_noise_enabled', 'process_noise_enabled', ...
        'scenario_id', 'scenario_name', 'Rt_model_input', ...
        'Rt_evaluation_target', 'S_model_input', 'I_model_input', 'tspan'};
    if ~all(isfield(loaded, required_fields))
        error('FORECAST:InvalidTruthArtifact', ...
            'Truth artifact is missing required fields: %s.', artifact_path);
    end
end

function scenario_entry = local_build_scenario_entry(loaded, cfg, exo_mode)
%LOCAL_BUILD_SCENARIO_ENTRY Build generic forecast input from model inputs.
    horizon = local_effective_horizon(cfg);
    Rt_model_input = double(loaded.Rt_model_input(:));
    Rt_target = double(loaded.Rt_evaluation_target(:));
    tspan = double(loaded.tspan(:));
    pop_size = local_population_size(loaded, cfg);
    I_model_input = double(loaded.I_model_input(:));
    S_model_input = double(loaded.S_model_input(:));

    switch char(exo_mode)
        case 'None'
            U_true = [];
        case 'I'
            U_true = I_model_input / pop_size;
        otherwise
            error('FORECAST:UnsupportedExoMode', ...
                'Part B robustness ladder evaluates only None and I exogenous modes.');
    end

    scenario_inputs = struct( ...
        'Rt_true', Rt_model_input, ...
        'tspan', tspan, ...
        'S_true', S_model_input, ...
        'I_true', I_model_input, ...
        'U_true', U_true);

    max_T = numel(Rt_model_input) - horizon;
    windows = cfg.forecast.min_window : cfg.forecast.step_size : max_T;
    if cfg.smoke_test.enabled
        windows = windows(1:min(numel(windows), cfg.smoke_test.max_windows));
    end

    if isempty(windows)
        window_data = struct([]);
    else
        window_data = repmat(prepare_window_data(scenario_inputs, windows(1), ...
            horizon, cfg.sirs_projection), numel(windows), 1);
        for w = 1:numel(windows)
            window_data(w) = prepare_window_data(scenario_inputs, windows(w), ...
                horizon, cfg.sirs_projection);
            if window_data(w).is_valid_window
                idx = window_data(w).horizon_indices;
                window_data(w).truth_Rt = Rt_target(idx);
            end
        end
    end

    scenario_entry = struct();
    scenario_entry.scenario_id = string(loaded.scenario_id);
    scenario_entry.scenario_name = string(loaded.scenario_name);
    scenario_entry.num_exo = size(U_true, 2);
    scenario_entry.windows = windows;
    scenario_entry.window_data = window_data;
    scenario_entry.Rt_true = Rt_target;
    scenario_entry.tspan = tspan;
end

function pop_size = local_population_size(loaded, cfg)
%LOCAL_POPULATION_SIZE Resolve scaling population for model inputs.
    if isfield(loaded, 'model_params') && isfield(loaded.model_params, 'pop_size')
        pop_size = double(loaded.model_params.pop_size);
    else
        pop_size = double(cfg.sirs_projection.pop_size);
    end
end

function forecast_options = local_forecast_options(cfg, exo_mode, scenario_entry)
%LOCAL_FORECAST_OPTIONS Build reusable forecast options for Part B.
    intervals = cfg.intervals;
    if cfg.smoke_test.enabled
        % Cap the canonical interval path count for fast smoke runs. Part A
        % unified the protocol on cfg.intervals.num_draws; final_num_draws is
        % only a deprecated compatibility mirror and is no longer relied on here.
        intervals.num_draws = min(intervals.num_draws, ...
            cfg.smoke_test.interval_draws);
    end

    forecast_options = struct( ...
        'horizon', local_effective_horizon(cfg), ...
        'wis_alphas', cfg.forecast.wis_alphas, ...
        'sirs_cfg', cfg.sirs_projection, ...
        'exo_mode', char(exo_mode), ...
        'sim_seed', cfg.sim.seed, ...
        'num_exo', scenario_entry.num_exo, ...
        'intervals', intervals, ...
        'scenario_id', scenario_entry.scenario_id);
end

function horizon = local_effective_horizon(cfg)
%LOCAL_EFFECTIVE_HORIZON Resolve full or smoke-test horizon.
    horizon = cfg.forecast.horizon;
    if cfg.smoke_test.enabled
        horizon = min(horizon, cfg.smoke_test.horizon);
    end
end

function cfg_snapshot = local_cfg_snapshot(cfg, loaded, forecast_options)
%LOCAL_CFG_SNAPSHOT Store relevant fixed-forecast configuration.
    cfg_snapshot = struct();
    cfg_snapshot.experiment_id = cfg.experiment_id;
    cfg_snapshot.experiment_name = cfg.experiment_name;
    cfg_snapshot.case_id = loaded.case_id;
    cfg_snapshot.case_name = loaded.case_name;
    cfg_snapshot.truth_model = loaded.truth_model;
    cfg_snapshot.solver = loaded.solver;
    cfg_snapshot.forecast_assumption = loaded.forecast_assumption;
    cfg_snapshot.forecast = cfg.forecast;
    cfg_snapshot.effective_horizon = forecast_options.horizon;
    cfg_snapshot.wis_alphas = forecast_options.wis_alphas;
    cfg_snapshot.sirs_projection = cfg.sirs_projection;
    cfg_snapshot.intervals = forecast_options.intervals;
    cfg_snapshot.fixed_forecast_cases = cfg.fixed_forecast_cases;
    cfg_snapshot.smoke_test = cfg.smoke_test;
    cfg_snapshot.sim_seed = cfg.sim.seed;
end
