function cfg = partC_config()
%PARTC_CONFIG Configuration for Part C: real-data transfer study.
%
%   Syntax:
%       cfg = partC_config()
%
%   Description:
%       Thin Part C wrapper around partA_config. Part C reuses the practical
%       Part A forecast settings and WIS alphas, but limits the real-data
%       transfer/adaptation study to AR/None and ARX/I. WHO reported cases
%       are converted into a smoothed infection proxy and empirical Rt
%       estimate during Part C preprocessing.
%
%   Outputs:
%       cfg - Structure containing:
%           .forecast : Shared expanding-window and WIS settings.
%           .sim      : Reproducibility settings.
%           .input    : WHO COVID-19 input schema and preprocessing settings.
%           .strategies : Real-data transfer/adaptation strategy registry.
%           .fixed_forecast_cases : Part A-selected AR/ARX model cases.
%           .local_order_grid : Local retuning grid settings.
%           .output   : Absolute paths for data and result storage.
%
%   See also PARTA_CONFIG, PARTC_01_PREPARE_REAL_DATA.

% A. M. Kaahin 2026-05-18
% Modified: 2026-06-03

    cfg = partA_config();
    partA_output = cfg.output;
    cfg = local_remove_fields(cfg, ["run", "time", "Rt", "scenarios", "sirs"]);

    %% 1. Experiment Identity
    cfg.experiment_id = "partC_real_data_validation";
    cfg.experiment_name = "Part C Swedish COVID real-data validation";
    cfg.data_source = "WHO-derived COVID-19 daily cases";
    cfg.forecast_assumption = ...
        "Part A-selected AR/None and ARX/I order transfer with increasing real-data adaptation";

    %% 2. Output Artifacts
    thisDir  = fileparts(mfilename('fullpath'));
    repoRoot = fileparts(thisDir);

    cfg.output = struct();
    cfg.output.partA_model_selection_dir = partA_output.model_selection_dir;
    cfg.output.partA_evaluation_dir = partA_output.score_dir;
    cfg.output.data_raw_dir       = fullfile(repoRoot, "data", "partC", "raw");
    cfg.output.data_processed_dir = fullfile(repoRoot, "data", "partC", "processed");
    cfg.output.root_dir           = fullfile(repoRoot, "results", "partC");
    cfg.output.forecast_dir       = fullfile(cfg.output.root_dir, "forecasts");
    cfg.output.evaluation_dir     = fullfile(cfg.output.root_dir, "evaluation");
    cfg.output.score_dir          = cfg.output.evaluation_dir;
    cfg.output.table_dir          = fullfile(cfg.output.root_dir, "tables");
    cfg.output.fig_dir            = fullfile(cfg.output.root_dir, "figures");
    cfg.output.refinement_dir     = fullfile(cfg.output.root_dir, "refinement");
    cfg.output.log_dir            = fullfile(cfg.output.root_dir, "logs");

    %% 3. WHO Input Schema and Preprocessing
    cfg.input.source     = "WHO daily COVID-19 cases";
    cfg.input.daily_csv  = fullfile(cfg.output.data_raw_dir, ...
        "WHO-COVID-19-global-daily-data.csv");

    cfg.input.country_code = "SE";
    cfg.input.country_name = "Sweden";
    cfg.input.start_date   = datetime(2020, 3, 1);
    cfg.input.end_date     = datetime(2022, 12, 31);

    cfg.input.date_col       = "Date_reported";
    cfg.input.country_code_col = "Country_code";
    cfg.input.country_col    = "Country";
    cfg.input.new_cases_col  = "New_cases";
    cfg.input.cumulative_cases_col = "Cumulative_cases";

    cfg.input.smoothing_window_days = 7;
    cfg.input.serial_interval_mean_days = 5;
    cfg.input.serial_interval_sd_days   = 2;
    cfg.input.serial_interval_max_lag_days = 21;

    %% 4. Part C Forecast Compatibility Projection
    cfg.sirs_projection = struct();
    cfg.sirs_projection.gamma = 1/7;
    cfg.sirs_projection.xi = 0;
    cfg.sirs_projection.pop_size = 100000;
    cfg.sirs_projection.I0 = 500;
    cfg.sirs_projection.R0_init = 0;
    cfg.sirs_projection.description = ...
        "Compatibility proxy for closed-loop ARX/I forecasting; not observed Swedish susceptible state.";

    %% 5. Strategy Registry
    cfg.strategies = repmat(struct( ...
        'strategy_id', "", ...
        'strategy_name', "", ...
        'order_treatment', "", ...
        'parameter_treatment', "", ...
        'uses_local_order_grid', false, ...
        'uses_online_parameter_reestimation', false, ...
        'uses_fixed_calibration_parameters', false, ...
        'calibration_fraction', 0.80, ...
        'evaluation_description', ""), 1, 3);

    cfg.strategies(1) = struct( ...
        'strategy_id', "fixed_parameters", ...
        'strategy_name', "Fixed-parameter transfer", ...
        'order_treatment', "Part A-selected order", ...
        'parameter_treatment', "Fit once on initial real-data calibration segment", ...
        'uses_local_order_grid', false, ...
        'uses_online_parameter_reestimation', false, ...
        'uses_fixed_calibration_parameters', true, ...
        'calibration_fraction', 0.80, ...
        'evaluation_description', ...
        "Evaluate post-calibration windows with one fixed real-data parameter fit.");

    cfg.strategies(2) = struct( ...
        'strategy_id', "online_reestimate", ...
        'strategy_name', "Online parameter re-estimation", ...
        'order_treatment', "Part A-selected order", ...
        'parameter_treatment', "Re-estimate parameters at each forecast origin", ...
        'uses_local_order_grid', false, ...
        'uses_online_parameter_reestimation', true, ...
        'uses_fixed_calibration_parameters', false, ...
        'calibration_fraction', 0.80, ...
        'evaluation_description', ...
        "Evaluate post-calibration windows with the shared expanding-window dispatcher.");

    cfg.strategies(3) = struct( ...
        'strategy_id', "local_order_retuning", ...
        'strategy_name', "Local order retuning", ...
        'order_treatment', "Local real-data order retuning around Part A-selected order", ...
        'parameter_treatment', "Re-estimate parameters at each forecast origin", ...
        'uses_local_order_grid', true, ...
        'uses_online_parameter_reestimation', true, ...
        'uses_fixed_calibration_parameters', false, ...
        'calibration_fraction', 0.80, ...
        'evaluation_description', ...
        "Select nearby order on calibration windows, then evaluate post-calibration windows online.");

    %% 6. Local Order Retuning Grid
    cfg.local_order_grid = struct();
    cfg.local_order_grid.max_calibration_windows = 16;
    cfg.local_order_grid.selection_intervals_enabled = false;

    cfg.local_order_grid.ar = struct();
    cfg.local_order_grid.ar.p_radius = 1;
    cfg.local_order_grid.ar.min_p = 1;
    cfg.local_order_grid.ar.max_p = 12;

    cfg.local_order_grid.arx = struct();
    cfg.local_order_grid.arx.na_radius = 1;
    cfg.local_order_grid.arx.nb_radius = 1;
    cfg.local_order_grid.arx.nk_radius = 1;
    cfg.local_order_grid.arx.min_na = 1;
    cfg.local_order_grid.arx.min_nb = 1;
    cfg.local_order_grid.arx.min_nk = 1;
    cfg.local_order_grid.arx.max_na = 9;
    cfg.local_order_grid.arx.max_nb = 3;
    cfg.local_order_grid.arx.max_nk = 5;

    %% 7. Fixed Real-Data Model Comparison
    cfg.fixed_forecast_cases = repmat(struct( ...
        'model_type', "", ...
        'exo_mode', "", ...
        'fallback_configuration', [], ...
        'selected_configuration_source', "", ...
        'selected_configuration_artifact', ""), 1, 2);

    cfg.fixed_forecast_cases(1).model_type = "AR";
    cfg.fixed_forecast_cases(1).exo_mode = "None";
    cfg.fixed_forecast_cases(1).fallback_configuration = 2;
    cfg.fixed_forecast_cases(1).selected_configuration_source = ...
        "partA_model_selection_or_partC_config_fallback";
    cfg.fixed_forecast_cases(1).selected_configuration_artifact = fullfile( ...
        cfg.output.partA_model_selection_dir, ...
        "partA_02_global_hyperparameters_AR_None.mat");

    cfg.fixed_forecast_cases(2).model_type = "ARX";
    cfg.fixed_forecast_cases(2).exo_mode = "I";
    cfg.fixed_forecast_cases(2).fallback_configuration = [7, 2, 1];
    cfg.fixed_forecast_cases(2).selected_configuration_source = ...
        "partA_model_selection_or_partC_config_fallback";
    cfg.fixed_forecast_cases(2).selected_configuration_artifact = fullfile( ...
        cfg.output.partA_model_selection_dir, ...
        "partA_02_global_hyperparameters_ARX_I.mat");
end

function cfg = local_remove_fields(cfg, field_names)
%LOCAL_REMOVE_FIELDS Drop Part A fields that are not part of Part C.
    for i = 1:numel(field_names)
        field_name = char(field_names(i));
        if isfield(cfg, field_name)
            cfg = rmfield(cfg, field_name);
        end
    end
end
