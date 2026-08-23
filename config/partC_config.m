function cfg = partC_config()

%PARTC_CONFIG Configure Part C real-data adaptation.
%
%   Syntax:
%       cfg = partC_config()
%
%   Description:
%       Defines the observed-data source, study period, renewal-estimator
%       assumptions, reported-case SIRS state reconstruction, chronological
%       validation split, limited local model selection, held-out forecasting,
%       evaluation, visualization, artifact snapshots, and output paths.
%
%   Inputs:
%       None.
%
%   Outputs:
%       cfg - Structure containing:
%           .source               : Observed-data source and CSV interpretation.
%           .study                : Inclusive study-period endpoints.
%           .renewal              : Serial-interval and infectiousness assumptions.
%           .preparation          : Incidence preprocessing assumption.
%           .state_reconstruction : Reported-case SIRS proxy assumptions.
%           .validation           : Calibration and test boundary dates.
%           .local_selection      : Limited local-selection settings.
%           .final_forecast       : Held-out forecast settings and strategies.
%           .evaluation           : Held-out evaluation settings.
%           .visualization        : Thesis-figure settings.
%           .snapshot             : Artifact compatibility snapshots.
%           .output               : Canonical Part C artifact paths.
%
%   See also PARTC_01_PREPARE_DATA, PARTA_CONFIG.
%
% A. M. Kaahin 2026-07-27
% Modified: 2026-08-23

%% 1. Configuration Initialization
cfg = struct();
partA_cfg = partA_config();

thisDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(thisDir);

%% 2. Observed-Data Source
cfg.source.file = fullfile(repoRoot, "data", "partC", "raw", "WHO-COVID-19-global-daily-data.csv");
cfg.source.date_column = "Date_reported";
cfg.source.incidence_column = "New_cases";
cfg.source.date_format = "yyyy-MM-dd";
cfg.source.filter_column = "Country_code";
cfg.source.filter_value = "SE";
cfg.source.series_name = "Sweden";

%% 3. Study Period
cfg.study.start_date = datetime(2020, 3, 3);
cfg.study.end_date = datetime(2021, 6, 14);

%% 4. Renewal Assumptions
cfg.renewal.serial_interval_mean_days = 4.7;
cfg.renewal.serial_interval_sd_days = 2.9;
cfg.renewal.serial_interval_max_lag_days = 21;
cfg.renewal.min_infectiousness = 0;
cfg.renewal.serial_interval_source = "Nishiura H, Linton NM, Akhmetzhanov AR (2020), International Journal of Infectious Diseases 93:284-286, doi:10.1016/j.ijid.2020.02.060.";

%% 5. Incidence Preparation
cfg.preparation.incidence_preprocessing = "none";

%% 6. Reported-Case SIRS State Reconstruction
cfg.state_reconstruction.method = "reported_case_sirs_proxy";
cfg.state_reconstruction.reference_population = 10379295;
cfg.state_reconstruction.reference_population_source = "Statistics Sweden: population at the end of 2020.";
cfg.state_reconstruction.reporting_fraction = 1.0;
cfg.state_reconstruction.effective_population = partA_cfg.sirs.pop_size;
cfg.state_reconstruction.effective_population_source = "Part A effective SIRS simulation population.";
cfg.state_reconstruction.gamma = partA_cfg.sirs.gamma;
cfg.state_reconstruction.xi = partA_cfg.sirs.xi;
cfg.state_reconstruction.sirs_parameter_source = "Part A SIRS transition assumptions.";
cfg.state_reconstruction.min_susceptible = partA_cfg.sirs.min_susceptible;
cfg.state_reconstruction.lookback_days = 0;
cfg.state_reconstruction.history_assumption = "No pre-study incidence is used. The SIRS proxy recursion begins immediately before the configured study start date. Renewal estimation begins on the configured study start date, and undefined initial estimates are preserved through Rt_valid_mask.";
cfg.state_reconstruction.initial_infectious = 0;
cfg.state_reconstruction.initial_recovered = 0;
cfg.state_reconstruction.initial_susceptible = cfg.state_reconstruction.effective_population - cfg.state_reconstruction.initial_infectious - cfg.state_reconstruction.initial_recovered;
cfg.state_reconstruction.conservation_tolerance = 1e-8 * cfg.state_reconstruction.effective_population;
cfg.state_reconstruction.state_timing_convention = "End-of-day state after processing the incidence reported for that date.";

