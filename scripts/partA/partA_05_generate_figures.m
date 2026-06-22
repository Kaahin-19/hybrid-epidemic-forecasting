%PARTA_05_GENERATE_FIGURES Generate and export Part A thesis figures (PDF).
%
%   Description:
%       Generates Part A thesis figures as vector PDFs, staged by pipeline
%       artifact section. Each section is independent and reads only the
%       artifacts it needs: scenario trajectories from partA_01 truth files,
%       forecast comparisons from partA_03 forecast files, and evaluation
%       figures from the partA_04 evaluation MAT artifact. A section whose
%       artifacts are missing is skipped with a message so the remaining
%       independent sections still run. This script owns artifact loading,
%       section ordering, figure and axes layout, export paths, exportgraphics
%       calls, and figure closing. It draws through three leaf helpers only:
%       PLOT_SERIES, PLOT_DISTRIBUTION, and APPLY_PANEL_STYLE.
%
%   Workflow:
%       1. Initialize configuration, output directory, and figure style.
%       2. Script 1 truth artifacts  -> Rt scenario trajectories.
%       3. Script 3 forecast artifacts -> fixed-lead forecast comparisons.
%       4. Script 4 evaluation artifact -> WIS distribution, horizon-wise WIS,
%          and coverage summary.
%       5. Local functions.
%
%   See also PARTA_01_GENERATE_TRUTH, PARTA_03_EVALUATE_FORECASTS, PARTA_04_EVALUATE_FORECASTS, ...
%            PLOT_SERIES, PLOT_DISTRIBUTION, APPLY_PANEL_STYLE.
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-22

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Figure Generation ===\n');

cfg = partA_config();
data_dir       = cfg.output.data_dir;
forecast_dir   = cfg.output.forecast_dir;
evaluation_dir = cfg.output.score_dir;
figure_dir     = cfg.output.fig_dir;

if ~exist(figure_dir, 'dir'), mkdir(figure_dir); end

style     = local_figure_style();
rt_bounds = cfg.Rt.bounds;

%% 2. Script 1 Truth Artifacts: Rt Scenario Trajectories
truth_files = local_sort_dir_by_name( ...
    dir(fullfile(data_dir, 'partA_01_truth_*.mat')));

if isempty(truth_files)
    fprintf('Skipping Rt scenario figure - no partA_01 truth artifacts in %s.\n', data_dir);
else
    fprintf('Drawing Rt scenario trajectories from %d truth artifact(s)...\n', ...
        numel(truth_files));
    scenarios = local_load_truth_scenarios(truth_files);

    n_panels = numel(scenarios);
    n_cols = ceil(sqrt(n_panels));
    n_rows = ceil(n_panels / n_cols);

    fig = figure('Visible', 'off', 'Units', 'centimeters', ...
        'Position', [2, 2, 17.0, 10.5], 'Color', 'w');
    tl = tiledlayout(fig, n_rows, n_cols, 'Padding', 'compact', ...
        'TileSpacing', 'compact');

    for i = 1:n_panels
        ax = nexttile(tl);
        panel = local_series_template();
        panel.type = "line";
        panel.x = scenarios(i).tspan;
        panel.y = scenarios(i).Rt_true;
        panel.color = style.palette(4, :);
        panel.line_width = style.truth_line_width;

        spec = struct('series', panel, 'style', struct( ...
            'y_limits', rt_bounds, 'grid', true, ...
            'axis_font_size', style.axis_font_size, ...
            'tick_font_size', style.tick_font_size, 'font_name', style.font_name));
        plot_series(ax, spec);
        local_panel_label(ax, sprintf("(%c)", 'a' + i - 1), style);
    end

    xlabel(tl, "Time, {\it t} (days)", 'Interpreter', 'tex', ...
        'FontName', style.font_name, 'FontSize', style.axis_font_size);
    ylabel(tl, "Effective reproduction number, {\it R}_t", 'Interpreter', 'tex', ...
        'FontName', style.font_name, 'FontSize', style.axis_font_size);

    local_export_pdf(fig, fullfile(figure_dir, 'partA_05_rt_scenarios.pdf'));
    close(fig);
end

%% 3. Script 3 Forecast Artifacts: Fixed-Lead Forecast Comparisons
forecast_files = local_sort_dir_by_name( ...
    dir(fullfile(forecast_dir, 'partA_03_forecast_*.mat')));

if isempty(forecast_files)
    fprintf('Skipping forecast comparisons - no partA_03 forecast artifacts in %s.\n', ...
        forecast_dir);
