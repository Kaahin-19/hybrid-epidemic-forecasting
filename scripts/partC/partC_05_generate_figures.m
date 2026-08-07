%PARTC_05_GENERATE_FIGURES Generate Part C thesis figures.
%
%   Description:
%       Generates seven thesis-ready figures from the canonical Part C
%       prepared-data, held-out forecast, and evaluation artifacts. The script
%       performs presentation-only transformations and does not prepare data,
%       fit models, generate forecasts, or recompute evaluation metrics.
%
%   Workflow:
%       1. Load and validate the Script 1, Script 3, and Script 4 artifacts.
%       2. Generate seven figures into staged vector-PDF files.
%       3. Validate the staged files and transactionally promote them.
%       4. Report the canonical figure paths and verify graphics cleanup.
%
%   See also PARTC_CONFIG, PARTC_01_PREPARE_DATA, ...
%            PARTC_03_RUN_FORECASTS, PARTC_04_EVALUATE_FORECASTS, ...
%            PLOT_SERIES, PLOT_DISTRIBUTION, APPLY_PANEL_STYLE.
%
% A. M. Kaahin 2026-08-06

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Thesis Figure Generation ===\n');

cfg = partC_config();
local_validate_visualization_configuration(cfg);
local_require_visualization_dependencies();

if exist(cfg.output.figure_dir, 'dir') ~= 7
    mkdir(cfg.output.figure_dir);
end

canonical_names = [ ...
    "partC_05_data_overview.pdf"
    "partC_05_sirs_proxy_states.pdf"
    "partC_05_fixed_lead_forecasts.pdf"
    "partC_05_origin_wis_distribution.pdf"
    "partC_05_performance_by_lead_time.pdf"
    "partC_05_interval_diagnostics.pdf"
    "partC_05_pairwise_wis_differences.pdf"];
canonical_paths = fullfile(cfg.output.figure_dir, canonical_names);
style = local_style();

%% 2. Load and Validate Source Artifacts
prepared = local_load_prepared_artifact(cfg);
fprintf('Prepared artifact validated\n');

artifacts = local_load_forecast_artifacts(prepared, cfg);
fprintf('Six forecast artifacts validated\n');

evaluation = local_load_evaluation_artifact(prepared, artifacts, cfg);
fprintf('Evaluation artifact validated\n');

%% 3. Generate Staged Figures
staged_paths = strings(numel(canonical_paths), 1);

try
    for figure_index = 1:numel(canonical_paths)
        fprintf('Generating figure %d/7 ...\n', figure_index);
        staged_paths(figure_index) = ...
            string(tempname(cfg.output.figure_dir)) + ".pdf";

        switch figure_index
            case 1
                local_generate_data_overview( ...
                    prepared, cfg, style, staged_paths(figure_index));
            case 2
                local_generate_sirs_proxy_states( ...
                    prepared, cfg, style, staged_paths(figure_index));
            case 3
                local_generate_fixed_lead_forecasts( ...
                    prepared, artifacts, evaluation.online_equivalence, ...
                    cfg, style, staged_paths(figure_index));
            case 4
                local_generate_origin_wis_distribution( ...
                    evaluation.origin_scores, style, ...
                    staged_paths(figure_index));
            case 5
                local_generate_performance_by_lead_time( ...
                    evaluation.summaries.horizon_summary, ...
                    evaluation.online_equivalence, cfg, style, ...
                    staged_paths(figure_index));
            case 6
                local_generate_interval_diagnostics( ...
                    evaluation.summaries.interval_summary, ...
                    evaluation.online_equivalence, cfg, style, ...
                    staged_paths(figure_index));
            case 7
                local_generate_pairwise_wis_differences( ...
                    evaluation.pairwise_comparisons, style, ...
                    staged_paths(figure_index));
        end

        if ~isempty(findall(groot, 'Type', 'figure'))
            error('PARTC_05:OpenFigureAfterExport', ...
                'Figure handles remained open after generating figure %d.', ...
                figure_index);
        end
    end

    local_validate_staged_figures( ...
        staged_paths, canonical_names, canonical_paths);
catch generation_error
    close all;
    local_delete_paths(staged_paths);
    rethrow(generation_error);
end

fprintf('Seven staged figures validated\n');

%% 4. Transactionally Promote Figures
local_promote_figures(staged_paths, canonical_paths);

%% 5. Completion Report
close all;
if ~isempty(findall(groot, 'Type', 'figure'))
    error('PARTC_05:OpenFigureAtCompletion', ...
        'Figure handles remained open after Script 5 completed.');
end

for figure_index = 1:numel(canonical_paths)
    fprintf('Saved figure: %s\n', canonical_paths(figure_index));
end

fprintf('=== Part C Thesis Figure Generation Complete ===\n\n');

%% 6. Local Functions
function local_validate_visualization_configuration(cfg)
%LOCAL_VALIDATE_VISUALIZATION_CONFIGURATION Validate the figure protocol.
required_fields = { ...
    'plot_lead_time'
    'plot_alphas'
    'output_format'
    'vector_content'
    'collapse_exact_online_duplicates'
    };

valid = all(isfield(cfg.visualization, required_fields)) && ...
    cfg.visualization.plot_lead_time == 7 && ...
    isequal(cfg.visualization.plot_alphas, [0.10; 0.50]) && ...
    cfg.visualization.output_format == "pdf" && ...
    cfg.visualization.vector_content && ...
    cfg.visualization.collapse_exact_online_duplicates && ...
    cfg.visualization.plot_lead_time <= cfg.final_forecast.horizon;

for alpha_index = 1:numel(cfg.visualization.plot_alphas)
    valid = valid && nnz(cfg.final_forecast.wis_alphas == ...
        cfg.visualization.plot_alphas(alpha_index)) == 1;
end

if ~valid
    error('PARTC_05:InvalidVisualizationConfiguration', ...
        'Part C visualization configuration does not match the required protocol.');
end
end

function local_require_visualization_dependencies()
%LOCAL_REQUIRE_VISUALIZATION_DEPENDENCIES Require shared plotting helpers.
required_functions = [ ...
    "plot_series"
    "plot_distribution"
    "apply_panel_style"];

for function_index = 1:numel(required_functions)
    if isempty(which(required_functions(function_index)))
        error('PARTC_05:MissingVisualizationDependency', ...
            'Required visualization function is unavailable: %s.', ...
            required_functions(function_index));
    end
end
end

function prepared = local_load_prepared_artifact(cfg)
%LOCAL_LOAD_PREPARED_ARTIFACT Load and validate the Script 1 artifact.
artifact_path = cfg.output.prepared_artifact_path;
if exist(artifact_path, 'file') ~= 2
    error('PARTC_05:MissingPreparedArtifact', ...
        'Missing prepared Part C artifact: %s. Run Part C Script 1 first.', ...
        artifact_path);
end

prepared = load(artifact_path);
required_fields = { ...
    'dates'
    'incidence_observed'
    'Rt_estimated'
    'Rt_valid_mask'
    'S_proxy'
    'I_proxy'
    'R_proxy'
    'I_fraction_proxy'
    'state_valid_mask'
    'preparation_snapshot'
    };

if ~all(isfield(prepared, required_fields))
    missing_fields = required_fields(~isfield(prepared, required_fields));
    error('PARTC_05:MissingPreparedFields', ...
        'Prepared artifact is missing fields: %s.', ...
        strjoin(string(missing_fields), ', '));
end

dates = prepared.dates;
num_observations = numel(dates);
valid_dates = isdatetime(dates) && iscolumn(dates) && ...
    ~any(isnat(dates)) && numel(unique(dates)) == num_observations && ...
    all(diff(dates) == days(1)) && num_observations == 469 && ...
    dates(1) == cfg.study.start_date && dates(end) == cfg.study.end_date;

if ~valid_dates
    error('PARTC_05:InvalidPreparedDates', ...
        'Prepared dates must contain the canonical 469-day configured study period.');
end

