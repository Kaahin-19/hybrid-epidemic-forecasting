%PARTC_01_PREPARE_DATA Prepare observed incidence, estimated Rt, and SIRS state proxies.
%
%   Description:
%       Reads the configured epidemiological CSV source, selects the configured
%       series and study period, estimates an operational renewal Rt series,
%       and reconstructs causal reported-case SIRS state proxies for later
%       forecasting. CSV-specific interpretation is defined in PARTC_CONFIG.
%
%   Workflow:
%       1. Load the Part C configuration.
%       2. Read and validate the configured incidence series.
%       3. Estimate Rt using the configured renewal assumptions.
%       4. Reconstruct reported-case SIRS state proxies.
%       5. Save the prepared data required by downstream Part C scripts.
%
%   See also PARTC_CONFIG, PARTC_02_SELECT_LOCAL_ORDERS,
%            SERIAL_INTERVAL_WEIGHTS, ESTIMATE_RT_RENEWAL,
%            RECONSTRUCT_SIRS_STATES_FROM_INCIDENCE.
%
% A. M. Kaahin 2026-07-27
% Modified: 2026-08-23

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Observed-Incidence and State Preparation ===\n');

cfg = partC_config();
source_file = cfg.source.file;

if ~isfile(source_file)
    error('PARTC_01:MissingSourceFile', 'Configured source file does not exist: %s.', source_file);
end

%% 2. Observed-Data Ingestion
import_options = detectImportOptions(source_file, 'FileType', 'text', 'VariableNamingRule', 'preserve');

required_columns = [cfg.source.date_column, cfg.source.incidence_column];

if strlength(cfg.source.filter_column) > 0
    required_columns(end + 1) = cfg.source.filter_column;
end

source_columns = string(import_options.VariableNames);
missing_columns = required_columns(~ismember(required_columns, source_columns));

if ~isempty(missing_columns)
    error('PARTC_01:MissingSourceColumns', 'Configured source columns are missing: %s.', strjoin(missing_columns, ', '));
end

import_options = setvartype(import_options, cfg.source.date_column, 'string');
import_options = setvartype(import_options, cfg.source.incidence_column, 'double');

if strlength(cfg.source.filter_column) > 0
    import_options = setvartype(import_options, cfg.source.filter_column, 'string');
end

source_table = readtable(source_file, import_options);

if strlength(cfg.source.filter_column) == 0
    source_mask = true(height(source_table), 1);
else
    source_mask = source_table.(cfg.source.filter_column) == cfg.source.filter_value;
end

if ~any(source_mask)
    error('PARTC_01:MissingSourceSeries', 'No observations match the configured source series: %s.', cfg.source.series_name);
end

source_dates = datetime(source_table.(cfg.source.date_column)(source_mask), 'InputFormat', cfg.source.date_format);
source_incidence = source_table.(cfg.source.incidence_column)(source_mask);

if any(isnat(source_dates))
    error('PARTC_01:InvalidSourceDates', 'The configured source series contains invalid dates.');
end

study_mask = source_dates >= cfg.study.start_date & source_dates <= cfg.study.end_date;

dates = source_dates(study_mask);
incidence_observed = source_incidence(study_mask);

expected_dates = (cfg.study.start_date:caldays(1):cfg.study.end_date).';

if ~isequal(dates, expected_dates)
    error('PARTC_01:IncompleteStudyPeriod', 'The selected source series must contain exactly one chronological observation per day from %s through %s.', string(cfg.study.start_date), string(cfg.study.end_date));
end

if any(~isfinite(incidence_observed)) || any(incidence_observed < 0)
    error('PARTC_01:InvalidStudyIncidence', 'Study-period incidence must be finite and nonnegative.');
end

if cfg.preparation.incidence_preprocessing ~= "none"
    error('PARTC_01:UnsupportedIncidencePreprocessing', 'Unsupported incidence preprocessing method: %s.', cfg.preparation.incidence_preprocessing);
end

fprintf('%s study period: %s to %s (%d days)\n', cfg.source.series_name, string(dates(1)), string(dates(end)), numel(dates));

%% 3. Renewal Rt Estimation
weights = serial_interval_weights(cfg.renewal.serial_interval_mean_days, cfg.renewal.serial_interval_sd_days, cfg.renewal.serial_interval_max_lag_days);

Rt_estimated = estimate_rt_renewal(incidence_observed, weights, cfg.renewal.min_infectiousness);
Rt_valid_mask = isfinite(Rt_estimated) & Rt_estimated > 0;

%% 4. Reported-Case SIRS State Reconstruction
[S_proxy, I_proxy, R_proxy] = reconstruct_sirs_states_from_incidence(incidence_observed, cfg.state_reconstruction);

I_fraction_proxy = I_proxy / cfg.state_reconstruction.effective_population;

%% 5. Persistence
if ~exist(cfg.output.prepared_artifact_dir, 'dir')
    mkdir(cfg.output.prepared_artifact_dir);
end

artifact = struct("dates", dates, "incidence_observed", incidence_observed, "Rt_estimated", Rt_estimated, "Rt_valid_mask", Rt_valid_mask, "S_proxy", S_proxy, "I_proxy", I_proxy, "R_proxy", R_proxy, "I_fraction_proxy", I_fraction_proxy);

save(cfg.output.prepared_artifact_path, '-struct', 'artifact');

fprintf('Estimated Rt on %d days; %d entries remain invalid during renewal warm-up.\n', nnz(Rt_valid_mask), nnz(~Rt_valid_mask));
fprintf('Reconstructed %d reported-case SIRS proxy states.\n', numel(S_proxy));
fprintf('Prepared artifact saved to: %s\n', cfg.output.prepared_artifact_path);
fprintf('=== Part C Observed-Incidence and State Preparation Complete ===\n\n');