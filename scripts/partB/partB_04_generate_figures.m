%PARTB_04_GENERATE_FIGURES Generate Part B infectious-population forecasting figures.
%
%   Description:
%       Generates the Part B thesis figures: persistence, oracle, AR, and ARX
%       infectious-population trajectories at a representative origin,
%       matched-window MAE by horizon for the primary (persistence, oracle,
%       ARX) and extended (all four methods) matched sets, condition-level
%       MAE and RMSE for both sets, the primary paired MAE improvement of ARX
%       over persistence, the extended paired comparisons involving AR, and
%       execution support. Withheld aggregates are marked and never drawn as
%       zero.
%
%   Workflow:
%       1. Initialize figure paths and shared styling.
%       2. Load and validate the evaluation artifact.
%       3. Generate the figures.
%
%   See also PARTB_CONFIG, PARTB_03_EVALUATE_FORECASTS, PLOT_SERIES,
%            PLOT_DISTRIBUTION, APPLY_PANEL_STYLE.
%
% A. M. Kaahin 2026-07-18
% Modified: 2026-11-25

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Figure Generation ===\n');

cfg        = partB_config();
pb         = cfg.partB;
figure_dir = pb.output.fig_dir;
snapshot   = pb.snapshot;
style      = local_style();

if ~exist(figure_dir, 'dir'), mkdir(figure_dir); end

%% 2. Load and Validate Evaluation Artifact
evaluation_artifact = fullfile(pb.output.evaluation_dir, 'partB_03_evaluation_results.mat');
if ~exist(evaluation_artifact, 'file')
    error('PARTB_04:MissingEvaluationArtifact', 'Missing Part B evaluation artifact: %s. Run partB_03 first.', evaluation_artifact);
end

evaluation = load(evaluation_artifact);
local_require_snapshot(evaluation.snapshot, snapshot, 'Evaluation artifact');
summaries = evaluation.summaries;

case_ids    = [pb.robustness_cases.case_id]';
case_labels = [pb.robustness_cases.case_name]';

primary  = pb.matched_sets([pb.matched_sets.set_id] == "primary");
extended = pb.matched_sets([pb.matched_sets.set_id] == "extended");

%% 3. Figures
local_figure_trajectories(cfg, snapshot, style, figure_dir);
local_figure_horizon(summaries.horizon_summary, summaries.condition_summary, case_ids, case_labels, primary, style, fullfile(figure_dir, 'partB_04_mae_by_horizon.pdf'));
local_figure_horizon(summaries.horizon_summary, summaries.condition_summary, case_ids, case_labels, extended, style, fullfile(figure_dir, 'partB_04_mae_by_horizon_extended.pdf'));
local_figure_conditions(summaries.condition_summary, case_ids, case_labels, pb.matched_sets, style, figure_dir);
local_figure_paired(evaluation.paired_windows, summaries.paired_condition_summary, "primary", "persistence_vs_arx", case_ids, case_labels, style, fullfile(figure_dir, 'partB_04_arx_improvement.pdf'));
local_figure_paired(evaluation.paired_windows, summaries.paired_condition_summary, "extended", ["persistence_vs_ar"; "persistence_vs_arx"; "ar_vs_arx"; "ar_vs_oracle"; "arx_vs_oracle"], case_ids, case_labels, style, fullfile(figure_dir, 'partB_04_paired_comparisons_extended.pdf'));
local_figure_support(summaries.support_condition, case_ids, case_labels, pb.method_ids, pb.matched_sets, style, figure_dir);

fprintf('Figures saved to: %s\n', figure_dir);
fprintf('=== Part B Figure Generation Complete ===\n\n');

%% 4. Local Functions
function local_require_snapshot(found, expected, label)
%LOCAL_REQUIRE_SNAPSHOT Reject an input produced under a different Part B configuration.
if ~isequal(found, expected)
    error('PARTB_04:IncompatibleArtifact', '%s was produced under a different Part B configuration. Rerun with ./run_partB_pipeline.sh --fresh.', label);
end
end

