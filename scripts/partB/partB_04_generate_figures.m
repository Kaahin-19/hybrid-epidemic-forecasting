%PARTB_04_GENERATE_FIGURES Generate Part B infectious-population forecasting figures.
%
%   Description:
%       Generates five thesis figures from the current Part B artifacts:
%           1. Infectious-population trajectories at a representative
%              origin: synthetic truth, the estimated history, and the
%              persistence, oracle, and ARX forecasts.
%           2. Matched-window MAE by forecast horizon per condition.
%           3. Condition-level MAE and RMSE per method.
%           4. Paired window-level MAE improvement of ARX over persistence.
%           5. Execution support: status shares of all intended windows.
%       Aggregates withheld for incomplete scenario coverage are marked and
%       never drawn as zero; methods without a valid forecast are not drawn.
%
%   Workflow:
%       1. Initialize figure paths, identity, and shared styling.
%       2. Load and validate the evaluation artifact.
%       3. Generate the five figures.
%
%   See also PARTB_CONFIG, PARTB_03_EVALUATE_FORECASTS, PLOT_SERIES,
%            PLOT_DISTRIBUTION, APPLY_PANEL_STYLE.
%
% A. M. Kaahin 2026-07-18
% Modified: 2026-11-18

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Figure Generation ===\n');

cfg        = partB_config();
pb         = cfg.partB;
figure_dir = pb.output.fig_dir;
identity   = local_identity(cfg);
style      = local_style();

if ~exist(figure_dir, 'dir'), mkdir(figure_dir); end

%% 2. Load and Validate Evaluation Artifact
evaluation_artifact = fullfile(pb.output.evaluation_dir, 'partB_03_evaluation_results.mat');
if ~exist(evaluation_artifact, 'file')
    error('PARTB_04:MissingEvaluationArtifact', 'Missing Part B evaluation artifact: %s. Run partB_03 first.', evaluation_artifact);
end

evaluation = load(evaluation_artifact);
local_require_identity(evaluation.identity, identity, 'evaluation artifact');
summaries = evaluation.summaries;

case_ids    = [pb.robustness_cases.case_id]';
case_labels = [pb.robustness_cases.case_name]';

%% 3. Figures
local_figure_trajectories(cfg, identity, style, figure_dir);
local_figure_horizon(summaries.horizon_summary, summaries.condition_summary, case_ids, case_labels, pb.method_ids, style, figure_dir);
local_figure_conditions(summaries.condition_summary, case_ids, case_labels, pb.method_ids, style, figure_dir);
local_figure_improvement(evaluation.paired_windows, summaries.paired_condition_summary, case_ids, case_labels, style, figure_dir);
local_figure_support(summaries.support_condition, case_ids, case_labels, pb.method_ids, style, figure_dir);

fprintf('Figures saved to: %s\n', figure_dir);
fprintf('=== Part B Figure Generation Complete ===\n\n');

%% 4. Local Functions
function identity = local_identity(cfg)
%LOCAL_IDENTITY Experiment, configuration, and source identity shared by all Part B artifacts.
identity = struct('experiment_id', cfg.partB.experiment_id, 'protocol_version', cfg.partB.protocol_version, 'config_id', cfg.partB.config_id, 'source_id', cfg.partB.provenance.source_id);
end

function local_require_identity(found, expected, label)
%LOCAL_REQUIRE_IDENTITY Reject inputs produced under a different protocol, configuration, or source.
if ~isequal(found, expected)
    error('PARTB_04:IncompatibleArtifact', ['%s was produced under protocol %s, config_id %s, source_id %s; the current run expects protocol %s, ' ...
        'config_id %s, source_id %s. Rerun with ./run_partB_pipeline.sh --fresh.'], label, found.protocol_version, found.config_id, found.source_id, expected.protocol_version, expected.config_id, expected.source_id);
end
end

