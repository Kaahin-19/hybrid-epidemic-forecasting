%PARTC_01_PREPARE_REAL_DATA Prepare WHO COVID-19 inputs for Part C.
%
%   Description:
%       Reads the configured WHO daily COVID-19 CSV, extracts the selected
%       country and date window, constructs a smoothed incidence proxy, and
%       estimates an empirical Rt signal with a renewal-style ratio. The
%       compact Part C processed dataset is then saved for forecast,
%       evaluation, and figure-generation stages.
%
%   Workflow:
%       1. Initialization and WHO CSV schema validation
%       2. Country/date filtering, case cleaning, smoothing, and Rt estimation
%       3. Processed artifact persistence
%
%   See also PARTC_CONFIG, PARTC_05_GENERATE_FIGURES.

% A. M. Kaahin 2026-05-18
% Modified: 2026-06-03

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

%% 2. WHO Filtering and Preprocessing
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
daily_cases = daily_cases_country(window_idx);
country_name_values = country_name_values(window_idx);

local_validate_dates(date);
daily_cases = local_validate_case_series(daily_cases);

I_proxy_full = movmean(daily_cases, ...
    [cfg.input.smoothing_window_days - 1, 0], 'Endpoints', 'shrink');

[Rt_est_full, renewal_lambda_full, serial_interval_weights] = ...
    local_estimate_rt_renewal(I_proxy_full, cfg);

warmup_rows = cfg.input.serial_interval_max_lag_days;
if numel(Rt_est_full) <= warmup_rows
    error('PREP:InsufficientWarmupData', ...
        'Not enough rows remain after filtering to estimate Rt with %d lags.', ...
        warmup_rows);
end

