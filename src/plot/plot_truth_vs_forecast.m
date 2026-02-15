function plot_truth_vs_forecast(results, umod_true, tspan, name, cfg)
%PLOT_TRUTH_VS_FORECAST Visualize hybrid forecasts against ground truth.
%
%   Description:
%       Generates a summary figure comparing the "Hybrid" forecasts against
%       the known synthetic ground truth using a modern tiledlayout-based
%       figure (consistent with other plotting utilities).
%
%   Panels:
%       1) Rt Forecasts
%       2) Infection Forecasts
%
%   See also PARTA_02_RUN_FORECASTS, EXPORTGRAPHICS.

    %% 1. Initialization
    fig = figure('Visible', 'off', 'Name', name);

    % Resolve output directory
    if isfield(cfg, 'output') && isfield(cfg.output, 'fig_dir')
        outDir = cfg.output.fig_dir;
    else
        outDir = fullfile('results', 'figures');
    end

    %% 2. Layout (modern, consistent)
    tlo = tiledlayout(fig, 2, 1, ...
        "Padding", "compact", ...
        "TileSpacing", "compact");

    %% 3. Panel 1: Rt Forecasts
    ax1 = nexttile_clean(tlo);
    hold(ax1, "on");

    title(ax1, sprintf('Forecasts: %s', name), 'Interpreter', 'none');

    % Reference line (Rt = 1)
    yline(ax1, 1, ':k', 'HandleVisibility', 'off');

    % Forecast spaghetti (stride = 2 for clarity)
    for k = 1:2:length(results)
        plot(ax1, results(k).time_horizon, results(k).forecast_Rt, ...
            'r-', 'LineWidth', 0.5);
    end

    ylabel(ax1, 'Predicted R_t');
    grid(ax1, 'on');
    xlim(ax1, [min(tspan) max(tspan)]);

    %% 4. Panel 2: Case Forecasts
    ax2 = nexttile_clean(tlo);
    hold(ax2, "on");

    % Ground truth (infected state)
    plot(ax2, tspan, umod_true.U(2,:), ...
        'k', 'LineWidth', 1.5, 'DisplayName', 'Truth');

    % Forecast spaghetti
    for k = 1:2:length(results)
        % X-coordinates: Start day + 14 future days (15 points)
        t_combined = [results(k).window_day, results(k).time_horizon];
        
        % Y-coordinates: Get starting point from ground truth, then append forecast
        idx_T   = results(k).window_day_idx;
        I_start = umod_true.U(2, idx_T);
        I_combined = [I_start, results(k).forecast_I]; % Now also 15 points

        plot(ax2, t_combined, I_combined, ...
            'b--', 'LineWidth', 1, 'HandleVisibility', 'off');
    end
    
    ylabel(ax2, 'Infected Cases');
    xlabel(ax2, 'Days');
    grid(ax2, 'on');
    xlim(ax2, [min(tspan) max(tspan)]);
    legend(ax2, 'show', 'Location', 'northeast');

    %% 5. Persistence
    savePath = fullfile(outDir, sprintf('hybrid_%s.png', name));
    exportgraphics(fig, savePath, 'Resolution', 150);
    fprintf('Saved plot: %s\n', savePath);

    close(fig);
end

