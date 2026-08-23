%PARTB_04_GENERATE_FIGURES Generate Part B robustness thesis figures.
%
%   Description:
%       Visualizes the completed Part B Script 3 evaluation summaries as a
%       compact set of thesis figures: a robustness overview (mean WIS by
%       stress case and WIS degradation relative to the matched Part A
%       baseline), horizon-wise WIS, replicate-level WIS distributions,
%       interval calibration, and Script 2 execution outcomes from the saved
%       evaluation summaries. Lower WIS is better and a WIS ratio above one
%       indicates degradation relative to the Part A baseline.
%
%   Workflow:
%       1. Initialize figure paths and shared styling.
%       2. Load and validate the Part B evaluation summaries.
%       3. Derive the plotted combinations, stress cases, and scenarios.
%       4. Generate the shared robustness overview.
%       5. Generate the execution-outcome figure.
%       6. Generate horizon, replicate, and calibration figures by combination.
%
%   See also PARTB_CONFIG, PARTB_03_EVALUATE_FORECASTS, PLOT_SERIES,
%            PLOT_DISTRIBUTION, APPLY_PANEL_STYLE.
%
% A. M. Kaahin 2026-07-18
% Modified: 2026-08-23

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Figure Generation ===\n');

cfg            = partB_config();
evaluation_dir = cfg.partB.output.evaluation_dir;
figure_dir     = cfg.partB.output.fig_dir;

if ~exist(figure_dir, 'dir'), mkdir(figure_dir); end

style = local_style();

%% 2. Load and Validate Evaluation Artifact
evaluation_artifact = fullfile(evaluation_dir, 'partB_03_evaluation_results.mat');
if ~exist(evaluation_artifact, 'file')
    error('PARTB_04:MissingEvaluationArtifact', 'Missing Part B evaluation artifact: %s. Run partB_03 first.', evaluation_artifact);
end

evaluation = load(evaluation_artifact);
summaries  = local_validate_evaluation(evaluation);

%% 3. Derive Combinations, Cases, and Scenarios
combos = local_combinations(summaries.stress_summary);
fprintf('Found %d model/exogenous combination(s).\n', numel(combos));

%% 4. Figure 1: Robustness Overview
local_figure_overview(summaries, style, figure_dir);

%% 5. Figure 5: Execution Outcomes
local_figure_execution(summaries.execution_summary, combos, style, figure_dir);

%% 6. Per-Combination Figures
for c = 1:numel(combos)
    combo = combos(c);
    fprintf('Drawing per-combination figures for %s...\n', combo.label);

    local_figure_horizon(summaries, combo, style, figure_dir);
    local_figure_replicates(summaries.replicate_summary, combo, style, figure_dir);
    local_figure_calibration(summaries.interval_summary, summaries.stress_summary, combo, style, figure_dir);
end

fprintf('Figures saved under %s\n', figure_dir);
fprintf('=== Part B Figure Generation Complete ===\n\n');

%% 7. Local Functions
function summaries = local_validate_evaluation(evaluation)
%LOCAL_VALIDATE_EVALUATION Require the evaluation artifact and summary schemas before plotting.
required_top = {'window_scores', 'horizon_scores', 'interval_scores', 'summaries', 'availability_report', 'evaluation_snapshot'};
if ~all(isfield(evaluation, required_top))
    error('PARTB_04:InvalidEvaluationArtifact', 'Evaluation artifact is missing one or more required variables.');
end

summaries        = evaluation.summaries;
required_summary = {'replicate_summary', 'scenario_summary', 'stress_summary', 'horizon_summary', 'interval_summary', 'execution_summary', 'degradation_summary'};
if ~all(isfield(summaries, required_summary))
    error('PARTB_04:InvalidSummaries', 'summaries is missing one or more required summary tables.');
end