keep_idx = ((1:numel(Rt_est_full))' > warmup_rows);
date = date(keep_idx);
daily_cases = daily_cases(keep_idx);
I_proxy = I_proxy_full(keep_idx);
Rt_est = Rt_est_full(keep_idx);
renewal_lambda = renewal_lambda_full(keep_idx);

max_i_proxy = max(I_proxy);
if ~isfinite(max_i_proxy) || max_i_proxy <= 0
    error('PREP:InvalidIProxyScale', ...
        'The smoothed WHO case proxy must contain at least one positive value.');
end
I_scaled = I_proxy / max_i_proxy;

local_validate_processed_signals(Rt_est, I_proxy, I_scaled, date, cfg);

t = (0:(numel(date) - 1))';

country_observed = local_observed_country_name(country_name_values, ...
    cfg.input.country_name);
metadata = local_build_metadata(cfg, rawPath, country_observed, ...
    numel(date), serial_interval_weights);
metadata.processed_date_range = [date(1), date(end)];
metadata.processed_t_range = [t(1), t(end)];
metadata.processed_artifact_name = "partC_01_real_data_processed.mat";
cfg_snapshot = local_cfg_snapshot(cfg);
processed_table = table(date, t, Rt_est, I_proxy, I_scaled, daily_cases, ...
    renewal_lambda, 'VariableNames', {'date', 't', 'Rt_est', 'I_proxy', ...
    'I_scaled', 'daily_cases', 'renewal_lambda'});

fprintf('Prepared %d WHO-derived real-data observations for %s.\n', ...
    numel(Rt_est), char(country_observed));

%% 3. Persistence
matPath = fullfile(cfg.output.data_processed_dir, ...
    'partC_01_real_data_processed.mat');
csvPath = fullfile(cfg.output.data_processed_dir, ...
    'partC_01_real_data_processed.csv');

save(matPath, 'date', 't', 'Rt_est', 'I_proxy', 'I_scaled', 'cfg', ...
    'cfg_snapshot', 'rawPath', 'daily_cases', 'renewal_lambda', 'metadata');
writetable(processed_table, csvPath);

fprintf('Processed MAT artifact saved to: %s\n', matPath);
fprintf('Processed CSV export saved to: %s\n', csvPath);

fprintf('=== Part C WHO Real Data Preparation Complete ===\n\n');

%% 4. Local Functions
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

function [Rt_est, renewal_lambda, serial_interval_weights] = ...
    local_estimate_rt_renewal(I_proxy, cfg)
%LOCAL_ESTIMATE_RT_RENEWAL Estimate Rt from smoothed incidence by renewal ratio.
    I_proxy = double(I_proxy(:));
    max_lag = cfg.input.serial_interval_max_lag_days;
    serial_interval_weights = local_serial_interval_weights( ...
        cfg.input.serial_interval_mean_days, ...
        cfg.input.serial_interval_sd_days, ...
        max_lag);

    renewal_lambda = nan(numel(I_proxy), 1);
    for t_idx = (max_lag + 1):numel(I_proxy)
        lagged_incidence = I_proxy(t_idx - (1:max_lag));
        renewal_lambda(t_idx) = sum(serial_interval_weights .* lagged_incidence);
    end

    Rt_est = I_proxy ./ renewal_lambda;
end

function weights = local_serial_interval_weights(mean_days, sd_days, max_lag)
%LOCAL_SERIAL_INTERVAL_WEIGHTS Discretize a gamma serial interval on day lags.
    if mean_days <= 0 || sd_days <= 0 || max_lag < 1
        error('PREP:InvalidSerialInterval', ...
            'Serial interval mean, standard deviation, and max lag must be positive.');
    end

    lag_days = (1:max_lag)';
    shape = (mean_days / sd_days)^2;
    scale = (sd_days^2) / mean_days;
    weights = (lag_days.^(shape - 1) .* exp(-lag_days / scale)) ./ ...
        (gamma(shape) * scale^shape);
    weights = weights / sum(weights);
end

function local_validate_processed_signals(Rt_est, I_proxy, I_scaled, date, cfg)
%LOCAL_VALIDATE_PROCESSED_SIGNALS Validate the WHO-derived Part C artifact.
    if numel(date) ~= numel(unique(date)) || any(diff(date) < days(0))
        error('PREP:InvalidProcessedDates', ...
            'Processed Part C dates must be unique and sorted.');
    end

    if any(~isfinite(Rt_est)) || any(Rt_est <= 0)
        error('PREP:InvalidRtSignal', ...
            'Estimated Rt must be finite and strictly positive after warmup removal.');
    end

    if any(~isfinite(I_proxy)) || any(I_proxy < 0) || ...
            any(~isfinite(I_scaled)) || any(I_scaled < 0)
        error('PREP:InvalidIProxy', ...
            'I_proxy and I_scaled must be finite and nonnegative.');
    end

    n = numel(Rt_est);
    min_required = cfg.forecast.min_window + cfg.forecast.horizon + 1;
    if n < min_required
        error('PREP:InsufficientForecastData', ...
            ['Only %d processed observations remain. Part C needs at least ' ...
            '%d for min_window=%d and horizon=%d.'], ...
            n, min_required, cfg.forecast.min_window, cfg.forecast.horizon);
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
    num_observations, serial_interval_weights)
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
    metadata.smoothing_window_days = cfg.input.smoothing_window_days;
    metadata.case_proxy = "I_proxy = trailing 7-day moving average of cleaned New_cases";
    metadata.rt_estimation_method = ...
        "renewal ratio Rt_est(t) = I_proxy(t) / sum_s w_s I_proxy(t-s)";
    metadata.serial_interval_mean_days = cfg.input.serial_interval_mean_days;
    metadata.serial_interval_sd_days = cfg.input.serial_interval_sd_days;
    metadata.serial_interval_max_lag_days = cfg.input.serial_interval_max_lag_days;
    metadata.serial_interval_lags = (1:cfg.input.serial_interval_max_lag_days)';
    metadata.serial_interval_weights = serial_interval_weights;
end

function cfg_snapshot = local_cfg_snapshot(cfg)
%LOCAL_CFG_SNAPSHOT Store relevant preprocessing configuration.
    cfg_snapshot = struct();
    cfg_snapshot.experiment_id = cfg.experiment_id;
    cfg_snapshot.experiment_name = cfg.experiment_name;
    cfg_snapshot.data_source = cfg.data_source;
    cfg_snapshot.input = cfg.input;
    cfg_snapshot.forecast = cfg.forecast;
    cfg_snapshot.output = cfg.output;
end
