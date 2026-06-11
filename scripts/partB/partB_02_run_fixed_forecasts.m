%PARTB_02_RUN_FIXED_FORECASTS Run fixed Part A forecasts across Part B cases.
%
%   Description:
%       Loads every Part B robustness-ladder truth artifact, including all
%       process-noise replicates, and evaluates only the fixed Part A-selected
%       AR/None and ARX/I configurations. Forecast histories use Rt_model_input
%       and I_model_input, while stored future truth for evaluation uses
%       Rt_evaluation_target. Replicate identity and seeds are carried into each
%       forecast artifact and its filename so replicates never overwrite.
%
%   Workflow:
%       1. Load configuration, truth artifacts, and fixed Part A choices.
%       2. Build generic expanding-window forecast inputs for each artifact.
%       3. Run forecasts through the reusable Part A forecasting dispatcher.
%       4. Save one MATLAB forecast artifact per case/scenario/replicate/model.
%
%   See also PARTB_CONFIG, BUILD_FORECAST_ENTRIES,
%            LOAD_FIXED_FORECAST_CONFIGURATIONS, RUN_EXPANDING_WINDOW_FORECAST.
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

fixed_configs = load_fixed_forecast_configurations(cfg, "partB");

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

        scenario_entry = build_forecast_entries(cfg, model_cfg.exo_mode, ...
            struct('mode', "partB", 'data', loaded));
        local_validate_forecast_wiring(scenario_entry, model_cfg, loaded);
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
        replicate_id = string(loaded.replicate_id);
        replicate_index = double(loaded.replicate_index);
        num_replicates_for_case = double(loaded.num_replicates_for_case);
        process_seed = double(loaded.process_seed);
        noise_seed = double(loaded.noise_seed);
        model_type = string(model_cfg.model_type);
        exo_mode = string(model_cfg.exo_mode);
        selected_configuration = model_cfg.selected_configuration;
        selected_configuration_source = string(model_cfg.selected_configuration_source);
        selected_configuration_artifact = string(model_cfg.selected_configuration_artifact);
        selection_metadata = model_cfg.selection_metadata;
        source_truth_artifact = string(truth_path);
        cfg_snapshot = local_cfg_snapshot(cfg, loaded, forecast_options);

        file_prefix = sprintf('partB_%s_forecast_%s_%s_%s_%s', ...
            char(case_id), char(scenario_id), char(replicate_id), ...
            char(model_type), char(exo_mode));
        out_path = fullfile(case_forecast_dir, [file_prefix, '.mat']);

        save(out_path, ...
            'experiment_id', 'experiment_name', 'case_id', 'case_name', ...
            'truth_model', 'solver', 'forecast_assumption', ...
            'structural_mismatch_enabled', 'observation_noise_enabled', ...
            'process_noise_enabled', 'scenario_id', ...
            'scenario_name', 'replicate_id', 'replicate_index', ...
            'num_replicates_for_case', 'process_seed', 'noise_seed', ...
            'model_type', 'exo_mode', ...
            'selected_configuration', 'selected_configuration_source', ...
            'selected_configuration_artifact', 'selection_metadata', ...
            'forecast_results', 'source_truth_artifact', 'cfg_snapshot');
        fprintf('      Forecast artifact saved to: %s\n', out_path);
    end
end

fprintf('=== Part B Robustness-Ladder Fixed Forecast Execution Complete ===\n\n');

%% 4. Local Functions
function paths = local_truth_artifact_paths(cfg)
%LOCAL_TRUTH_ARTIFACT_PATHS Return all active truth artifacts, every replicate.
    cases = local_active_cases(cfg);
    active_scenarios = local_active_scenario_ids(cfg);
    paths = strings(0, 1);
    for i = 1:numel(cases)
        for j = 1:numel(active_scenarios)
            pattern = sprintf('partB_%s_truth_%s_rep*.mat', ...
                char(cases(i).case_id), char(active_scenarios(j)));
            listing = dir(fullfile(cfg.output.data_root_dir, pattern));
            for k = 1:numel(listing)
                paths(end + 1, 1) = string(fullfile(listing(k).folder, ...
                    listing(k).name)); %#ok<AGROW>
            end
        end
    end
    paths = sort(paths);
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

