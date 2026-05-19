%PARTC_02_RUN_FORECASTS Run fixed AR/ARX forecasts on WHO-derived Rt estimates.
%
%   Description:
%       Loads the processed Part C real-data series and executes
%       expanding-window forecasts of the WHO-derived Rt_est signal. The
%       comparison is frozen to AR/None and ARX/I. For ARX/I, historical
%       exogenous input is the scaled infection proxy up to the forecast
%       origin. Retrospective future exogenous input is the observed future
%       I_scaled series over the forecast horizon, so this is a proof of
%       concept evaluation rather than a deployable real-time forecast.
%
%   Workflow:
%       1. Initialization and processed-data loading
%       2. Forecast loop over the fixed real-data configurations
%       3. Artifact and figure persistence, including diagnostic capped
%          forecast figures for readability.
%
%   See also PARTC_CONFIG, FIT_ARIMA, FIT_ARIMAX.

% A. M. Kaahin 2026-05-18

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Fixed Forecast Execution ===\n');

cfg = partC_config();
processedPath = fullfile(cfg.output.data_processed_dir, ...
    'partC_01_real_data_processed.mat');
saveDir = cfg.output.forecast_dir;
figDir  = cfg.output.fig_dir;
wis_alphas = cfg.forecast.wis_alphas;

if ~exist(processedPath, 'file')
    error('FORECAST:MissingProcessedData', ...
        ['Missing processed WHO-derived real-data artifact. ' ...
        'Run partC_01_prepare_real_data.m first.']);
end

if ~exist(saveDir, 'dir'), mkdir(saveDir); end
if ~exist(figDir, 'dir'),  mkdir(figDir); end

loaded = load(processedPath);
local_validate_processed_data(loaded, processedPath);

date = loaded.date(:);
tspan = loaded.t(:);
Rt_true = loaded.Rt_est(:);
I_scaled = loaded.I_scaled(:);

fprintf('Loaded %d processed real-data observations.\n', numel(Rt_true));

%% 2. Forecast Loop
for c = 1:numel(cfg.models)
    model_cfg = cfg.models(c);
    fprintf('  - Fixed model %s | %s\n', ...
        model_cfg.model_type, model_cfg.exo_mode);

    results = local_run_real_forecasts(Rt_true, I_scaled, tspan, date, ...
        cfg, model_cfg, wis_alphas);

    summary_table = local_summary_table(model_cfg, numel(results));
    file_prefix = sprintf('partC_02_forecast_real_%s_%s', ...
        model_cfg.model_type, model_cfg.exo_mode);

    csvName = fullfile(saveDir, [file_prefix, '_summary.csv']);
    writetable(summary_table, csvName);
    fprintf('Forecast summary saved to: %s\n', csvName);

    outName = fullfile(saveDir, [file_prefix, '.mat']);
    model_type = model_cfg.model_type;
    exo_mode = model_cfg.exo_mode;
    selected_model = model_cfg.selected_model;
    save(outName, 'results', 'cfg', 'model_type', 'exo_mode', ...
        'selected_model', 'processedPath');
    fprintf('Forecast artifact saved to: %s\n', outName);

    plot_name = sprintf('real_%s_%s', model_cfg.model_type, model_cfg.exo_mode);
    plotPath = plot_rt_forecast_comparison(results, Rt_true, tspan, ...
        plot_name, cfg);
    partCPlotPath = fullfile(figDir, ...
        sprintf('partC_02_forecast_plot_%s.png', plot_name));
    if exist(plotPath, 'file')
        movefile(plotPath, partCPlotPath, 'f');
        plotPath = partCPlotPath;
    end
    fprintf('Forecast visualization saved to: %s\n', plotPath);

    % The full forecast figure remains the primary visual artifact. This
    % capped diagnostic view only improves readability when forecasts explode.
    zoomedPlotPath = local_plot_zoomed_rt_forecast_comparison(results, ...
        Rt_true, tspan, plot_name, cfg, figDir);
    fprintf('Diagnostic zoomed forecast visualization saved to: %s\n', ...
        zoomedPlotPath);
end

fprintf('=== Part C Fixed Forecast Execution Complete ===\n\n');

