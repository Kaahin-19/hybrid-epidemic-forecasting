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

% A. M. Kaahin 2026-02-19

    % Initialize figure with standard dimensions
    fig = figure('Name', 'Forecast Performance Comparison', ...
                 'Position', [100, 100, 1200, 700]);
    tlo = tiledlayout(1, 1, 'Padding', 'compact');

    ax = nexttile(tlo);
    hold(ax, 'on');

    % Disable interactive toolbar to prevent artifacts during exportgraphics
    axtoolbar(ax, {'export'});

    % Create composite grouping variable for X-axis labels
    % Format: "Model (ExoMode)"
    config_id = string(score_registry.Model) + " (" + string(score_registry.ExoMode) + ")";
    
    % Filter out Inf/NaN values to ensure plot stability
    valid_idx = isfinite(score_registry.RMSE);
    
    if ~any(valid_idx)
        warning('PLOT:NoData', 'All RMSE values are Inf or NaN. Skipping visualization.');
        close(fig);
        return;
    end
    
    plot_data = score_registry(valid_idx, :);
    plot_config = config_id(valid_idx);

    % Boxplot grouped by Scenario (Color) and Configuration (X-axis)
    boxchart(ax, categorical(plot_config), plot_data.RMSE, ...
        'GroupByColor', plot_data.Scenario);

    ylabel(ax, 'RMSE (R_t)');
    title(ax, 'Model Accuracy Distribution by Configuration');
    legend(ax, 'Location', 'bestoutside');
    grid(ax, 'on');

    % Apply logarithmic scale if error magnitudes vary significantly
    % (e.g., spanning from 10^-2 to 10^50)
    if max(plot_data.RMSE) > 100
        set(ax, 'YScale', 'log');
        ylabel(ax, 'RMSE (R_t) [Log Scale]');
    end

    % Save Artifact
    out_path = fullfile(cfg.output.fig_dir, 'partA_03_performance_boxplot.png');
    exportgraphics(fig, out_path, 'Resolution', 300);
end