else
    lead = cfg.forecast.plot_lead_time;
    plot_alphas = sort(cfg.forecast.plot_alphas);
    fprintf('Drawing %d forecast comparison figure(s) at lead %d day(s)...\n', ...
        numel(forecast_files), lead);

    for f = 1:numel(forecast_files)
        loaded = load(fullfile(forecast_files(f).folder, forecast_files(f).name));
        fc = local_extract_fixed_lead(loaded.forecast_results, lead, plot_alphas);

        spec = struct('series', local_forecast_series(fc, plot_alphas, style), ...
            'style', struct('x_label', "Time, {\it t} (days)", ...
            'y_label', "Effective reproduction number, {\it R}_t", ...
            'y_limits', rt_bounds, 'grid', true, ...
            'axis_font_size', style.axis_font_size, ...
            'tick_font_size', style.tick_font_size, 'font_name', style.font_name));

        fig = figure('Visible', 'off', 'Units', 'centimeters', ...
            'Position', [2, 2, 17.0, 9.0], 'Color', 'w');
        ax = axes('Parent', fig); %#ok<LAXES>
        [h, lab] = plot_series(ax, spec);
        local_apply_legend(ax, h, lab, style, 'horizontal', numel(lab));

        plot_name = sprintf('partA_05_forecast_comparison_%s_%s_%s.pdf', ...
            local_safe_token(loaded.scenario_id), ...
            local_safe_token(loaded.model_type), ...
            local_safe_token(loaded.exo_mode));
        local_export_pdf(fig, fullfile(figure_dir, plot_name));
        close(fig);
    end
end

%% 4. Script 4 Evaluation Artifact: WIS Distribution, Horizon WIS, Coverage
evaluation_artifact = fullfile(evaluation_dir, 'partA_04_evaluation_results.mat');

if exist(evaluation_artifact, 'file') ~= 2
    fprintf('Skipping evaluation figures - no partA_04 evaluation artifact in %s.\n', ...
        evaluation_dir);
else
    fprintf('Drawing evaluation figures from partA_04 artifact...\n');
    evaluation = load(evaluation_artifact);
    window_scores    = evaluation.window_scores;
    horizon_summary  = evaluation.summaries.horizon_summary;
    interval_summary = evaluation.summaries.interval_summary;

    %% 4a. Model WIS distribution
    fig = figure('Visible', 'off', 'Units', 'centimeters', ...
        'Position', [2, 2, 17.0, 9.5], 'Color', 'w');
    ax = axes('Parent', fig);
    dist_spec = struct( ...
        'x', window_scores.Model + " / " + window_scores.ExoMode, ...
        'y', window_scores.WindowWIS, ...
        'group', window_scores.Scenario, ...
        'color_order', style.palette, ...
        'style', struct('x_label', "Model / exogenous mode", ...
        'y_label', "Window WIS", 'x_tick_rotation', 20, 'grid', true, ...
        'axis_font_size', style.axis_font_size, ...
        'tick_font_size', style.tick_font_size, 'font_name', style.font_name));
    [hd, ld] = plot_distribution(ax, dist_spec);
    local_apply_legend(ax, hd, ld, style, 'horizontal', numel(ld));
    local_export_pdf(fig, fullfile(figure_dir, 'partA_05_model_wis_distribution.pdf'));
    close(fig);

    %% 4b. Horizon-wise mean WIS
    horizon_series = local_grouped_line_series( ...
        horizon_summary, 'HorizonIdx', 'MeanWIS', style);
    fig = figure('Visible', 'off', 'Units', 'centimeters', ...
        'Position', [2, 2, 17.0, 9.0], 'Color', 'w');
    ax = axes('Parent', fig);
    spec = struct('series', horizon_series, 'style', struct( ...
        'x_label', "Forecast horizon, {\it h} (days)", 'y_label', "Mean WIS", ...
        'grid', true, 'axis_font_size', style.axis_font_size, ...
        'tick_font_size', style.tick_font_size, 'font_name', style.font_name));
    [hh, lh] = plot_series(ax, spec);
    local_apply_legend(ax, hh, lh, style, 'horizontal', 3);
    local_export_pdf(fig, fullfile(figure_dir, 'partA_05_mean_wis_by_horizon.pdf'));
    close(fig);

    %% 4c. Coverage summary
    coverage_series = local_grouped_line_series( ...
        interval_summary, 'NominalCoverage', 'MeanCoverage', style);
    coverage_series = [coverage_series; local_coverage_reference()];
    fig = figure('Visible', 'off', 'Units', 'centimeters', ...
        'Position', [2, 2, 16.0, 10.0], 'Color', 'w');
    ax = axes('Parent', fig);
    spec = struct('series', coverage_series, 'style', struct( ...
        'x_label', "Nominal coverage", 'y_label', "Empirical coverage", ...
        'x_limits', [0, 1], 'y_limits', [0, 1], 'grid', true, ...
        'axis_font_size', style.axis_font_size, ...
        'tick_font_size', style.tick_font_size, 'font_name', style.font_name));
    [hc, lc] = plot_series(ax, spec);
    local_apply_legend(ax, hc, lc, style, 'horizontal', 4);
    local_export_pdf(fig, fullfile(figure_dir, 'partA_05_coverage_summary.pdf'));
    close(fig);