local_require_vars(summaries.replicate_summary, {'Case', 'Scenario', 'Replicate', 'Model', 'ExoMode', 'MeanWIS', 'NumWindows', 'NumHorizonRows'}, 'replicate_summary');
local_require_vars(summaries.stress_summary, {'Case', 'Model', 'ExoMode', 'NumScenarios', 'TotalReplicates', 'MeanWIS', 'MeanMAE', 'MeanRMSE', 'MeanCoverage', 'MeanIntervalWidth'}, 'stress_summary');
local_require_vars(summaries.horizon_summary, {'Case', 'Model', 'ExoMode', 'HorizonIdx', 'MeanWIS', 'MeanAbsoluteError', 'MeanSquaredError', 'RMSE', 'MeanCoverage', 'MeanIntervalWidth'}, 'horizon_summary');
local_require_vars(summaries.interval_summary, {'Case', 'Model', 'ExoMode', 'Alpha', 'NominalCoverage', 'MeanCoverage', 'MeanIntervalWidth', 'CoverageError'}, 'interval_summary');
local_require_vars(summaries.execution_summary, {'Case', 'Model', 'ExoMode', 'Attempts', 'Saved', 'NoWindows', 'DomainFailures', 'Pending', 'SuccessRate'}, 'execution_summary');
local_require_vars(summaries.degradation_summary, {'Case', 'Model', 'ExoMode', 'PartA_MeanWIS', 'PartB_MeanWIS', 'MeanWISDifference', 'MeanWISRatio', 'RelativeWISIncrease'}, 'degradation_summary');

exec = summaries.execution_summary;
if any(exec.Attempts <= 0) || any(exec.Saved < 0) || any(exec.NoWindows < 0) || any(exec.DomainFailures < 0) || any(exec.Pending ~= 0)
    error('PARTB_04:InvalidExecutionCounts', 'Execution counts violate the required non-negativity or zero-pending constraints.');
end
if any(exec.Saved + exec.NoWindows + exec.DomainFailures + exec.Pending ~= exec.Attempts)
    error('PARTB_04:InconsistentExecutionCounts', 'Execution outcome counts do not sum to the number of attempts.');
end
end

function local_require_vars(tbl, names, tbl_name)
%LOCAL_REQUIRE_VARS Fail fast when a summary table lacks a required variable or holds non-finite metrics.
missing = names(~ismember(names, tbl.Properties.VariableNames));
if ~isempty(missing)
    error('PARTB_04:MissingVariable', 'Summary table %s is missing required variable(s): %s.', tbl_name, strjoin(missing, ', '));
end

for i = 1:numel(names)
    column = tbl.(names{i});
    if isnumeric(column) && ~all(isfinite(column))
        error('PARTB_04:NonFiniteMetric', 'Summary table %s has non-finite values in %s.', tbl_name, names{i});
    end
end
end

function combos = local_combinations(stress_summary)
%LOCAL_COMBINATIONS Derive model/exogenous combinations present in the evaluation.
pairs = sortrows(unique(stress_summary(:, {'Model', 'ExoMode'}), 'rows'), {'Model', 'ExoMode'});
combos = repmat(struct('model', "", 'exo', "", 'label', "", 'token', ""), height(pairs), 1);
for i = 1:height(pairs)
    combos(i).model = string(pairs.Model(i));
    combos(i).exo   = string(pairs.ExoMode(i));
    combos(i).label = combos(i).model + " / " + combos(i).exo;
    combos(i).token = local_safe_token(combos(i).model) + "_" + local_safe_token(combos(i).exo);
end
end

function local_figure_overview(summaries, style, figure_dir)
%LOCAL_FIGURE_OVERVIEW Two-panel mean-WIS and WIS-degradation overview across stress cases.
stress  = summaries.stress_summary;
degrade = summaries.degradation_summary;

[case_ids, case_labels] = local_case_system(unique(stress.Case), style);
combo_labels = local_combo_labels(stress);

fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.5, 8.5], 'Color', 'w');
tl  = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

wis_matrix = local_case_combo_matrix(stress, case_ids, combo_labels, 'MeanWIS');

