function plot_rt_scenarios(scenarios, cfg)
%PLOT_RT_SCENARIOS Visualize the synthetic Rt profiles for Part A.
%
%   Syntax:
%       plot_rt_scenarios(scenarios, cfg)
%
%   Description:
%       Generates a tiled summary figure of the synthetic Reproduction Number
%       (Rt) curves defined in the configuration. This serves as a visual
%       verification artifact for the experiment setup, ensuring the signals
%       look as expected before simulation begins.
%
%   Inputs:
%       scenarios - Struct array containing .t, .Rt, .id, and .name.
%       cfg       - Configuration struct containing .output.fig_dir and
%                   .Rt.bounds.
%
%   See also PARTA_00_MAKE_SCENARIOS, PARTA_CONFIG.

    %% 1. Initialization
    % Extract absolute paths from the configuration.
    % Note: cfg.output.fig_dir is already an absolute path (resolved in config).
    figDirAbs = cfg.output.fig_dir; 
    outPath   = fullfile(figDirAbs, cfg.output.fig_name);
    
    % Ensure the output directory exists using the project utility
    ensure_dirs(figDirAbs);

    %% 2. Visualization
    % Create a tiled layout to display all scenarios in a single view
    fig = figure("Name", "Synthetic Rt Scenarios (Part A)");
    
    n     = numel(scenarios);
    nRows = 2;
    nCols = ceil(n / nRows);
    
    tiledlayout(nRows, nCols, "Padding", "compact", "TileSpacing", "compact");
    
    for i = 1:n
        nexttile;
        plot(scenarios(i).t, scenarios(i).Rt, "LineWidth", 2);
        
        % Formatting
        title(sprintf("%s: %s", scenarios(i).id, scenarios(i).name));
        xlabel("Time (days)");
        ylabel("R_t");
        grid on;
        
        % Enforce consistent y-axis limits if bounds are defined in config
        if isfield(cfg, "Rt") && isfield(cfg.Rt, "bounds")
            ylim(cfg.Rt.bounds);
        end
    end

    %% 3. Persistence
    % Save the figure to disk at high resolution
    exportgraphics(fig, outPath, "Resolution", 200);
    fprintf("Saved: %s\n", outPath);
    
end