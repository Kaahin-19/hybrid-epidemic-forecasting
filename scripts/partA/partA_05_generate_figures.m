%PARTA_05_GENERATE_FIGURES Generate synthetic-validation thesis figures.
%
%   Description:
%       Exports figures summarizing synthetic Rt trajectories, fixed-lead
%       forecast behaviour, window-level forecast accuracy, horizon-wise
%       forecast degradation, empirical interval coverage, and infected-state
%       projection error relative to Rt persistence.
%
%   Workflow:
%       1. Initialize figure paths, source artifacts, and shared styling.
%       2. Generate the Rt scenario trajectory panels.
%       3. Generate the fixed-lead forecast comparison figures.
%       4. Generate the Rt evaluation and infected-state projection figures.
%
%   See also PARTA_CONFIG, PARTA_04_EVALUATE_FORECASTS, PLOT_SERIES,
%            PLOT_DISTRIBUTION.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-08-23

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Figure Generation ===\n');

cfg = partA_config();

data_dir       = cfg.output.data_dir;
forecast_dir   = cfg.output.forecast_dir;
evaluation_dir = cfg.output.score_dir;
figure_dir     = cfg.output.fig_dir;

if ~exist(figure_dir, 'dir'), mkdir(figure_dir); end

style       = local_style();
rt_bounds   = cfg.Rt.bounds;
truth_files = local_sort_dir_by_name(dir(fullfile(data_dir, 'partA_01_truth_*.mat')));
forecast_files = local_sort_dir_by_name(dir(fullfile(forecast_dir, 'partA_03_forecast_*.mat')));

%% 2. Rt Scenario Trajectories
if isempty(truth_files)
    fprintf('Skipping Rt scenario figure - no truth artifacts in %s.\n', data_dir);
else
    fprintf('Drawing Rt scenario trajectories from %d truth artifact(s)...\n', numel(truth_files));

    scenarios = repmat(struct('tspan', [], 'Rt_true', []), numel(truth_files), 1);

    for i = 1:numel(truth_files)
        loaded = load(fullfile(truth_files(i).folder, truth_files(i).name));
        scenarios(i).tspan   = loaded.tspan;
        scenarios(i).Rt_true = loaded.Rt_true;
    end

    n_panels = numel(scenarios);
    n_cols   = ceil(sqrt(n_panels));
    n_rows   = ceil(n_panels / n_cols);

    fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.0, 10.5], 'Color', 'w');

    tl = tiledlayout(fig, n_rows, n_cols, 'Padding', 'compact', 'TileSpacing', 'compact');

    for i = 1:n_panels
        ax = nexttile(tl);

        panel = local_series_template();
        panel.type       = "line";
        panel.x          = scenarios(i).tspan;
        panel.y          = scenarios(i).Rt_true;
        panel.color      = style.palette(4, :);
        panel.line_width = style.truth_line_width;

        spec = struct('series', panel, 'style', struct('y_limits', rt_bounds, 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));

        plot_series(ax, spec);
        local_panel_label(ax, sprintf("(%c)", 'a' + i - 1), style);
    end

    xlabel(tl, "Time, {\it t} (days)", 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);

    ylabel(tl, "Effective reproduction number, {\it R}_t", 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);

    exportgraphics(fig, fullfile(figure_dir, 'partA_05_rt_scenarios.pdf'), 'ContentType', 'vector');
    close(fig);
end

%% 3. Fixed-Lead Forecast Comparisons
if isempty(forecast_files)
    fprintf('Skipping forecast comparisons - no forecast artifacts in %s.\n', forecast_dir);
else
    lead        = cfg.forecast.plot_lead_time;
    plot_alphas = sort(cfg.forecast.plot_alphas);

    fprintf('Drawing %d forecast comparison figure(s) at lead %d day(s)...\n', numel(forecast_files), lead);

    for f = 1:numel(forecast_files)
        loaded = load(fullfile(forecast_files(f).folder, forecast_files(f).name));

        fc = local_fixed_lead(loaded.results, loaded.wis_alphas, loaded.tspan, loaded.Rt_true, lead, plot_alphas);

        spec = struct('series', local_forecast_series(fc, plot_alphas, style), 'style', struct('x_label', "Time, {\it t} (days)", 'y_label', "Effective reproduction number, {\it R}_t", 'y_limits', rt_bounds, 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));

        fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.0, 9.0], 'Color', 'w');

        ax = axes('Parent', fig);
        [h, labels] = plot_series(ax, spec);
        local_apply_legend(ax, h, labels, style, numel(labels));

        plot_name = sprintf('partA_05_forecast_comparison_%s_%s_%s.pdf', local_safe_token(loaded.scenario_id), local_safe_token(loaded.model_type), local_safe_token(loaded.exo_mode));

        exportgraphics(fig, fullfile(figure_dir, plot_name), 'ContentType', 'vector');
        close(fig);
    end
