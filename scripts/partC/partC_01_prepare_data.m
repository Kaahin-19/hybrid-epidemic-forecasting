%PARTC_01_PREPARE_DATA Prepare observed incidence, estimated Rt, and SIRS state proxies.
%
%   Description:
%       Reads the configured epidemiological CSV source, selects the configured
%       series and study period, preserves observed incidence unchanged,
%       estimates an operational renewal Rt series, and reconstructs causal
%       reported-case SIRS state proxies for later forecasting. CSV-specific
%       interpretation is defined entirely in PARTC_CONFIG. Rt_estimated and
%       the reconstructed compartments are model-derived quantities rather
%       than known biological truth.
%
%   Workflow:
%       1. Load the Part C configuration.
%       2. Read and validate the configured incidence series.
%       3. Estimate Rt using the configured renewal assumptions.
%       4. Reconstruct reported-case SIRS state proxies.
%       5. Save one canonical prepared-data artifact.
%
%   See also PARTC_CONFIG, SERIAL_INTERVAL_WEIGHTS, ESTIMATE_RT_RENEWAL,
%            RECONSTRUCT_SIRS_STATES_FROM_INCIDENCE.
%
% A. M. Kaahin 2026-07-27
% Modified: 2026-08-22

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

source_date_text = source_table.(cfg.source.date_column);
source_incidence = source_table.(cfg.source.incidence_column);

source_date_text = source_date_text(source_mask);
source_incidence = source_incidence(source_mask);
source_dates = datetime(source_date_text, 'InputFormat', cfg.source.date_format);

if any(isnat(source_dates))
    error('PARTC_01:InvalidSourceDates', 'The configured source series contains invalid dates.');
end

study_mask = source_dates >= cfg.study.start_date & source_dates <= cfg.study.end_date;
dates = source_dates(study_mask);
incidence_observed = source_incidence(study_mask);

expected_dates = (cfg.study.start_date:caldays(1):cfg.study.end_date)';

if ~isequal(dates, expected_dates)
    error('PARTC_01:IncompleteStudyPeriod', 'The selected source series must contain exactly one chronological observation per day from %s through %s.', string(cfg.study.start_date), string(cfg.study.end_date));
end

if any(~isfinite(incidence_observed)) || any(incidence_observed < 0)
    error('PARTC_01:InvalidStudyIncidence', 'Study-period incidence must be finite and nonnegative.');
end

if cfg.preparation.incidence_preprocessing ~= "none"
    error('PARTC_01:UnsupportedIncidencePreprocessing', 'Unsupported incidence preprocessing method: %s.', cfg.preparation.incidence_preprocessing);
end

incidence_renewal_input = incidence_observed;

fprintf('%s study period: %s to %s (%d days)\n', cfg.source.series_name, string(dates(1)), string(dates(end)), numel(dates));

%% 3. Renewal Rt Estimation
weights = serial_interval_weights(cfg.renewal.serial_interval_mean_days, cfg.renewal.serial_interval_sd_days, cfg.renewal.serial_interval_max_lag_days);

Rt_estimated = estimate_rt_renewal(incidence_renewal_input, weights, cfg.renewal.min_infectiousness);
Rt_valid_mask = isfinite(Rt_estimated) & Rt_estimated > 0;

%% 4. Reported-Case SIRS State Reconstruction
state_model_params = struct("reference_population", cfg.state_reconstruction.reference_population, "reporting_fraction", cfg.state_reconstruction.reporting_fraction, "effective_population", cfg.state_reconstruction.effective_population, "gamma", cfg.state_reconstruction.gamma, "xi", cfg.state_reconstruction.xi, "initial_susceptible", cfg.state_reconstruction.initial_susceptible, "initial_infectious", cfg.state_reconstruction.initial_infectious, "initial_recovered", cfg.state_reconstruction.initial_recovered, "min_susceptible", cfg.state_reconstruction.min_susceptible, "conservation_tolerance", cfg.state_reconstruction.conservation_tolerance);

[S_proxy, I_proxy, R_proxy, incidence_scaled_proxy, state_diagnostics] = reconstruct_sirs_states_from_incidence(incidence_observed, state_model_params);

I_fraction_proxy = I_proxy ./ cfg.state_reconstruction.effective_population;

