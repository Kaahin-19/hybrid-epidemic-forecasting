function plot_model_performance(score_registry, cfg)
%PLOT_MODEL_PERFORMANCE Visualize comparative RMSE distributions.
%
%   Syntax:
%       plot_model_performance(score_registry, cfg)
%
%   Description:
%       Generates a comparative boxplot of Root Mean Square Error (RMSE)
%       across different model configurations and scenarios. Automatically
%       filters non-finite values and applies logarithmic scaling if errors
%       span multiple orders of magnitude.
%
%   Inputs:
%       score_registry - Table containing merged evaluation scores.
%       cfg            - Configuration struct containing output paths.
%
%   See also PARTA_03_EVALUATE_MODELS, PARTA_CONFIG.

% A. M. Kaahin 2026-02-19

    %% 1. Initialization
    if isfield(cfg, 'output') && isfield(cfg.output, 'fig_dir')
        figDir = cfg.output.fig_dir;
    else
        figDir = fullfile(pwd, 'results', 'figures');
    end
    out_path = fullfile(figDir, 'partA_03_performance_boxplot.png');

    %% 2. Visualization
    fig = figure('Name', 'Forecast Performance Comparison', ...
                 'Position', [100, 100, 1200, 700], 'Visible', 'off');
    tlo = tiledlayout(1, 1, 'Padding', 'compact');

    ax = nexttile(tlo);
    hold(ax, 'on');

    axtoolbar(ax, {'export'});

    config_id = string(score_registry.Model) + " (" + string(score_registry.ExoMode) + ")";
    
    valid_idx = isfinite(score_registry.RMSE);
    
    if ~any(valid_idx)
        warning('PLOT:NoData', 'All RMSE values are Inf or NaN. Skipping visualization.');
        close(fig);
        return;
    end
    
    plot_data = score_registry(valid_idx, :);
    plot_config = config_id(valid_idx);

    boxchart(ax, categorical(plot_config), plot_data.RMSE, ...
        'GroupByColor', plot_data.Scenario);

    ylabel(ax, 'RMSE (R_t)');
    title(ax, 'Model Accuracy Distribution by Configuration');
    legend(ax, 'Location', 'bestoutside');
    grid(ax, 'on');

    if max(plot_data.RMSE) > 100
        set(ax, 'YScale', 'log');
        ylabel(ax, 'RMSE (R_t) [Log Scale]');
    end

    %% 3. Persistence
    exportgraphics(fig, out_path, 'Resolution', 300);
end