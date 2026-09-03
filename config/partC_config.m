function cfg = partC_config()

%PARTC_CONFIG Configure Part C real-data adaptation.
%
%   Syntax:
%       cfg = partC_config()
%
%   Description:
%       Defines the observed-data source, study period, renewal-estimator
%       parameters, SIRS state reconstruction, chronological validation split,
%       local model selection, held-out forecasting, evaluation, visualization,
%       and output paths.
%
%   Inputs:
%       None.
%
%   Outputs:
%       cfg - Structure containing:
%           .source               : Observed-data source and CSV interpretation.
%           .study                : Study-period endpoints.
%           .renewal              : Renewal-estimator parameters.
%           .preparation          : Incidence preprocessing.
%           .state_reconstruction : SIRS state-reconstruction parameters.
%           .validation           : Calibration and test boundaries.
%           .local_selection      : Local-selection settings.
%           .final_forecast       : Held-out forecasting settings.
%           .evaluation           : Evaluation settings.
%           .visualization        : Figure-generation settings.
%           .output               : Part C output paths.
%
%   See also PARTC_01_PREPARE_DATA, PARTA_CONFIG.
%
% A. M. Kaahin 2026-07-27
% Modified: 2026-09-03

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

%% 4. Renewal Parameters
cfg.renewal.serial_interval_mean_days = 4.7;
cfg.renewal.serial_interval_sd_days = 2.9;
cfg.renewal.serial_interval_max_lag_days = 21;
cfg.renewal.min_infectiousness = 0;

%% 5. Incidence Preparation
cfg.preparation.incidence_preprocessing = "none";

%% 6. SIRS State Reconstruction
cfg.state_reconstruction.reference_population = 10379295;
cfg.state_reconstruction.reporting_fraction = 1.0;
cfg.state_reconstruction.effective_population = partA_cfg.sirs.pop_size;
cfg.state_reconstruction.gamma = partA_cfg.sirs.gamma;
cfg.state_reconstruction.xi = partA_cfg.sirs.xi;
cfg.state_reconstruction.min_susceptible = partA_cfg.sirs.min_susceptible;

cfg.state_reconstruction.initial_infectious = 0;
cfg.state_reconstruction.initial_recovered = 0;
cfg.state_reconstruction.initial_susceptible = cfg.state_reconstruction.effective_population - cfg.state_reconstruction.initial_infectious - cfg.state_reconstruction.initial_recovered;
cfg.state_reconstruction.conservation_tolerance = 1e-8 * cfg.state_reconstruction.effective_population;

%% 7. Chronological Validation
cfg.validation.calibration_end_date = datetime(2020, 12, 31);
cfg.validation.test_start_date = datetime(2021, 1, 1);

if cfg.validation.test_start_date ~= cfg.validation.calibration_end_date + caldays(1)
    error('PARTC_CONFIG:InvalidValidationBoundary', 'The Part C test period must begin one day after calibration ends.');
end

%% 8. Local Configuration Selection
cfg.local_selection.order_radius = 1;
cfg.local_selection.min_window = partA_cfg.forecast.min_window;
cfg.local_selection.step_size = partA_cfg.forecast.step_size;
cfg.local_selection.horizon = partA_cfg.forecast.horizon;
cfg.local_selection.wis_alphas = partA_cfg.forecast.wis_alphas;
cfg.local_selection.num_draws = partA_cfg.intervals.num_draws;
cfg.local_selection.seed = partA_cfg.run.seed;
cfg.local_selection.include_epidemic_seed_variation = partA_cfg.intervals.include_epidemic_seed_variation;

%% 9. Final Held-Out Forecasting
cfg.final_forecast.step_size = partA_cfg.forecast.step_size;
cfg.final_forecast.horizon = partA_cfg.forecast.horizon;
cfg.final_forecast.wis_alphas = partA_cfg.forecast.wis_alphas;
cfg.final_forecast.num_draws = partA_cfg.intervals.num_draws;
cfg.final_forecast.base_seed = partA_cfg.run.seed;
cfg.final_forecast.include_epidemic_seed_variation = partA_cfg.intervals.include_epidemic_seed_variation;

cfg.final_forecast.strategies = struct( ...
    "identifier", {"partA_online_fit", "local_online_fit", "partA_fixed_fit"}, ...
    "configuration_source", {"partA", "partC_local_selection", "partA"}, ...
    "parameter_update_mode", {"online", "online", "fixed_calibration_fit"});

%% 10. Output Paths
cfg.output.prepared_artifact_dir = fullfile(repoRoot, "data", "partC", "prepared");
cfg.output.prepared_artifact_path = fullfile(cfg.output.prepared_artifact_dir, "partC_01_prepared_data.mat");

cfg.output.root_dir = fullfile(repoRoot, "results", "partC");
cfg.output.model_selection_dir = fullfile(cfg.output.root_dir, "model_selection");
cfg.output.forecast_dir = fullfile(cfg.output.root_dir, "forecasts");
cfg.output.evaluation_dir = fullfile(cfg.output.root_dir, "evaluation");
cfg.output.table_dir = fullfile(cfg.output.root_dir, "tables");
cfg.output.figure_dir = fullfile(cfg.output.root_dir, "figures");

%% 11. Supported Configurations
configurations = struct( ...
    "model_type", {"AR", "ARX"}, ...
    "exo_mode", {"None", "I"}, ...
    "partA_selection_artifact_path", { ...
        fullfile(partA_cfg.output.model_selection_dir, "partA_02_global_hyperparameters_AR_None.mat"), ...
        fullfile(partA_cfg.output.model_selection_dir, "partA_02_global_hyperparameters_ARX_I.mat")}, ...
    "local_selection_artifact_path", { ...
        fullfile(cfg.output.model_selection_dir, "partC_02_local_orders_AR_None.mat"), ...
        fullfile(cfg.output.model_selection_dir, "partC_02_local_orders_ARX_I.mat")});

cfg.local_selection.configurations = configurations;

cfg.final_forecast.configurations = struct( ...
    "model_type", {configurations.model_type}, ...
    "exo_mode", {configurations.exo_mode}, ...
    "selection_artifact_path", {configurations.local_selection_artifact_path});

%% 12. Held-Out Forecast Evaluation
expected_forecast_artifact_names = [
    "partC_03_forecast_AR_None_partA_online_fit.mat"
    "partC_03_forecast_AR_None_local_online_fit.mat"
    "partC_03_forecast_AR_None_partA_fixed_fit.mat"
    "partC_03_forecast_ARX_I_partA_online_fit.mat"
    "partC_03_forecast_ARX_I_local_online_fit.mat"
    "partC_03_forecast_ARX_I_partA_fixed_fit.mat"
    ];

cfg.evaluation.expected_forecast_artifact_paths = fullfile(cfg.output.forecast_dir, expected_forecast_artifact_names);
cfg.evaluation.wis_equality_tolerance = 1e-12;

%% 13. Figure Generation
cfg.visualization.plot_lead_time = 7;
cfg.visualization.plot_alphas = [0.10; 0.50];
cfg.visualization.collapse_exact_online_duplicates = true;

for alpha_index = 1:numel(cfg.visualization.plot_alphas)
    plot_alpha = cfg.visualization.plot_alphas(alpha_index);

    if nnz(cfg.final_forecast.wis_alphas == plot_alpha) ~= 1
        error('PARTC_CONFIG:InvalidVisualizationAlpha', 'Visualization alpha %.17g must occur exactly once in final_forecast.wis_alphas.', plot_alpha);
    end
end

end