vector_fields = { ...
    'incidence_observed'
    'Rt_estimated'
    'S_proxy'
    'I_proxy'
    'R_proxy'
    'I_fraction_proxy'
    };
for field_index = 1:numel(vector_fields)
    values = prepared.(vector_fields{field_index});
    if ~isnumeric(values) || ~isreal(values) || ~iscolumn(values) || ...
            numel(values) ~= num_observations
        error('PARTC_05:InvalidPreparedVector', ...
            'Prepared field %s must be a real numeric column matching dates.', ...
            vector_fields{field_index});
    end
end

if any(~isfinite(prepared.incidence_observed)) || ...
        any(prepared.incidence_observed < 0)
    error('PARTC_05:InvalidPreparedIncidence', ...
        'Reported incidence must be finite and nonnegative.');
end

if ~islogical(prepared.Rt_valid_mask) || ...
        ~iscolumn(prepared.Rt_valid_mask) || ...
        numel(prepared.Rt_valid_mask) ~= num_observations || ...
        ~isequal(prepared.Rt_valid_mask, ...
        isfinite(prepared.Rt_estimated) & prepared.Rt_estimated > 0)
    error('PARTC_05:EstimatedRtMaskMismatch', ...
        'Rt_valid_mask must exactly identify finite positive Rt estimates.');
end

if ~islogical(prepared.state_valid_mask) || ...
        ~iscolumn(prepared.state_valid_mask) || ...
        numel(prepared.state_valid_mask) ~= num_observations
    error('PARTC_05:InvalidStateMask', ...
        'state_valid_mask must be a logical column matching dates.');
end

valid_state = prepared.state_valid_mask;
state_matrix = [prepared.S_proxy, prepared.I_proxy, prepared.R_proxy];
if any(~isfinite(state_matrix(valid_state, :)), 'all') || ...
        any(state_matrix(valid_state, :) < 0, 'all')
    error('PARTC_05:InvalidProxyStates', ...
        'Valid reported-case proxy states must be finite and nonnegative.');
end

population = cfg.state_reconstruction.effective_population;
conservation_error = abs(sum(state_matrix(valid_state, :), 2) - population);
if any(conservation_error > ...
        cfg.state_reconstruction.conservation_tolerance)
    error('PARTC_05:ProxyPopulationConservationFailure', ...
        'Valid reported-case proxy states do not conserve population.');
end

infectious_fraction = prepared.I_fraction_proxy(valid_state);
fraction_tolerance = eps(population);
if any(~isfinite(infectious_fraction)) || ...
        any(infectious_fraction < 0 | infectious_fraction > 1) || ...
        any(abs(infectious_fraction - ...
        prepared.I_proxy(valid_state) / population) > fraction_tolerance)
    error('PARTC_05:InvalidInfectiousFraction', ...
        'Valid infectious proxy fractions must equal I_proxy/effective_population in [0,1].');
end

if ~isequaln(prepared.preparation_snapshot, cfg.snapshot.preparation)
    error('PARTC_05:PreparationSnapshotMismatch', ...
        'Prepared data do not match the configured preparation snapshot.');
end

prepared.artifact_path = artifact_path;
prepared.num_observations = num_observations;
end

function artifacts = local_load_forecast_artifacts(prepared, cfg)
%LOCAL_LOAD_FORECAST_ARTIFACTS Load and validate six canonical forecasts.
artifact_paths = cfg.evaluation.expected_forecast_artifact_paths;
if numel(artifact_paths) ~= 6
    error('PARTC_05:InvalidForecastPathCount', ...
        'Exactly six configured forecast artifact paths are required.');
end

artifacts = cell(numel(artifact_paths), 1);
for artifact_index = 1:numel(artifact_paths)
    artifact_path = artifact_paths(artifact_index);
    if exist(artifact_path, 'file') ~= 2
        error('PARTC_05:MissingForecastArtifact', ...
            'Missing required forecast artifact: %s. Run Part C Script 3 first.', ...
            artifact_path);
    end

    artifact = load(artifact_path);
    local_validate_forecast_artifact( ...
        artifact, artifact_path, artifact_index, prepared, cfg);
    artifacts{artifact_index} = artifact;
end

local_validate_forecast_set(artifacts, cfg);
end

function local_validate_forecast_artifact( ...
        artifact, artifact_path, artifact_index, prepared, cfg)
%LOCAL_VALIDATE_FORECAST_ARTIFACT Validate one Script 3 artifact.
required_fields = { ...
    'model_type'
    'exo_mode'
    'strategy'
    'prepared_artifact_path'
    'calibration_end_date'
    'test_start_date'
    'study_end_date'
    'wis_alphas'
    'results'
    'preparation_snapshot'
    'local_selection_snapshot'
    'forecast_snapshot'
    };
required_result_fields = { ...
    'origin_index'
    'origin_date'
    'target_indices'
    'target_dates'
    'target_Rt_estimated'
    'forecast_median'
    'forecast_lower'
    'forecast_upper'
    };

if ~all(isfield(artifact, required_fields)) || ...
        ~isstruct(artifact.results) || ...
        ~all(isfield(artifact.results, required_result_fields))
    error('PARTC_05:InvalidForecastArtifactSchema', ...
        'Forecast artifact has an incomplete schema: %s.', artifact_path);
end

[expected_model, expected_exo, expected_strategy] = ...
    local_expected_forecast_identity(artifact_index);
configuration_index = 1 + (artifact_index > 3);
valid_metadata = string(artifact.model_type) == expected_model && ...
    string(artifact.exo_mode) == expected_exo && ...
    string(artifact.strategy) == expected_strategy && ...
    string(artifact.prepared_artifact_path) == ...
    string(cfg.output.prepared_artifact_path) && ...
    artifact.calibration_end_date == cfg.validation.calibration_end_date && ...
    artifact.test_start_date == cfg.validation.test_start_date && ...
    artifact.study_end_date == cfg.study.end_date && ...
    isequal(artifact.wis_alphas, cfg.final_forecast.wis_alphas) && ...
    isequaln(artifact.preparation_snapshot, cfg.snapshot.preparation) && ...
    isequaln(artifact.local_selection_snapshot, ...
    cfg.snapshot.local_selection(configuration_index)) && ...
    isequaln(artifact.forecast_snapshot, cfg.snapshot.forecast) && ...
    numel(artifact.results) == 22;

if ~valid_metadata
    error('PARTC_05:ForecastMetadataMismatch', ...
        'Forecast artifact metadata or snapshots are incompatible: %s.', ...
        artifact_path);
end

horizon = cfg.final_forecast.horizon;
num_alphas = numel(cfg.final_forecast.wis_alphas);
for origin_position = 1:numel(artifact.results)
    result = artifact.results(origin_position);
    valid_shapes = isnumeric(result.origin_index) && ...
        isscalar(result.origin_index) && isfinite(result.origin_index) && ...
        isdatetime(result.origin_date) && isscalar(result.origin_date) && ...
        isequal(size(result.target_indices), [horizon, 1]) && ...
        isequal(size(result.target_dates), [horizon, 1]) && ...
        isequal(size(result.target_Rt_estimated), [horizon, 1]) && ...
        isequal(size(result.forecast_median), [horizon, 1]) && ...
        isequal(size(result.forecast_lower), [horizon, num_alphas]) && ...
        isequal(size(result.forecast_upper), [horizon, num_alphas]);
    valid_values = all(isfinite(result.target_Rt_estimated)) && ...
        all(isfinite(result.forecast_median)) && ...
        all(isfinite(result.forecast_lower), 'all') && ...
        all(isfinite(result.forecast_upper), 'all') && ...
        all(result.forecast_lower <= result.forecast_upper, 'all') && ...
        all(result.forecast_lower <= result.forecast_median, 'all') && ...
        all(result.forecast_median <= result.forecast_upper, 'all');

    if ~valid_shapes || ~valid_values || ...
            ~isequal(result.target_dates, ...
            prepared.dates(result.target_indices)) || ...
            ~isequal(result.target_Rt_estimated, ...
            prepared.Rt_estimated(result.target_indices)) || ...
            result.origin_date ~= prepared.dates(result.origin_index)
        error('PARTC_05:InvalidForecastResult', ...
            'Forecast result %d is invalid in %s.', ...
            origin_position, artifact_path);
    end