end

fprintf('Figures saved under %s\n', figure_dir);
fprintf('=== Part A Figure Generation Complete ===\n\n');

%% 5. Local Functions - Style
function style = local_figure_style()
%LOCAL_FIGURE_STYLE Return shared Part A figure style constants.
style = struct();
style.font_name        = "Arial";
style.axis_font_size   = 9;
style.tick_font_size   = 8;
style.legend_font_size = 8;
style.panel_font_size  = 9;
style.line_width       = 1.2;
style.truth_line_width = 1.3;
style.marker_size      = 3.5;
style.palette          = local_thesis_color_order();
end

function colors = local_thesis_color_order()
%LOCAL_THESIS_COLOR_ORDER Return the Part A categorical colour order.
colors = [
    0.902, 0.624, 0.000;   % orange
    0.337, 0.706, 0.914;   % sky blue
    0.000, 0.620, 0.451;   % bluish green
    0.000, 0.447, 0.698;   % blue
    0.835, 0.369, 0.000;   % vermillion
    0.800, 0.475, 0.655];  % reddish purple
end

function colors = local_interval_colors(num_intervals)
%LOCAL_INTERVAL_COLORS Return light solid fills for forecast interval bands.
base_colors = [
    0.80, 0.88, 0.97;   % lightest (widest band)
    0.62, 0.76, 0.92;
    0.45, 0.64, 0.86;
    0.30, 0.52, 0.78];
colors = base_colors(1:num_intervals, :);
end

function marker = local_series_marker(idx)
%LOCAL_SERIES_MARKER Cycle distinguishable line markers.
markers = ["o", "s", "^", "d", "v", ">", "<", "p", "h"];
marker = markers(mod(idx - 1, numel(markers)) + 1);
end

%% 6. Local Functions - Artifact Loading
function scenarios = local_load_truth_scenarios(truth_files)
%LOCAL_LOAD_TRUTH_SCENARIOS Load Part A truth trajectories from partA_01 artifacts.
scenarios = repmat(struct('scenario_id', "", 'scenario_name', "", ...
    'tspan', [], 'Rt_true', []), numel(truth_files), 1);
for i = 1:numel(truth_files)
    loaded = load(fullfile(truth_files(i).folder, truth_files(i).name));
    scenarios(i).scenario_id   = loaded.scenario_id;
    scenarios(i).scenario_name = loaded.scenario_name;
    scenarios(i).tspan         = loaded.tspan;
    scenarios(i).Rt_true       = loaded.Rt_true;
end
end

%% 7. Local Functions - Forecast Series Assembly
function fc = local_extract_fixed_lead(forecast_results, lead, plot_alphas)
%LOCAL_EXTRACT_FIXED_LEAD Collect fixed-lead forecast values across windows.
num_windows = numel(forecast_results);
num_alphas = numel(plot_alphas);

target_days = nan(num_windows, 1);
truth = nan(num_windows, 1);
median_forecast = nan(num_windows, 1);
lower = nan(num_windows, num_alphas);
upper = nan(num_windows, num_alphas);

for w = 1:num_windows
    result = forecast_results(w);
    target_days(w) = result.t_future(lead);
    truth(w) = result.Rt_true_future(lead);
    median_forecast(w) = result.Rt_pred(lead);
    for k = 1:num_alphas
        col = local_alpha_index(result.interval_alphas, plot_alphas(k));
        lower(w, k) = result.lower_bounds(lead, col);
        upper(w, k) = result.upper_bounds(lead, col);
    end
end

[target_days, order] = sort(target_days);
fc = struct('target_days', target_days, 'truth', truth(order), ...
    'median', median_forecast(order), 'lower', lower(order, :), ...
    'upper', upper(order, :));
end

function col = local_alpha_index(interval_alphas, target_alpha)
%LOCAL_ALPHA_INDEX Locate the stored interval column for a requested alpha.
col = find(abs(interval_alphas - target_alpha) <= 1e-8, 1);
if isempty(col)
    error('FIG:AlphaNotFound', ...
        'Requested plot alpha %.4g is not among the stored interval alphas.', ...
        target_alpha);
end
end

