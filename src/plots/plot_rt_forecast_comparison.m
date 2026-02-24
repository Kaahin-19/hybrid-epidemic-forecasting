function plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg)
%PLOT_RT_FORECAST_COMPARISON Visualize forecast performance against ground truth.
%
%   Syntax:
%       plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg)
%
%   Description:
%       Generates a summary figure comparing the expanding window forecasts 
%       against the synthetic ground truth.
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
    fig.Position(4) = 8.5;
    
    tiledlayout(2, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
    
    % --- Panel 1: Trajectories ---
    ax1 = nexttile();
    hold(ax1, 'on');
    
    axtoolbar(ax1, {'export'});
    
    plot(ax1, tspan, Rt_true, 'k-', 'LineWidth', 2.2, 'DisplayName', 'Ground Truth');
    
    first_plot = true;
    for i = 1:numel(results)
        t_f = results(i).time_horizon;
        y_f = results(i).forecast_Rt;
        
        if first_plot
            plot(ax1, t_f, y_f, 'b--', 'LineWidth', 1.4, 'DisplayName', 'Forecasts');
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
    
    % --- Panel 2: AICc Landscape ---
    ax2 = nexttile();
    hold(ax2, 'on');
    axtoolbar(ax2, {'export'});
    
    win_days = [results.window_day];
    scores   = arrayfun(@(x) x.aic_landscape(1, end), results);
    
    plot(ax2, win_days, scores, 'ro-', 'LineWidth', 1.5, 'MarkerFaceColor', 'r');
    
    title(ax2, 'Model Selection Stability (AICc)');
    xlabel(ax2, 'Time (days)');
    ylabel(ax2, 'Best AICc Score');
    grid(ax2, 'on');
    xlim(ax2, [tspan(1), tspan(end)]);
    
    %% 3. Persistence
    exportgraphics(fig, outPath, 'Resolution', 300);
end