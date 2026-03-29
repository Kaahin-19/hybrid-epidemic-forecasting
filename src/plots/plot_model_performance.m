function was_saved = plot_model_performance(score_registry, cfg)
%PLOT_MODEL_PERFORMANCE Visualize comparative WIS distributions.
%
%   Syntax:
%       was_saved = plot_model_performance(score_registry, cfg)
%
%   Description:
%       Generates a comparative boxplot of Weighted Interval Score (WIS)
%       across different model configurations and scenarios. Automatically
%       filters non-finite values and applies logarithmic scaling if scores
%       span multiple orders of magnitude.
%
%   Inputs:
%       score_registry - Table containing merged evaluation scores.
%       cfg            - Configuration struct containing output paths.
%
%   Outputs:
%       was_saved      - Logical flag indicating whether the figure was
%                        written to disk.
%
%   See also PARTA_04_EVALUATE_MODELS, PARTA_CONFIG.

% A. M. Kaahin 2026-02-19
% Modified: 2026-03-29

    %% 1. Initialization
    was_saved = false;

    if isfield(cfg, 'output') && isfield(cfg.output, 'fig_dir')
        figDir = cfg.output.fig_dir;
    else
        figDir = fullfile(pwd, 'results', 'figures');
    end
    out_path = fullfile(figDir, 'partA_04_wis_performance_boxplot.png');

    %% 2. Visualization
    fig = figure('Name', 'WIS Performance Comparison', 'Visible', 'off');
    fig.Units = 'centimeters';
    fig.Position(3) = 17.0;
    fig.Position(4) = 8.5;

    tlo = tiledlayout(1, 1, 'Padding', 'compact');

    ax = nexttile(tlo);
    hold(ax, 'on');

    axtoolbar(ax, {'export'});

    config_id = string(score_registry.Model) + " (" + string(score_registry.ExoMode) + ")";
    
    valid_idx = isfinite(score_registry.WindowWIS);
    
    if ~any(valid_idx)
        warning('PLOT:NoData', 'All WIS values are Inf or NaN. Skipping visualization.');
        close(fig);
        return;
    end
    
    plot_data = score_registry(valid_idx, :);
    plot_config = config_id(valid_idx);

    boxchart(ax, categorical(plot_config), plot_data.WindowWIS, ...
        'GroupByColor', plot_data.Scenario);

    ylabel(ax, 'WIS (R_t)');
    title(ax, 'Model WIS Distribution by Configuration');
    legend(ax, 'Location', 'bestoutside');
    grid(ax, 'on');

    if max(plot_data.WindowWIS) > 100
        set(ax, 'YScale', 'log');
        ylabel(ax, 'WIS (R_t) [Log Scale]');
    end

    %% 3. Persistence
    exportgraphics(fig, out_path, 'Resolution', 300);
    was_saved = true;
end