function local_figure_trajectories(cfg, snapshot, style, figure_dir)
%LOCAL_FIGURE_TRAJECTORIES Truth, estimated history, and every method forecast at a representative origin.
vis       = cfg.partB.visualization;
scenarios = cfg.scenarios;
n_rows    = numel(vis.trajectory_cases);
n_cols    = numel(scenarios);
[method_labels, method_colors] = local_method_style(cfg.partB.method_ids);
method_labels = method_labels + " forecast";

fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.5, 4.6 * n_rows + 1.5], 'Color', 'w');
tl  = tiledlayout(fig, n_rows, n_cols, 'Padding', 'compact', 'TileSpacing', 'compact');
legend_handles = [];
legend_labels  = strings(0, 1);

for r = 1:n_rows
    case_id  = vis.trajectory_cases(r);
    case_def = cfg.partB.robustness_cases([cfg.partB.robustness_cases.case_id] == case_id);

    for c = 1:n_cols
        ax = nexttile(tl);
        dataset_id    = case_id + "_" + scenarios(c).id + "_" + vis.trajectory_replicate;
        dataset_path  = fullfile(cfg.partB.output.data_dir, "partB_01_dataset_" + dataset_id + ".mat");
        forecast_path = fullfile(cfg.partB.output.forecast_dir, "partB_02_forecast_" + dataset_id + ".mat");
        title(ax, case_def.case_name + " | " + scenarios(c).id, 'FontName', style.font_name, 'FontSize', style.panel_font_size, 'FontWeight', 'normal', 'Interpreter', 'tex');

        if exist(dataset_path, 'file') ~= 2 || exist(forecast_path, 'file') ~= 2
            text(ax, 0.5, 0.5, 'Dataset unavailable', 'Units', 'normalized', 'HorizontalAlignment', 'center', 'FontName', style.font_name, 'FontSize', style.tick_font_size);
            apply_panel_style(ax, struct('font_name', style.font_name));
            continue;
        end

        dataset  = load(dataset_path);
        forecast = load(forecast_path);
        local_require_snapshot(dataset.snapshot, snapshot, dataset_id + " dataset");
        local_require_snapshot(forecast.snapshot, snapshot, dataset_id + " forecast");

        win = forecast.windows([forecast.windows.window_day] == vis.trajectory_origin_day);
        if isempty(win)
            error('PARTB_04:TrajectoryOriginUnavailable', 'Origin day %d is not on the forecast grid.', vis.trajectory_origin_day);
        end

        iT       = win.window_day_idx;
        history  = (max(1, iT - vis.history_days):iT)';
        future   = (iT:iT + numel(win.truth_I))';
        series   = repmat(local_series_template(), 0, 1);

        s = local_series_template();
        s.x = dataset.tspan([history; future(2:end)]); s.y = dataset.I_true([history; future(2:end)]); s.color = [0, 0, 0]; s.line_width = style.truth_line_width; s.label = "Synthetic truth {\itI}";
        series(end + 1, 1) = s;

        s = local_series_template();
        s.x = dataset.tspan(history); s.y = dataset.I_estimated(history); s.color = [0.45, 0.45, 0.45]; s.line_style = "--"; s.line_width = style.line_width; s.label = "Estimated history {\itI}";
        series(end + 1, 1) = s;

        unavailable = strings(0, 1);
        for m = 1:numel(forecast.method_ids)
            if win.status(m) ~= "ok"
                unavailable(end + 1, 1) = forecast.method_ids(m) + ": " + strrep(win.status(m), "_", " ");
                continue;
            end
            s = local_series_template();
            s.x = dataset.tspan(future); s.y = [win.X_hat_T(2); win.I_pred(:, m)]; s.color = method_colors(m, :); s.line_width = style.line_width; s.label = method_labels(m);
            series(end + 1, 1) = s;
        end

        [h, labels] = plot_series(ax, struct('series', series, 'style', struct('x_label', "Day", 'y_label', "Infectious population", 'grid', true, 'font_name', style.font_name, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size)));
        xline(ax, dataset.tspan(iT), ':', 'Color', [0.3, 0.3, 0.3], 'HandleVisibility', 'off');

        if ~isempty(unavailable)
            text(ax, 0.02, 0.04, strjoin(unavailable, newline), 'Units', 'normalized', 'VerticalAlignment', 'bottom', 'FontName', style.font_name, 'FontSize', style.tick_font_size - 1, 'Color', style.unavailable_color, 'Interpreter', 'none');
        end

        if numel(labels) > numel(legend_labels)
            legend_handles = h;
            legend_labels  = labels;
        end
    end
