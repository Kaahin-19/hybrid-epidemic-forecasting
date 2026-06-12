%PARTC_01_PREPARE_REAL_DATA Prepare WHO COVID-19 inputs and a renewal Rt proxy.
%
%   Description:
%       Reads the configured WHO daily COVID-19 CSV, extracts the selected
%       country and date window, and builds a clearly named observed/smoothed
%       incidence pair. A fixed serial/generation-interval assumption from the
%       Part C configuration is discretized into normalized weights, and a
%       renewal-based effective reproduction-number proxy is estimated from the
%       smoothed incidence with the shared epidemic helpers. The renewal Rt is a
%       smoothing-dependent proxy for latent transmission, never ground truth.
%       The full-length series (with NaN warmup) is saved for the later Part C
%       forecast, evaluation, and figure-generation stages.
%
%   Workflow:
%       1. Initialization and WHO CSV schema validation.
%       2. Country/date filtering, case cleaning, and trailing smoothing.
%       3. Serial-interval discretization and renewal Rt-proxy estimation.
%       4. Processed artifact persistence.
%
%   See also PARTC_CONFIG, SERIAL_INTERVAL_WEIGHTS, ESTIMATE_RT_RENEWAL.
%
% A. M. Kaahin 2026-05-18
% Modified: 2026-06-12

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C WHO Real Data Preparation ===\n');

cfg = partC_config();
rawPath = cfg.input.daily_csv;

if ~exist(rawPath, 'file')
    error('PREP:MissingDailyWHOFile', ...
        ['Missing required Part C WHO daily CSV: %s.\n' ...
        'Expected file: data/partC/raw/WHO-COVID-19-global-daily-data.csv.'], ...
        rawPath);
end

if ~exist(cfg.output.data_processed_dir, 'dir')
    mkdir(cfg.output.data_processed_dir);
end

fprintf('Reading WHO daily CSV: %s\n', rawPath);
raw_table = readtable(rawPath, 'VariableNamingRule', 'preserve');

date_col = local_resolve_column(raw_table, cfg.input.date_col, rawPath);
country_code_col = local_resolve_column(raw_table, ...
    cfg.input.country_code_col, rawPath);
country_col = local_resolve_column(raw_table, cfg.input.country_col, rawPath);
new_cases_col = local_resolve_column(raw_table, ...
    cfg.input.new_cases_col, rawPath);
cumulative_cases_col = local_resolve_column(raw_table, ...
    cfg.input.cumulative_cases_col, rawPath);

%% 2. WHO Filtering and Incidence Construction
date_all = local_parse_dates(raw_table.(date_col), cfg.input.date_col);
if any(isnat(date_all))
    bad_rows = find(isnat(date_all));
    error('PREP:InvalidWHODate', ...
        'WHO date column contains invalid dates. First bad row: %d.', ...
        bad_rows(1));
end

country_code = strtrim(string(raw_table.(country_code_col)));
country_idx = country_code == cfg.input.country_code;
if ~any(country_idx)
    error('PREP:MissingCountry', ...
        'No WHO daily rows found for country code %s.', ...
        char(cfg.input.country_code));
end

date_country = date_all(country_idx);
country_name_values = string(raw_table.(country_col));
country_name_values = country_name_values(country_idx);
new_cases_raw = local_to_double(raw_table.(new_cases_col), ...
    cfg.input.new_cases_col);
cumulative_cases_raw = local_to_double(raw_table.(cumulative_cases_col), ...
    cfg.input.cumulative_cases_col);

new_cases_country = new_cases_raw(country_idx);
cumulative_cases_country = cumulative_cases_raw(country_idx);

[date_country, sort_idx] = sort(date_country);
country_name_values = country_name_values(sort_idx);
new_cases_country = new_cases_country(sort_idx);
cumulative_cases_country = cumulative_cases_country(sort_idx);

daily_cases_country = local_clean_daily_cases(new_cases_country, ...
    cumulative_cases_country);

window_idx = date_country >= cfg.input.start_date & ...
    date_country <= cfg.input.end_date;
if ~any(window_idx)
    error('PREP:EmptyDateWindow', ...
        'No WHO daily rows found for %s between %s and %s.', ...
        char(cfg.input.country_code), char(string(cfg.input.start_date)), ...
        char(string(cfg.input.end_date)));
end

date = date_country(window_idx);
country_name_values = country_name_values(window_idx);

local_validate_dates(date);

% Observed incidence is the cleaned daily reported case series; the smoothed
% incidence is a trailing moving average used as the renewal estimator input.
I_observed = local_validate_case_series(daily_cases_country(window_idx));
I_smoothed = movmean(I_observed, ...
    [cfg.input.smoothing_window_days - 1, 0], 'Endpoints', 'shrink');