end
end

function local_validate_forecast_set(artifacts, cfg)
%LOCAL_VALIDATE_FORECAST_SET Validate shared forecast grids.
reference = artifacts{1};
reference_origin_indices = [reference.results.origin_index].';
reference_origin_dates = [reference.results.origin_date].';

for artifact_index = 1:numel(artifacts)
    artifact = artifacts{artifact_index};
    if ~isequal(artifact.wis_alphas, reference.wis_alphas) || ...
            ~isequal([artifact.results.origin_index].', ...
            reference_origin_indices) || ...
            ~isequal([artifact.results.origin_date].', ...
            reference_origin_dates)
        error('PARTC_05:ForecastOriginGridMismatch', ...
            'All forecast artifacts must use identical origins and alphas.');
    end

    for origin_position = 1:numel(reference.results)
        actual = artifact.results(origin_position);
        expected = reference.results(origin_position);
        if ~isequal(actual.target_indices, expected.target_indices) || ...
                ~isequal(actual.target_dates, expected.target_dates) || ...
                ~isequal(actual.target_Rt_estimated, ...
                expected.target_Rt_estimated)
            error('PARTC_05:ForecastTargetGridMismatch', ...
                'All forecast artifacts must use identical target grids.');
        end
    end
end

first_result = reference.results(1);
last_result = reference.results(end);
if reference_origin_dates(1) ~= datetime(2020, 12, 31) || ...
        first_result.target_dates(1) ~= cfg.validation.test_start_date || ...
        reference_origin_dates(end) ~= datetime(2021, 5, 27) || ...
        last_result.target_dates(end) ~= datetime(2021, 6, 10)
    error('PARTC_05:HeldOutGridMismatch', ...
        'Forecast artifacts do not contain the canonical 22-origin held-out grid.');
end
end

function [model, exo_mode, strategy] = ...
        local_expected_forecast_identity(artifact_index)
%LOCAL_EXPECTED_FORECAST_IDENTITY Return one canonical artifact identity.
models = ["AR"; "AR"; "AR"; "ARX"; "ARX"; "ARX"];
exo_modes = ["None"; "None"; "None"; "I"; "I"; "I"];
strategies = [ ...
    "partA_online_fit"
    "local_online_fit"
    "partA_fixed_fit"
    "partA_online_fit"
    "local_online_fit"
    "partA_fixed_fit"];
model = models(artifact_index);
exo_mode = exo_modes(artifact_index);
strategy = strategies(artifact_index);
end

function evaluation = local_load_evaluation_artifact(prepared, artifacts, cfg)
%LOCAL_LOAD_EVALUATION_ARTIFACT Load and validate Script 4 results.
artifact_path = fullfile( ...
    cfg.output.evaluation_dir, "partC_04_evaluation_results.mat");
if exist(artifact_path, 'file') ~= 2
    error('PARTC_05:MissingEvaluationArtifact', ...
        'Missing evaluation artifact: %s. Run Part C Script 4 first.', ...
        artifact_path);
end

evaluation = load(artifact_path);
required_fields = { ...
    'origin_scores'
    'horizon_scores'
    'interval_scores'
    'summaries'
    'pairwise_comparisons'
    'online_equivalence'
    'forecast_artifact_paths'
    'prepared_artifact_path'
    'preparation_snapshot'
    'forecast_snapshot'
    'evaluation_snapshot'
    'target_description'
    };

if ~all(isfield(evaluation, required_fields)) || ...
        ~isstruct(evaluation.summaries) || ...
        ~all(isfield(evaluation.summaries, ...
        {'strategy_summary', 'horizon_summary', 'interval_summary'}))
    error('PARTC_05:InvalidEvaluationSchema', ...
        'The Script 4 evaluation artifact has an incomplete schema.');
end

local_validate_evaluation_tables(evaluation, cfg);
local_validate_evaluation_sources(evaluation, prepared, artifacts, cfg);
local_validate_online_equivalence( ...
    evaluation.online_equivalence, artifacts);
evaluation.artifact_path = artifact_path;
end

function local_validate_evaluation_tables(evaluation, cfg)
%LOCAL_VALIDATE_EVALUATION_TABLES Validate stored table contracts.
origin_variables = { ...
    'Model', 'ExoMode', 'Strategy', 'StrategyDescription', ...
    'ConfigurationSource', 'ParameterUpdateMode', ...
    'ForecastConfiguration', 'OriginPosition', 'OriginIndex', ...
    'OriginDate', 'TargetStartDate', 'TargetEndDate', 'MeanWIS', ...
    'RMSE', 'MAE', 'MeanError', 'MeanCoverage', ...
    'MeanIntervalWidth', 'FitAICc'};
horizon_variables = { ...
    'Model', 'ExoMode', 'Strategy', 'ForecastConfiguration', ...
    'OriginPosition', 'OriginIndex', 'OriginDate', 'LeadTime', ...
    'TargetIndex', 'TargetDate', 'TargetRtEstimated', ...
    'MedianForecast', 'Error', 'AbsoluteError', 'SquaredError', ...
    'WIS', 'MeanCoverage', 'MeanIntervalWidth'};
interval_variables = { ...
    'Model', 'ExoMode', 'Strategy', 'ForecastConfiguration', ...
    'OriginPosition', 'OriginDate', 'Alpha', 'NominalCoverage', ...
    'EmpiricalCoverage', 'CoverageError', 'MeanIntervalWidth'};
strategy_variables = { ...
    'Model', 'ExoMode', 'Strategy', 'ForecastConfiguration', ...
    'ConfigurationSource', 'ParameterUpdateMode', 'NumOrigins', ...
    'MeanOriginWIS', 'MedianOriginWIS', 'StdOriginWIS', ...
    'MinOriginWIS', 'MaxOriginWIS', 'MeanRMSE', 'MeanMAE', ...
    'MeanError', 'MeanCoverage', 'MeanIntervalWidth'};
horizon_summary_variables = { ...
    'Model', 'ExoMode', 'Strategy', 'LeadTime', 'NumForecasts', ...
    'MeanWIS', 'MedianWIS', 'MeanAbsoluteError', ...
    'MeanSquaredError', 'RMSE', 'MeanError', 'MeanCoverage', ...
    'MeanIntervalWidth'};
interval_summary_variables = { ...
    'Model', 'ExoMode', 'Strategy', 'Alpha', 'NominalCoverage', ...
    'NumIntervalForecasts', 'EmpiricalCoverage', ...
    'CoverageError', 'MeanIntervalWidth'};
comparison_variables = { ...
    'ComparisonType', 'ModelOrStrategy', 'LeftLabel', 'RightLabel', ...
    'DifferenceDefinition', 'NumMatchedOrigins', 'MeanWISDifference', ...
    'MedianWISDifference', 'MinWISDifference', 'MaxWISDifference', ...
    'ProportionLeftBetter', 'ProportionEqual', ...
    'ProportionRightBetter'};
equivalence_variables = { ...
    'Model', 'ExoMode', 'PartAConfiguration', 'LocalConfiguration', ...
    'ConfigurationsEqual', 'ForecastsExactlyIdentical', ...
    'MaxMedianAbsoluteDifference', 'MaxLowerAbsoluteDifference', ...
    'MaxUpperAbsoluteDifference', 'TargetsExactlyIdentical', ...
    'Interpretation'};

local_require_table( ...
    evaluation.origin_scores, origin_variables, 132, 'origin_scores');
local_require_table( ...
    evaluation.horizon_scores, horizon_variables, 1848, 'horizon_scores');
local_require_table( ...
    evaluation.interval_scores, interval_variables, 528, 'interval_scores');
local_require_table(evaluation.summaries.strategy_summary, ...
    strategy_variables, 6, 'strategy_summary');
