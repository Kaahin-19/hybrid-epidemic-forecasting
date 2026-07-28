function cfg = partC_config()
%PARTC_CONFIG Configure Part C observed-incidence adaptation.
%
%   Description:
%       Defines the WHO source schema, Swedish study period, renewal-estimator
%       assumptions, chronological validation split, limited local AR-order
%       selection protocol, compatibility snapshots, and canonical Part C
%       artifact paths.
%
%   Outputs:
%       cfg - Structure containing:
%           .source      : WHO source file and exact input columns.
%           .country     : Selected country name and code.
%           .study       : Inclusive study-period endpoints.
%           .renewal     : Serial-interval and infectiousness assumptions.
%           .preparation : Approved incidence preprocessing method.
%           .validation  : Fixed calibration and test boundary dates.
%           .local_selection : Limited AR-order selection settings.
%           .snapshot    : Stable Part C compatibility snapshots.
%           .output      : Canonical prepared-data and selection paths.
%
%   See also PARTC_01_PREPARE_DATA, PARTC_02_SELECT_LOCAL_ORDERS, ...
%            PARTA_CONFIG, SERIAL_INTERVAL_WEIGHTS.
%
% A. M. Kaahin 2026-07-27
% Modified: 2026-07-28

cfg = struct();

%% 1. WHO Source
thisDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(thisDir);

cfg.source.file = fullfile(repoRoot, "data", "partC", "raw", ...
    "WHO-COVID-19-global-daily-data.csv");
cfg.source.columns = struct( ...
    "date", "Date_reported", ...
    "country_code", "Country_code", ...
    "country", "Country", ...
    "incidence", "New_cases");

cfg.country.name = "Sweden";
cfg.country.code = "SE";

%% 2. Study Period
cfg.study.start_date = datetime(2020, 3, 3);
cfg.study.end_date   = datetime(2021, 6, 14);

%% 3. Renewal Assumptions
% Nishiura, Linton, and Akhmetzhanov (2020), "Serial interval of
% novel coronavirus (COVID-19) infections", International Journal of
% Infectious Diseases 93:284-286, doi:10.1016/j.ijid.2020.02.060,
% estimated an early-COVID serial-interval mean of 4.7 days and standard
% deviation of 2.9 days from 28 transmission pairs. Part C uses those moments
% as a gamma approximation for this renewal estimator; they are not a general
% project convention or universally fixed biological truth. The 21-day lag is
% a numerical truncation of the positive distribution.
cfg.renewal.serial_interval_mean_days = 4.7;
cfg.renewal.serial_interval_sd_days = 2.9;
cfg.renewal.serial_interval_max_lag_days = 21;
cfg.renewal.min_infectiousness = 0;
cfg.renewal.serial_interval_source = ...
    "Nishiura H, Linton NM, Akhmetzhanov AR (2020), International Journal of Infectious Diseases 93:284-286, doi:10.1016/j.ijid.2020.02.060.";

%% 4. Incidence Preparation
cfg.preparation.incidence_preprocessing = "none";

%% 5. Preparation Snapshot
cfg.snapshot.preparation = struct( ...
    "country_name", cfg.country.name, ...
    "country_code", cfg.country.code, ...
    "study_start_date", cfg.study.start_date, ...
    "study_end_date", cfg.study.end_date, ...
    "serial_interval_mean_days", cfg.renewal.serial_interval_mean_days, ...
    "serial_interval_sd_days", cfg.renewal.serial_interval_sd_days, ...
    "serial_interval_max_lag_days", cfg.renewal.serial_interval_max_lag_days, ...
    "min_infectiousness", cfg.renewal.min_infectiousness, ...
    "incidence_preprocessing", cfg.preparation.incidence_preprocessing);

%% 6. Chronological Validation
cfg.validation.calibration_end_date = datetime(2020, 12, 31);
cfg.validation.test_start_date = datetime(2021, 1, 1);

if cfg.validation.test_start_date ~= ...
        cfg.validation.calibration_end_date + caldays(1)
    error('PARTC_CONFIG:InvalidValidationBoundary', ...
        'The Part C test period must begin one day after calibration ends.');
end

%% 7. Limited Local AR-Order Selection
partA_cfg = partA_config();

cfg.local_selection.model_type = "AR";
cfg.local_selection.exo_mode = "None";
cfg.local_selection.order_radius = 1;
cfg.local_selection.min_window = partA_cfg.forecast.min_window;
cfg.local_selection.step_size = partA_cfg.forecast.step_size;
cfg.local_selection.horizon = partA_cfg.forecast.horizon;
cfg.local_selection.wis_alphas = partA_cfg.forecast.wis_alphas;
cfg.local_selection.num_draws = partA_cfg.intervals.num_draws;
cfg.local_selection.seed = partA_cfg.run.seed;
cfg.local_selection.selection_rule = ...
    "Simplest local AR order within one standard error of the numerically best mean calibration WIS.";
cfg.local_selection.partA_selection_artifact_path = fullfile( ...
    partA_cfg.output.model_selection_dir, ...
    "partA_02_global_hyperparameters_AR_None.mat");

partA_selection_snapshot = partA_cfg.snapshot.selection;
partA_selection_snapshot.model_type = cfg.local_selection.model_type;
partA_selection_snapshot.exo_mode = cfg.local_selection.exo_mode;
cfg.local_selection.partA_selection_snapshot = partA_selection_snapshot;

%% 8. Local-Selection Snapshot
cfg.snapshot.local_selection = struct( ...
    "preparation_snapshot", cfg.snapshot.preparation, ...
    "model_type", cfg.local_selection.model_type, ...
    "exo_mode", cfg.local_selection.exo_mode, ...
    "calibration_end_date", cfg.validation.calibration_end_date, ...
    "test_start_date", cfg.validation.test_start_date, ...
    "order_radius", cfg.local_selection.order_radius, ...
    "min_window", cfg.local_selection.min_window, ...
    "step_size", cfg.local_selection.step_size, ...
    "horizon", cfg.local_selection.horizon, ...
    "wis_alphas", cfg.local_selection.wis_alphas, ...
    "num_draws", cfg.local_selection.num_draws, ...
    "seed", cfg.local_selection.seed, ...
    "selection_rule", cfg.local_selection.selection_rule);

%% 9. Artifact Paths
cfg.output.prepared_artifact_dir = fullfile(repoRoot, "data", "partC", "prepared");
cfg.output.prepared_artifact_path = fullfile( ...
    cfg.output.prepared_artifact_dir, "partC_01_prepared_data.mat");
cfg.output.model_selection_dir = fullfile(repoRoot, "results", "partC", "model_selection");
cfg.output.local_selection_artifact_path = fullfile( ...
    cfg.output.model_selection_dir, "partC_02_local_orders_AR_None.mat");
end
