%PARTB_02_RUN_FIXED_FORECASTS Run fixed Part A forecasts on SEIR truth.
%
%   Description:
%       Loads structural-mismatch SEIR truth artifacts and evaluates only the
%       fixed Part A-selected AR/None and ARX/I forecasting configurations.
%       No model selection or order retuning is performed on SEIR truth.
%
%   Workflow:
%       1. Load configuration, SEIR truth artifacts, and fixed Part A choices.
%       2. Build generic expanding-window forecast inputs for each scenario.
%       3. Run forecasts through the reusable Part A forecasting dispatcher.
%       4. Save one MATLAB forecast artifact per scenario/model case.
%
%   See also PARTB_CONFIG, PREPARE_WINDOW_DATA, RUN_EXPANDING_WINDOW_FORECAST.
%
% A. M. Kaahin 2026-05-18
% Modified: 2026-06-02

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Structural-Mismatch Fixed Forecast Execution ===\n');

cfg = partB_config();
data_dir = cfg.output.data_dir;
forecast_dir = cfg.output.forecast_dir;

if ~exist(forecast_dir, 'dir')
    mkdir(forecast_dir);
end

truth_files = dir(fullfile(data_dir, sprintf('%s_truth_*.mat', ...
    char(cfg.experiment_id))));
truth_files = local_sort_dir_by_name(truth_files);
if isempty(truth_files)
    error('FORECAST:NoTruthArtifacts', ...
        'No structural-mismatch truth files found under %s. Run Part B 01 first.', ...
        data_dir);
end

fixed_configs = local_load_fixed_partA_configs(cfg);

%% 2. Forecast Loop
fprintf('Experiment: %s\n', cfg.experiment_id);
fprintf('Found %d truth artifact(s) in %s\n', numel(truth_files), data_dir);

for i = 1:numel(truth_files)
    truth_path = fullfile(truth_files(i).folder, truth_files(i).name);
    loaded = load(truth_path);
    local_validate_truth_artifact(loaded, truth_path);

    scenario_id = string(loaded.scenario_id);
    scenario_name = string(loaded.scenario_name);
    fprintf('  - Forecasting scenario %s (%s)\n', scenario_id, scenario_name);

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
                'No valid forecast windows for %s / %s / %s.', ...
                scenario_id, model_cfg.model_type, model_cfg.exo_mode);
        end

        %% 3. Persist Forecast Artifact
        experiment_id = string(cfg.experiment_id);
        experiment_name = string(cfg.experiment_name);
        truth_model = string(cfg.truth_model);
        forecast_assumption = string(cfg.forecast_assumption);
        model_type = string(model_cfg.model_type);
        exo_mode = string(model_cfg.exo_mode);
        selected_configuration = model_cfg.selected_configuration;
        selected_configuration_source = string(model_cfg.selected_configuration_source);
        selected_configuration_artifact = string(model_cfg.selected_configuration_artifact);
        selection_metadata = model_cfg.selection_metadata;
        source_truth_artifact = string(truth_path);
        cfg_snapshot = local_cfg_snapshot(cfg, forecast_options);

        file_prefix = sprintf('%s_forecast_%s_%s_%s', char(cfg.experiment_id), ...
            char(scenario_id), char(model_type), char(exo_mode));
        out_path = fullfile(forecast_dir, [file_prefix, '.mat']);

        save(out_path, ...
            'experiment_id', 'experiment_name', 'truth_model', ...
            'forecast_assumption', 'scenario_id', 'scenario_name', ...
            'model_type', 'exo_mode', 'selected_configuration', ...
            'selected_configuration_source', 'selected_configuration_artifact', ...
            'selection_metadata', 'forecast_results', 'source_truth_artifact', ...
            'cfg_snapshot');
        fprintf('      Forecast artifact saved to: %s\n', out_path);
    end
end

fprintf('=== Part B Structural-Mismatch Fixed Forecast Execution Complete ===\n\n');

%% 4. Local Functions
function fixed_configs = local_load_fixed_partA_configs(cfg)
%LOCAL_LOAD_FIXED_PARTA_CONFIGS Load or fall back to frozen Part A selections.
    cases = cfg.fixed_forecast_cases;
    if cfg.smoke_test.enabled
        n = min(numel(cases), cfg.smoke_test.num_cases);
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
                'Part B structural mismatch supports only AR and ARX.');
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
%LOCAL_VALIDATE_TRUTH_ARTIFACT Verify required SEIR truth fields.
    required_fields = {'experiment_id', 'experiment_name', 'truth_model', ...
        'forecast_assumption', 'scenario_id', 'scenario_name', 'Rt_true', ...
        'S_true', 'E_true', 'I_true', 'R_true', 'tspan'};
    if ~all(isfield(loaded, required_fields))
        error('FORECAST:InvalidTruthArtifact', ...
            'Truth artifact is missing required fields: %s.', artifact_path);
    end