function series = local_forecast_series(fc, plot_alphas, style)
%LOCAL_FORECAST_SERIES Assemble bands, truth, and median; bands drawn first.
num_alphas = numel(plot_alphas);
fill_colors = local_interval_colors(num_alphas);
pi_labels = compose("%d%% PI", round((1 - plot_alphas) * 100));

series = repmat(local_series_template(), num_alphas + 2, 1);

for k = 1:num_alphas
    series(k).type = "ribbon";
    series(k).x = fc.target_days;
    series(k).lower = fc.lower(:, k);
    series(k).upper = fc.upper(:, k);
    series(k).face_color = fill_colors(k, :);
    series(k).label = pi_labels(k);
end

idx_truth = num_alphas + 1;
series(idx_truth).type = "line";
series(idx_truth).x = fc.target_days;
series(idx_truth).y = fc.truth;
series(idx_truth).color = [0, 0, 0];
series(idx_truth).line_width = style.truth_line_width;
series(idx_truth).label = "Ground truth";

idx_median = num_alphas + 2;
series(idx_median).type = "line";
series(idx_median).x = fc.target_days;
series(idx_median).y = fc.median;
series(idx_median).color = style.palette(4, :);
series(idx_median).line_style = "--";
series(idx_median).line_width = style.line_width;
series(idx_median).marker = "o";
series(idx_median).marker_size = style.marker_size;
series(idx_median).label = "Median forecast";
end

%% 8. Local Functions - Evaluation Series Assembly
function series = local_grouped_line_series(summary, x_var, y_var, style)
%LOCAL_GROUPED_LINE_SERIES Build one line series per model/exogenous group.
group_ids = summary.Model + " / " + summary.ExoMode;
groups = unique(group_ids, 'stable');
series = repmat(local_series_template(), numel(groups), 1);

for i = 1:numel(groups)
    idx = group_ids == groups(i);
    [x_values, order] = sort(summary.(x_var)(idx));
    y_values = summary.(y_var)(idx);
    series(i).type = "line";
    series(i).x = x_values;
    series(i).y = y_values(order);
    series(i).color = style.palette(mod(i - 1, size(style.palette, 1)) + 1, :);
    series(i).line_width = style.line_width;
    series(i).marker = local_series_marker(i);
    series(i).marker_size = style.marker_size;
    series(i).label = groups(i);
end
end

function series = local_coverage_reference()
%LOCAL_COVERAGE_REFERENCE Build the nominal=empirical reference diagonal.
series = local_series_template();
series.type = "reference";
series.x = [0; 1];
series.y = [0; 1];
series.color = [0, 0, 0];
series.line_style = "--";
series.line_width = 1.0;
series.label = "Nominal = empirical";
end

%% 9. Local Functions - Layout, Export, and Utilities
function series = local_series_template()
%LOCAL_SERIES_TEMPLATE Uniform empty series struct for PLOT_SERIES input.
series = struct('type', "line", 'x', [], 'y', [], 'lower', [], 'upper', [], ...
    'color', [], 'line_style', "-", 'line_width', 1.0, ...
    'marker', "none", 'marker_size', 4, 'face_color', [], ...
    'face_alpha', 1, 'label', "");
end

function local_panel_label(ax, label_text, style)
%LOCAL_PANEL_LABEL Place a bold panel label in the top-left of an axes.
text(ax, 0.04, 0.94, label_text, 'Units', 'normalized', ...
    'FontName', style.font_name, 'FontSize', style.panel_font_size, ...
    'FontWeight', 'bold', 'Interpreter', 'tex', ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'top');
end

function local_apply_legend(ax, handles, labels, style, orientation, num_columns)
%LOCAL_APPLY_LEGEND Attach a shared legend outside the data region.
if isempty(handles)
    return;
end
lg = legend(ax, handles, labels);
lg.Interpreter = 'tex';
lg.FontName = style.font_name;
lg.FontSize = style.legend_font_size;
lg.Box = 'off';
lg.Location = 'northoutside';
lg.Orientation = orientation;
lg.NumColumns = num_columns;
end

function local_export_pdf(fig, output_path)
%LOCAL_EXPORT_PDF Export a figure as a vector PDF.
exportgraphics(fig, output_path, 'ContentType', 'vector');
end

function token = local_safe_token(value)
%LOCAL_SAFE_TOKEN Convert a value into a filename-safe token.
token = regexprep(value, '[^A-Za-z0-9]+', '_');
token = regexprep(token, '^_+|_+$', '');
end

function sorted_files = local_sort_dir_by_name(files)
%LOCAL_SORT_DIR_BY_NAME Sort a dir struct array by file name.
if isempty(files)
    sorted_files = files;
    return;
end
[~, order] = sort({files.name});
sorted_files = files(order);
end