local_require_table(evaluation.summaries.horizon_summary, ...
    horizon_summary_variables, 84, 'horizon_summary');
local_require_table(evaluation.summaries.interval_summary, ...
    interval_summary_variables, 24, 'interval_summary');
local_require_table(evaluation.pairwise_comparisons, ...
    comparison_variables, 7, 'pairwise_comparisons');
local_require_table(evaluation.online_equivalence, ...
    equivalence_variables, 2, 'online_equivalence');

expected_models = ["AR"; "AR"; "AR"; "ARX"; "ARX"; "ARX"];
expected_exo_modes = ["None"; "None"; "None"; "I"; "I"; "I"];
expected_strategies = [ ...
    "partA_online_fit"
    "local_online_fit"
    "partA_fixed_fit"
    "partA_online_fit"
    "local_online_fit"
    "partA_fixed_fit"];
identities = unique(evaluation.origin_scores(:, ...
    {'Model', 'ExoMode', 'Strategy'}), 'rows', 'stable');

if ~isequal(identities.Model, expected_models) || ...
        ~isequal(identities.ExoMode, expected_exo_modes) || ...
        ~isequal(identities.Strategy, expected_strategies) || ...
        ~isequal(unique(evaluation.horizon_scores.LeadTime, 'stable'), ...
        (1:cfg.final_forecast.horizon).') || ...
        ~isequal(unique(evaluation.interval_scores.Alpha, 'stable'), ...
        cfg.final_forecast.wis_alphas) || ...
        ~isequal(unique( ...
        evaluation.summaries.interval_summary.NominalCoverage, 'stable'), ...
        1 - cfg.final_forecast.wis_alphas)
    error('PARTC_05:EvaluationGridMismatch', ...
        'Evaluation tables do not contain the required identities or grids.');
end

numeric_values = { ...
    evaluation.origin_scores.MeanWIS
    evaluation.horizon_scores.WIS
    evaluation.horizon_scores.AbsoluteError
    evaluation.interval_scores.EmpiricalCoverage
    evaluation.interval_scores.MeanIntervalWidth
    evaluation.summaries.horizon_summary.MeanWIS
    evaluation.summaries.horizon_summary.MeanAbsoluteError
    evaluation.summaries.interval_summary.EmpiricalCoverage
    evaluation.summaries.interval_summary.MeanIntervalWidth
    evaluation.pairwise_comparisons.MeanWISDifference
    };
if any(cellfun(@(values) any(~isfinite(values)), numeric_values)) || ...
        any(evaluation.summaries.interval_summary.EmpiricalCoverage < 0 | ...
        evaluation.summaries.interval_summary.EmpiricalCoverage > 1) || ...
        any(evaluation.summaries.interval_summary.MeanIntervalWidth < 0)
    error('PARTC_05:InvalidEvaluationValues', ...
        'Stored evaluation values are nonfinite or outside their valid domains.');
end

zero_rows = evaluation.pairwise_comparisons.ComparisonType == ...
    "local_vs_partA_online_within_model";
if nnz(zero_rows) ~= 2 || ...
        any(evaluation.pairwise_comparisons.MeanWISDifference(zero_rows) ~= 0)
    error('PARTC_05:CurrentOnlineComparisonMismatch', ...
        'Current local-online versus Part A-online comparisons must equal zero.');
end
end

function local_require_table(table_data, variables, row_count, table_name)
%LOCAL_REQUIRE_TABLE Require an exact stored table contract.
if ~istable(table_data) || ...
        ~isequal(table_data.Properties.VariableNames, variables) || ...
        height(table_data) ~= row_count
    error('PARTC_05:InvalidEvaluationTable', ...
        '%s does not satisfy its required variable and row-count contract.', ...
        table_name);
end
end

function local_validate_evaluation_sources(evaluation, prepared, artifacts, cfg)
%LOCAL_VALIDATE_EVALUATION_SOURCES Validate evaluation provenance.
artifact_paths = strings(numel(artifacts), 1);
for artifact_index = 1:numel(artifacts)
    artifact_paths(artifact_index) = ...
        string(cfg.evaluation.expected_forecast_artifact_paths(artifact_index));
end

valid = isequal(string(evaluation.forecast_artifact_paths), ...
    artifact_paths) && ...
    string(evaluation.prepared_artifact_path) == ...
    string(prepared.artifact_path) && ...
    isequaln(evaluation.preparation_snapshot, cfg.snapshot.preparation) && ...
    isequaln(evaluation.forecast_snapshot, cfg.snapshot.forecast) && ...
    isequaln(evaluation.evaluation_snapshot, cfg.snapshot.evaluation) && ...
    contains(string(evaluation.target_description), ...
    "Operational Rt estimate") && ...
    ~contains(lower(string(evaluation.target_description)), "true rt");

if ~valid
    error('PARTC_05:EvaluationProvenanceMismatch', ...
        'Evaluation artifact paths, snapshots, or target description are incompatible.');
end
end

function local_validate_online_equivalence(equivalence, artifacts)
%LOCAL_VALIDATE_ONLINE_EQUIVALENCE Reconcile stored equivalence with forecasts.
if ~isequal(equivalence.Model, ["AR"; "ARX"]) || ...
        ~isequal(equivalence.ExoMode, ["None"; "I"]) || ...
        ~all(equivalence.TargetsExactlyIdentical)
    error('PARTC_05:InvalidOnlineEquivalence', ...
        'Online-equivalence rows do not identify the required model pairs.');
end

for pair_index = 1:2
    base_index = (pair_index - 1) * 3;
    partA_online = artifacts{base_index + 1};
    local_online = artifacts{base_index + 2};
    medians_equal = isequal( ...
        vertcat(partA_online.results.forecast_median), ...
        vertcat(local_online.results.forecast_median));
    lower_equal = isequal( ...
        vertcat(partA_online.results.forecast_lower), ...
        vertcat(local_online.results.forecast_lower));
    upper_equal = isequal( ...
        vertcat(partA_online.results.forecast_upper), ...
        vertcat(local_online.results.forecast_upper));
    targets_equal = isequal( ...
        vertcat(partA_online.results.target_Rt_estimated), ...
        vertcat(local_online.results.target_Rt_estimated));
    forecasts_equal = medians_equal && lower_equal && upper_equal;

    if equivalence.ForecastsExactlyIdentical(pair_index) ~= ...
            forecasts_equal || ...
            equivalence.TargetsExactlyIdentical(pair_index) ~= targets_equal
        error('PARTC_05:OnlineEquivalenceMismatch', ...
            'Stored online equivalence does not match the forecast artifacts.');
    end
end
end

function local_generate_data_overview(prepared, cfg, style, output_path)
%LOCAL_GENERATE_DATA_OVERVIEW Generate incidence and operational-Rt panels.
num_observations = prepared.num_observations;
dates = prepared.dates(1:num_observations);
incidence = prepared.incidence_observed(1:num_observations);
Rt_plot = prepared.Rt_estimated(1:num_observations);
Rt_plot(~prepared.Rt_valid_mask(1:num_observations)) = NaN;

fig = local_new_figure([2, 2, 17.0, 12.0]);
cleanup = onCleanup(@() local_close_figure(fig));
layout = tiledlayout(fig, 2, 1, ...
    'Padding', 'compact', 'TileSpacing', 'compact');

ax = nexttile(layout);
series = [ ...
    local_line_series(dates, incidence, style.data_color, "-", "", style.line_width)
    local_vertical_reference(cfg.validation.test_start_date, ...
    incidence, style)];
spec = struct('series', series, 'style', ...
    local_axis_style("", "Reported daily incidence", style));
plot_series(ax, spec);
xlim(ax, [dates(1), dates(end)]);
xtickformat(ax, 'MMM yyyy');
local_period_labels(ax, style);
local_panel_label(ax, "(a)", style);

ax = nexttile(layout);
valid_Rt = Rt_plot(isfinite(Rt_plot));
series = [ ...
    local_line_series(dates, Rt_plot, style.data_color, "-", "", style.line_width)
    local_vertical_reference(cfg.validation.test_start_date, ...
    valid_Rt, style)];
spec = struct('series', series, 'style', ...
    local_axis_style("", ...
    "Operational effective reproduction number, R_t", style));
plot_series(ax, spec);
xlim(ax, [dates(1), dates(end)]);
xtickformat(ax, 'MMM yyyy');
local_period_labels(ax, style);
local_panel_label(ax, "(b)", style);

local_export_and_close(fig, output_path);
clear cleanup;
end

function local_generate_sirs_proxy_states(prepared, cfg, style, output_path)
%LOCAL_GENERATE_SIRS_PROXY_STATES Generate three proxy-fraction panels.
dates = prepared.dates;
population = cfg.state_reconstruction.effective_population;
state_valid = prepared.state_valid_mask;
fractions = [ ...
    prepared.S_proxy / population, ...
    prepared.I_fraction_proxy, ...
    prepared.R_proxy / population];
fractions(~state_valid, :) = NaN;
y_labels = [ ...
    "Susceptible proxy fraction, S/N"
    "Infectious proxy fraction, I/N"
    "Recovered proxy fraction, R/N"];
colors = [style.model.AR; style.model.ARX; style.proxy_recovered];

fig = local_new_figure([2, 2, 17.0, 15.0]);
cleanup = onCleanup(@() local_close_figure(fig));
layout = tiledlayout(fig, 3, 1, ...
    'Padding', 'compact', 'TileSpacing', 'compact');
title(layout, "Reported-case SIRS proxy fractions", ...
    'FontName', style.font_name, 'FontSize', style.title_font_size, ...
    'FontWeight', 'normal', 'Interpreter', 'tex');

for panel_index = 1:3
    ax = nexttile(layout);
    values = fractions(:, panel_index);
    valid_values = values(isfinite(values));
    series = [ ...
        local_line_series(dates, values, colors(panel_index, :), ...
        "-", "", style.line_width)
        local_vertical_reference(cfg.validation.test_start_date, ...
        valid_values, style)];
    spec = struct('series', series, 'style', ...
        local_axis_style("", y_labels(panel_index), style));
    plot_series(ax, spec);
    xlim(ax, [dates(1), dates(end)]);
    xtickformat(ax, 'MMM yyyy');
    local_panel_label(ax, "(" + char('a' + panel_index - 1) + ")", style);
end

local_export_and_close(fig, output_path);
clear cleanup;
end

function local_generate_fixed_lead_forecasts( ...
        prepared, artifacts, equivalence, cfg, style, output_path)
%LOCAL_GENERATE_FIXED_LEAD_FORECASTS Generate fixed-lead comparison panels.
panels = local_forecast_panels(artifacts, equivalence, cfg);
lead_time = cfg.visualization.plot_lead_time;
plot_alphas = cfg.visualization.plot_alphas;
num_panels = numel(panels);
num_columns = 2;
num_rows = ceil(num_panels / num_columns);
figure_height = 6.2 * num_rows + 1.8;

held_out_mask = prepared.dates >= cfg.validation.test_start_date;
held_out_dates = prepared.dates(held_out_mask);
held_out_Rt = prepared.Rt_estimated(held_out_mask);
held_out_valid = prepared.Rt_valid_mask(held_out_mask);
held_out_Rt(~held_out_valid) = NaN;

panel_data = cell(num_panels, 1);
displayed_value_blocks = cell(num_panels + 1, 1);
displayed_value_blocks{1} = held_out_Rt(isfinite(held_out_Rt));
for panel_index = 1:num_panels
    panel_data{panel_index} = local_extract_fixed_lead( ...
        panels(panel_index).artifact, lead_time, plot_alphas);
    data = panel_data{panel_index};
    displayed_value_blocks{panel_index + 1} = [ ...
        data.target_Rt
        data.median
        data.lower(:)
        data.upper(:)];
end
all_displayed_values = vertcat(displayed_value_blocks{:});

[common_lower, common_upper] = ...
    local_forecast_axis_limits(all_displayed_values);

fig = local_new_figure([2, 2, 17.5, figure_height]);
cleanup = onCleanup(@() local_close_figure(fig));
layout = tiledlayout(fig, num_rows, num_columns, ...
    'Padding', 'compact', 'TileSpacing', 'compact');
legend_handles = gobjects(0, 1);
legend_labels = strings(0, 1);
legend_axes = gobjects(1, 1);

for panel_index = 1:num_panels
    ax = nexttile(layout);
    data = panel_data{panel_index};
    model_color = local_model_color( ...
        panels(panel_index).artifact.model_type, style);
    series = local_forecast_series( ...
        held_out_dates, held_out_Rt, data, model_color, style);
    axis_style = local_axis_style("", ...
        "Operational effective reproduction number, R_t", style);
    axis_style.y_limits = [common_lower, common_upper];
    spec = struct('series', series, 'style', axis_style);
    [handles, labels] = plot_series(ax, spec);
    xlim(ax, [held_out_dates(1), held_out_dates(end)]);
    xtickformat(ax, 'MMM yyyy');
    title(ax, panels(panel_index).title, ...
        'FontName', style.font_name, ...
        'FontSize', style.panel_font_size, ...
        'FontWeight', 'normal', 'Interpreter', 'tex');
    local_panel_label(ax, ...
        "(" + char('a' + panel_index - 1) + ")", style);

    if panel_index == 1
        legend_handles = handles;
        legend_labels = labels;
        legend_axes = ax;
    end
end

local_shared_legend( ...
    legend_axes, legend_handles, legend_labels, style, 4);
local_export_and_close(fig, output_path);
clear cleanup;
end

function panels = local_forecast_panels(artifacts, equivalence, cfg)
%LOCAL_FORECAST_PANELS Resolve online equivalence into display panels.
panel_template = struct('artifact', struct(), 'title', "");
collapse_flags = cfg.visualization.collapse_exact_online_duplicates & ...
    equivalence.ForecastsExactlyIdentical;
panels = repmat(panel_template, 4 + nnz(~collapse_flags), 1);
panel_index = 0;

for pair_index = 1:2
    base_index = (pair_index - 1) * 3;
    partA_online = artifacts{base_index + 1};
    local_online = artifacts{base_index + 2};
    fixed_fit = artifacts{base_index + 3};
    model_label = local_model_label( ...
        partA_online.model_type, partA_online.exo_mode);
    collapse = cfg.visualization.collapse_exact_online_duplicates && ...
        equivalence.ForecastsExactlyIdentical(pair_index);

    if collapse
        panel_index = panel_index + 1;
        panels(panel_index) = struct( ...
            'artifact', partA_online, ...
            'title', model_label + " — Part A/local online — identical");
    else
        panel_index = panel_index + 1;
        panels(panel_index) = struct( ...
            'artifact', partA_online, ...
            'title', model_label + " — Part A online");
        panel_index = panel_index + 1;
        panels(panel_index) = struct( ...
            'artifact', local_online, ...
            'title', model_label + " — Local online");
    end

    panel_index = panel_index + 1;
    panels(panel_index) = struct( ...
        'artifact', fixed_fit, ...
        'title', model_label + " — Fixed calibration fit");
end
end

function data = local_extract_fixed_lead(artifact, lead_time, plot_alphas)
%LOCAL_EXTRACT_FIXED_LEAD Extract one lead and two stored interval levels.
num_origins = numel(artifact.results);
num_alphas = numel(plot_alphas);
target_dates = NaT(num_origins, 1);
target_Rt = zeros(num_origins, 1);
median_forecast = zeros(num_origins, 1);
lower = zeros(num_origins, num_alphas);
upper = zeros(num_origins, num_alphas);

alpha_columns = zeros(num_alphas, 1);
for alpha_index = 1:num_alphas
    alpha_columns(alpha_index) = find( ...
        artifact.wis_alphas == plot_alphas(alpha_index), 1);
end

for origin_position = 1:num_origins
    result = artifact.results(origin_position);
    target_dates(origin_position) = result.target_dates(lead_time);
    target_Rt(origin_position) = result.target_Rt_estimated(lead_time);
    median_forecast(origin_position) = result.forecast_median(lead_time);
    lower(origin_position, :) = ...
        result.forecast_lower(lead_time, alpha_columns);
    upper(origin_position, :) = ...
        result.forecast_upper(lead_time, alpha_columns);
end

data = struct( ...
    'target_dates', target_dates, ...
    'target_Rt', target_Rt, ...
    'median', median_forecast, ...
    'lower', lower, ...
    'upper', upper);
end

function series = local_forecast_series( ...
        held_out_dates, held_out_Rt, data, model_color, style)
%LOCAL_FORECAST_SERIES Build ordered ribbons, target, and median series.
series = repmat(local_series_template(), 4, 1);

series(1).type = "ribbon";
series(1).x = data.target_dates;
series(1).lower = data.lower(:, 1);
series(1).upper = data.upper(:, 1);
series(1).face_color = local_lighten_color(model_color, 0.82);
series(1).face_alpha = 1;
series(1).label = "90% PI";

series(2).type = "ribbon";
series(2).x = data.target_dates;
series(2).lower = data.lower(:, 2);
series(2).upper = data.upper(:, 2);
series(2).face_color = local_lighten_color(model_color, 0.62);
series(2).face_alpha = 1;
series(2).label = "50% PI";

series(3) = local_line_series( ...
    held_out_dates, held_out_Rt, style.data_color, "-", ...
    "Operational Rt estimate", style.target_line_width);

series(4) = local_line_series( ...
    data.target_dates, data.median, model_color, "-", ...
    "Median forecast", style.forecast_line_width);
series(4).marker = "o";
series(4).marker_size = style.marker_size;
end

function [lower_limit, upper_limit] = local_forecast_axis_limits(values)
%LOCAL_FORECAST_AXIS_LIMITS Compute common uncapped limits with padding.
data_minimum = min(values);
data_maximum = max(values);
data_range = data_maximum - data_minimum;
padding = 0.05 * max([data_range, abs(data_maximum), eps]);
lower_limit = max(0, data_minimum - padding);
upper_limit = data_maximum + padding;
end

function local_generate_origin_wis_distribution( ...
        origin_scores, style, output_path)
%LOCAL_GENERATE_ORIGIN_WIS_DISTRIBUTION Generate grouped origin-WIS boxes.
model_labels = local_model_labels(origin_scores.Model, origin_scores.ExoMode);
strategy_labels = local_strategy_labels(origin_scores.Strategy);
model_plot_labels = model_labels;
model_plot_labels(model_labels == "AR / None") = "1 AR / None";
model_plot_labels(model_labels == "ARX/I") = "2 ARX / I";
strategy_plot_labels = strategy_labels;
strategy_plot_labels(strategy_labels == "Part A online") = ...
    "1 Part A online";
strategy_plot_labels(strategy_labels == "Local online") = ...
    "2 Local online";
strategy_plot_labels(strategy_labels == "Part A fixed") = ...
    "3 Part A fixed";

fig = local_new_figure([2, 2, 16.0, 10.0]);
cleanup = onCleanup(@() local_close_figure(fig));
ax = axes('Parent', fig);
dist_spec = struct( ...
    'x', model_plot_labels, ...
    'y', origin_scores.MeanWIS, ...
    'group', strategy_plot_labels, ...
    'color_order', style.strategy_colors, ...
    'style', local_axis_style( ...
    "Model / exogenous mode", "Mean origin WIS", style));
[handles, labels] = plot_distribution(ax, dist_spec);
xticklabels(ax, ["AR / None", "ARX / I"]);
labels = erase(labels, ["1 ", "2 ", "3 "]);
local_axes_legend(ax, handles, labels, style, 3);
local_export_and_close(fig, output_path);
clear cleanup;
end

function local_generate_performance_by_lead_time( ...
        horizon_summary, equivalence, cfg, style, output_path)
%LOCAL_GENERATE_PERFORMANCE_BY_LEAD_TIME Generate WIS and MAE panels.
fig = local_new_figure([2, 2, 17.5, 8.5]);
cleanup = onCleanup(@() local_close_figure(fig));
layout = tiledlayout(fig, 1, 2, ...
    'Padding', 'compact', 'TileSpacing', 'compact');

ax = nexttile(layout);
series = local_summary_series( ...
    horizon_summary, 'LeadTime', 'MeanWIS', equivalence, cfg, style);
spec = struct('series', series, 'style', ...
    local_axis_style("Lead time (days)", "Mean WIS", style));
[handles, labels] = plot_series(ax, spec);
xticks(ax, 1:cfg.final_forecast.horizon);
xlim(ax, [1, cfg.final_forecast.horizon]);
local_panel_label(ax, "(a)", style);

ax = nexttile(layout);
series = local_summary_series( ...
    horizon_summary, 'LeadTime', 'MeanAbsoluteError', ...
    equivalence, cfg, style);
spec = struct('series', series, 'style', ...
    local_axis_style("Lead time (days)", "Mean absolute error", style));
plot_series(ax, spec);
xticks(ax, 1:cfg.final_forecast.horizon);
xlim(ax, [1, cfg.final_forecast.horizon]);
local_panel_label(ax, "(b)", style);

local_shared_legend(ax, handles, labels, style, 2);
local_export_and_close(fig, output_path);
clear cleanup;
end

function local_generate_interval_diagnostics( ...
        interval_summary, equivalence, cfg, style, output_path)
%LOCAL_GENERATE_INTERVAL_DIAGNOSTICS Generate coverage and width panels.
fig = local_new_figure([2, 2, 17.5, 8.5]);
cleanup = onCleanup(@() local_close_figure(fig));
layout = tiledlayout(fig, 1, 2, ...
    'Padding', 'compact', 'TileSpacing', 'compact');

ax = nexttile(layout);
reference = local_line_series( ...
    [0; 1], [0; 1], style.data_color, "--", ...
    "Nominal = empirical", style.reference_line_width);
reference.type = "reference";
method_series = local_summary_series( ...
    interval_summary, 'NominalCoverage', 'EmpiricalCoverage', ...
    equivalence, cfg, style);
series = [reference; method_series];
axis_style = local_axis_style( ...
    "Nominal coverage", "Empirical coverage", style);
axis_style.x_limits = [0, 1];
axis_style.y_limits = [0, 1];
spec = struct('series', series, 'style', axis_style);
[handles, labels] = plot_series(ax, spec);
local_panel_label(ax, "(a)", style);

ax = nexttile(layout);
series = local_summary_series( ...
    interval_summary, 'NominalCoverage', 'MeanIntervalWidth', ...
    equivalence, cfg, style);
maximum_width = max(interval_summary.MeanIntervalWidth);
width_upper = 1.05 * maximum_width;
if width_upper == 0
    width_upper = eps;
end
axis_style = local_axis_style( ...
    "Nominal coverage", "Mean interval width", style);
axis_style.x_limits = [0, 1];
axis_style.y_limits = [0, width_upper];
spec = struct('series', series, 'style', axis_style);
plot_series(ax, spec);
local_panel_label(ax, "(b)", style);

local_shared_legend(ax, handles, labels, style, 2);
local_export_and_close(fig, output_path);
clear cleanup;
end

function series = local_summary_series( ...
        summary, x_variable, y_variable, equivalence, cfg, style)
%LOCAL_SUMMARY_SERIES Build model-colour and strategy-style curves.
models = ["AR", "None"; "ARX", "I"];
collapse_flags = cfg.visualization.collapse_exact_online_duplicates & ...
    equivalence.ForecastsExactlyIdentical;
series = repmat(local_series_template(), 4 + nnz(~collapse_flags), 1);
series_index = 0;

for model_index = 1:size(models, 1)
    model = models(model_index, 1);
    exo_mode = models(model_index, 2);
    model_rows = summary(summary.Model == model & ...
        summary.ExoMode == exo_mode, :);
    model_color = local_model_color(model, style);
    model_label = local_model_label(model, exo_mode);
    collapse = cfg.visualization.collapse_exact_online_duplicates && ...
        equivalence.ForecastsExactlyIdentical(model_index);

    partA_rows = sortrows(model_rows( ...
        model_rows.Strategy == "partA_online_fit", :), x_variable);
    local_rows = sortrows(model_rows( ...
        model_rows.Strategy == "local_online_fit", :), x_variable);
    fixed_rows = sortrows(model_rows( ...
        model_rows.Strategy == "partA_fixed_fit", :), x_variable);

    if collapse
        if ~isequal(partA_rows.(x_variable), local_rows.(x_variable)) || ...
                ~isequal(partA_rows.(y_variable), local_rows.(y_variable))
            error('PARTC_05:CollapsedSummaryMismatch', ...
                'Exactly equivalent online forecasts have inconsistent stored summaries.');
        end

        next_series = local_line_series( ...
            partA_rows.(x_variable), partA_rows.(y_variable), ...
            model_color, "-", ...
            model_label + " online — Part A/local identical", ...
            style.line_width);
        next_series.marker = "o";
        next_series.marker_size = style.marker_size;
        series_index = series_index + 1;
        series(series_index) = next_series;
    else
        next_series = local_line_series( ...
            partA_rows.(x_variable), partA_rows.(y_variable), ...
            model_color, "-", model_label + " — Part A online", ...
            style.line_width);
        next_series.marker = "o";
        next_series.marker_size = style.marker_size;
        series_index = series_index + 1;
        series(series_index) = next_series;

        next_series = local_line_series( ...
            local_rows.(x_variable), local_rows.(y_variable), ...
            model_color, "--", model_label + " — Local online", ...
            style.line_width);
        next_series.marker = "s";
        next_series.marker_size = style.marker_size;
        series_index = series_index + 1;
        series(series_index) = next_series;
    end

    next_series = local_line_series( ...
        fixed_rows.(x_variable), fixed_rows.(y_variable), ...
        model_color, ":", model_label + " — Part A fixed", ...
        style.line_width);
    next_series.marker = "^";
    next_series.marker_size = style.marker_size;
    series_index = series_index + 1;
    series(series_index) = next_series;
end
end

function local_generate_pairwise_wis_differences( ...
        comparisons, style, output_path)
%LOCAL_GENERATE_PAIRWISE_WIS_DIFFERENCES Generate matched WIS lollipops.
differences = comparisons.MeanWISDifference;
num_comparisons = numel(differences);
positions = (1:num_comparisons).';
labels = strings(num_comparisons, 1);
for comparison_index = 1:num_comparisons
    labels(comparison_index) = local_comparison_label( ...
        comparisons(comparison_index, :));
end

axis_limit = 1.08 * max(abs(differences));
if axis_limit == 0
    axis_limit = 1e-6;
end

stem_x = NaN(3 * num_comparisons, 1);
stem_y = NaN(3 * num_comparisons, 1);
for comparison_index = 1:num_comparisons
    row_indices = (comparison_index - 1) * 3 + (1:3);
    stem_x(row_indices) = [0; differences(comparison_index); NaN];
    stem_y(row_indices) = [ ...
        positions(comparison_index); positions(comparison_index); NaN];
end

series = repmat(local_series_template(), 3, 1);
series(1) = local_line_series( ...
    [0; 0], [0.5; num_comparisons + 0.5], ...
    style.data_color, "--", "", style.reference_line_width);
series(1).type = "reference";
series(2) = local_line_series( ...
    stem_x, stem_y, style.pairwise_color, "-", "", style.line_width);
series(3) = local_line_series( ...
    differences, positions, style.pairwise_color, "none", "", ...
    style.line_width);
series(3).marker = "o";
series(3).marker_size = style.pairwise_marker_size;

fig = local_new_figure([2, 2, 17.0, 10.0]);
cleanup = onCleanup(@() local_close_figure(fig));
ax = axes('Parent', fig);
axis_style = local_axis_style( ...
    "Left mean WIS − right mean WIS; negative values favour the left-hand method", ...
    "", style);
axis_style.x_limits = [-axis_limit, axis_limit];
axis_style.y_limits = [0.5, num_comparisons + 0.5];
spec = struct('series', series, 'style', axis_style);
plot_series(ax, spec);
yticks(ax, positions);
yticklabels(ax, labels);
ax.YDir = 'reverse';
local_export_and_close(fig, output_path);
clear cleanup;
end

function label = local_comparison_label(row)
%LOCAL_COMPARISON_LABEL Build a concise stored-orientation label.
context = local_pretty_identity(row.ModelOrStrategy);
left = local_pretty_identity(row.LeftLabel);
right = local_pretty_identity(row.RightLabel);
label = context + ": " + left + " − " + right;
end

function label = local_pretty_identity(identifier)
%LOCAL_PRETTY_IDENTITY Convert stored identifiers to display labels.
identifier = string(identifier);
switch identifier
    case "partA_online_fit"
        label = "Part A online";
    case "local_online_fit"
        label = "Local online";
    case "partA_fixed_fit"
        label = "Part A fixed";
    case "AR/None"
        label = "AR";
    otherwise
        label = replace(identifier, "_", " ");
end
end

function local_validate_staged_figures( ...
        staged_paths, canonical_names, canonical_paths)
%LOCAL_VALIDATE_STAGED_FIGURES Validate the complete staged PDF set.
if numel(staged_paths) ~= 7 || numel(unique(staged_paths)) ~= 7 || ...
        numel(canonical_names) ~= 7 || numel(unique(canonical_names)) ~= 7 || ...
        numel(canonical_paths) ~= 7 || numel(unique(canonical_paths)) ~= 7
    error('PARTC_05:InvalidFigureSet', ...
        'The staged and canonical figure sets must contain seven unique paths.');
end

for figure_index = 1:numel(staged_paths)
    if exist(staged_paths(figure_index), 'file') ~= 2
        error('PARTC_05:MissingStagedFigure', ...
            'Missing staged figure: %s.', staged_paths(figure_index));
    end

    file_info = dir(staged_paths(figure_index));
    if numel(file_info) ~= 1 || file_info.isdir || file_info.bytes <= 0
        error('PARTC_05:InvalidStagedFigure', ...
            'Staged figure is not a nonempty regular file: %s.', ...
            staged_paths(figure_index));
    end
end
end

function local_promote_figures(staged_paths, canonical_paths)
%LOCAL_PROMOTE_FIGURES Promote seven PDFs with complete rollback.
num_figures = numel(canonical_paths);
backup_paths = strings(num_figures, 1);
had_canonical = false(num_figures, 1);
promoted = false(num_figures, 1);

try
    for figure_index = 1:num_figures
        if exist(canonical_paths(figure_index), 'file') == 2
            had_canonical(figure_index) = true;
            backup_paths(figure_index) = ...
                string(tempname(fileparts(canonical_paths(figure_index)))) ...
                + ".pdf";
            [copied, message] = copyfile( ...
                canonical_paths(figure_index), backup_paths(figure_index));
            if ~copied
                error('PARTC_05:FigureBackupFailed', ...
                    'Could not back up %s: %s', ...
                    canonical_paths(figure_index), message);
            end
        end
    end

    for figure_index = 1:num_figures
        [moved, message] = movefile( ...
            staged_paths(figure_index), canonical_paths(figure_index), 'f');
        if ~moved
            error('PARTC_05:FigurePromotionFailed', ...
                'Could not promote %s: %s', ...
                canonical_paths(figure_index), message);
        end
        promoted(figure_index) = true;
        staged_paths(figure_index) = "";
    end

    for figure_index = 1:num_figures
        if exist(canonical_paths(figure_index), 'file') ~= 2 || ...
                dir(canonical_paths(figure_index)).bytes <= 0
            error('PARTC_05:IncompleteCanonicalFigureSet', ...
                'The canonical figure set is incomplete after promotion.');
        end
    end
catch promotion_error
    rollback_failures = strings(num_figures, 1);
    rollback_failure_count = 0;
    for figure_index = 1:num_figures
        if ~promoted(figure_index)
            continue
        end

        if had_canonical(figure_index)
            [restored, message] = copyfile( ...
                backup_paths(figure_index), ...
                canonical_paths(figure_index), 'f');
            if ~restored
                rollback_failure_count = rollback_failure_count + 1;
                rollback_failures(rollback_failure_count) = ...
                    canonical_paths(figure_index) + ": " + string(message);
            end
        elseif exist(canonical_paths(figure_index), 'file') == 2
            delete(canonical_paths(figure_index));
        end
    end

    local_delete_paths(staged_paths);
    if rollback_failure_count == 0
        local_delete_paths(backup_paths);
    else
        warning('PARTC_05:RollbackIncomplete', ...
            'Rollback was incomplete; recovery backups were retained. %s', ...
            strjoin(rollback_failures(1:rollback_failure_count), ' | '));
    end
    rethrow(promotion_error);
end

local_delete_paths(backup_paths);
end

function fig = local_new_figure(position)
%LOCAL_NEW_FIGURE Create one invisible white thesis figure.
fig = figure( ...
    'Visible', 'off', ...
    'Units', 'centimeters', ...
    'Position', position, ...
    'Color', 'w');
end

function local_export_and_close(fig, output_path)
%LOCAL_EXPORT_AND_CLOSE Export one vector PDF and close its figure.
exportgraphics(fig, char(output_path), 'ContentType', 'vector');
close(fig);
end

function local_close_figure(fig)
%LOCAL_CLOSE_FIGURE Close a figure when it still exists.
if isgraphics(fig, 'figure')
    close(fig);
end
end

function local_delete_paths(paths)
%LOCAL_DELETE_PATHS Delete existing transaction files.
for path_index = 1:numel(paths)
    if strlength(paths(path_index)) > 0 && ...
            exist(paths(path_index), 'file') == 2
        delete(paths(path_index));
    end
end
end

function series = local_line_series( ...
        x, y, color, line_style, label, line_width)
%LOCAL_LINE_SERIES Construct one shared-helper line series.
series = local_series_template();
series.type = "line";
series.x = x;
series.y = y;
series.color = color;
series.line_style = line_style;
series.label = label;
series.line_width = line_width;
end

function series = local_vertical_reference(boundary_date, values, style)
%LOCAL_VERTICAL_REFERENCE Construct a calibration/test boundary line.
minimum_value = min(values);
maximum_value = max(values);
if minimum_value == maximum_value
    maximum_value = minimum_value + eps(maximum_value);
end
series = local_line_series( ...
    [boundary_date; boundary_date], [minimum_value; maximum_value], ...
    style.boundary_color, "--", "", style.reference_line_width);
series.type = "reference";
end

function series = local_series_template()
%LOCAL_SERIES_TEMPLATE Return a complete plot-series structure.
series = struct( ...
    'type', "", ...
    'x', [], ...
    'y', [], ...
    'lower', [], ...
    'upper', [], ...
    'label', "", ...
    'color', [], ...
    'line_style', "", ...
    'line_width', [], ...
    'marker', "", ...
    'marker_size', [], ...
    'face_color', [], ...
    'face_alpha', []);
end

function axis_style = local_axis_style(x_label, y_label, style)
%LOCAL_AXIS_STYLE Construct shared axis styling.
axis_style = struct( ...
    'x_label', x_label, ...
    'y_label', y_label, ...
    'grid', true, ...
    'font_name', style.font_name, ...
    'axis_font_size', style.axis_font_size, ...
    'tick_font_size', style.tick_font_size);
end

function local_panel_label(ax, label, style)
%LOCAL_PANEL_LABEL Add a compact panel identifier.
text(ax, 0.015, 0.97, label, ...
    'Units', 'normalized', ...
    'HorizontalAlignment', 'left', ...
    'VerticalAlignment', 'top', ...
    'FontName', style.font_name, ...
    'FontSize', style.panel_font_size, ...
    'FontWeight', 'bold', ...
    'Interpreter', 'tex');
end

function local_period_labels(ax, style)
%LOCAL_PERIOD_LABELS Label calibration and held-out regions.
text(ax, 0.25, 0.88, "Calibration", ...
    'Units', 'normalized', ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'top', ...
    'FontName', style.font_name, ...
    'FontSize', style.annotation_font_size, ...
    'Color', style.annotation_color, ...
    'Interpreter', 'tex');
text(ax, 0.80, 0.88, "Held-out", ...
    'Units', 'normalized', ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'top', ...
    'FontName', style.font_name, ...
    'FontSize', style.annotation_font_size, ...
    'Color', style.annotation_color, ...
    'Interpreter', 'tex');
end

function local_shared_legend(ax, handles, labels, style, num_columns)
%LOCAL_SHARED_LEGEND Place a boxless legend in the outer south tile.
legend_handle = legend(ax, handles, cellstr(labels), ...
    'Box', 'off', ...
    'FontName', style.font_name, ...
    'FontSize', style.legend_font_size, ...
    'NumColumns', num_columns, ...
    'Interpreter', 'tex');
legend_handle.Layout.Tile = 'south';
end

function local_axes_legend(ax, handles, labels, style, num_columns)
%LOCAL_AXES_LEGEND Place a boxless legend outside a single axes.
legend(ax, handles, cellstr(labels), ...
    'Location', 'southoutside', ...
    'Box', 'off', ...
    'FontName', style.font_name, ...
    'FontSize', style.legend_font_size, ...
    'NumColumns', num_columns, ...
    'Interpreter', 'tex');
end

function color = local_model_color(model, style)
%LOCAL_MODEL_COLOR Return the fixed colour for one model.
if string(model) == "AR"
    color = style.model.AR;
else
    color = style.model.ARX;
end
end

function labels = local_model_labels(models, exo_modes)
%LOCAL_MODEL_LABELS Return readable model/exogenous labels.
labels = strings(numel(models), 1);
for row_index = 1:numel(models)
    if string(models(row_index)) == "AR"
        labels(row_index) = "AR / None";
    else
        labels(row_index) = local_model_label( ...
            models(row_index), exo_modes(row_index));
    end
end
end

function label = local_model_label(model, exo_mode)
%LOCAL_MODEL_LABEL Return one readable model/exogenous label.
if string(model) == "AR"
    label = "AR";
else
    label = string(model) + "/" + string(exo_mode);
end
end

function labels = local_strategy_labels(strategies)
%LOCAL_STRATEGY_LABELS Return readable strategy labels.
labels = strings(numel(strategies), 1);
for row_index = 1:numel(strategies)
    labels(row_index) = local_pretty_identity(strategies(row_index));
end
end

function light_color = local_lighten_color(color, amount)
%LOCAL_LIGHTEN_COLOR Mix one model colour with white.
light_color = color + amount * (1 - color);
end

function style = local_style()
%LOCAL_STYLE Define the consistent Part C thesis figure style.
style = struct();
style.font_name = "Arial";
style.axis_font_size = 9;
style.tick_font_size = 8;
style.legend_font_size = 8;
style.panel_font_size = 9;
style.title_font_size = 10;
style.annotation_font_size = 8;
style.line_width = 1.25;
style.target_line_width = 1.15;
style.forecast_line_width = 1.35;
style.reference_line_width = 0.9;
style.marker_size = 4.5;
style.pairwise_marker_size = 5.5;
style.data_color = [0.10, 0.10, 0.10];
style.boundary_color = [0.45, 0.45, 0.45];
style.annotation_color = [0.35, 0.35, 0.35];
style.proxy_recovered = [0.000, 0.620, 0.451];
style.pairwise_color = [0.337, 0.706, 0.914];
style.model = struct( ...
    'AR', [0.000, 0.447, 0.698], ...
    'ARX', [0.835, 0.369, 0.000]);
style.strategy_colors = [ ...
    0.000, 0.447, 0.698
    0.835, 0.369, 0.000
    0.400, 0.400, 0.400];
end