ax = nexttile(tl);
h = local_grouped_bars(ax, wis_matrix, style);
local_style_bar_axis(ax, (1:numel(case_ids))', case_labels, "Mean WIS", style);
local_apply_legend(ax, h, combo_labels, style, numel(combo_labels));
local_panel_label(ax, "(a)", style);

ratio_matrix = local_case_combo_matrix(degrade, case_ids, combo_labels, 'MeanWISRatio');

ax = nexttile(tl);
h = local_grouped_bars(ax, ratio_matrix, style);
local_style_bar_axis(ax, (1:numel(case_ids))', case_labels, "Mean WIS ratio (Part B / Part A)", style);
yline(ax, 1, '--', 'Color', [0, 0, 0], 'LineWidth', 1.0, 'Label', 'Part A baseline', 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.legend_font_size, 'LabelHorizontalAlignment', 'left');
local_apply_legend(ax, h, combo_labels, style, numel(combo_labels));
local_panel_label(ax, "(b)", style);

exportgraphics(fig, fullfile(figure_dir, 'partB_04_robustness_overview.pdf'), 'ContentType', 'vector');
close(fig);
end

function local_figure_execution(execution_summary, combos, style, figure_dir)
%LOCAL_FIGURE_EXECUTION Per-combination stacked shares of Script 2 forecast outcomes.
outcome_colors = [0.000, 0.620, 0.451; 0.835, 0.369, 0.000; 0.600, 0.600, 0.600];
outcome_labels = ["Saved", "Domain failure", "No valid windows"];

fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.5, 8.5], 'Color', 'w');
tl  = tiledlayout(fig, 1, numel(combos), 'Padding', 'compact', 'TileSpacing', 'compact');

for c = 1:numel(combos)
    combo = combos(c);
    rows  = execution_summary(execution_summary.Model == combo.model & execution_summary.ExoMode == combo.exo, :);
    [case_ids, case_labels] = local_case_system(unique(rows.Case), style);

    shares   = zeros(numel(case_ids), 3);
    attempts = zeros(numel(case_ids), 1);
    for i = 1:numel(case_ids)
        r = rows(rows.Case == case_ids(i), :);

        if height(r) ~= 1
            error('PARTB_04:ExecutionRowCount', 'Expected one execution-summary row for case %s and combination %s, but found %d.', case_ids(i), combo.label, height(r));
        end

        attempts(i) = r.Attempts;
        shares(i, :) = [r.Saved, r.DomainFailures, r.NoWindows] / r.Attempts;
    end

    if any(abs(sum(shares, 2) - 1) > 1e-9)
        error('PARTB_04:ExecutionSharesUnnormalized', 'Execution outcome shares do not sum to one for %s.', combo.label);
    end

    ax = nexttile(tl);
    b  = bar(ax, (1:numel(case_ids))', shares, 'stacked');
    for j = 1:3
        b(j).FaceColor = outcome_colors(j, :);
    end
    for i = 1:numel(case_ids)
        text(ax, i, 1.02, sprintf('{\\itN} = %d', attempts(i)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontName', style.font_name, 'FontSize', style.tick_font_size, 'Interpreter', 'tex');
    end

    local_style_bar_axis(ax, (1:numel(case_ids))', case_labels, "Share of Script 2 attempts", style);
    ylim(ax, [0, 1]);
    title(ax, combo.label, 'FontName', style.font_name, 'FontSize', style.panel_font_size, 'FontWeight', 'normal', 'Interpreter', 'tex');
    if c == numel(combos)
        local_apply_legend(ax, b, outcome_labels, style, 3);
    end
end

exportgraphics(fig, fullfile(figure_dir, 'partB_04_execution_outcomes.pdf'), 'ContentType', 'vector');
close(fig);
end

function local_figure_horizon(summaries, combo, style, figure_dir)
%LOCAL_FIGURE_HORIZON Horizon-wise mean WIS, one line per stress case.
horizon = summaries.horizon_summary(summaries.horizon_summary.Model == combo.model & summaries.horizon_summary.ExoMode == combo.exo, :);
stress  = summaries.stress_summary;

[case_ids, case_labels, case_colors, case_markers] = local_case_system(unique(horizon.Case), style);

series = repmat(local_series_template(), numel(case_ids), 1);
for i = 1:numel(case_ids)
    rows = sortrows(horizon(horizon.Case == case_ids(i), :), 'HorizonIdx');
    n_scen = local_scenario_count(stress, case_ids(i), combo);

    series(i).type        = "line";
    series(i).x           = rows.HorizonIdx;
    series(i).y           = rows.MeanWIS;
    series(i).color       = case_colors(i, :);
    series(i).line_width  = style.line_width;
    series(i).marker      = case_markers(i);
    series(i).marker_size = style.marker_size;
    series(i).label       = case_labels(i) + " (" + string(n_scen) + local_scenario_word(n_scen) + ")";
end

fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 16.0, 9.0], 'Color', 'w');
ax  = axes('Parent', fig);

spec = struct('series', series, 'style', struct('x_label', "Forecast horizon, {\it h} (days)", 'y_label', "Mean WIS", 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));
[h, labels] = plot_series(ax, spec);
xticks(ax, unique(horizon.HorizonIdx));
local_apply_legend(ax, h, labels, style, min(numel(labels), 2));

exportgraphics(fig, fullfile(figure_dir, char("partB_04_mean_wis_by_horizon_" + combo.token + ".pdf")), 'ContentType', 'vector');
close(fig);
end

function local_figure_replicates(replicate_summary, combo, style, figure_dir)
%LOCAL_FIGURE_REPLICATES Replicate-level WIS distributions, one panel per scenario.
rows = replicate_summary(replicate_summary.Model == combo.model & replicate_summary.ExoMode == combo.exo, :);
scenarios = sort(unique(rows.Scenario));

y_max = max(rows.MeanWIS);
y_limits = [0, y_max * 1.08 + eps];

n_panels = numel(scenarios);
n_cols   = ceil(sqrt(n_panels));
n_rows   = ceil(n_panels / n_cols);

fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.0, 11.0], 'Color', 'w');
tl  = tiledlayout(fig, n_rows, n_cols, 'Padding', 'compact', 'TileSpacing', 'compact');