function local_figure_trajectories(cfg, identity, style, figure_dir)
%LOCAL_FIGURE_TRAJECTORIES Truth, estimated history, and three forecasts at a representative origin.
vis       = cfg.partB.visualization;
scenarios = cfg.scenarios;
n_rows    = numel(vis.trajectory_cases);
n_cols    = numel(scenarios);
method_labels = ["Persistence forecast", "Oracle forecast", "ARX/I forecast"];

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
        local_require_identity(dataset.identity, identity, dataset_id + " dataset");
        local_require_identity(forecast.identity, identity, dataset_id + " forecast");

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
        for m = 1:3
            if win.status(m) ~= "ok"
                unavailable(end + 1, 1) = forecast.method_ids(m) + ": " + strrep(win.status(m), "_", " ");
                continue;
            end
            s = local_series_template();
            s.x = dataset.tspan(future); s.y = [win.X_hat_T(2); win.I_pred(:, m)]; s.color = style.method_colors(m, :); s.line_width = style.line_width; s.label = method_labels(m);
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

function local_figure_horizon(horizon_summary, condition_summary, case_ids, case_labels, method_ids, style, figure_dir)
%LOCAL_FIGURE_HORIZON Matched-window infectious-population MAE by horizon, one panel per condition.
method_labels = local_method_labels(method_ids);
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
        s.x = rows.HorizonIdx; s.y = rows.MAE; s.color = style.method_colors(m, :); s.line_width = style.line_width; s.marker = "o"; s.marker_size = style.marker_size; s.label = method_labels(m);
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

exportgraphics(fig, fullfile(figure_dir, 'partB_04_mae_by_horizon.pdf'), 'ContentType', 'vector');
close(fig);
end

function local_figure_conditions(condition_summary, case_ids, case_labels, method_ids, style, figure_dir)
%LOCAL_FIGURE_CONDITIONS Condition-level MAE and RMSE per method with incomplete-coverage markers.
method_labels = local_method_labels(method_ids);
fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.5, 8.5], 'Color', 'w');
tl  = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
metrics = ["MAE", "RMSE"];
y_labels = ["MAE of {\itI} (persons)", "RMSE of {\itI} (persons)"];

complete_matrix = local_case_method_matrix(condition_summary, case_ids, method_ids, 'Complete');

for k = 1:2
    ax = nexttile(tl);
    matrix = local_case_method_matrix(condition_summary, case_ids, method_ids, metrics(k));
    h = local_grouped_bars(ax, matrix, style);
    local_style_bar_axis(ax, (1:numel(case_ids))', case_labels, y_labels(k), style);
    if any(isfinite(matrix), 'all')
        ylim(ax, [0, 1.15 * max(matrix(isfinite(matrix)))]);
    end
    local_mark_incomplete(ax, h, complete_matrix, style);
    local_apply_legend(ax, h, method_labels, style, numel(method_ids));
    local_panel_label(ax, "(" + char('a' + k - 1) + ")", style);
end

exportgraphics(fig, fullfile(figure_dir, 'partB_04_condition_comparison.pdf'), 'ContentType', 'vector');
close(fig);
end

function local_figure_improvement(paired_windows, paired_condition, case_ids, case_labels, style, figure_dir)
%LOCAL_FIGURE_IMPROVEMENT Distribution of paired window-level MAE improvement of ARX over persistence.
fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.5, 9.0], 'Color', 'w');
ax  = axes(fig);

present = ismember(case_ids, unique(paired_windows.Case));
x_labels = strings(height(paired_windows), 1);
for i = 1:numel(case_ids)
    x_labels(paired_windows.Case == case_ids(i)) = case_labels(i);
end

plot_distribution(ax, struct('x', categorical(x_labels, case_labels(present)), 'y', paired_windows.DeltaMAE, 'group', [], 'style', struct('y_label', "{\Delta}MAE = MAE_{persistence} - MAE_{ARX} (persons)", 'grid', true, 'font_name', style.font_name, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size)));
yline(ax, 0, '--', 'Color', [0, 0, 0], 'LineWidth', 1.0, 'HandleVisibility', 'off');

