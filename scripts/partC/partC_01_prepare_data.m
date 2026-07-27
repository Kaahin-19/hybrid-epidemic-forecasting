%PARTC_01_PREPARE_DATA Prepare Swedish observed incidence and estimated Rt.
%
%   Description:
%       Reads the configured WHO daily COVID-19 file, selects the approved
%       uninterrupted Swedish study period, preserves reported incidence
%       unchanged, and estimates an operational Rt series with the configured
%       serial-interval approximation. Rt_estimated is an incidence-derived
%       estimate and is not the biological true Rt.
%
%   Workflow:
%       1. Load the Part C preparation configuration.
%       2. Read and validate the configured WHO source and exact schema.
%       3. Select and validate the Swedish daily study period.
%       4. Construct serial-interval weights and estimate Rt.
%       5. Save one canonical prepared-data artifact.
%
%   See also PARTC_CONFIG, SERIAL_INTERVAL_WEIGHTS, ESTIMATE_RT_RENEWAL.
%
% A. M. Kaahin 2026-07-27

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Observed-Incidence Preparation ===\n');

cfg = partC_config();
source_file = cfg.source.file;

if exist(source_file, 'file') ~= 2
    error('PARTC_01:MissingSourceFile', ...
        'Configured WHO source file does not exist: %s.', source_file);
end

%% 2. WHO Source Ingestion
import_options = detectImportOptions(source_file, ...
    'FileType', 'text', 'VariableNamingRule', 'preserve');

source_columns = string(import_options.VariableNames);
required_columns = string(struct2cell(cfg.source.columns));
if ~all(ismember(required_columns, source_columns))
    missing_columns = required_columns(~ismember(required_columns, source_columns));
    error('PARTC_01:MissingSourceColumns', ...
        'Configured WHO source columns are missing: %s.', ...
        strjoin(missing_columns, ', '));
end

import_options = setvartype(import_options, ...
    [cfg.source.columns.date, cfg.source.columns.country_code, ...
    cfg.source.columns.country], 'string');
import_options = setvartype(import_options, cfg.source.columns.incidence, 'double');
source_table = readtable(source_file, import_options);

%% 3. Swedish Study-Period Selection
country_names = source_table.(cfg.source.columns.country);
country_codes = source_table.(cfg.source.columns.country_code);
sweden_mask = country_names == cfg.country.name & country_codes == cfg.country.code;

if ~any(sweden_mask)
    error('PARTC_01:MissingCountry', ...
        'No rows match country %s with code %s.', ...
        cfg.country.name, cfg.country.code);
end

sweden_date_text = source_table.(cfg.source.columns.date);
sweden_date_text = sweden_date_text(sweden_mask);
sweden_dates = datetime(sweden_date_text, 'InputFormat', 'yyyy-MM-dd');

study_mask = sweden_dates >= cfg.study.start_date & ...
    sweden_dates <= cfg.study.end_date;
dates = sweden_dates(study_mask);

sweden_incidence = source_table.(cfg.source.columns.incidence);
sweden_incidence = sweden_incidence(sweden_mask);
incidence_observed = sweden_incidence(study_mask);
incidence_renewal_input = incidence_observed;

expected_dates = (cfg.study.start_date:caldays(1):cfg.study.end_date)';

if any(isnat(dates))
    error('PARTC_01:InvalidDates', ...
        'The selected WHO date column contains invalid dates.');
end

if numel(dates) ~= numel(expected_dates)
    error('PARTC_01:IncompleteStudyPeriod', ...
        'Expected %d Swedish daily rows but found %d.', ...
        numel(expected_dates), numel(dates));
end

if numel(unique(dates)) ~= numel(dates)
    error('PARTC_01:DuplicateDates', ...
        'The selected Swedish study period contains duplicate dates.');
end

if ~issorted(dates) || any(diff(dates) ~= days(1))
    error('PARTC_01:InvalidDateOrder', ...
        'Selected dates must be ordered with daily spacing.');
end

if ~isequal(dates, expected_dates)
    error('PARTC_01:DateCoverageMismatch', ...
        'Selected dates do not exactly cover the configured study period.');
end

if ~isnumeric(incidence_observed) || ~isreal(incidence_observed) || ...
        ~iscolumn(incidence_observed) || any(~isfinite(incidence_observed)) || ...
        any(incidence_observed < 0)
    error('PARTC_01:InvalidIncidence', ...
        'Selected incidence must be a real, finite, nonnegative column vector.');
end

if numel(incidence_observed) ~= numel(dates) || ...
        numel(incidence_renewal_input) ~= numel(dates)
    error('PARTC_01:SignalLengthMismatch', ...
        'Dates and prepared incidence series must have matching lengths.');
end

%% 4. Renewal Rt Estimation
weights = serial_interval_weights( ...
    cfg.renewal.serial_interval_mean_days, ...
    cfg.renewal.serial_interval_sd_days, ...
    cfg.renewal.serial_interval_max_lag_days);

Rt_estimated = estimate_rt_renewal( ...
    incidence_renewal_input, weights, cfg.renewal.min_infectiousness);
Rt_valid_mask = isfinite(Rt_estimated);

%% 5. Metadata and Persistence
source_metadata = struct();
source_metadata.source_file = source_file;
source_metadata.source_columns = cfg.source.columns;
source_metadata.country = cfg.country.name;
source_metadata.country_code = cfg.country.code;
source_metadata.selected_start_date = dates(1);
source_metadata.selected_end_date = dates(end);
source_metadata.observation_count = numel(dates);
source_metadata.incidence_processing = ...
    "Observed daily incidence was used directly; no smoothing or incidence repair was applied.";
source_metadata.serial_interval_assumption_source = ...
    cfg.renewal.serial_interval_source;
source_metadata.serial_interval_assumption = ...
    "Part C gamma approximation using an early-COVID mean of 4.7 days and standard deviation of 2.9 days; not universally fixed biological truth.";
source_metadata.serial_interval_truncation = ...
    "The positive gamma approximation was numerically truncated at 21 daily lags and renormalized.";

preparation_snapshot = cfg.snapshot.preparation;

if exist(cfg.output.prepared_artifact_dir, 'dir') ~= 7
    mkdir(cfg.output.prepared_artifact_dir);
end

artifact = struct();
artifact.dates = dates;
artifact.incidence_observed = incidence_observed;
artifact.incidence_renewal_input = incidence_renewal_input;
artifact.Rt_estimated = Rt_estimated;
artifact.Rt_valid_mask = Rt_valid_mask;
artifact.serial_interval_weights = weights;
artifact.source_metadata = source_metadata;
artifact.preparation_snapshot = preparation_snapshot;

save(cfg.output.prepared_artifact_path, '-struct', 'artifact');

fprintf('Prepared %d Swedish daily observations.\n', numel(dates));
fprintf('Estimated Rt on %d days; %d entries remain invalid.\n', ...
    nnz(Rt_valid_mask), nnz(~Rt_valid_mask));
fprintf('Prepared artifact saved to: %s\n', ...
    cfg.output.prepared_artifact_path);
fprintf('=== Part C Observed-Incidence Preparation Complete ===\n\n');