%% 3. Local Functions
function local_validate_processed_data(data, processedPath)
%LOCAL_VALIDATE_PROCESSED_DATA Verify processed Part C artifact fields.
    required_fields = {'date', 't', 'Rt_est', 'I_proxy', 'I_scaled'};
    if ~all(isfield(data, required_fields))
        error('FORECAST:InvalidProcessedData', ...
            'Processed artifact is missing required fields: %s.', processedPath);
    end

    n = numel(data.Rt_est(:));
    if n == 0 || numel(data.t(:)) ~= n || numel(data.I_proxy(:)) ~= n || ...
            numel(data.I_scaled(:)) ~= n || numel(data.date(:)) ~= n
        error('FORECAST:InvalidProcessedData', ...
            'Processed Part C vectors must be nonempty and have equal length.');
    end

    values = [double(data.t(:)); double(data.Rt_est(:)); ...
        double(data.I_proxy(:)); double(data.I_scaled(:))];
    if any(~isfinite(values)) || any(double(data.Rt_est(:)) <= 0) || ...
            any(double(data.I_proxy(:)) < 0) || any(double(data.I_scaled(:)) < 0)
        error('FORECAST:InvalidProcessedData', ...
            ['Processed Part C data must have finite positive Rt_est and ' ...
            'finite nonnegative I_proxy/I_scaled values.']);
    end
end

function results = local_run_real_forecasts(Rt_true, I_scaled, tspan, date, ...
    cfg, model_cfg, wis_alphas)
