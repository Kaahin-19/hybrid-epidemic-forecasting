function plot_rt_scenarios(scenarios, cfg)
%PLOT_RT_SCENARIOS Visualize the synthetic Rt profiles for Part A.
%
%   Syntax:
%       plot_rt_scenarios(scenarios, cfg)
%
%   Description:
%       Generates a tiled summary figure of the synthetic Reproduction Number
%       (Rt) curves.
%
%   Inputs:
%       scenarios - Struct array containing .t, .Rt, .id, and .name.
%       cfg       - Configuration struct containing output paths and bounds.
%
%   See also PARTA_00_MAKE_SCENARIOS, PARTA_CONFIG.

% A. M. Kaahin 2026-02-18

    %% 1. Initialization
    outPath   = fullfile(cfg.output.fig_dir, "partA_00_rt_scenarios.png");

    %% 2. Visualization
    fig = figure("Name", "Synthetic Rt Scenarios (Part A)", "Visible", "off");

    n     = numel(scenarios);
    nRows = 2;
    nCols = ceil(n / nRows);

    tiledlayout(nRows, nCols, "Padding", "compact", "TileSpacing", "compact");

    for i = 1:n
        ax = nexttile();

        plot(ax, scenarios(i).t, scenarios(i).Rt, "LineWidth", 2);

        title(ax, sprintf("%s: %s", scenarios(i).id, scenarios(i).name));
        xlabel(ax, "Time (days)");
        ylabel(ax, "R_t");
        grid(ax, "on");

        if isfield(cfg, "Rt") && isfield(cfg.Rt, "bounds")
            ylim(ax, cfg.Rt.bounds);
        end
    end

    %% 3. Persistence
    exportgraphics(fig, outPath, "Resolution", 300);
end