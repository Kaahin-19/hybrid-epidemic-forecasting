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
    figDirAbs = cfg.output.fig_dir;
    outPath   = fullfile(figDirAbs, cfg.output.fig_name);

    %% 2. Visualization
    fig = figure("Name", "Synthetic Rt Scenarios (Part A)");

    n     = numel(scenarios);
    nRows = 2;
    nCols = ceil(n / nRows);

    tiledlayout(nRows, nCols, "Padding", "compact", "TileSpacing", "compact");

    for i = 1:n
        ax = nexttile_clean();

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
    exportgraphics(fig, outPath, "Resolution", 200);
    fprintf("Saved: %s\n", outPath);
end