%% 3. Serial Interval and Renewal Rt Proxy
% si_weights holds the discretized serial-interval weights; it is deliberately
% not named serial_interval_weights so the shared function of that name stays
% callable in this script scope. The artifact still exposes the canonical
% serial_interval_weights field via the struct save below.
serial_interval_config = local_serial_interval_config(cfg);
si_weights = serial_interval_weights( ...
    serial_interval_config.mean_days, serial_interval_config.sd_days, ...
    serial_interval_config.max_lag_days);

[Rt_est, Lambda_t] = estimate_rt_renewal(I_smoothed, si_weights);

% Treat undefined or non-positive renewal denominators as warmup/invalid so the
% saved Rt proxy is NaN wherever Lambda_t cannot support a valid ratio.
invalid_lambda = ~isfinite(Lambda_t) | (Lambda_t <= 0);
Rt_est(invalid_lambda) = NaN;

% The model-input history and the evaluation proxy are both the renewal Rt
% estimate: on real data there is no latent Rt to separate them. They are kept
% as distinct named signals for the downstream forecast and evaluation stages.
Rt_model_input = Rt_est;
Rt_evaluation_proxy = Rt_est;

t = (0:(numel(date) - 1))';

local_validate_processed_signals(Rt_est, I_observed, I_smoothed, ...
    si_weights, cfg);

%% 4. Metadata and Persistence
country_observed = local_observed_country_name(country_name_values, ...
    cfg.input.country_name);
metadata = local_build_metadata(cfg, rawPath, country_observed, ...
    numel(date), serial_interval_config, si_weights, ...
    nnz(~isnan(Rt_est)));
metadata.processed_date_range = [date(1), date(end)];
metadata.processed_t_range = [t(1), t(end)];
metadata.processed_artifact_name = "partC_01_real_data_processed.mat";
cfg_snapshot = local_cfg_snapshot(cfg, serial_interval_config);

processed_table = table(date, t, I_observed, I_smoothed, Lambda_t, ...
    Rt_est, Rt_model_input, Rt_evaluation_proxy, 'VariableNames', ...
    {'date', 't', 'I_observed', 'I_smoothed', 'Lambda_t', 'Rt_est', ...
    'Rt_model_input', 'Rt_evaluation_proxy'});

fprintf('Prepared %d WHO-derived real-data observations for %s.\n', ...
    numel(date), char(country_observed));
fprintf('Renewal Rt proxy defined on %d of %d days (%d-day NaN warmup).\n', ...
    nnz(~isnan(Rt_est)), numel(Rt_est), serial_interval_config.max_lag_days);

matPath = fullfile(cfg.output.data_processed_dir, ...
    'partC_01_real_data_processed.mat');
csvPath = fullfile(cfg.output.data_processed_dir, ...
    'partC_01_real_data_processed.csv');

% Assemble the artifact as a struct and save its fields as top-level variables
% (save -struct). This exposes the canonical serial_interval_weights field name
% without binding a script variable of that name.
artifact = struct();
artifact.date = date;
artifact.t = t;
artifact.I_observed = I_observed;
artifact.I_smoothed = I_smoothed;
artifact.serial_interval_weights = si_weights;
artifact.serial_interval_config = serial_interval_config;
artifact.Lambda_t = Lambda_t;
artifact.Rt_est = Rt_est;
artifact.Rt_model_input = Rt_model_input;
artifact.Rt_evaluation_proxy = Rt_evaluation_proxy;
artifact.cfg = cfg;
artifact.cfg_snapshot = cfg_snapshot;
artifact.rawPath = rawPath;
artifact.metadata = metadata;

save(matPath, '-struct', 'artifact');
writetable(processed_table, csvPath);

fprintf('Processed MAT artifact saved to: %s\n', matPath);
fprintf('Processed CSV export saved to: %s\n', csvPath);

fprintf('=== Part C WHO Real Data Preparation Complete ===\n\n');

%% 5. Local Functions
function actual_col = local_resolve_column(data_table, expected_col, source_path)
%LOCAL_RESOLVE_COLUMN Resolve a configured WHO column name in a table.
    expected_col = string(expected_col);
    expected_col_text = char(expected_col);
    available_cols = string(data_table.Properties.VariableNames);
    normalized_cols = erase(available_cols, char(65279));

    match_idx = find(normalized_cols == expected_col, 1);
    if isempty(match_idx)
        error('PREP:MissingColumns', ...
            'Missing required column in %s: %s.', ...
            source_path, expected_col_text);
    end

    actual_col = char(available_cols(match_idx));
end