%LOCAL_RUN_REAL_FORECASTS Run expanding-window forecasts for one model.
    horizon = cfg.forecast.horizon;
    max_origin = tspan(end) - horizon;
    windows = cfg.forecast.min_window : cfg.forecast.step_size : max_origin;

    results = repmat(struct( ...
        'window_day', [], ...
        'window_day_idx', [], ...
        'window_date', [], ...
        'forecast_median', [], ...
        'forecast_interval_alphas', [], ...
        'forecast_lower', [], ...
        'forecast_upper', [], ...
        'best_model', [], ...
        'aic_landscape', [], ...
        'truth_Rt_window', [], ...
        'truth_I_scaled_window', [], ...
        'time_horizon', [], ...
        'date_horizon', []), numel(windows), 1);
    count = 1;

    for T = windows
        idx_T = find(tspan == T, 1);
        if isempty(idx_T)
            continue;
        end

        idx_end = idx_T + horizon;
        if idx_end > numel(Rt_true)
            continue;
        end

        Rt_past = Rt_true(1:idx_T);
        [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
            local_fit_fixed_model(model_cfg, Rt_past, I_scaled, idx_T, ...
            idx_end, horizon, wis_alphas, cfg);

        results(count).window_day      = T;
        results(count).window_day_idx  = idx_T;
        results(count).window_date     = date(idx_T);
        results(count).forecast_median = Rt_pred;
        results(count).forecast_interval_alphas = out_alphas;
        results(count).forecast_lower  = Rt_lower;
        results(count).forecast_upper  = Rt_upper;
        results(count).best_model      = model_cfg.selected_model;
        results(count).aic_landscape   = [model_cfg.selected_model, aicc];
        results(count).truth_Rt_window = Rt_true(idx_T+1:idx_end);
        results(count).truth_I_scaled_window = I_scaled(idx_T+1:idx_end);
        results(count).time_horizon    = tspan(idx_T+1:idx_end);
        results(count).date_horizon    = date(idx_T+1:idx_end);

        count = count + 1;
    end

    results = results(1:count-1);
    if isempty(results)
        error('FORECAST:NoValidWindows', ...
            ['No valid Part C forecast windows were available. ' ...
            'Check data length, min_window, step_size, and horizon.']);
    end
end

function [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
    local_fit_fixed_model(model_cfg, Rt_past, I_scaled, idx_T, idx_end, ...
    horizon, wis_alphas, cfg)
%LOCAL_FIT_FIXED_MODEL Dispatch Part C fixed-order model fits.
    switch model_cfg.model_type
        case 'AR'
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                fit_arima(Rt_past, model_cfg.selected_model(1), 0, 0, ...
                horizon, wis_alphas);

        case 'ARX'
            U_past = I_scaled(1:idx_T);
            U_future = I_scaled(idx_T+1:idx_end);
            nb_vec = model_cfg.selected_model(2);
            nk_vec = model_cfg.selected_model(3);

            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                fit_arimax(Rt_past, U_past, U_future, ...
                model_cfg.selected_model(1), 0, 0, nb_vec, nk_vec, ...
                horizon, wis_alphas, [], [], '', cfg.sim.seed);

        otherwise
            error('CFG:UnknownModel', ...
                'Part C fixed forecasts support only AR and ARX.');
    end
end

function summary_table = local_summary_table(model_cfg, num_windows)
%LOCAL_SUMMARY_TABLE Build one-row fixed configuration summary.
    values = [model_cfg.selected_model, num_windows];
    summary_table = array2table(values, ...
        'VariableNames', [model_cfg.headers, {'Times_Selected'}]);
end

function outPath = local_plot_zoomed_rt_forecast_comparison(results, Rt_true, ...
    tspan, plot_name, cfg, figDir)
%LOCAL_PLOT_ZOOMED_RT_FORECAST_COMPARISON Save a capped diagnostic plot.
    outPath = fullfile(figDir, ...
        sprintf('partC_02_forecast_plot_%s_zoomed.png', plot_name));

    fig = figure('Name', ['Forecast Comparison Zoomed: ', plot_name], ...
        'Visible', 'off');
    fig.Units = 'centimeters';
    fig.Position(3) = 17.0;
    fig.Position(4) = 8.5;

    ax = axes(fig);
    hold(ax, 'on');

    axtoolbar(ax, {'export'});

    plot_alphas = sort(double(cfg.forecast.plot_alphas(:)'), 'ascend');
    lead_time = local_plot_lead_time(cfg);
    num_intervals = min(numel(plot_alphas), 2);
    interval_colors = [0.30, 0.65, 0.95; 0.10, 0.45, 0.85];
    interval_face_alpha = [0.14, 0.28];
    interval_handles = gobjects(1, num_intervals);
    interval_labels = cellstr(compose('%d%% Predictive Interval', ...
        round((1 - plot_alphas(1:num_intervals)) * 100)));
    hMed = gobjects(0);

    [target_days, median_forecast, lower_forecast, upper_forecast] = ...
        local_extract_fixed_lead(results, lead_time, plot_alphas);

    for j = 1:num_intervals
        valid_interval = isfinite(target_days) & ...
            isfinite(lower_forecast(:, j)) & isfinite(upper_forecast(:, j));

        if nnz(valid_interval) >= 2
            interval_handles(j) = local_fill_interval(ax, ...
                target_days(valid_interval), ...
                lower_forecast(valid_interval, j), ...
                upper_forecast(valid_interval, j), ...
                interval_colors(j, :), interval_face_alpha(j), ...
                interval_labels{j});
        end
    end

    hTruth = plot(ax, tspan, Rt_true, 'k-', 'LineWidth', 2.2, ...
        'DisplayName', 'Ground Truth');

    valid_median = isfinite(target_days) & isfinite(median_forecast);
    if any(valid_median)
        hMed = plot(ax, target_days(valid_median), ...
            median_forecast(valid_median), 'b--o', 'LineWidth', 1.3, ...
            'MarkerSize', 3.2, ...
            'DisplayName', sprintf('%d-Day-Ahead Median Forecast', lead_time));
    end

    title(ax, {sprintf('%d-Day-Ahead Forecast vs Truth: %s', ...
        lead_time, strrep(plot_name, '_', ' ')), ...
        'Rt axis capped at 5.5 for readability'});
    xlabel(ax, 'Time (days)');
    ylabel(ax, '$\mathcal{R}_t$', 'Interpreter', 'latex');
    grid(ax, 'on');
    ylim(ax, [0, 5.5]);
    xlim(ax, [tspan(1), tspan(end)]);

    max_legend_items = 1 + double(~isempty(hMed)) + num_intervals;
    legend_handles = gobjects(1, max_legend_items);
    legend_labels = cell(1, max_legend_items);
    legend_count = 1;

    legend_handles(legend_count) = hTruth;
    legend_labels{legend_count} = 'Ground Truth';

    if ~isempty(hMed)
        legend_count = legend_count + 1;
        legend_handles(legend_count) = hMed;
        legend_labels{legend_count} = ...
            sprintf('%d-Day-Ahead Median Forecast', lead_time);
    end

    for j = 1:num_intervals
        if isgraphics(interval_handles(j))
            legend_count = legend_count + 1;
            legend_handles(legend_count) = interval_handles(j);
            legend_labels{legend_count} = interval_labels{j};
        end
    end

    legend_handles = legend_handles(1:legend_count);
    legend_labels = legend_labels(1:legend_count);
    legend(ax, legend_handles, legend_labels, 'Location', 'northwest');
    exportgraphics(fig, outPath, 'Resolution', 300);
    close(fig);
end

function lead_time = local_plot_lead_time(cfg)
%LOCAL_PLOT_LEAD_TIME Read the configured fixed-lead forecast horizon.
    lead_time = 7;
    if isfield(cfg, 'forecast') && isfield(cfg.forecast, 'plot_lead_time')
        lead_time = double(cfg.forecast.plot_lead_time);
    end

    if ~isscalar(lead_time) || ~isfinite(lead_time) || lead_time < 1
        error('PLOT:InvalidLeadTime', ...
            'Forecast plot lead time must be a positive scalar.');
    end

    lead_time = round(lead_time);
end

function [target_days, median_forecast, lower_forecast, upper_forecast] = ...
    local_extract_fixed_lead(results, lead_time, plot_alphas)
%LOCAL_EXTRACT_FIXED_LEAD Extract a fixed forecast lead for plotting.
    num_results = numel(results);
    num_alphas = numel(plot_alphas);

    target_days = nan(num_results, 1);
    median_forecast = nan(num_results, 1);
    lower_forecast = nan(num_results, num_alphas);
    upper_forecast = nan(num_results, num_alphas);

    if isempty(results) || ~isfield(results, 'forecast_interval_alphas')
        return;
    end

    for i = 1:num_results
        t_f = results(i).time_horizon(:);
        y_f = results(i).forecast_median(:);

        if numel(t_f) < lead_time || numel(y_f) < lead_time
            continue;
        end

        target_days(i) = t_f(lead_time);
        median_forecast(i) = y_f(lead_time);

        stored_alphas = double(results(i).forecast_interval_alphas(:)');
        for j = 1:num_alphas
            idx_alpha = local_alpha_index(stored_alphas, plot_alphas(j));
            if isempty(idx_alpha)
                continue;
            end

            if size(results(i).forecast_lower, 1) >= lead_time && ...
                    size(results(i).forecast_upper, 1) >= lead_time && ...
                    size(results(i).forecast_lower, 2) >= idx_alpha && ...
                    size(results(i).forecast_upper, 2) >= idx_alpha
                lower_forecast(i, j) = ...
                    results(i).forecast_lower(lead_time, idx_alpha);
                upper_forecast(i, j) = ...
                    results(i).forecast_upper(lead_time, idx_alpha);
            end
        end
    end
end

function idx = local_alpha_index(stored_alphas, target_alpha)
%LOCAL_ALPHA_INDEX Find a stored predictive interval alpha.
    [min_diff, idx] = min(abs(stored_alphas - target_alpha));
    if isempty(idx) || min_diff > 1e-8
        idx = [];
    end
end

function h = local_fill_interval(ax, t_fcst, lower_bound, upper_bound, ...
    face_color, face_alpha, display_name)
%LOCAL_FILL_INTERVAL Draw one predictive interval ribbon.
    lower_bound = lower_bound(:);
    upper_bound = upper_bound(:);
    t_fcst = t_fcst(:);

    if isempty(display_name)
        h = fill(ax, [t_fcst; flipud(t_fcst)], ...
            [upper_bound; flipud(lower_bound)], face_color, ...
            'FaceAlpha', face_alpha, 'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
    else
        h = fill(ax, [t_fcst; flipud(t_fcst)], ...
            [upper_bound; flipud(lower_bound)], face_color, ...
            'FaceAlpha', face_alpha, 'EdgeColor', 'none', ...
            'DisplayName', display_name);
    end
end