end

%% 4. Evaluation Figures
evaluation_artifact = fullfile(evaluation_dir, 'partA_04_evaluation_results.mat');

if exist(evaluation_artifact, 'file') ~= 2
    fprintf('Skipping evaluation figures - no evaluation artifact in %s.\n', evaluation_dir);
else
    fprintf('Drawing evaluation figures from partA_04 artifact...\n');

    evaluation       = load(evaluation_artifact);
    window_scores    = evaluation.window_scores;
    horizon_summary  = evaluation.summaries.horizon_summary;
    interval_summary = evaluation.summaries.interval_summary;
    i_projection_horizon_summary = evaluation.summaries.i_projection_horizon_summary;

    fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.0, 9.5], 'Color', 'w');

    ax = axes('Parent', fig);

    dist_spec = struct('x', window_scores.Model + " / " + window_scores.ExoMode, 'y', window_scores.WindowWIS, 'group', window_scores.Scenario, 'color_order', style.palette, 'style', struct('x_label', "Model / exogenous mode", 'y_label', "Window WIS", 'x_tick_rotation', 20, 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));

    [h, labels] = plot_distribution(ax, dist_spec);
    local_apply_legend(ax, h, labels, style, numel(labels));

    exportgraphics(fig, fullfile(figure_dir, 'partA_05_model_wis_distribution.pdf'), 'ContentType', 'vector');
    close(fig);

    horizon_series = local_grouped_line_series(horizon_summary, 'HorizonIdx', 'MeanWIS', style);

    fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.0, 9.0], 'Color', 'w');

    ax = axes('Parent', fig);

    spec = struct('series', horizon_series, 'style', struct('x_label', "Forecast horizon, {\it h} (days)", 'y_label', "Mean WIS", 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));

    [h, labels] = plot_series(ax, spec);
    local_apply_legend(ax, h, labels, style, 3);

    exportgraphics(fig, fullfile(figure_dir, 'partA_05_mean_wis_by_horizon.pdf'), 'ContentType', 'vector');
    close(fig);

    coverage_series = local_grouped_line_series(interval_summary, 'NominalCoverage', 'MeanCoverage', style);

    reference = local_series_template();
    reference.type       = "reference";
    reference.x          = [0; 1];
    reference.y          = [0; 1];
    reference.color      = [0, 0, 0];
    reference.line_style = "--";
    reference.line_width = 1.0;
    reference.label      = "Nominal = empirical";

    coverage_series = [coverage_series; reference];

    fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 16.0, 10.0], 'Color', 'w');

    ax = axes('Parent', fig);

    spec = struct('series', coverage_series, 'style', struct('x_label', "Nominal coverage", 'y_label', "Empirical coverage", 'x_limits', [0, 1], 'y_limits', [0, 1], 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));

    [h, labels] = plot_series(ax, spec);
    local_apply_legend(ax, h, labels, style, 4);

    exportgraphics(fig, fullfile(figure_dir, 'partA_05_coverage_summary.pdf'), 'ContentType', 'vector');
    close(fig);

    projection_groups = unique(i_projection_horizon_summary.Model + " / " + i_projection_horizon_summary.ExoMode, 'stable');
    n_panels = numel(projection_groups);
    n_cols   = ceil(sqrt(n_panels));
    n_rows   = ceil(n_panels / n_cols);

    projection_y_max = 1.05 * max([i_projection_horizon_summary.MeanForecastDrivenAbsoluteError; i_projection_horizon_summary.MeanPersistenceRtAbsoluteError]);

    fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.0, 11.5], 'Color', 'w');

    tl = tiledlayout(fig, n_rows, n_cols, 'Padding', 'compact', 'TileSpacing', 'compact');

    legend_handles = gobjects(0, 1);
    legend_labels  = strings(0, 1);

    for i = 1:n_panels
        ax = nexttile(tl);
        group_idx = i_projection_horizon_summary.Model + " / " + i_projection_horizon_summary.ExoMode == projection_groups(i);
        group_summary = i_projection_horizon_summary(group_idx, :);

        projection_series = local_i_projection_series(group_summary, style);
        spec = struct('series', projection_series, 'style', struct('x_limits', [1, cfg.forecast.horizon], 'y_limits', [0, projection_y_max], 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));

        [h, labels] = plot_series(ax, spec);
        title(ax, projection_groups(i), 'Interpreter', 'none', 'FontName', style.font_name, 'FontSize', style.axis_font_size, 'FontWeight', 'normal');

        if i == 1
            legend_handles = h;
            legend_labels  = labels;
        end
    end

    xlabel(tl, "Forecast horizon, {\it h} (days)", 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
    ylabel(tl, "Mean absolute error in infected population, {\it I}(t)", 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);

    lg = legend(legend_handles, legend_labels);
    lg.Interpreter = 'tex';
    lg.FontName    = style.font_name;
    lg.FontSize    = style.legend_font_size;
    lg.Box         = 'off';
    lg.Orientation = 'horizontal';
    lg.NumColumns  = numel(legend_labels);
    lg.Layout.Tile = 'north';

    exportgraphics(fig, fullfile(figure_dir, 'partA_05_infected_projection_mae_by_horizon.pdf'), 'ContentType', 'vector');
    close(fig);
end

fprintf('Figures saved under %s\n', figure_dir);
fprintf('=== Part A Figure Generation Complete ===\n\n');

%% 5. Local Functions

function fc = local_fixed_lead(results, interval_alphas, tspan, Rt_true, lead, plot_alphas)
%LOCAL_FIXED_LEAD Collect fixed-lead forecasts and full truth trajectory.
num_windows = numel(results);
num_alphas  = numel(plot_alphas);

target_days = nan(num_windows, 1);
median_fc   = nan(num_windows, 1);
lower       = nan(num_windows, num_alphas);
upper       = nan(num_windows, num_alphas);

for w = 1:num_windows
    result = results(w);

    target_days(w) = result.time_horizon(lead);
    median_fc(w)   = result.forecast_median(lead);

    for k = 1:num_alphas
        col = find(abs(interval_alphas(:) - plot_alphas(k)) <= 1e-8, 1);

        if isempty(col)
            error('PARTA_05:AlphaNotFound', 'Requested alpha %.4g is not stored in the forecast artifact.', plot_alphas(k));
        end

        lower(w, k) = result.forecast_lower(lead, col);
        upper(w, k) = result.forecast_upper(lead, col);
    end
end

[target_days, order] = sort(target_days);

fc = struct('truth_days', tspan(:), 'truth_Rt', Rt_true(:), 'target_days', target_days, 'median', median_fc(order), 'lower', lower(order, :), 'upper', upper(order, :));
end

function series = local_forecast_series(fc, plot_alphas, style)
%LOCAL_FORECAST_SERIES Build interval bands, truth, and median forecast.
num_alphas = numel(plot_alphas);

band_colors = [
    0.80, 0.88, 0.97;
    0.62, 0.76, 0.92;
    0.45, 0.64, 0.86;
    0.30, 0.52, 0.78];

band_labels = compose("%d%% PI", round((1 - plot_alphas) * 100));

series = repmat(local_series_template(), num_alphas + 2, 1);

for k = 1:num_alphas
    series(k).type       = "ribbon";
    series(k).x          = fc.target_days;
    series(k).lower      = fc.lower(:, k);
    series(k).upper      = fc.upper(:, k);
    series(k).face_color = band_colors(k, :);
    series(k).label      = band_labels(k);
end

truth_idx = num_alphas + 1;
series(truth_idx).type       = "line";
series(truth_idx).x          = fc.truth_days;
series(truth_idx).y          = fc.truth_Rt;
series(truth_idx).color      = [0, 0, 0];
series(truth_idx).line_width = style.truth_line_width;
series(truth_idx).label      = "Ground truth";

median_idx = num_alphas + 2;
series(median_idx).type        = "line";
series(median_idx).x           = fc.target_days;
series(median_idx).y           = fc.median;
series(median_idx).color       = style.palette(4, :);
series(median_idx).line_style  = "--";
series(median_idx).line_width  = style.line_width;
series(median_idx).marker      = "o";
series(median_idx).marker_size = style.marker_size;
series(median_idx).label       = "Median forecast";
end

function series = local_grouped_line_series(tbl, x_var, y_var, style)
%LOCAL_GROUPED_LINE_SERIES Build one line series per model/exogenous group.
group_ids = tbl.Model + " / " + tbl.ExoMode;
groups    = unique(group_ids, 'stable');
markers   = ["o", "s", "^", "d", "v", ">", "<", "p", "h"];

series = repmat(local_series_template(), numel(groups), 1);

for i = 1:numel(groups)
    idx = group_ids == groups(i);

    [x_values, order] = sort(tbl.(x_var)(idx));
    y_values = tbl.(y_var)(idx);

    series(i).type        = "line";
    series(i).x           = x_values;
    series(i).y           = y_values(order);
    series(i).color       = style.palette(mod(i - 1, size(style.palette, 1)) + 1, :);
    series(i).line_width  = style.line_width;
    series(i).marker      = markers(mod(i - 1, numel(markers)) + 1);
    series(i).marker_size = style.marker_size;
    series(i).label       = groups(i);
end
end

function series = local_i_projection_series(summary, style)
%LOCAL_I_PROJECTION_SERIES Build forecast-driven and persistence-Rt error series.
[horizon_idx, order] = sort(summary.HorizonIdx);

series = repmat(local_series_template(), 2, 1);

series(1).type        = "line";
series(1).x           = horizon_idx;
series(1).y           = summary.MeanForecastDrivenAbsoluteError(order);
series(1).color       = style.palette(4, :);
series(1).line_width  = style.line_width;
series(1).marker      = "o";
series(1).marker_size = style.marker_size;
series(1).label       = "Forecast-driven projection";

series(2).type        = "line";
series(2).x           = horizon_idx;
series(2).y           = summary.MeanPersistenceRtAbsoluteError(order);
series(2).color       = style.palette(1, :);
series(2).line_style  = "--";
series(2).line_width  = style.line_width;
series(2).marker      = "s";
series(2).marker_size = style.marker_size;
series(2).label       = "Persistence-{\it R}_t projection";
end

function series = local_series_template()
%LOCAL_SERIES_TEMPLATE Return an empty plot-series struct.
series = struct('type', "line", 'x', [], 'y', [], 'lower', [], 'upper', [], 'color', [], 'line_style', "-", 'line_width', 1.0, 'marker', "none", 'marker_size', 4, 'face_color', [], 'face_alpha', 1, 'label', "");
end

function style = local_style()
%LOCAL_STYLE Return synthetic-validation figure style constants.
style = struct();
style.font_name        = "Arial";
style.axis_font_size   = 9;
style.tick_font_size   = 8;
style.legend_font_size = 8;
style.panel_font_size  = 9;
style.line_width       = 1.2;
style.truth_line_width = 1.3;
style.marker_size      = 3.5;
style.palette          = [
    0.902, 0.624, 0.000;
    0.337, 0.706, 0.914;
    0.000, 0.620, 0.451;
    0.000, 0.447, 0.698;
    0.835, 0.369, 0.000;
    0.800, 0.475, 0.655];
end

function local_apply_legend(ax, handles, labels, style, num_columns)
%LOCAL_APPLY_LEGEND Attach a horizontal legend above an axes.
if isempty(handles)
    return;
end

lg = legend(ax, handles, labels);
lg.Interpreter = 'tex';
lg.FontName    = style.font_name;
lg.FontSize    = style.legend_font_size;
lg.Box         = 'off';
lg.Location    = 'northoutside';
lg.Orientation = 'horizontal';
lg.NumColumns  = num_columns;
end

function local_panel_label(ax, label_text, style)
%LOCAL_PANEL_LABEL Place a bold panel label in the top-left corner.
text(ax, 0.04, 0.94, label_text, 'Units', 'normalized', 'FontName', style.font_name, 'FontSize', style.panel_font_size, 'FontWeight', 'bold', 'Interpreter', 'tex', 'HorizontalAlignment', 'left', 'VerticalAlignment', 'top');
end

function token = local_safe_token(value)
%LOCAL_SAFE_TOKEN Convert a value into a filename-safe token.
token = char(regexprep(string(value), '[^A-Za-z0-9]+', '_'));
token = regexprep(token, '^_+|_+$', '');
end

function files = local_sort_dir_by_name(files)
%LOCAL_SORT_DIR_BY_NAME Sort a dir struct array by file name.
[~, order] = sort({files.name});
files = files(order);
end