for s = 1:n_panels
    panel_rows = rows(rows.Scenario == scenarios(s), :);
    [case_ids, case_labels, case_colors] = local_case_system(unique(panel_rows.Case), style);

    [~, pos]     = ismember(panel_rows.Case, case_ids);
    obs_labels   = case_labels(pos);
    obs_category = categorical(obs_labels, case_labels);

    ax = nexttile(tl);
    dist_spec = struct('x', obs_category, 'y', panel_rows.MeanWIS, 'group', obs_category, 'color_order', case_colors, 'style', struct('y_limits', y_limits, 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));
    plot_distribution(ax, dist_spec);
    title(ax, char(scenarios(s)), 'FontName', style.font_name, 'FontSize', style.panel_font_size, 'FontWeight', 'normal', 'Interpreter', 'tex');
end

xlabel(tl, "Stress case", 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
ylabel(tl, "Replicate mean WIS", 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);

exportgraphics(fig, fullfile(figure_dir, char("partB_04_replicate_wis_distribution_" + combo.token + ".pdf")), 'ContentType', 'vector');
close(fig);
end

function local_figure_calibration(interval_summary, stress_summary, combo, style, figure_dir)
%LOCAL_FIGURE_CALIBRATION Nominal-versus-empirical interval coverage, one line per stress case.
interval = interval_summary(interval_summary.Model == combo.model & interval_summary.ExoMode == combo.exo, :);
[case_ids, case_labels, case_colors, case_markers] = local_case_system(unique(interval.Case), style);

series = repmat(local_series_template(), numel(case_ids) + 1, 1);

reference = local_series_template();
reference.type       = "reference";
reference.x          = [0; 1];
reference.y          = [0; 1];
reference.color      = [0, 0, 0];
reference.line_style = "--";
reference.line_width = 1.0;
reference.label      = "Nominal = empirical";
series(1) = reference;

for i = 1:numel(case_ids)
    rows = sortrows(interval(interval.Case == case_ids(i), :), 'NominalCoverage');
    n_scen = local_scenario_count(stress_summary, case_ids(i), combo);

    series(i + 1).type        = "line";
    series(i + 1).x           = rows.NominalCoverage;
    series(i + 1).y           = rows.MeanCoverage;
    series(i + 1).color       = case_colors(i, :);
    series(i + 1).line_width  = style.line_width;
    series(i + 1).marker      = case_markers(i);
    series(i + 1).marker_size = style.marker_size;
    series(i + 1).label       = case_labels(i) + " (" + string(n_scen) + local_scenario_word(n_scen) + ")";
end

fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 16.0, 10.0], 'Color', 'w');
ax  = axes('Parent', fig);

spec = struct('series', series, 'style', struct('x_label', "Nominal coverage", 'y_label', "Empirical coverage", 'x_limits', [0, 1], 'y_limits', [0, 1], 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));
[h, labels] = plot_series(ax, spec);
local_apply_legend(ax, h, labels, style, min(numel(labels), 3));

exportgraphics(fig, fullfile(figure_dir, char("partB_04_interval_calibration_" + combo.token + ".pdf")), 'ContentType', 'vector');
close(fig);
end