end

if ~isempty(legend_handles)
    lg = legend(legend_handles, legend_labels, 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.legend_font_size, 'Box', 'off', 'Orientation', 'horizontal', 'NumColumns', 3);
    lg.Layout.Tile = 'north';
end

exportgraphics(fig, fullfile(figure_dir, 'partB_04_infectious_trajectories.pdf'), 'ContentType', 'vector');
close(fig);
end

function local_figure_horizon(horizon_summary, condition_summary, case_ids, case_labels, set_def, style, output_path)
%LOCAL_FIGURE_HORIZON Matched-window infectious-population MAE by horizon for one matched set, one panel per condition.
method_ids = set_def.method_ids;
[method_labels, method_colors] = local_method_style(method_ids);
horizon_summary   = horizon_summary(horizon_summary.MatchedSet == set_def.set_id, :);
condition_summary = condition_summary(condition_summary.MatchedSet == set_def.set_id, :);
fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.5, 10.5], 'Color', 'w');
tl  = tiledlayout(fig, 2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');
legend_handles = [];

for i = 1:numel(case_ids)
    ax = nexttile(tl);
    complete = all(condition_summary.Complete(condition_summary.Case == case_ids(i)));
    series = repmat(local_series_template(), 0, 1);

    for m = 1:numel(method_ids)
        rows = sortrows(horizon_summary(horizon_summary.Case == case_ids(i) & horizon_summary.Method == method_ids(m), :), 'HorizonIdx');
        s = local_series_template();
        s.x = rows.HorizonIdx; s.y = rows.MAE; s.color = method_colors(m, :); s.line_width = style.line_width; s.marker = "o"; s.marker_size = style.marker_size; s.label = method_labels(m);
        series(end + 1, 1) = s;
    end

    [h, ~] = plot_series(ax, struct('series', series, 'style', struct('x_label', "Forecast horizon {\ith} (days)", 'y_label', "MAE of {\itI} (persons)", 'grid', true, 'font_name', style.font_name, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size)));
    ylim(ax, [0, Inf]);
    title(ax, case_labels(i), 'FontName', style.font_name, 'FontSize', style.panel_font_size, 'FontWeight', 'normal', 'Interpreter', 'tex');

    if ~complete
        text(ax, 0.5, 0.5, 'Withheld: incomplete scenario coverage', 'Units', 'normalized', 'HorizontalAlignment', 'center', 'FontName', style.font_name, 'FontSize', style.tick_font_size, 'Color', style.unavailable_color);
    elseif isempty(legend_handles)
        legend_handles = h;
    end
end

if ~isempty(legend_handles)
    lg = legend(legend_handles, method_labels, 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.legend_font_size, 'Box', 'off', 'Orientation', 'horizontal');
    lg.Layout.Tile = 'north';
end
title(tl, set_def.set_name, 'FontName', style.font_name, 'FontSize', style.panel_font_size, 'FontWeight', 'normal');

exportgraphics(fig, output_path, 'ContentType', 'vector');
close(fig);
end

function local_figure_conditions(condition_summary, case_ids, case_labels, matched_sets, style, figure_dir)
%LOCAL_FIGURE_CONDITIONS Condition-level MAE and RMSE per method and matched set with incomplete-coverage markers.
fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.5, 8.0 * numel(matched_sets) + 0.5], 'Color', 'w');
tl  = tiledlayout(fig, numel(matched_sets), 2, 'Padding', 'compact', 'TileSpacing', 'compact');
metrics = ["MAE", "RMSE"];
y_labels = ["MAE of {\itI} (persons)", "RMSE of {\itI} (persons)"];
panel = 0;

