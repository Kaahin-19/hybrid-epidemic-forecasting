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
%           .models   : Fixed Part C AR/ARX configurations.
%           .refinement : Held-out local recalibration extension settings.
%           .output   : Absolute paths for data and result storage.
%
%   See also PARTA_CONFIG, PARTC_01_PREPARE_REAL_DATA.

% A. M. Kaahin 2026-05-18

    cfg = partA_config();
    cfg = local_remove_fields(cfg, ["run", "time", "Rt", "scenarios", "sirs"]);

    %% 1. Output Artifacts
    thisDir  = fileparts(mfilename('fullpath'));
    repoRoot = fileparts(thisDir);

    cfg.output = struct();
    cfg.output.data_raw_dir       = fullfile(repoRoot, "data", "partC", "raw");
    cfg.output.data_processed_dir = fullfile(repoRoot, "data", "partC", "processed");
    cfg.output.root_dir           = fullfile(repoRoot, "results", "partC");
    cfg.output.forecast_dir       = fullfile(cfg.output.root_dir, "forecasts");
    cfg.output.score_dir          = fullfile(cfg.output.root_dir, "scores");
    cfg.output.fig_dir            = fullfile(cfg.output.root_dir, "figures");
    cfg.output.refinement_dir     = fullfile(cfg.output.root_dir, "refinement");
    cfg.output.log_dir            = fullfile(cfg.output.root_dir, "logs");

    %% 2. WHO Input Schema and Preprocessing
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

    %% 3. Local Refinement Extension
    cfg.refinement = struct();
    cfg.refinement.calibration_fraction = 0.80;
    cfg.refinement.output_dir = cfg.output.refinement_dir;

    cfg.refinement.ar_grid = struct();
    cfg.refinement.ar_grid.p = 1:5;

    cfg.refinement.arx_i_grid = struct();
    cfg.refinement.arx_i_grid.na = 5:9;
    cfg.refinement.arx_i_grid.nb = 1:3;
    cfg.refinement.arx_i_grid.nk = 1:4;

    %% 4. Fixed Real-Data Model Comparison
    cfg.models = repmat(struct( ...
        'model_type', '', ...
        'exo_mode', '', ...
        'selected_model', [], ...
        'headers', {{}}), 1, 2);

    cfg.models(1) = struct( ...
        'model_type', 'AR', ...
        'exo_mode', 'None', ...
        'selected_model', 2, ...
        'headers', {{'p'}});

    cfg.models(2) = struct( ...
        'model_type', 'ARX', ...
        'exo_mode', 'I', ...
        'selected_model', [7, 2, 1], ...
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
