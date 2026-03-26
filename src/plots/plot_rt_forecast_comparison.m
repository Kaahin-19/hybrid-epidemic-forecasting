function plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg)
%PLOT_RT_FORECAST_COMPARISON Visualize forecast performance against ground truth.
%
%   Syntax:
%       plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg)
%
%   Description:
%       Generates a summary figure comparing the expanding-window forecasts
%       against the synthetic ground truth and displaying final-window
%       predictive intervals.
%
%   Inputs:
%       results   - Struct array of forecast results per window.
%       Rt_true   - Numeric vector of the ground truth Rt curve.
%       tspan     - Numeric vector of time points.
%       plot_name - String identifier for the plot title (scenario name).
%       cfg       - Configuration struct containing output directories.
%
%   See also PARTA_02_RUN_FORECASTS, PARTA_CONFIG.

% A. M. Kaahin 2026-02-19
% Modified: 2026-03-26

    %% 1. Initialization
    if isfield(cfg, 'output') && isfield(cfg.output, 'fig_dir')
        figDir = cfg.output.fig_dir;
    else
        figDir = fullfile(pwd, 'results', 'figures');
    end
    
    filename = sprintf('partA_02_forecast_plot_%s.png', plot_name);
    outPath  = fullfile(figDir, filename);

    %% 2. Visualization
    fig = figure('Name', ['Forecast Comparison: ', plot_name], 'Visible', 'off');
    fig.Units = 'centimeters';
    fig.Position(3) = 17.0;
    fig.Position(4) = 9.5;
    
    tiledlayout(2, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
    
    % --- Panel 1: Trajectories ---
    ax1 = nexttile();
    hold(ax1, 'on');
    
    axtoolbar(ax1, {'export'});
    
    plot(ax1, tspan, Rt_true, 'k-', 'LineWidth', 2.2, 'DisplayName', 'Ground Truth');
    
    first_plot = true;
    for i = 1:numel(results)
        t_f = results(i).time_horizon;
        y_f = results(i).forecast_median;
        
        if first_plot
            plot(ax1, t_f, y_f, 'b--', 'LineWidth', 1.4, 'DisplayName', 'Median Forecasts');
            first_plot = false;
        else
            plot(ax1, t_f, y_f, 'b--', 'LineWidth', 1, 'HandleVisibility', 'off');
        end
    end
    
    title(ax1, sprintf('Forecast vs Truth: %s', strrep(plot_name, '_', ' ')));
    ylabel(ax1, 'R_t Value');
    grid(ax1, 'on');
    legend(ax1, 'show', 'Location', 'northwest');

    if isfield(cfg, 'Rt') && isfield(cfg.Rt, 'bounds')
        ylim(ax1, cfg.Rt.bounds);
    end
    
    xlim(ax1, [tspan(1), tspan(end)]);
    
    % --- Panel 2: Final-Window Predictive Intervals ---
    ax2 = nexttile();
    hold(ax2, 'on');
    axtoolbar(ax2, {'export'});

    final_result = results(end);
    context_days = cfg.forecast.plot_context;
    idx_start = max(1, final_result.window_day_idx - context_days + 1);
    idx_stop  = final_result.window_day_idx + numel(final_result.time_horizon);

    t_local = tspan(idx_start:idx_stop);
    Rt_local = Rt_true(idx_start:idx_stop);
    t_fcst = final_result.time_horizon(:);
    Rt_med = final_result.forecast_median(:);

    if isfield(final_result, 'forecast_interval_alphas')
        plot_alphas = cfg.forecast.plot_alphas(:)';
        stored_alphas = double(final_result.forecast_interval_alphas(:)');

        idx90 = local_alpha_index(stored_alphas, plot_alphas(1));
        idx50 = local_alpha_index(stored_alphas, plot_alphas(2));

        if ~isempty(idx90)
            fill_interval(ax2, t_fcst, final_result.forecast_lower(:, idx90), ...
                final_result.forecast_upper(:, idx90), [0.30, 0.65, 0.95], ...
                0.18, '90% Predictive Interval');
        end

        if ~isempty(idx50)
            fill_interval(ax2, t_fcst, final_result.forecast_lower(:, idx50), ...
                final_result.forecast_upper(:, idx50), [0.10, 0.45, 0.85], ...
                0.30, '50% Predictive Interval');
        end
    end

    plot(ax2, t_local, Rt_local, 'k-', 'LineWidth', 2.0, 'DisplayName', 'Ground Truth');
    xline(ax2, tspan(final_result.window_day_idx), 'k:', 'LineWidth', 1.0, ...
        'HandleVisibility', 'off');
    plot(ax2, t_fcst, Rt_med, 'b-', 'LineWidth', 1.6, 'DisplayName', 'Forecast Median');

    title(ax2, 'Final-Window Predictive Intervals');
    xlabel(ax2, 'Time (days)');
    ylabel(ax2, 'R_t Value');
    grid(ax2, 'on');
    xlim(ax2, [t_local(1), t_local(end)]);

    if isfield(cfg, 'Rt') && isfield(cfg.Rt, 'bounds')
        ylim(ax2, cfg.Rt.bounds);
    end

    legend(ax2, 'show', 'Location', 'northwest');
    
    %% 3. Persistence
    exportgraphics(fig, outPath, 'Resolution', 300);
end

function idx = local_alpha_index(stored_alphas, target_alpha)
    [min_diff, idx] = min(abs(stored_alphas - target_alpha));
    if isempty(idx) || min_diff > 1e-8
        idx = [];
    end
end

function fill_interval(ax, t_fcst, lower_bound, upper_bound, face_color, face_alpha, display_name)
    lower_bound = lower_bound(:);
    upper_bound = upper_bound(:);
    t_fcst = t_fcst(:);

    fill(ax, [t_fcst; flipud(t_fcst)], [upper_bound; flipud(lower_bound)], ...
        face_color, 'FaceAlpha', face_alpha, 'EdgeColor', 'none', ...
        'DisplayName', display_name);
end