%% 7. Preparation Snapshot
cfg.snapshot.preparation = struct("country_name", cfg.source.series_name, "country_code", cfg.source.filter_value, "study_start_date", cfg.study.start_date, "study_end_date", cfg.study.end_date, "serial_interval_mean_days", cfg.renewal.serial_interval_mean_days, "serial_interval_sd_days", cfg.renewal.serial_interval_sd_days, "serial_interval_max_lag_days", cfg.renewal.serial_interval_max_lag_days, "min_infectiousness", cfg.renewal.min_infectiousness, "incidence_preprocessing", cfg.preparation.incidence_preprocessing, "state_reconstruction_method", cfg.state_reconstruction.method, "reference_population", cfg.state_reconstruction.reference_population, "reporting_fraction", cfg.state_reconstruction.reporting_fraction, "effective_population", cfg.state_reconstruction.effective_population, "gamma", cfg.state_reconstruction.gamma, "xi", cfg.state_reconstruction.xi, "min_susceptible", cfg.state_reconstruction.min_susceptible, "lookback_days", cfg.state_reconstruction.lookback_days, "initial_infectious", cfg.state_reconstruction.initial_infectious, "initial_recovered", cfg.state_reconstruction.initial_recovered, "conservation_tolerance", cfg.state_reconstruction.conservation_tolerance, "state_timing_convention", cfg.state_reconstruction.state_timing_convention);

%% 8. Chronological Validation
cfg.validation.calibration_end_date = datetime(2020, 12, 31);
cfg.validation.test_start_date = datetime(2021, 1, 1);

if cfg.validation.test_start_date ~= cfg.validation.calibration_end_date + caldays(1)
    error('PARTC_CONFIG:InvalidValidationBoundary', 'The Part C test period must begin one day after calibration ends.');
end

%% 9. Limited Local Configuration Selection
cfg.local_selection.order_radius = 1;
cfg.local_selection.min_window = partA_cfg.forecast.min_window;
cfg.local_selection.step_size = partA_cfg.forecast.step_size;
cfg.local_selection.horizon = partA_cfg.forecast.horizon;
cfg.local_selection.wis_alphas = partA_cfg.forecast.wis_alphas;
cfg.local_selection.num_draws = partA_cfg.intervals.num_draws;
cfg.local_selection.seed = partA_cfg.run.seed;
cfg.local_selection.include_epidemic_seed_variation = partA_cfg.intervals.include_epidemic_seed_variation;
cfg.local_selection.selection_rule = "Lowest-complexity local configuration within one standard error of the numerically best mean calibration WIS, with ties resolved by mean WIS and original candidate index.";

%% 10. Final Held-Out Forecasting
cfg.final_forecast.step_size = partA_cfg.forecast.step_size;
cfg.final_forecast.horizon = partA_cfg.forecast.horizon;
cfg.final_forecast.wis_alphas = partA_cfg.forecast.wis_alphas;
cfg.final_forecast.num_draws = partA_cfg.intervals.num_draws;
cfg.final_forecast.base_seed = partA_cfg.run.seed;
cfg.final_forecast.include_epidemic_seed_variation = partA_cfg.intervals.include_epidemic_seed_variation;

cfg.final_forecast.strategies = struct("identifier", {"partA_online_fit", "local_online_fit", "partA_fixed_fit"}, "description", {"Use the Part A-selected configuration and refit model parameters at every held-out forecast origin.", "Use the Part C locally selected configuration and refit model parameters at every held-out forecast origin.", "Use the Part A-selected configuration with coefficients and centred residuals fitted once on the calibration block."}, "configuration_source", {"partA", "partC_local_selection", "partA"}, "parameter_update_mode", {"online", "online", "fixed_calibration_fit"});

