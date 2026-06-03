function cfg = partC_config()
%PARTC_CONFIG Configuration for Part C: Real-Data Proof of Concept.
%
%   Syntax:
%       cfg = partC_config()
%
%   Description:
%       Thin Part C wrapper around partA_config. Part C reuses the practical
%       Part A forecast settings and WIS alphas, but freezes the real-data
%       comparison to AR/None and ARX/I. WHO reported cases are converted
%       into a smoothed infection proxy and empirical Rt estimate during
%       Part C preprocessing.
%
%   Outputs:
%       cfg - Structure containing:
%           .forecast : Shared expanding-window and WIS settings.
%           .sim      : Reproducibility settings.
%           .input    : WHO COVID-19 input schema and preprocessing settings.
%           .fixed_forecast_cases : Frozen Part C AR/ARX configurations.
%           .models   : Legacy alias used by the local refinement extension.
%           .refinement : Held-out local recalibration extension settings.
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
        "Fixed Part A-selected or documented fallback AR/None and ARX/I configurations";

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

    %% 5. Local Refinement Extension
    cfg.refinement = struct();
    cfg.refinement.calibration_fraction = 0.80;
    cfg.refinement.output_dir = cfg.output.refinement_dir;

    cfg.refinement.ar_grid = struct();
    cfg.refinement.ar_grid.p = 1:5;

    cfg.refinement.arx_i_grid = struct();
    cfg.refinement.arx_i_grid.na = 5:9;
    cfg.refinement.arx_i_grid.nb = 1:3;
    cfg.refinement.arx_i_grid.nk = 1:4;

    %% 6. Fixed Real-Data Model Comparison
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

    %% 7. Legacy Alias for Part C 04
    cfg.models = repmat(struct( ...
        'model_type', '', ...
        'exo_mode', '', ...
        'selected_model', [], ...
        'headers', {{}}), 1, 2);

    cfg.models(1) = struct( ...
        'model_type', 'AR', ...
        'exo_mode', 'None', ...
        'selected_model', cfg.fixed_forecast_cases(1).fallback_configuration, ...
        'headers', {{'p'}});

    cfg.models(2) = struct( ...
        'model_type', 'ARX', ...
        'exo_mode', 'I', ...
        'selected_model', cfg.fixed_forecast_cases(2).fallback_configuration, ...
        'headers', {{'na', 'nb', 'nk'}});
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
