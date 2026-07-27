function cfg = partC_config()
%PARTC_CONFIG Configure Part C observed-incidence preparation.
%
%   Description:
%       Defines the WHO source schema, Swedish study period, renewal-estimator
%       assumptions, preparation snapshot, and canonical prepared-data path
%       used by Part C Script 1.
%
%   Outputs:
%       cfg - Structure containing:
%           .source    : WHO source file and exact input columns.
%           .country   : Selected country name and code.
%           .study     : Inclusive study-period endpoints.
%           .renewal   : Serial-interval and infectiousness assumptions.
%           .snapshot  : Stable preparation compatibility snapshot.
%           .output    : Prepared-artifact directory and path.
%
%   See also PARTC_01_PREPARE_DATA, SERIAL_INTERVAL_WEIGHTS.
%
% A. M. Kaahin 2026-07-27

cfg = struct();

%% 1. WHO Source
thisDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(thisDir);

cfg.source.file = fullfile(repoRoot, "data", "partC", "processed", ...
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

%% 4. Preparation Snapshot
cfg.snapshot.preparation = struct( ...
    "country_name", cfg.country.name, ...
    "country_code", cfg.country.code, ...
    "study_start_date", cfg.study.start_date, ...
    "study_end_date", cfg.study.end_date, ...
    "serial_interval_mean_days", cfg.renewal.serial_interval_mean_days, ...
    "serial_interval_sd_days", cfg.renewal.serial_interval_sd_days, ...
    "serial_interval_max_lag_days", cfg.renewal.serial_interval_max_lag_days, ...
    "min_infectiousness", cfg.renewal.min_infectiousness, ...
    "incidence_preprocessing", "none");

%% 5. Prepared Artifact
cfg.output.prepared_artifact_dir = fullfile(repoRoot, "data", "partC", "prepared");
cfg.output.prepared_artifact_path = fullfile( ...
    cfg.output.prepared_artifact_dir, "partC_01_prepared_data.mat");
end