function local_validate_truth_artifact(loaded, artifact_path)
%LOCAL_VALIDATE_TRUTH_ARTIFACT Verify required Part B truth fields.
    required_fields = {'case_id', 'case_name', 'truth_model', 'solver', ...
        'forecast_assumption', 'structural_mismatch_enabled', ...
        'observation_noise_enabled', 'process_noise_enabled', ...
        'scenario_id', 'scenario_name', 'replicate_id', 'replicate_index', ...
        'num_replicates_for_case', 'process_seed', 'noise_seed', ...
        'Rt_true', 'Rt_model_input', ...
        'Rt_evaluation_target', 'S_model_input', 'I_model_input', ...
        'incidence_true', 'incidence_observed', 'incidence_model_input', ...
        'renewal_lambda_model_input', 'serial_interval_weights', ...
        'observation_metadata', 'tspan'};
    if ~all(isfield(loaded, required_fields))
        error('FORECAST:InvalidTruthArtifact', ...
            'Truth artifact is missing required fields: %s.', artifact_path);
    end

    if ~isfield(loaded.observation_metadata, 'direct_Rt_noise_used') || ...
            logical(loaded.observation_metadata.direct_Rt_noise_used)
        error('FORECAST:DirectRtNoise', ...
            'Truth artifact must record direct_Rt_noise_used = false: %s.', ...
            artifact_path);
    end

    if logical(loaded.observation_noise_enabled) && ...
            isequal(double(loaded.Rt_model_input(:)), double(loaded.Rt_true(:)))
        error('FORECAST:RtModelInputNotEstimated', ...
            ['Observation-noise truth artifact has Rt_model_input equal to ' ...
            'latent Rt_true: %s.'], artifact_path);
    end
end

function local_validate_forecast_wiring(scenario_entry, model_cfg, loaded)
%LOCAL_VALIDATE_FORECAST_WIRING Confirm history/target/exogenous wiring.
    tol = 1e-9;
    if ~isequal(double(scenario_entry.Rt_model_input(:)), ...
            double(loaded.Rt_model_input(:)))
        error('FORECAST:HistoryWiring', ...
            'Forecast history must come from Rt_model_input.');
    end
    if ~isequal(double(scenario_entry.Rt_true(:)), ...
            double(loaded.Rt_evaluation_target(:)))
        error('FORECAST:EvaluationWiring', ...
            'Forecast evaluation truth must come from Rt_evaluation_target.');
    end

    pop_size = double(loaded.model_params.pop_size);
    switch char(string(model_cfg.exo_mode))
        case 'None'
            if scenario_entry.num_exo ~= 0 || ~isempty(scenario_entry.U_true)
                error('FORECAST:ExoWiringNone', ...
                    'AR/None must not use any exogenous input.');
            end
        case 'I'
            expected_U = double(loaded.I_model_input(:)) / pop_size;
            if scenario_entry.num_exo ~= 1 || ...
                    numel(scenario_entry.U_true) ~= numel(expected_U) || ...
                    max(abs(double(scenario_entry.U_true(:)) - expected_U)) > tol
                error('FORECAST:ExoWiringI', ...
                    'ARX/I U_past must be I_model_input / pop_size.');
            end
    end

    % Spot-check the first valid window: history is Rt_model_input up to the
    % origin, future scoring truth is the evaluation target. Closed-loop future
    % exogenous I is generated downstream from the SIRS projection, never read
    % from future truth (U_past is history only, length == origin index).
    window_data = scenario_entry.window_data;
    for w = 1:numel(window_data)
        if ~window_data(w).is_valid_window
            continue;
        end
        idx_T = window_data(w).window_day_idx;
        if ~isequal(double(window_data(w).Rt_past(:)), ...
                double(loaded.Rt_model_input(1:idx_T)).')
            error('FORECAST:WindowHistoryWiring', ...
                'Window Rt_past must equal Rt_model_input history.');
        end
        if ~isempty(window_data(w).U_past) && size(window_data(w).U_past, 1) ~= idx_T
            error('FORECAST:WindowExoLookahead', ...
                'Window U_past must contain only history up to the origin.');
        end
        break;
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