state_valid_mask = S_proxy > cfg.state_reconstruction.min_susceptible & I_proxy >= 0 & R_proxy >= 0 & abs(S_proxy + I_proxy + R_proxy - cfg.state_reconstruction.effective_population) <= cfg.state_reconstruction.conservation_tolerance;

if any(~state_valid_mask)
    invalid_state_index = find(~state_valid_mask, 1);
    error('PARTC_01:InvalidStudyStateProxy', 'The reconstructed SIRS proxy state is invalid on %s.', string(dates(invalid_state_index)));
end

%% 5. Metadata and Persistence
source_metadata = struct();
source_metadata.source_file = source_file;
source_metadata.date_column = cfg.source.date_column;
source_metadata.incidence_column = cfg.source.incidence_column;
source_metadata.date_format = cfg.source.date_format;
source_metadata.filter_column = cfg.source.filter_column;
source_metadata.filter_value = cfg.source.filter_value;
source_metadata.series_name = cfg.source.series_name;
source_metadata.selected_start_date = dates(1);
source_metadata.selected_end_date = dates(end);
source_metadata.observation_count = numel(dates);
source_metadata.incidence_processing = cfg.preparation.incidence_preprocessing;
source_metadata.serial_interval_source = cfg.renewal.serial_interval_source;
source_metadata.rt_interpretation = "Rt_estimated is an operational incidence-derived estimate and is not known true Rt.";

state_reconstruction_metadata = struct();
state_reconstruction_metadata.method = cfg.state_reconstruction.method;
state_reconstruction_metadata.interpretation = "S_proxy, I_proxy, and R_proxy are model-derived reported-case SIRS state proxies rather than observed biological compartments.";
state_reconstruction_metadata.reference_population = cfg.state_reconstruction.reference_population;
state_reconstruction_metadata.reference_population_source = cfg.state_reconstruction.reference_population_source;
state_reconstruction_metadata.reporting_fraction = cfg.state_reconstruction.reporting_fraction;
state_reconstruction_metadata.effective_population = cfg.state_reconstruction.effective_population;
state_reconstruction_metadata.effective_population_source = cfg.state_reconstruction.effective_population_source;
state_reconstruction_metadata.gamma = cfg.state_reconstruction.gamma;
state_reconstruction_metadata.xi = cfg.state_reconstruction.xi;
state_reconstruction_metadata.sirs_parameter_source = cfg.state_reconstruction.sirs_parameter_source;
state_reconstruction_metadata.initial_state_before_study = [cfg.state_reconstruction.initial_susceptible; cfg.state_reconstruction.initial_infectious; cfg.state_reconstruction.initial_recovered];
state_reconstruction_metadata.state_timing_convention = cfg.state_reconstruction.state_timing_convention;
state_reconstruction_metadata.diagnostics = state_diagnostics;

preparation_snapshot = cfg.snapshot.preparation;

if ~exist(cfg.output.prepared_artifact_dir, 'dir')
    mkdir(cfg.output.prepared_artifact_dir);
end

artifact = struct("dates", dates, "incidence_observed", incidence_observed, "incidence_renewal_input", incidence_renewal_input, "incidence_scaled_proxy", incidence_scaled_proxy, "Rt_estimated", Rt_estimated, "Rt_valid_mask", Rt_valid_mask, "serial_interval_weights", weights, "S_proxy", S_proxy, "I_proxy", I_proxy, "R_proxy", R_proxy, "I_fraction_proxy", I_fraction_proxy, "state_valid_mask", state_valid_mask, "source_metadata", source_metadata, "state_reconstruction_metadata", state_reconstruction_metadata, "preparation_snapshot", preparation_snapshot);

save(cfg.output.prepared_artifact_path, '-struct', 'artifact');

fprintf('Estimated Rt on %d days; %d entries remain invalid.\n', nnz(Rt_valid_mask), nnz(~Rt_valid_mask));
fprintf('Reconstructed %d valid reported-case SIRS proxy states.\n', nnz(state_valid_mask));
fprintf('Maximum state-conservation error: %.6g\n', state_diagnostics.maximum_conservation_error);
fprintf('Prepared artifact saved to: %s\n', cfg.output.prepared_artifact_path);
fprintf('=== Part C Observed-Incidence and State Preparation Complete ===\n\n');