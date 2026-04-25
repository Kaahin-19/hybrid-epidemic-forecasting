function outPath = plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg)
%PLOT_RT_FORECAST_COMPARISON Visualize forecast performance against ground truth.
%
%   Syntax:
%       outPath = plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg)
%
%   Description:
%       Generates a summary figure comparing the expanding-window forecasts
%       against the synthetic ground truth and overlaying predictive
%       intervals across all forecast windows in a single visualization.
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
% Modified: 2026-03-29

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
    num_intervals = min(numel(plot_alphas), 2);
    interval_colors = [0.30, 0.65, 0.95; 0.10, 0.45, 0.85];
    interval_face_alpha = [0.08, 0.16];
    interval_handles = gobjects(1, num_intervals);
    interval_labels = cellstr(compose('%d%% Predictive Interval', round((1 - plot_alphas(1:num_intervals)) * 100)));
    hMed = gobjects(0);

    if ~isempty(results) && isfield(results, 'forecast_interval_alphas')
        for i = 1:numel(results)
            stored_alphas = double(results(i).forecast_interval_alphas(:)');
            t_f = results(i).time_horizon(:);

            for j = 1:num_intervals
                idx_alpha = local_alpha_index(stored_alphas, plot_alphas(j));
                if ~isempty(idx_alpha)
                    display_name = '';
                    if ~isgraphics(interval_handles(j))
                        display_name = interval_labels{j};
                    end
                    h = fill_interval(ax, t_f, results(i).forecast_lower(:, idx_alpha), ...
                        results(i).forecast_upper(:, idx_alpha), interval_colors(j, :), ...
                        interval_face_alpha(j), display_name);
                    if ~isgraphics(interval_handles(j))
                        interval_handles(j) = h;
                    end
                end
            end
        end
    end

    for i = 1:numel(results)
        t_f = results(i).time_horizon(:);
        y_f = results(i).forecast_median(:);

        if isempty(hMed)
            hMed = plot(ax, t_f, y_f, 'b--', 'LineWidth', 1.3, ...
                'DisplayName', 'Median Forecasts');
        else
            plot(ax, t_f, y_f, 'b--', 'LineWidth', 1.0, 'HandleVisibility', 'off');
        end
    end

    hTruth = plot(ax, tspan, Rt_true, 'k-', 'LineWidth', 2.2, ...
        'DisplayName', 'Ground Truth');

    title(ax, sprintf('Forecast vs Truth: %s', strrep(plot_name, '_', ' ')));
    xlabel(ax, 'Time (days)');
    ylabel(ax, '$\mathcal{R}_t$ Value', 'Interpreter', 'latex');
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
        legend_labels{end+1} = 'Median Forecasts';
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