for r = 1:numel(matched_sets)
    set_def = matched_sets(r);
    [method_labels, method_colors] = local_method_style(set_def.method_ids);
    set_rows = condition_summary(condition_summary.MatchedSet == set_def.set_id, :);
    complete_matrix = local_case_method_matrix(set_rows, case_ids, set_def.method_ids, 'Complete');

    for k = 1:2
        panel = panel + 1;
        ax = nexttile(tl);
        matrix = local_case_method_matrix(set_rows, case_ids, set_def.method_ids, metrics(k));
        h = local_grouped_bars(ax, matrix, method_colors);
        local_style_bar_axis(ax, (1:numel(case_ids))', case_labels, y_labels(k), style);
        if any(isfinite(matrix), 'all')
            ylim(ax, [0, 1.15 * max(matrix(isfinite(matrix)))]);
        end
        local_mark_incomplete(ax, h, complete_matrix, style);
        local_apply_legend(ax, h, method_labels, style, numel(set_def.method_ids));
        title(ax, set_def.set_name, 'FontName', style.font_name, 'FontSize', style.panel_font_size, 'FontWeight', 'normal', 'Interpreter', 'tex');
        local_panel_label(ax, "(" + char('a' + panel - 1) + ")", style);
    end
end

exportgraphics(fig, fullfile(figure_dir, 'partB_04_condition_comparison.pdf'), 'ContentType', 'vector');
close(fig);
end

function local_figure_paired(paired_windows, paired_condition, set_id, comparison_ids, case_ids, case_labels, style, output_path)
%LOCAL_FIGURE_PAIRED Distributions of paired window-level DeltaMAE = MAE_reference - MAE_candidate, one panel per comparison.
num_panels = numel(comparison_ids);
num_cols   = min(num_panels, 2);
num_rows   = ceil(num_panels / num_cols);
fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.5, max(9.0, 7.0 * num_rows)], 'Color', 'w');
tl  = tiledlayout(fig, num_rows, num_cols, 'Padding', 'compact', 'TileSpacing', 'compact');

