function outPath = plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg)
%PLOT_RT_FORECAST_COMPARISON Visualize forecast performance against ground truth.
%
%   Syntax:
%       outPath = plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg)
%
%   Description:
%       Generates a fixed-lead summary figure comparing forecasts against
%       the synthetic ground truth. For each forecast origin, one horizon
%       index is selected so the plotted median and intervals describe the
%       same lead time throughout the figure.
%
%   Inputs:
%       results   - Struct array of forecast results per window.
%       Rt_true   - Numeric vector of the ground-truth transmission-potential curve.
%       tspan     - Numeric vector of time points.
%       plot_name - String identifier for the plot title (scenario name).
%       cfg       - Configuration struct containing output directories.
%
%   Outputs:
%       outPath   - Absolute path to the saved forecast-comparison figure.
%
%   See also PARTA_03_RUN_FORECASTS, PARTA_CONFIG.

% A. M. Kaahin 2026-02-19
% Modified: 2026-04-30

    %% 1. Initialization
    if isfield(cfg, 'output') && isfield(cfg.output, 'fig_dir')
        figDir = cfg.output.fig_dir;
    else
        figDir = fullfile(pwd, 'results', 'figures');
    end
    
    filename = sprintf('partA_03_forecast_plot_%s.png', plot_name);
    outPath  = fullfile(figDir, filename);

    %% 2. Visualization
    fig = figure('Name', ['Forecast Comparison: ', plot_name], 'Visible', 'off');
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
    interval_labels = cellstr(compose('%d%% Predictive Interval', round((1 - plot_alphas(1:num_intervals)) * 100)));
    hMed = gobjects(0);

    [target_days, median_forecast, lower_forecast, upper_forecast] = ...
        local_extract_fixed_lead(results, lead_time, plot_alphas);

    for j = 1:num_intervals
        valid_interval = isfinite(target_days) & ...
            isfinite(lower_forecast(:, j)) & isfinite(upper_forecast(:, j));

        if nnz(valid_interval) >= 2
            interval_handles(j) = fill_interval(ax, target_days(valid_interval), ...
                lower_forecast(valid_interval, j), upper_forecast(valid_interval, j), ...
                interval_colors(j, :), interval_face_alpha(j), interval_labels{j});
        end
    end

    hTruth = plot(ax, tspan, Rt_true, 'k-', 'LineWidth', 2.2, ...
        'DisplayName', 'Ground Truth');

    valid_median = isfinite(target_days) & isfinite(median_forecast);
    if any(valid_median)
        hMed = plot(ax, target_days(valid_median), median_forecast(valid_median), ...
            'b--o', 'LineWidth', 1.3, 'MarkerSize', 3.2, ...
            'DisplayName', sprintf('%d-Day-Ahead Median Forecast', lead_time));
    end

    title(ax, sprintf('%d-Day-Ahead Forecast vs Truth: %s', lead_time, strrep(plot_name, '_', ' ')));
    xlabel(ax, 'Time (days)');
    ylabel(ax, '$\mathcal{R}_t$', 'Interpreter', 'latex');
    grid(ax, 'on');

    if isfield(cfg, 'Rt') && isfield(cfg.Rt, 'bounds')
        ylim(ax, cfg.Rt.bounds);
    end

    xlim(ax, [tspan(1), tspan(end)]);

    legend_handles = gobjects(0);
    legend_labels = {};

    legend_handles(end+1) = hTruth;
    legend_labels{end+1} = 'Ground Truth';

    if ~isempty(hMed)
        legend_handles(end+1) = hMed;
        legend_labels{end+1} = sprintf('%d-Day-Ahead Median Forecast', lead_time);
    end

    for j = 1:num_intervals
        if isgraphics(interval_handles(j))
            legend_handles(end+1) = interval_handles(j);
            legend_labels{end+1} = interval_labels{j};
        end
    end

    legend(ax, legend_handles, legend_labels, 'Location', 'northwest');
    
    %% 3. Persistence
    exportgraphics(fig, outPath, 'Resolution', 300);
end

function lead_time = local_plot_lead_time(cfg)
    lead_time = 7;
    if isfield(cfg, 'forecast') && isfield(cfg.forecast, 'plot_lead_time')
        lead_time = double(cfg.forecast.plot_lead_time);
    end

    if ~isscalar(lead_time) || ~isfinite(lead_time) || lead_time < 1
        error('PLOT:InvalidLeadTime', 'Forecast plot lead time must be a positive scalar.');
    end

    lead_time = round(lead_time);
end

function [target_days, median_forecast, lower_forecast, upper_forecast] = ...
    local_extract_fixed_lead(results, lead_time, plot_alphas)
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
                lower_forecast(i, j) = results(i).forecast_lower(lead_time, idx_alpha);
                upper_forecast(i, j) = results(i).forecast_upper(lead_time, idx_alpha);
            end
        end
    end
end

function idx = local_alpha_index(stored_alphas, target_alpha)
    [min_diff, idx] = min(abs(stored_alphas - target_alpha));
    if isempty(idx) || min_diff > 1e-8
        idx = [];
    end
end

function h = fill_interval(ax, t_fcst, lower_bound, upper_bound, face_color, face_alpha, display_name)
    lower_bound = lower_bound(:);
    upper_bound = upper_bound(:);
    t_fcst = t_fcst(:);

    if isempty(display_name)
        h = fill(ax, [t_fcst; flipud(t_fcst)], [upper_bound; flipud(lower_bound)], ...
            face_color, 'FaceAlpha', face_alpha, 'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
    else
        h = fill(ax, [t_fcst; flipud(t_fcst)], [upper_bound; flipud(lower_bound)], ...
            face_color, 'FaceAlpha', face_alpha, 'EdgeColor', 'none', ...
            'DisplayName', display_name);
    end
end