end

function scenario_entry = local_build_scenario_entry(loaded, cfg, exo_mode)
%LOCAL_BUILD_SCENARIO_ENTRY Build generic forecast input for one SEIR scenario.
    horizon = local_effective_horizon(cfg);
    Rt_true = double(loaded.Rt_true(:));
    tspan = double(loaded.tspan(:));
    scaled_I = double(loaded.I_true(:)) / cfg.seir.pop_size;

    switch char(exo_mode)
        case 'None'
            U_true = [];
        case 'I'
            U_true = scaled_I;
        otherwise
            error('FORECAST:UnsupportedExoMode', ...
                'Part B structural mismatch evaluates only None and I exogenous modes.');
    end

    scenario_inputs = struct( ...
        'Rt_true', Rt_true, ...
        'tspan', tspan, ...
        'S_true', double(loaded.S_true(:)), ...
        'I_true', double(loaded.I_true(:)), ...
        'U_true', U_true);

    max_T = numel(Rt_true) - horizon;
    windows = cfg.forecast.min_window : cfg.forecast.step_size : max_T;
    if cfg.smoke_test.enabled
        windows = windows(1:min(numel(windows), cfg.smoke_test.max_windows));
    end

    if isempty(windows)
        window_data = struct([]);
    else
        window_data = repmat(prepare_window_data(scenario_inputs, windows(1), ...
            horizon, cfg.sirs_projection), numel(windows), 1);
        for w = 2:numel(windows)
            window_data(w) = prepare_window_data(scenario_inputs, windows(w), ...
                horizon, cfg.sirs_projection);
        end
    end

    scenario_entry = struct();
    scenario_entry.scenario_id = string(loaded.scenario_id);
    scenario_entry.scenario_name = string(loaded.scenario_name);
    scenario_entry.num_exo = size(U_true, 2);
    scenario_entry.windows = windows;
    scenario_entry.window_data = window_data;
    scenario_entry.Rt_true = Rt_true;
    scenario_entry.tspan = tspan;
end

function forecast_options = local_forecast_options(cfg, exo_mode, scenario_entry)
%LOCAL_FORECAST_OPTIONS Build reusable forecast options for Part B.
    forecast_options = struct( ...
        'horizon', local_effective_horizon(cfg), ...
        'wis_alphas', cfg.forecast.wis_alphas, ...
        'sirs_cfg', cfg.sirs_projection, ...
        'exo_mode', char(exo_mode), ...
        'sim_seed', cfg.sim.seed, ...
        'num_exo', scenario_entry.num_exo, ...
        'intervals', cfg.intervals, ...
        'scenario_id', scenario_entry.scenario_id);

    if cfg.smoke_test.enabled
        forecast_options.intervals.final_num_draws = min( ...
            forecast_options.intervals.final_num_draws, 10);
    end
end

function horizon = local_effective_horizon(cfg)
%LOCAL_EFFECTIVE_HORIZON Resolve full or smoke-test horizon.
    horizon = cfg.forecast.horizon;
    if cfg.smoke_test.enabled
        horizon = min(horizon, cfg.smoke_test.horizon);
    end
end

function cfg_snapshot = local_cfg_snapshot(cfg, forecast_options)
%LOCAL_CFG_SNAPSHOT Store relevant fixed-forecast configuration.
    cfg_snapshot = struct();
    cfg_snapshot.experiment_id = cfg.experiment_id;
    cfg_snapshot.experiment_name = cfg.experiment_name;
    cfg_snapshot.truth_model = cfg.truth_model;
    cfg_snapshot.forecast_assumption = cfg.forecast_assumption;
    cfg_snapshot.forecast = cfg.forecast;
    cfg_snapshot.effective_horizon = forecast_options.horizon;
    cfg_snapshot.wis_alphas = forecast_options.wis_alphas;
    cfg_snapshot.sirs_projection = cfg.sirs_projection;
    cfg_snapshot.intervals = forecast_options.intervals;
    cfg_snapshot.fixed_forecast_cases = cfg.fixed_forecast_cases;
    cfg_snapshot.smoke_test = cfg.smoke_test;
    cfg_snapshot.sim_seed = cfg.sim.seed;
end

function files = local_sort_dir_by_name(files)
%LOCAL_SORT_DIR_BY_NAME Sort a dir struct by name.
    [~, order] = sort({files.name});
    files = files(order);
end