function date_vec = local_parse_dates(raw_dates, date_col)
%LOCAL_PARSE_DATES Parse the configured WHO date column into datetimes.
    date_col = char(date_col);

    if isdatetime(raw_dates)
        date_vec = raw_dates(:);
        date_vec.Format = 'yyyy-MM-dd';
        return;
    end

    if iscell(raw_dates) || isstring(raw_dates) || iscategorical(raw_dates)
        date_text = string(raw_dates(:));
        date_vec = local_parse_date_strings(date_text, date_col);
        date_vec.Format = 'yyyy-MM-dd';
        return;
    end

    if isnumeric(raw_dates)
        try
            date_vec = datetime(raw_dates(:), 'ConvertFrom', 'excel');
            date_vec.Format = 'yyyy-MM-dd';
            return;
        catch ME
            error('PREP:InvalidDateColumn', ...
                'Could not parse numeric date column %s as Excel serial dates: %s', ...
                date_col, ME.message);
        end
    end

    error('PREP:InvalidDateColumn', ...
        'Date column %s must be datetime, text, categorical, or numeric.', ...
        date_col);
end

function date_vec = local_parse_date_strings(date_text, date_col)
%LOCAL_PARSE_DATE_STRINGS Try common date formats before using auto-detect.
    date_text = strtrim(date_text);
    nonmissing_text = ~ismissing(date_text) & strlength(date_text) > 0;
    formats = ["yyyy-MM-dd", "yyyy/MM/dd", "dd/MM/yyyy", "MM/dd/yyyy", ...
        "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss"];

    for i = 1:numel(formats)
        try
            candidate = datetime(date_text, 'InputFormat', formats(i));
            if all(~isnat(candidate(nonmissing_text)))
                date_vec = candidate;
                return;
            end
        catch
        end
    end

    try
        date_vec = datetime(date_text);
    catch ME
        error('PREP:InvalidDateColumn', ...
            'Could not parse date column %s: %s', date_col, ME.message);
    end
end

function values = local_to_double(raw_values, col_name)
%LOCAL_TO_DOUBLE Convert WHO numeric columns, preserving blanks as NaN.
    col_name = char(col_name);

    if isnumeric(raw_values)
        values = double(raw_values(:));
        return;
    end

    if iscell(raw_values) || isstring(raw_values) || iscategorical(raw_values)
        values = str2double(strtrim(string(raw_values(:))));
        return;
    end

    error('PREP:InvalidNumericColumn', ...
        'WHO column %s must be numeric or text convertible to numeric.', ...
        col_name);
end

function daily_cases = local_clean_daily_cases(new_cases, cumulative_cases)
%LOCAL_CLEAN_DAILY_CASES Prefer New_cases and fill blanks from cumulative diffs.
    new_cases = double(new_cases(:));
    cumulative_cases = double(cumulative_cases(:));

    if numel(new_cases) ~= numel(cumulative_cases)
        error('PREP:CaseLengthMismatch', ...
            'WHO New_cases and Cumulative_cases columns must have equal length.');
    end

    cumulative_diff = [cumulative_cases(1); diff(cumulative_cases)];
    cumulative_diff = max(cumulative_diff, 0);

    daily_cases = new_cases;
    missing_new_cases = ~isfinite(daily_cases);
    daily_cases(missing_new_cases) = cumulative_diff(missing_new_cases);
    daily_cases = max(daily_cases, 0);

    if any(~isfinite(daily_cases))
        bad_rows = find(~isfinite(daily_cases));
        error('PREP:MissingCaseValues', ...
            ['Could not derive daily cases from WHO New_cases or ' ...
            'Cumulative_cases. First bad country row: %d.'], bad_rows(1));
    end
end

function local_validate_dates(date)
%LOCAL_VALIDATE_DATES Ensure the processed WHO date vector is unique and sorted.
    if numel(date) ~= numel(unique(date))
        error('PREP:DuplicateDates', ...
            'WHO daily data contains duplicate dates after country/date filtering.');
    end

    if any(diff(date) < days(0))
        error('PREP:UnsortedDates', ...
            'WHO daily dates must be sorted after preprocessing.');
    end
end

function daily_cases = local_validate_case_series(daily_cases)
%LOCAL_VALIDATE_CASE_SERIES Validate the cleaned daily case series.
    daily_cases = double(daily_cases(:));
    if isempty(daily_cases) || any(~isfinite(daily_cases)) || ...
            any(daily_cases < 0)
        error('PREP:InvalidCaseSeries', ...
            'Cleaned WHO daily cases must be finite and nonnegative.');
    end
end

function serial_interval_config = local_serial_interval_config(cfg)
%LOCAL_SERIAL_INTERVAL_CONFIG Assemble the fixed serial-interval assumption.
    serial_interval_config = struct();
    serial_interval_config.distribution = "gamma";
    serial_interval_config.mean_days = cfg.input.serial_interval_mean_days;
    serial_interval_config.sd_days = cfg.input.serial_interval_sd_days;
    serial_interval_config.max_lag_days = cfg.input.serial_interval_max_lag_days;
    serial_interval_config.lags = (1:cfg.input.serial_interval_max_lag_days)';
    serial_interval_config.normalized = true;
    serial_interval_config.source = ...
        "Fixed external COVID-19 serial-interval assumption from partC_config; not inferred from the case series.";
    serial_interval_config.discretization = ...
        "Gamma density evaluated at integer day lags 1..max_lag, normalized to sum one.";