drawnow;
y_limits = ylim(ax);
y_limits(2) = y_limits(2) + 0.18 * diff(y_limits);
ylim(ax, y_limits);
present_ids = case_ids(present);
for i = 1:numel(present_ids)
    row = paired_condition(paired_condition.Case == present_ids(i), :);
    n   = sum(paired_windows.Case == present_ids(i));
    share = mean(paired_windows.ArxBetter(paired_windows.Case == present_ids(i)));
    text(ax, i, y_limits(2), [sprintf('{\\itn} = %d', n), sprintf('ARX better: %.0f%%', 100 * share) + string(local_incomplete_tag(row.Complete))], 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontName', style.font_name, 'FontSize', style.tick_font_size - 1, 'Interpreter', 'tex');
end
text(ax, 0.01, 0.02, 'Positive values: ARX more accurate than persistence (matched windows)', 'Units', 'normalized', 'VerticalAlignment', 'bottom', 'FontName', style.font_name, 'FontSize', style.tick_font_size - 1);

exportgraphics(fig, fullfile(figure_dir, 'partB_04_arx_improvement.pdf'), 'ContentType', 'vector');
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

function local_figure_support(support_condition, case_ids, case_labels, method_ids, style, figure_dir)
%LOCAL_FIGURE_SUPPORT Stacked status shares of all intended forecast windows per condition and method.
status_vars   = {'Ok', 'EstimationUnavailable', 'InsufficientHistory', 'DomainFailure', 'ForecastFailure', 'DatasetUnavailable'};
status_labels = ["Valid forecast", "Estimation unavailable", "Insufficient history", "Domain failure", "Forecast failure", "Dataset unavailable"];
status_colors = [0.000, 0.620, 0.451; 0.600, 0.600, 0.600; 0.800, 0.475, 0.655; 0.835, 0.369, 0.000; 0.902, 0.624, 0.000; 0.250, 0.250, 0.250];
method_labels = local_method_labels(method_ids);

fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.5, 8.5], 'Color', 'w');
tl  = tiledlayout(fig, 1, numel(method_ids), 'Padding', 'compact', 'TileSpacing', 'compact');

for m = 1:numel(method_ids)
    shares   = zeros(numel(case_ids), numel(status_vars));
    intended = zeros(numel(case_ids), 1);
    matched  = zeros(numel(case_ids), 1);
    for i = 1:numel(case_ids)
        row = support_condition(support_condition.Case == case_ids(i) & support_condition.Method == method_ids(m), :);
        intended(i) = row.IntendedWindows;
        matched(i)  = row.Matched;
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

    if m == numel(method_ids)
        lg = legend(b, status_labels, 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.legend_font_size, 'Box', 'off', 'Orientation', 'horizontal', 'NumColumns', 3);
        lg.Layout.Tile = 'north';
    end
end

exportgraphics(fig, fullfile(figure_dir, 'partB_04_execution_support.pdf'), 'ContentType', 'vector');
close(fig);
end

function labels = local_method_labels(method_ids)
%LOCAL_METHOD_LABELS Display labels for the forecast methods.
labels = strings(numel(method_ids), 1);
for m = 1:numel(method_ids)
    switch method_ids(m)
        case "persistence"; labels(m) = "Persistence";
        case "oracle";      labels(m) = "Oracle";
        case "arx";         labels(m) = "ARX/I";
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

function h = local_grouped_bars(ax, matrix, style)
%LOCAL_GROUPED_BARS Grouped categorical bars colored by method.
h = bar(ax, (1:size(matrix, 1))', matrix);
for j = 1:numel(h)
    h(j).FaceColor = style.method_colors(j, :);
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
style.method_colors     = [
    0.902, 0.624, 0.000;
    0.000, 0.447, 0.698;
    0.000, 0.620, 0.451];
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