%% 11. Output Paths
cfg.output.prepared_artifact_dir = fullfile(repoRoot, "data", "partC", "prepared");
cfg.output.prepared_artifact_path = fullfile(cfg.output.prepared_artifact_dir, "partC_01_prepared_data.mat");

cfg.output.root_dir = fullfile(repoRoot, "results", "partC");
cfg.output.model_selection_dir = fullfile(cfg.output.root_dir, "model_selection");
cfg.output.forecast_dir = fullfile(cfg.output.root_dir, "forecasts");
cfg.output.evaluation_dir = fullfile(cfg.output.root_dir, "evaluation");
cfg.output.table_dir = fullfile(cfg.output.root_dir, "tables");
cfg.output.figure_dir = fullfile(cfg.output.root_dir, "figures");

%% 12. Supported Configurations
configurations = struct("model_type", {"AR", "ARX"}, "exo_mode", {"None", "I"}, "partA_selection_artifact_path", {fullfile(partA_cfg.output.model_selection_dir, "partA_02_global_hyperparameters_AR_None.mat"), fullfile(partA_cfg.output.model_selection_dir, "partA_02_global_hyperparameters_ARX_I.mat")}, "local_selection_artifact_path", {fullfile(cfg.output.model_selection_dir, "partC_02_local_orders_AR_None.mat"), fullfile(cfg.output.model_selection_dir, "partC_02_local_orders_ARX_I.mat")}, "partA_selection_snapshot", {struct(), struct()}, "local_selection_snapshot", {struct(), struct()});

for configuration_index = 1:numel(configurations)
    partA_selection_snapshot = partA_cfg.snapshot.selection;
    partA_selection_snapshot.model_type = configurations(configuration_index).model_type;
    partA_selection_snapshot.exo_mode = configurations(configuration_index).exo_mode;
    configurations(configuration_index).partA_selection_snapshot = partA_selection_snapshot;

    configurations(configuration_index).local_selection_snapshot = struct("preparation_snapshot", cfg.snapshot.preparation, "model_type", configurations(configuration_index).model_type, "exo_mode", configurations(configuration_index).exo_mode, "calibration_end_date", cfg.validation.calibration_end_date, "test_start_date", cfg.validation.test_start_date, "order_radius", cfg.local_selection.order_radius, "min_window", cfg.local_selection.min_window, "step_size", cfg.local_selection.step_size, "horizon", cfg.local_selection.horizon, "wis_alphas", cfg.local_selection.wis_alphas, "num_draws", cfg.local_selection.num_draws, "seed", cfg.local_selection.seed, "include_epidemic_seed_variation", cfg.local_selection.include_epidemic_seed_variation, "selection_rule", cfg.local_selection.selection_rule);
end

cfg.local_selection.configurations = configurations;
cfg.snapshot.local_selection = [configurations.local_selection_snapshot];

forecast_configurations = struct("model_type", {configurations.model_type}, "exo_mode", {configurations.exo_mode}, "selection_artifact_path", {configurations.local_selection_artifact_path});

cfg.final_forecast.configurations = forecast_configurations;

supported_pairs = rmfield(forecast_configurations, 'selection_artifact_path');