end

function local_validate_processed_signals(Rt_est, I_observed, I_smoothed, ...
    weights, cfg)
%LOCAL_VALIDATE_PROCESSED_SIGNALS Validate the WHO-derived Part C artifact.
%   Dates are already checked by local_validate_dates on the same vector.
    if any(~isfinite(I_observed)) || any(I_observed < 0) || ...
            any(~isfinite(I_smoothed)) || any(I_smoothed < 0)
        error('PREP:InvalidIncidence', ...
            'I_observed and I_smoothed must be finite and nonnegative.');
    end

    weights = double(weights(:));
    if isempty(weights) || any(~isfinite(weights)) || any(weights < 0) || ...
            abs(sum(weights) - 1) > 1e-9
        error('PREP:InvalidSerialIntervalWeights', ...
            'Serial-interval weights must be finite, nonnegative, and sum to one.');
    end

    % Rt_est carries NaN warmup by construction; the defined entries must be a
    % finite, strictly positive renewal-ratio proxy.
    defined_Rt = Rt_est(~isnan(Rt_est));
    if any(~isfinite(defined_Rt)) || any(defined_Rt <= 0)
        error('PREP:InvalidRtSignal', ...
            'Defined renewal Rt-proxy values must be finite and strictly positive.');
    end

    min_required = cfg.forecast.min_window + cfg.forecast.horizon + 1;
    if numel(defined_Rt) < min_required
        error('PREP:InsufficientForecastData', ...
            ['Only %d defined Rt-proxy observations remain. Part C needs at ' ...
            'least %d for min_window=%d and horizon=%d.'], ...
            numel(defined_Rt), min_required, cfg.forecast.min_window, ...
            cfg.forecast.horizon);
    end
end

function country_observed = local_observed_country_name(country_values, fallback)
%LOCAL_OBSERVED_COUNTRY_NAME Pick a stable country label for metadata.
    country_values = strtrim(string(country_values(:)));
    country_values = country_values(~ismissing(country_values) & ...
        strlength(country_values) > 0);

    if isempty(country_values)
        country_observed = string(fallback);
    else
        country_observed = mode(categorical(country_values));
        country_observed = string(country_observed);
    end
end

function metadata = local_build_metadata(cfg, rawPath, country_observed, ...
    num_observations, serial_interval_config, weights, num_defined_rt)
%LOCAL_BUILD_METADATA Record WHO preprocessing details with the artifact.
    metadata = struct();
    metadata.source = cfg.input.source;
    metadata.source_file = string(rawPath);
    metadata.country_code = cfg.input.country_code;
    metadata.country_name = country_observed;
    metadata.configured_country_name = cfg.input.country_name;
    metadata.start_date = cfg.input.start_date;
    metadata.end_date = cfg.input.end_date;
    metadata.num_observations = num_observations;
    metadata.num_defined_rt = num_defined_rt;
    metadata.smoothing_window_days = cfg.input.smoothing_window_days;
    metadata.I_observed_definition = ...
        "Cleaned WHO daily reported New_cases (cumulative-difference fallback).";
    metadata.I_smoothed_definition = ...
        "Trailing moving average of I_observed over smoothing_window_days.";
    metadata.rt_estimation_method = ...
        "Renewal ratio Rt_est(t) = I_smoothed(t) / sum_s w(s) I_smoothed(t-s).";
    metadata.rt_is_proxy = true;
    metadata.rt_interpretation = ...
        "Rt_est is a smoothing-dependent renewal-based proxy for latent transmission, not the true latent Rt and not a SIRS/SIR hidden state.";
    metadata.rt_warmup_days = serial_interval_config.max_lag_days;
    metadata.rt_warmup_handling = ...
        "First max_lag days, and any day with undefined or non-positive renewal infectiousness, are NaN.";
    metadata.serial_interval_config = serial_interval_config;
    metadata.serial_interval_weights = weights(:);
end

function cfg_snapshot = local_cfg_snapshot(cfg, serial_interval_config)
%LOCAL_CFG_SNAPSHOT Store relevant preprocessing configuration.
    cfg_snapshot = struct();
    cfg_snapshot.experiment_id = cfg.experiment_id;
    cfg_snapshot.experiment_name = cfg.experiment_name;
    cfg_snapshot.data_source = cfg.data_source;
    cfg_snapshot.input = cfg.input;
    cfg_snapshot.forecast = cfg.forecast;
    cfg_snapshot.output = cfg.output;
    cfg_snapshot.serial_interval_config = serial_interval_config;
end
