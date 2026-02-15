function plot_rt_forecast_comparison(results, Rt_true, tspan, name, cfg)
%PLOT_RT_FORECAST_COMPARISON Reusable 2-panel plotter for Rt truth vs forecasts.
%
%   Produces thesis-quality, 300 DPI multi-panel figures.

    %% 1. Setup & Dimensions
    % Force a specific figure size (800x600) for consistent aspect ratios in print
    fig = figure('Visible', 'off', 'Name', ['Rt Comparison: ' name], ...
                 'Position', [100, 100, 800, 600]);
    
    if isfield(cfg, 'output') && isfield(cfg.output, 'fig_dir')
        outDir = cfg.output.fig_dir;
    else
        outDir = fullfile('results', 'figures');
    end

    % Tiledlayout with minimal whitespace
    tlo = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    % Shared Y-limits + dynamic buffer
    y_max = max(max(Rt_true)*1.2, 3);
    
    % Professional Color Palette (RGB)
    color_truth_top = [0.15 0.15 0.15];        % Near black for high contrast
    color_truth_bot = [0 0.4470 0.7410];       % Dark blue for the clean reference
    color_forecast  = [0.8500 0.3250 0.0980];  % Orange-Red
    color_ref_line  = [0.5 0.5 0.5];           % Subdued gray

    %% 2. TOP PANEL: Spaghetti Forecasts + Ground Truth
    ax1 = nexttile_clean(tlo);
    hold(ax1, "on");
    
    % Clean title using LaTeX interpreter
    clean_name = strrep(name, '_', '\_'); % Escape underscores for LaTeX
    title(ax1, sprintf('Forecast vs. Ground Truth: %s', clean_name), ...
          'Interpreter', 'latex', 'FontSize', 12);

    % Plot Ground Truth (Thickened for hierarchy)
    plot(ax1, tspan, Rt_true, 'Color', color_truth_top, 'LineWidth', 2.0, 'DisplayName', 'True $R_t$');
    
    % Subdued threshold line
    yline(ax1, 1, '--', 'Color', color_ref_line, 'LineWidth', 1.2, 'HandleVisibility', 'off');

    % Plot Forecast Spaghetti with transparency (Alpha = 0.4)
    for k = 1:2:length(results)
        t_combined = [results(k).window_day, results(k).time_horizon(:)'];
        
        idx_T = results(k).window_day_idx;
        Rt_combined = [Rt_true(idx_T), results(k).forecast_Rt(:)'];
        
        % Using 4-element RGBA array for transparency
        plot(ax1, t_combined, Rt_combined, 'Color', [color_forecast, 0.4], ...
            'LineWidth', 1.0, 'HandleVisibility', 'off');
    end

    ylabel(ax1, 'Predicted $R_t$', 'Interpreter', 'latex', 'FontSize', 11);
    grid(ax1, 'on');
    ylim(ax1, [0, y_max]);
    
    % Legend formatting
    leg = legend(ax1, 'show', 'Location', 'northeast', 'Interpreter', 'latex');
    leg.ItemTokenSize = [20, 18]; % Keeps the legend box compact

    % Remove X-axis labels to prevent clutter on shared axes
    xticklabels(ax1, {});

    %% 3. BOTTOM PANEL: Ground Truth Only (Clean Reference)
    ax2 = nexttile_clean(tlo);
    hold(ax2, "on");
    
    % Explicit distinct color for the bottom panel
    plot(ax2, tspan, Rt_true, 'Color', color_truth_bot, 'LineWidth', 2.0);
    
    % Subdued threshold line matching the top panel
    yline(ax2, 1, '--', 'Color', color_ref_line, 'LineWidth', 1.2, 'HandleVisibility', 'off');

    ylabel(ax2, 'Reference $R_t$', 'Interpreter', 'latex', 'FontSize', 11);
    xlabel(ax2, 'Days', 'Interpreter', 'latex', 'FontSize', 11);
    grid(ax2, 'on');
    ylim(ax2, [0, y_max]);

    %% 4. Link Axes & Save
    linkaxes([ax1, ax2], 'x');
    xlim(ax1, [min(tspan) max(tspan)]);
    
    % Apply LaTeX font globally to axis tick labels
    set([ax1, ax2], 'TickLabelInterpreter', 'latex');

    % Export at 300 DPI for thesis print quality
    saveName = fullfile(outDir, sprintf('comparison_Rt_%s.png', name));
    exportgraphics(fig, saveName, 'Resolution', 300);
    
    close(fig);
end