cfg.snapshot.forecast = struct("step_size", cfg.final_forecast.step_size, "horizon", cfg.final_forecast.horizon, "supported_pairs", supported_pairs, "strategies", cfg.final_forecast.strategies, "calibration_end_date", cfg.validation.calibration_end_date, "test_start_date", cfg.validation.test_start_date, "study_end_date", cfg.study.end_date, "wis_alphas", cfg.final_forecast.wis_alphas, "num_draws", cfg.final_forecast.num_draws, "base_seed", cfg.final_forecast.base_seed, "include_epidemic_seed_variation", cfg.final_forecast.include_epidemic_seed_variation, "sirs", struct("state_reconstruction_method", cfg.state_reconstruction.method, "gamma", cfg.state_reconstruction.gamma, "xi", cfg.state_reconstruction.xi, "effective_population", cfg.state_reconstruction.effective_population, "min_susceptible", cfg.state_reconstruction.min_susceptible, "state_timing_convention", cfg.state_reconstruction.state_timing_convention));

%% 13. Held-Out Forecast Evaluation
expected_forecast_artifact_names = [
    "partC_03_forecast_AR_None_partA_online_fit.mat"
    "partC_03_forecast_AR_None_local_online_fit.mat"
    "partC_03_forecast_AR_None_partA_fixed_fit.mat"
    "partC_03_forecast_ARX_I_partA_online_fit.mat"
    "partC_03_forecast_ARX_I_local_online_fit.mat"
    "partC_03_forecast_ARX_I_partA_fixed_fit.mat"
    ];

cfg.evaluation.target_identifier = "target_Rt_estimated";

cfg.evaluation.metric_identifiers = [
    "WIS"
    "RMSE"
    "MAE"
    "MeanError"
    "EmpiricalCoverage"
    "IntervalWidth"
    ];

cfg.evaluation.grouping_dimensions = [
    "Model"
    "ExoMode"
    "Strategy"
    "ForecastOrigin"
    "LeadTime"
    "NominalIntervalLevel"
    ];

cfg.evaluation.expected_forecast_artifact_names = expected_forecast_artifact_names;
cfg.evaluation.expected_forecast_artifact_paths = fullfile(cfg.output.forecast_dir, expected_forecast_artifact_names);
cfg.evaluation.required_strategy_identifiers = [cfg.final_forecast.strategies.identifier].';
cfg.evaluation.required_supported_pairs = supported_pairs;
cfg.evaluation.metric_direction_policy = "Lower WIS, MAE, RMSE, and interval width are better, subject to coverage interpretation.";
cfg.evaluation.coverage_comparison_policy = "Empirical coverage is compared with nominal coverage.";
cfg.evaluation.retain_all_origins = true;
cfg.evaluation.pairwise_comparison_policy = "Pairwise comparisons are descriptive and matched by common forecast origin; no inferential statistics are calculated.";
cfg.evaluation.wis_equality_tolerance = 1e-12;

cfg.snapshot.evaluation = struct("forecast_snapshot", cfg.snapshot.forecast, "target_identifier", cfg.evaluation.target_identifier, "metric_identifiers", cfg.evaluation.metric_identifiers, "grouping_dimensions", cfg.evaluation.grouping_dimensions, "required_strategy_identifiers", cfg.evaluation.required_strategy_identifiers, "required_supported_pairs", cfg.evaluation.required_supported_pairs, "expected_forecast_artifact_names", cfg.evaluation.expected_forecast_artifact_names, "retain_all_origins", cfg.evaluation.retain_all_origins, "pairwise_comparison_policy", cfg.evaluation.pairwise_comparison_policy, "wis_equality_tolerance", cfg.evaluation.wis_equality_tolerance);

%% 14. Thesis Figure Generation
cfg.visualization.plot_lead_time = 7;
cfg.visualization.plot_alphas = [0.10; 0.50];
cfg.visualization.output_format = "pdf";
cfg.visualization.vector_content = true;
cfg.visualization.collapse_exact_online_duplicates = true;

for alpha_index = 1:numel(cfg.visualization.plot_alphas)
    plot_alpha = cfg.visualization.plot_alphas(alpha_index);

    if nnz(cfg.final_forecast.wis_alphas == plot_alpha) ~= 1
        error('PARTC_CONFIG:InvalidVisualizationAlpha', 'Visualization alpha %.17g must occur exactly once in final_forecast.wis_alphas.', plot_alpha);
    end
end

end