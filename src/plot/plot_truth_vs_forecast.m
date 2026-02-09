function plot_truth_vs_forecast(results, umod_true, tspan, name, cfg)
%PLOT_TRUTH_VS_FORECAST Visualize hybrid forecasts against ground truth.
%
%   Syntax:
%       plot_truth_vs_forecast(results, umod_true, tspan, name, cfg)
%
%   Description:
%       Generates a summary figure comparing the "Hybrid" forecasts against
%       the known synthetic ground truth. It creates two subplots:
%       1. Rt Forecasts: Shows the AR-predicted trajectories.
%       2. Infection Forecasts: Shows the resulting ODE-simulated case counts
%          superimposed on the true epidemic curve.
%
%   Inputs:
%       results   - Struct array of forecast results (from PartA_02).
%       umod_true - Ground truth simulation object (for full state history).
%       tspan     - Full time vector of the simulation.
%       name      - String identifier for the scenario (Title/Filename).
%       cfg       - Configuration struct (used for output paths).
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
    ensure_dirs(outDir);

    %% 2. Subplot 1: Rt Forecasts
    subplot(2,1,1); hold on;
    title(sprintf('Forecasts: %s', name), 'Interpreter', 'none');
    
    % Reference Line (Rt = 1)
    yline(1, ':k', 'HandleVisibility', 'off'); 
    
    % Plot Forecast Spaghettis (Strid = 2 for clarity)
    for k = 1:2:length(results)
        plot(results(k).time_horizon, results(k).forecast_Rt, 'r-', 'LineWidth', 0.5);
    end
    
    ylabel('Predicted R_t'); 
    grid on;
    xlim([min(tspan) max(tspan)]);
    
    %% 3. Subplot 2: Case Forecasts
    subplot(2,1,2); hold on;
    
    % Plot Ground Truth (Row 2 = Infected)
    plot(tspan, umod_true.U(2,:), 'k', 'LineWidth', 1.5, 'DisplayName', 'Truth');
    
    % Plot Forecast Spaghettis
    for k = 1:2:length(results)
        % Align time vector: Prepend current day (t=0) to future horizon
        t_combined = [results(k).window_day, results(k).time_horizon];
        I_combined = results(k).forecast_I;
        
        plot(t_combined, I_combined, 'b--', 'LineWidth', 1, 'HandleVisibility', 'off');
    end
    
    ylabel('Infected Cases'); 
    xlabel('Days'); 
    grid on;
    xlim([min(tspan) max(tspan)]);
    legend('show', 'Location', 'northeast');
    
    %% 4. Persistence
    savePath = fullfile(outDir, sprintf('hybrid_%s.png', name));
    
    exportgraphics(fig, savePath, 'Resolution', 150);
    fprintf('Saved plot: %s\n', savePath);
    
    close(fig);
end