function [ordered_ids, labels, colors, markers] = local_case_system(present_ids, style)
%LOCAL_CASE_SYSTEM Stable stress-case display order, labels, colors, and markers.
catalog  = ["observation_noise", "process_noise", "structural_mismatch", "combined_stress"];
readable = ["Noisy Rt input", "Process noise", "Structural mismatch", "Combined stress"];
markers_all = ["o", "s", "^", "d", "v", ">", "<", "p", "h"];

present_ids = string(present_ids(:));
[is_known, catalog_pos] = ismember(present_ids, catalog);
known = sortrows([catalog_pos(is_known), find(is_known)], 1);
extra = sort(present_ids(~is_known));
ordered_ids = [present_ids(known(:, 2)); extra];

labels  = strings(numel(ordered_ids), 1);
colors  = zeros(numel(ordered_ids), 3);
markers = strings(numel(ordered_ids), 1);
for i = 1:numel(ordered_ids)
    k = find(catalog == ordered_ids(i), 1);
    if isempty(k)
        k = numel(catalog) + find(extra == ordered_ids(i), 1);
        labels(i) = local_prettify(ordered_ids(i));
    else
        labels(i) = readable(k);
    end
    colors(i, :) = style.palette(mod(k - 1, size(style.palette, 1)) + 1, :);
    markers(i)   = markers_all(mod(k - 1, numel(markers_all)) + 1);
end
end

function labels = local_combo_labels(tbl)
%LOCAL_COMBO_LABELS Sorted unique "Model / ExoMode" labels present in a table.
pairs = sortrows(unique(tbl(:, {'Model', 'ExoMode'}), 'rows'), {'Model', 'ExoMode'});
labels = string(pairs.Model) + " / " + string(pairs.ExoMode);
end

function matrix = local_case_combo_matrix(tbl, case_ids, combo_labels, value_var)
%LOCAL_CASE_COMBO_MATRIX Case-by-combination value matrix with NaN for absent rows.
combo_ids = string(tbl.Model) + " / " + string(tbl.ExoMode);
matrix    = nan(numel(case_ids), numel(combo_labels));
for i = 1:numel(case_ids)
    for j = 1:numel(combo_labels)
        row = tbl(tbl.Case == case_ids(i) & combo_ids == combo_labels(j), :);

        if height(row) == 1
            matrix(i, j) = row.(value_var);
        elseif height(row) > 1
            error('PARTB_04:DuplicateSummaryRows', 'Found multiple rows for case %s and combination %s.', case_ids(i), combo_labels(j));
        end
    end
end
end

function n_scen = local_scenario_count(stress_summary, case_id, combo)
%LOCAL_SCENARIO_COUNT Scenario count for one stress case and model/exogenous combination.
row = stress_summary(stress_summary.Case == case_id & stress_summary.Model == combo.model & stress_summary.ExoMode == combo.exo, :);

if height(row) ~= 1
    error('PARTB_04:StressRowCount', 'Expected one stress-summary row for case %s and combination %s, but found %d.', case_id, combo.label, height(row));
end

n_scen = row.NumScenarios;
end

function word = local_scenario_word(n_scen)
%LOCAL_SCENARIO_WORD Singular or plural scenario word for legend text.
if n_scen == 1
    word = " scenario";
else
    word = " scenarios";
end
end

function h = local_grouped_bars(ax, matrix, style)
%LOCAL_GROUPED_BARS Grouped categorical bars colored by combination.
h = bar(ax, (1:size(matrix, 1))', matrix);
for j = 1:numel(h)
    h(j).FaceColor = style.palette(mod(j - 1, size(style.palette, 1)) + 1, :);
    h(j).EdgeColor = 'none';
end
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
%LOCAL_STYLE Return Part B figure style constants (matching the Part A palette).
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

function label = local_prettify(case_id)
%LOCAL_PRETTIFY Human-readable label for a stress case not in the known catalog.
label = regexprep(string(case_id), '_+', ' ');
label = strtrim(label);
if strlength(label) > 0
    label = upper(extractBefore(label, 2)) + extractAfter(label, 1);
end
end

function token = local_safe_token(value)
%LOCAL_SAFE_TOKEN Convert a value into a filename-safe token.
token = string(regexprep(string(value), '[^A-Za-z0-9]+', '_'));
token = regexprep(token, '^_+|_+$', '');
end