for p = 1:num_panels
    ax = nexttile(tl);
    rows = paired_windows(paired_windows.MatchedSet == set_id & paired_windows.Comparison == comparison_ids(p), :);
    condition_rows = paired_condition(paired_condition.MatchedSet == set_id & paired_condition.Comparison == comparison_ids(p), :);
    reference_label = local_method_style(condition_rows.Reference(1));
    candidate_label = local_method_style(condition_rows.Candidate(1));

    present = ismember(case_ids, unique(rows.Case));
    x_labels = strings(height(rows), 1);
    for i = 1:numel(case_ids)
        x_labels(rows.Case == case_ids(i)) = case_labels(i);
    end

    plot_distribution(ax, struct('x', categorical(x_labels, case_labels(present)), 'y', rows.DeltaMAE, 'group', [], 'style', struct('y_label', "{\Delta}MAE (persons)", 'grid', true, 'font_name', style.font_name, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size)));
    yline(ax, 0, '--', 'Color', [0, 0, 0], 'LineWidth', 1.0, 'HandleVisibility', 'off');
    if num_panels > 1
        ax.XTickLabelRotation = 35;
    end
    title(ax, "{\Delta}MAE = MAE_{" + reference_label + "} - MAE_{" + candidate_label + "}", 'FontName', style.font_name, 'FontSize', style.panel_font_size, 'FontWeight', 'normal', 'Interpreter', 'tex');

    drawnow;
    y_limits = ylim(ax);
    y_limits(2) = y_limits(2) + 0.25 * diff(y_limits);
    ylim(ax, y_limits);
    present_ids = case_ids(present);
    for i = 1:numel(present_ids)
        row   = condition_rows(condition_rows.Case == present_ids(i), :);
        n     = sum(rows.Case == present_ids(i));
        share = mean(rows.CandidateBetter(rows.Case == present_ids(i)));
        text(ax, i, y_limits(2), [sprintf('{\\itn} = %d', n), sprintf('%s better: %.0f%%', candidate_label, 100 * share) + string(local_incomplete_tag(row.Complete))], 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontName', style.font_name, 'FontSize', style.tick_font_size - 1, 'Interpreter', 'tex');
    end
    text(ax, 0.01, 0.02, sprintf('Positive values: %s more accurate than %s', candidate_label, reference_label), 'Units', 'normalized', 'VerticalAlignment', 'bottom', 'FontName', style.font_name, 'FontSize', style.tick_font_size - 1);
end

set_name = "Primary matched set";
if set_id == "extended"
    set_name = "Extended matched set";
end
title(tl, set_name, 'FontName', style.font_name, 'FontSize', style.panel_font_size, 'FontWeight', 'normal');

exportgraphics(fig, output_path, 'ContentType', 'vector');
close(fig);
end

function tag = local_incomplete_tag(complete)
%LOCAL_INCOMPLETE_TAG Annotation suffix for conditions with incomplete scenario coverage.
if complete
    tag = "";
else
    tag = " (incomplete)";
end
end

function local_figure_support(support_condition, case_ids, case_labels, method_ids, matched_sets, style, figure_dir)
%LOCAL_FIGURE_SUPPORT Stacked status shares of all intended forecast windows per condition and method, plus matched-set shares.
status_vars   = {'Ok', 'EstimationUnavailable', 'InsufficientHistory', 'DomainFailure', 'ForecastFailure', 'DatasetUnavailable'};
status_labels = ["Valid forecast", "Estimation unavailable", "Insufficient history", "Domain failure", "Forecast failure", "Dataset unavailable"];
status_colors = [0.000, 0.620, 0.451; 0.600, 0.600, 0.600; 0.800, 0.475, 0.655; 0.835, 0.369, 0.000; 0.902, 0.624, 0.000; 0.250, 0.250, 0.250];
method_labels = local_method_style(method_ids);

fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.5, 15.0], 'Color', 'w');
tl  = tiledlayout(fig, 2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

for m = 1:numel(method_ids)
    shares   = zeros(numel(case_ids), numel(status_vars));
    intended = zeros(numel(case_ids), 1);
    for i = 1:numel(case_ids)
        row = support_condition(support_condition.Case == case_ids(i) & support_condition.Method == method_ids(m), :);
        intended(i) = row.IntendedWindows;
        for j = 1:numel(status_vars)
            shares(i, j) = row.(status_vars{j}) / row.IntendedWindows;
        end
    end

    ax = nexttile(tl);
    b  = bar(ax, (1:numel(case_ids))', shares, 'stacked');
    for j = 1:numel(b)
        b(j).FaceColor = status_colors(j, :);
        b(j).EdgeColor = 'none';
    end
    for i = 1:numel(case_ids)
        text(ax, i, 1.02, sprintf('{\\itN} = %d', intended(i)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontName', style.font_name, 'FontSize', style.tick_font_size - 1, 'Interpreter', 'tex');
    end

    local_style_bar_axis(ax, (1:numel(case_ids))', case_labels, "Share of intended forecast windows", style);
    ax.XTickLabelRotation = 35;
    ylim(ax, [0, 1.12]);
    title(ax, method_labels(m), 'FontName', style.font_name, 'FontSize', style.panel_font_size, 'FontWeight', 'normal', 'Interpreter', 'tex');

    if m == 1
        lg = legend(b, status_labels, 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.legend_font_size, 'Box', 'off', 'Orientation', 'horizontal', 'NumColumns', 3);
        lg.Layout.Tile = 'north';
    end
end

matched_shares = zeros(numel(case_ids), numel(matched_sets));
for i = 1:numel(case_ids)
    for k = 1:numel(matched_sets)
        row = support_condition(support_condition.Case == case_ids(i) & support_condition.Method == matched_sets(k).method_ids(1), :);
        matched_shares(i, k) = row.("Matched_" + matched_sets(k).set_id) / row.IntendedWindows;
    end
end

ax = nexttile(tl);
b  = bar(ax, (1:numel(case_ids))', matched_shares);
set_colors = [0.350, 0.350, 0.350; 0.700, 0.700, 0.700];
for k = 1:numel(b)
    b(k).FaceColor = set_colors(k, :);
    b(k).EdgeColor = 'none';
end
local_style_bar_axis(ax, (1:numel(case_ids))', case_labels, "Share of intended forecast windows", style);
ax.XTickLabelRotation = 35;
ylim(ax, [0, 1.12]);
title(ax, "Matched sets", 'FontName', style.font_name, 'FontSize', style.panel_font_size, 'FontWeight', 'normal', 'Interpreter', 'tex');
local_apply_legend(ax, b, [matched_sets.set_name], style, 1);

exportgraphics(fig, fullfile(figure_dir, 'partB_04_execution_support.pdf'), 'ContentType', 'vector');
close(fig);
end

function [labels, colors] = local_method_style(method_ids)
%LOCAL_METHOD_STYLE Display labels (M-by-1) and RGB colors (M-by-3) for the forecast methods.
labels = strings(numel(method_ids), 1);
colors = zeros(numel(method_ids), 3);
for m = 1:numel(method_ids)
    switch method_ids(m)
        case "persistence"; labels(m) = "Persistence"; colors(m, :) = [0.902, 0.624, 0.000];
        case "oracle";      labels(m) = "Oracle";      colors(m, :) = [0.000, 0.447, 0.698];
        case "ar";          labels(m) = "AR/None";     colors(m, :) = [0.800, 0.475, 0.655];
        case "arx";         labels(m) = "ARX/I";       colors(m, :) = [0.000, 0.620, 0.451];
    end
end
end

function matrix = local_case_method_matrix(tbl, case_ids, method_ids, value_var)
%LOCAL_CASE_METHOD_MATRIX Case-by-method value matrix with NaN for absent rows.
matrix = NaN(numel(case_ids), numel(method_ids));
for i = 1:numel(case_ids)
    for j = 1:numel(method_ids)
        row = tbl(tbl.Case == case_ids(i) & tbl.Method == method_ids(j), :);
        if height(row) == 1
            matrix(i, j) = double(row.(value_var));
        end
    end
end
end

function h = local_grouped_bars(ax, matrix, colors)
%LOCAL_GROUPED_BARS Grouped categorical bars colored by method.
h = bar(ax, (1:size(matrix, 1))', matrix);
for j = 1:numel(h)
    h(j).FaceColor = colors(j, :);
    h(j).EdgeColor = 'none';
end
end

function local_mark_incomplete(ax, bars, complete_matrix, style)
%LOCAL_MARK_INCOMPLETE Mark aggregate slots withheld for incomplete scenario coverage.
drawnow;
hold(ax, 'on');
y_limits = ylim(ax);
y_marker = y_limits(1) + 0.04 * (y_limits(2) - y_limits(1));
for j = 1:numel(bars)
    incomplete = complete_matrix(:, j) == 0;
    if any(incomplete)
        plot(ax, bars(j).XEndPoints(incomplete), repmat(y_marker, sum(incomplete), 1), 'x', 'Color', style.unavailable_color, 'LineWidth', 1.2, 'MarkerSize', 6, 'HandleVisibility', 'off');
    end
end
if any(complete_matrix == 0, 'all')
    text(ax, 0.99, 0.98, '{\times} withheld: incomplete coverage', 'Units', 'normalized', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', 'FontName', style.font_name, 'FontSize', style.tick_font_size, 'Color', style.unavailable_color, 'Interpreter', 'tex');
end
hold(ax, 'off');
end

function local_style_bar_axis(ax, ticks, tick_labels, y_label, style)
%LOCAL_STYLE_BAR_AXIS Apply shared styling and categorical tick labels to a bar axes.
apply_panel_style(ax, struct('y_label', y_label, 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));
set(ax, 'XTick', ticks, 'XTickLabel', cellstr(tick_labels));
xlim(ax, [0.5, numel(ticks) + 0.5]);
end

function series = local_series_template()
%LOCAL_SERIES_TEMPLATE Return an empty plot-series struct.
series = struct('type', "line", 'x', [], 'y', [], 'lower', [], 'upper', [], 'color', [], 'line_style', "-", 'line_width', 1.0, 'marker', "none", 'marker_size', 4, 'face_color', [], 'face_alpha', 1, 'label', "");
end

function style = local_style()
%LOCAL_STYLE Return figure style constants using the shared palette.
style = struct();
style.font_name         = "Arial";
style.axis_font_size    = 9;
style.tick_font_size    = 8;
style.legend_font_size  = 8;
style.panel_font_size   = 9;
style.line_width        = 1.2;
style.truth_line_width  = 1.3;
style.marker_size       = 3.5;
style.unavailable_color = [0.835, 0.369, 0.000];
end

function local_apply_legend(ax, handles, labels, style, num_columns)
%LOCAL_APPLY_LEGEND Attach a horizontal legend above an axes.
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
