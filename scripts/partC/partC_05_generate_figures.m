%PARTC_05_GENERATE_FIGURES Generate real-data adaptation thesis figures.
%
%   Description:
%       Generates seven thesis-ready figures from the prepared-data, held-out
%       forecast, and evaluation artifacts. It draws the observed-data and
%       reconstructed-state summaries together with held-out forecast and
%       evaluation comparisons, then exports each figure as a vector PDF.
%
%   Workflow:
%       1. Load the prepared-data, forecast, and evaluation artifacts.
%       2. Generate the seven configured thesis figures.
%       3. Export each figure directly as a vector PDF.
%       4. Report the saved figure paths.
%
%   See also PARTC_CONFIG, PARTC_04_EVALUATE_FORECASTS, PLOT_SERIES,
%            PLOT_DISTRIBUTION.
%
% A. M. Kaahin 2026-08-06
% Modified: 2026-08-23

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Thesis Figure Generation ===\n');

cfg = partC_config();

if ~exist(cfg.output.figure_dir, 'dir')
    mkdir(cfg.output.figure_dir);
end

canonical_names = [
    "partC_05_data_overview.pdf"
    "partC_05_sirs_proxy_states.pdf"
    "partC_05_fixed_lead_forecasts.pdf"
    "partC_05_origin_wis_distribution.pdf"
    "partC_05_performance_by_lead_time.pdf"
    "partC_05_interval_diagnostics.pdf"
    "partC_05_pairwise_wis_differences.pdf"
    ];

canonical_paths = fullfile(cfg.output.figure_dir, canonical_names);
style = local_style();

%% 2. Source Artifacts
prepared = local_load_prepared_artifact(cfg);
artifacts = local_load_forecast_artifacts(cfg);
evaluation = local_load_evaluation_artifact(cfg);

fprintf('Prepared, forecast, and evaluation artifacts loaded.\n');

%% 3. Figure Generation
fprintf('Generating figure 1/7\n');
local_generate_data_overview(prepared, cfg, style, canonical_paths(1));

fprintf('Generating figure 2/7\n');
local_generate_sirs_proxy_states(prepared, cfg, style, canonical_paths(2));

fprintf('Generating figure 3/7\n');
local_generate_fixed_lead_forecasts(prepared, artifacts, evaluation.online_equivalence, cfg, style, canonical_paths(3));

fprintf('Generating figure 4/7\n');
local_generate_origin_wis_distribution(evaluation.origin_scores, style, canonical_paths(4));

fprintf('Generating figure 5/7\n');
local_generate_performance_by_lead_time(evaluation.summaries.horizon_summary, evaluation.online_equivalence, cfg, style, canonical_paths(5));

fprintf('Generating figure 6/7\n');
local_generate_interval_diagnostics(evaluation.summaries.interval_summary, evaluation.online_equivalence, cfg, style, canonical_paths(6));

fprintf('Generating figure 7/7\n');
local_generate_pairwise_wis_differences(evaluation.pairwise_comparisons, style, canonical_paths(7));

%% 4. Completion Report
close all;

for figure_index = 1:numel(canonical_paths)
    fprintf('Saved figure: %s\n', canonical_paths(figure_index));
end

fprintf('=== Part C Thesis Figure Generation Complete ===\n\n');

%% 5. Local Functions
function prepared = local_load_prepared_artifact(cfg)
%LOCAL_LOAD_PREPARED_ARTIFACT Load the Script 1 prepared data.

artifact_path = cfg.output.prepared_artifact_path;

if ~isfile(artifact_path)
    error('PARTC_05:MissingPreparedArtifact', 'Missing prepared Part C artifact: %s. Run Part C Script 1 first.', artifact_path);
end

prepared = load(artifact_path, 'dates', 'incidence_observed', 'Rt_estimated', 'S_proxy', 'I_fraction_proxy', 'R_proxy');

end

function artifacts = local_load_forecast_artifacts(cfg)
%LOCAL_LOAD_FORECAST_ARTIFACTS Load the six Script 3 forecast artifacts.

artifact_paths = cfg.evaluation.expected_forecast_artifact_paths;
artifacts = cell(numel(artifact_paths), 1);

for artifact_index = 1:numel(artifact_paths)
    artifact_path = artifact_paths(artifact_index);

    if ~isfile(artifact_path)
        error('PARTC_05:MissingForecastArtifact', 'Missing required forecast artifact: %s. Run Part C Script 3 first.', artifact_path);
    end

    artifacts{artifact_index} = load(artifact_path, 'model_type', 'exo_mode', 'strategy', 'forecast_configuration', 'wis_alphas', 'results');
end

end

function evaluation = local_load_evaluation_artifact(cfg)
%LOCAL_LOAD_EVALUATION_ARTIFACT Load the Script 4 evaluation artifact.

artifact_path = fullfile(cfg.output.evaluation_dir, "partC_04_evaluation_results.mat");

if ~isfile(artifact_path)
    error('PARTC_05:MissingEvaluationArtifact', 'Missing evaluation artifact: %s. Run Part C Script 4 first.', artifact_path);
end

evaluation = load(artifact_path, 'origin_scores', 'summaries', 'pairwise_comparisons', 'online_equivalence');

end

function local_generate_data_overview(prepared, cfg, style, output_path)
%LOCAL_GENERATE_DATA_OVERVIEW Generate incidence and operational-Rt panels.

dates = prepared.dates;
incidence = prepared.incidence_observed;
Rt_plot = prepared.Rt_estimated;

fig = local_new_figure([2, 2, 17.0, 12.0]);
layout = tiledlayout(fig, 2, 1, 'Padding', 'compact', 'TileSpacing', 'compact');

ax = nexttile(layout);

series = [
    local_line_series(dates, incidence, style.data_color, "-", "", style.line_width)
    local_vertical_reference(cfg.validation.test_start_date, incidence, style)
    ];

spec = struct('series', series, 'style', local_axis_style("", "Reported daily incidence", style));

plot_series(ax, spec);
xlim(ax, [dates(1), dates(end)]);
xtickformat(ax, 'MMM yyyy');

local_period_labels(ax, style);
local_panel_label(ax, "(a)", style);

ax = nexttile(layout);

valid_Rt = Rt_plot(isfinite(Rt_plot));

series = [
    local_line_series(dates, Rt_plot, style.data_color, "-", "", style.line_width)
    local_vertical_reference(cfg.validation.test_start_date, valid_Rt, style)
    ];

spec = struct('series', series, 'style', local_axis_style("", "Operational effective reproduction number, R_t", style));

plot_series(ax, spec);
xlim(ax, [dates(1), dates(end)]);
xtickformat(ax, 'MMM yyyy');

local_period_labels(ax, style);
local_panel_label(ax, "(b)", style);

local_export_and_close(fig, output_path);

end

function local_generate_sirs_proxy_states(prepared, cfg, style, output_path)
%LOCAL_GENERATE_SIRS_PROXY_STATES Generate three proxy-fraction panels.

dates = prepared.dates;
population = cfg.state_reconstruction.effective_population;

fractions = [
    prepared.S_proxy / population, prepared.I_fraction_proxy, prepared.R_proxy / population
    ];

y_labels = [
    "Susceptible proxy fraction, S/N"
    "Infectious proxy fraction, I/N"
    "Recovered proxy fraction, R/N"
    ];

colors = [
    style.model.AR
    style.model.ARX
    style.proxy_recovered
    ];

panel_labels = ["(a)", "(b)", "(c)"];

fig = local_new_figure([2, 2, 17.0, 15.0]);
layout = tiledlayout(fig, 3, 1, 'Padding', 'compact', 'TileSpacing', 'compact');

title(layout, "Reported-case SIRS proxy fractions", 'FontName', style.font_name, 'FontSize', style.title_font_size, 'FontWeight', 'normal', 'Interpreter', 'tex');

for panel_index = 1:3
    ax = nexttile(layout);

    values = fractions(:, panel_index);

    series = [
        local_line_series(dates, values, colors(panel_index, :), "-", "", style.line_width)
        local_vertical_reference(cfg.validation.test_start_date, values, style)
        ];

    spec = struct('series', series, 'style', local_axis_style("", y_labels(panel_index), style));

    plot_series(ax, spec);

    xlim(ax, [dates(1), dates(end)]);
    xtickformat(ax, 'MMM yyyy');

    local_panel_label(ax, panel_labels(panel_index), style);
end

local_export_and_close(fig, output_path);

end

function local_generate_fixed_lead_forecasts(prepared, artifacts, equivalence, cfg, style, output_path)
%LOCAL_GENERATE_FIXED_LEAD_FORECASTS Generate fixed-lead comparison panels.

panels = local_forecast_panels(artifacts, equivalence, cfg);

lead_time = cfg.visualization.plot_lead_time;
plot_alphas = cfg.visualization.plot_alphas;

num_panels = numel(panels);
num_columns = 2;
num_rows = ceil(num_panels / num_columns);
figure_height = 6.2 * num_rows + 1.8;

held_out_mask = prepared.dates >= cfg.validation.test_start_date;
held_out_dates = prepared.dates(held_out_mask);
held_out_Rt = prepared.Rt_estimated(held_out_mask);

panel_data = cell(num_panels, 1);

data_minimum = min(held_out_Rt);
data_maximum = max(held_out_Rt);

for panel_index = 1:num_panels
    panel_data{panel_index} = local_extract_fixed_lead(panels(panel_index).artifact, lead_time, plot_alphas);

    data = panel_data{panel_index};

    data_minimum = min(data_minimum, min(data.target_Rt));
    data_minimum = min(data_minimum, min(data.median));
    data_minimum = min(data_minimum, min(data.lower, [], 'all'));
    data_minimum = min(data_minimum, min(data.upper, [], 'all'));

    data_maximum = max(data_maximum, max(data.target_Rt));
    data_maximum = max(data_maximum, max(data.median));
    data_maximum = max(data_maximum, max(data.lower, [], 'all'));
    data_maximum = max(data_maximum, max(data.upper, [], 'all'));
end

[common_lower, common_upper] = local_forecast_axis_limits(data_minimum, data_maximum);

panel_labels = ["(a)", "(b)", "(c)", "(d)", "(e)", "(f)"];

fig = local_new_figure([2, 2, 17.5, figure_height]);
layout = tiledlayout(fig, num_rows, num_columns, 'Padding', 'compact', 'TileSpacing', 'compact');

legend_handles = gobjects(0, 1);
legend_labels = strings(0, 1);
legend_axes = gobjects(1, 1);

for panel_index = 1:num_panels
    ax = nexttile(layout);

    data = panel_data{panel_index};
    model_color = local_model_color(panels(panel_index).artifact.model_type, style);
    series = local_forecast_series(held_out_dates, held_out_Rt, data, model_color, style);

    axis_style = local_axis_style("", "Operational effective reproduction number, R_t", style);
    axis_style.y_limits = [common_lower, common_upper];

    spec = struct('series', series, 'style', axis_style);

    [handles, labels] = plot_series(ax, spec);

    xlim(ax, [held_out_dates(1), held_out_dates(end)]);
    xtickformat(ax, 'MMM yyyy');

    title(ax, panels(panel_index).title, 'FontName', style.font_name, 'FontSize', style.panel_font_size, 'FontWeight', 'normal', 'Interpreter', 'tex');

    local_panel_label(ax, panel_labels(panel_index), style);

    if panel_index == 1
        legend_handles = handles;
        legend_labels = labels;
        legend_axes = ax;
    end
end

local_shared_legend(legend_axes, legend_handles, legend_labels, style, 4);
local_export_and_close(fig, output_path);

end

function panels = local_forecast_panels(artifacts, equivalence, cfg)
%LOCAL_FORECAST_PANELS Resolve online equivalence into display panels.

panel_template = struct('artifact', struct(), 'title', "");

collapse_flags = cfg.visualization.collapse_exact_online_duplicates & equivalence.ForecastsExactlyIdentical;

panels = repmat(panel_template, 4 + nnz(~collapse_flags), 1);
panel_index = 0;

for pair_index = 1:2
    base_index = (pair_index - 1) * 3;

    partA_online = artifacts{base_index + 1};
    local_online = artifacts{base_index + 2};
    fixed_fit = artifacts{base_index + 3};

    model_label = local_model_label(partA_online.model_type, partA_online.exo_mode);
    collapse = cfg.visualization.collapse_exact_online_duplicates && equivalence.ForecastsExactlyIdentical(pair_index);

    if collapse
        panel_index = panel_index + 1;
        panels(panel_index) = struct('artifact', partA_online, 'title', model_label + " — Part A/local online — identical");
    else
        panel_index = panel_index + 1;
        panels(panel_index) = struct('artifact', partA_online, 'title', model_label + " — Part A online");

        panel_index = panel_index + 1;
        panels(panel_index) = struct('artifact', local_online, 'title', model_label + " — Local online");
    end

    panel_index = panel_index + 1;
    panels(panel_index) = struct('artifact', fixed_fit, 'title', model_label + " — Fixed calibration fit");
end

end

function data = local_extract_fixed_lead(artifact, lead_time, plot_alphas)
%LOCAL_EXTRACT_FIXED_LEAD Extract one lead and selected interval levels.

num_origins = numel(artifact.results);
num_alphas = numel(plot_alphas);

target_dates = NaT(num_origins, 1);
target_Rt = zeros(num_origins, 1);
median_forecast = zeros(num_origins, 1);
lower = zeros(num_origins, num_alphas);
upper = zeros(num_origins, num_alphas);

alpha_columns = zeros(num_alphas, 1);

for alpha_index = 1:num_alphas
    alpha_columns(alpha_index) = find(artifact.wis_alphas == plot_alphas(alpha_index), 1);
end

for origin_position = 1:num_origins
    result = artifact.results(origin_position);

    target_dates(origin_position) = result.target_dates(lead_time);
    target_Rt(origin_position) = result.target_Rt_estimated(lead_time);
    median_forecast(origin_position) = result.forecast_median(lead_time);
    lower(origin_position, :) = result.forecast_lower(lead_time, alpha_columns);
    upper(origin_position, :) = result.forecast_upper(lead_time, alpha_columns);
end

data = struct('target_dates', target_dates, 'target_Rt', target_Rt, 'median', median_forecast, 'lower', lower, 'upper', upper);

end

function series = local_forecast_series(held_out_dates, held_out_Rt, data, model_color, style)
%LOCAL_FORECAST_SERIES Build prediction intervals, target, and median series.

series = repmat(local_series_template(), 4, 1);

series(1).type = "ribbon";
series(1).x = data.target_dates;
series(1).lower = data.lower(:, 1);
series(1).upper = data.upper(:, 1);
series(1).face_color = local_lighten_color(model_color, 0.82);
series(1).face_alpha = 1;
series(1).label = "90% PI";

series(2).type = "ribbon";
series(2).x = data.target_dates;
series(2).lower = data.lower(:, 2);
series(2).upper = data.upper(:, 2);
series(2).face_color = local_lighten_color(model_color, 0.62);
series(2).face_alpha = 1;
series(2).label = "50% PI";

series(3) = local_line_series(held_out_dates, held_out_Rt, style.data_color, "-", "Operational Rt estimate", style.target_line_width);

series(4) = local_line_series(data.target_dates, data.median, model_color, "-", "Median forecast", style.forecast_line_width);
series(4).marker = "o";
series(4).marker_size = style.marker_size;

end

function [lower_limit, upper_limit] = local_forecast_axis_limits(data_minimum, data_maximum)
%LOCAL_FORECAST_AXIS_LIMITS Compute common forecast-axis limits.

data_range = data_maximum - data_minimum;
padding = 0.05 * max([data_range, abs(data_maximum), eps]);

lower_limit = max(0, data_minimum - padding);
upper_limit = data_maximum + padding;

end

function local_generate_origin_wis_distribution(origin_scores, style, output_path)
%LOCAL_GENERATE_ORIGIN_WIS_DISTRIBUTION Generate grouped origin-WIS boxes.

model_labels = local_model_labels(origin_scores.Model, origin_scores.ExoMode);
strategy_labels = local_strategy_labels(origin_scores.Strategy);

model_plot_labels = model_labels;
model_plot_labels(model_labels == "AR / None") = "1 AR / None";
model_plot_labels(model_labels == "ARX/I") = "2 ARX / I";

strategy_plot_labels = strategy_labels;
strategy_plot_labels(strategy_labels == "Part A online") = "1 Part A online";
strategy_plot_labels(strategy_labels == "Local online") = "2 Local online";
strategy_plot_labels(strategy_labels == "Part A fixed") = "3 Part A fixed";

fig = local_new_figure([2, 2, 16.0, 10.0]);
ax = axes('Parent', fig);

dist_spec = struct('x', model_plot_labels, 'y', origin_scores.MeanWIS, 'group', strategy_plot_labels, 'color_order', style.strategy_colors, 'style', local_axis_style("Model / exogenous mode", "Mean origin WIS", style));

[handles, labels] = plot_distribution(ax, dist_spec);

xticklabels(ax, ["AR / None", "ARX / I"]);

labels = erase(labels, ["1 ", "2 ", "3 "]);

local_axes_legend(ax, handles, labels, style, 3);
local_export_and_close(fig, output_path);

end

function local_generate_performance_by_lead_time(horizon_summary, equivalence, cfg, style, output_path)
%LOCAL_GENERATE_PERFORMANCE_BY_LEAD_TIME Generate WIS and MAE panels.

fig = local_new_figure([2, 2, 17.5, 8.5]);
layout = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

ax = nexttile(layout);

series = local_summary_series(horizon_summary, 'LeadTime', 'MeanWIS', equivalence, cfg, style);
spec = struct('series', series, 'style', local_axis_style("Lead time (days)", "Mean WIS", style));

[handles, labels] = plot_series(ax, spec);

xticks(ax, 1:cfg.final_forecast.horizon);
xlim(ax, [1, cfg.final_forecast.horizon]);

local_panel_label(ax, "(a)", style);

ax = nexttile(layout);

series = local_summary_series(horizon_summary, 'LeadTime', 'MeanAbsoluteError', equivalence, cfg, style);
spec = struct('series', series, 'style', local_axis_style("Lead time (days)", "Mean absolute error", style));

plot_series(ax, spec);

xticks(ax, 1:cfg.final_forecast.horizon);
xlim(ax, [1, cfg.final_forecast.horizon]);

local_panel_label(ax, "(b)", style);

local_shared_legend(ax, handles, labels, style, 2);
local_export_and_close(fig, output_path);

end

function local_generate_interval_diagnostics(interval_summary, equivalence, cfg, style, output_path)
%LOCAL_GENERATE_INTERVAL_DIAGNOSTICS Generate coverage and width panels.

fig = local_new_figure([2, 2, 17.5, 8.5]);
layout = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

ax = nexttile(layout);

reference = local_line_series([0; 1], [0; 1], style.data_color, "--", "Nominal = empirical", style.reference_line_width);
reference.type = "reference";

method_series = local_summary_series(interval_summary, 'NominalCoverage', 'EmpiricalCoverage', equivalence, cfg, style);

series = [reference; method_series];

axis_style = local_axis_style("Nominal coverage", "Empirical coverage", style);
axis_style.x_limits = [0, 1];
axis_style.y_limits = [0, 1];

spec = struct('series', series, 'style', axis_style);

[handles, labels] = plot_series(ax, spec);

local_panel_label(ax, "(a)", style);

ax = nexttile(layout);

series = local_summary_series(interval_summary, 'NominalCoverage', 'MeanIntervalWidth', equivalence, cfg, style);

maximum_width = max(interval_summary.MeanIntervalWidth);
width_upper = 1.05 * maximum_width;

if width_upper == 0
    width_upper = eps;
end

axis_style = local_axis_style("Nominal coverage", "Mean interval width", style);
axis_style.x_limits = [0, 1];
axis_style.y_limits = [0, width_upper];

spec = struct('series', series, 'style', axis_style);

plot_series(ax, spec);

local_panel_label(ax, "(b)", style);

local_shared_legend(ax, handles, labels, style, 2);
local_export_and_close(fig, output_path);

end

function series = local_summary_series(summary, x_variable, y_variable, equivalence, cfg, style)
%LOCAL_SUMMARY_SERIES Build model-colour and strategy-style curves.

models = [
    "AR", "None"
    "ARX", "I"
    ];

collapse_flags = cfg.visualization.collapse_exact_online_duplicates & equivalence.ForecastsExactlyIdentical;

series = repmat(local_series_template(), 4 + nnz(~collapse_flags), 1);
series_index = 0;

for model_index = 1:size(models, 1)
    model = models(model_index, 1);
    exo_mode = models(model_index, 2);

    model_rows = summary(summary.Model == model & summary.ExoMode == exo_mode, :);

    model_color = local_model_color(model, style);
    model_label = local_model_label(model, exo_mode);

    collapse = cfg.visualization.collapse_exact_online_duplicates && equivalence.ForecastsExactlyIdentical(model_index);

    partA_rows = sortrows(model_rows(model_rows.Strategy == "partA_online_fit", :), x_variable);
    local_rows = sortrows(model_rows(model_rows.Strategy == "local_online_fit", :), x_variable);
    fixed_rows = sortrows(model_rows(model_rows.Strategy == "partA_fixed_fit", :), x_variable);

    if collapse
        next_series = local_line_series(partA_rows.(x_variable), partA_rows.(y_variable), model_color, "-", model_label + " online — Part A/local identical", style.line_width);
        next_series.marker = "o";
        next_series.marker_size = style.marker_size;

        series_index = series_index + 1;
        series(series_index) = next_series;
    else
        next_series = local_line_series(partA_rows.(x_variable), partA_rows.(y_variable), model_color, "-", model_label + " — Part A online", style.line_width);
        next_series.marker = "o";
        next_series.marker_size = style.marker_size;

        series_index = series_index + 1;
        series(series_index) = next_series;

        next_series = local_line_series(local_rows.(x_variable), local_rows.(y_variable), model_color, "--", model_label + " — Local online", style.line_width);
        next_series.marker = "s";
        next_series.marker_size = style.marker_size;

        series_index = series_index + 1;
        series(series_index) = next_series;
    end

    next_series = local_line_series(fixed_rows.(x_variable), fixed_rows.(y_variable), model_color, ":", model_label + " — Part A fixed", style.line_width);
    next_series.marker = "^";
    next_series.marker_size = style.marker_size;

    series_index = series_index + 1;
    series(series_index) = next_series;
end

end

function local_generate_pairwise_wis_differences(comparisons, style, output_path)
%LOCAL_GENERATE_PAIRWISE_WIS_DIFFERENCES Generate matched WIS lollipops.

differences = comparisons.MeanWISDifference;
num_comparisons = numel(differences);

positions = (1:num_comparisons).';
labels = strings(num_comparisons, 1);

for comparison_index = 1:num_comparisons
    labels(comparison_index) = local_comparison_label(comparisons(comparison_index, :));
end

axis_limit = 1.08 * max(abs(differences));

if axis_limit == 0
    axis_limit = 1e-6;
end

stem_x = NaN(3 * num_comparisons, 1);
stem_y = NaN(3 * num_comparisons, 1);

for comparison_index = 1:num_comparisons
    row_indices = (comparison_index - 1) * 3 + (1:3);

    stem_x(row_indices) = [0; differences(comparison_index); NaN];
    stem_y(row_indices) = [positions(comparison_index); positions(comparison_index); NaN];
end

series = repmat(local_series_template(), 3, 1);

series(1) = local_line_series([0; 0], [0.5; num_comparisons + 0.5], style.data_color, "--", "", style.reference_line_width);
series(1).type = "reference";

series(2) = local_line_series(stem_x, stem_y, style.pairwise_color, "-", "", style.line_width);

series(3) = local_line_series(differences, positions, style.pairwise_color, "none", "", style.line_width);
series(3).marker = "o";
series(3).marker_size = style.pairwise_marker_size;

fig = local_new_figure([2, 2, 17.0, 10.0]);
ax = axes('Parent', fig);

axis_style = local_axis_style("Left mean WIS − right mean WIS; negative values favour the left-hand method", "", style);
axis_style.x_limits = [-axis_limit, axis_limit];
axis_style.y_limits = [0.5, num_comparisons + 0.5];

spec = struct('series', series, 'style', axis_style);

plot_series(ax, spec);

yticks(ax, positions);
yticklabels(ax, labels);

ax.YDir = 'reverse';

local_export_and_close(fig, output_path);

end

function label = local_comparison_label(row)
%LOCAL_COMPARISON_LABEL Build a concise comparison label.

context = local_pretty_identity(row.ModelOrStrategy);
left = local_pretty_identity(row.LeftLabel);
right = local_pretty_identity(row.RightLabel);

label = context + ": " + left + " − " + right;

end

function label = local_pretty_identity(identifier)
%LOCAL_PRETTY_IDENTITY Convert stored identifiers to display labels.

switch identifier
    case "partA_online_fit"
        label = "Part A online";

    case "local_online_fit"
        label = "Local online";

    case "partA_fixed_fit"
        label = "Part A fixed";

    case "AR/None"
        label = "AR";

    otherwise
        label = replace(identifier, "_", " ");
end

end

function fig = local_new_figure(position)
%LOCAL_NEW_FIGURE Create one invisible white thesis figure.

fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', position, 'Color', 'w');

end

function local_export_and_close(fig, output_path)
%LOCAL_EXPORT_AND_CLOSE Export one vector PDF and close its figure.

exportgraphics(fig, output_path, 'ContentType', 'vector');
close(fig);

end

function series = local_line_series(x, y, color, line_style, label, line_width)
%LOCAL_LINE_SERIES Construct one shared-helper line series.

series = local_series_template();

series.type = "line";
series.x = x;
series.y = y;
series.color = color;
series.line_style = line_style;
series.label = label;
series.line_width = line_width;

end

function series = local_vertical_reference(boundary_date, values, style)
%LOCAL_VERTICAL_REFERENCE Construct a calibration/test boundary line.

minimum_value = min(values);
maximum_value = max(values);

if minimum_value == maximum_value
    maximum_value = minimum_value + eps(maximum_value);
end

series = local_line_series([boundary_date; boundary_date], [minimum_value; maximum_value], style.boundary_color, "--", "", style.reference_line_width);
series.type = "reference";

end

function series = local_series_template()
%LOCAL_SERIES_TEMPLATE Return a complete plot-series structure.

series = struct('type', "", 'x', [], 'y', [], 'lower', [], 'upper', [], 'label', "", 'color', [], 'line_style', "", 'line_width', [], 'marker', "", 'marker_size', [], 'face_color', [], 'face_alpha', []);

end

function axis_style = local_axis_style(x_label, y_label, style)
%LOCAL_AXIS_STYLE Construct shared axis styling.

axis_style = struct('x_label', x_label, 'y_label', y_label, 'grid', true, 'font_name', style.font_name, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size);

end

function local_panel_label(ax, label, style)
%LOCAL_PANEL_LABEL Add a compact panel identifier.

text(ax, 0.015, 0.97, label, 'Units', 'normalized', 'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', 'FontName', style.font_name, 'FontSize', style.panel_font_size, 'FontWeight', 'bold', 'Interpreter', 'tex');

end

function local_period_labels(ax, style)
%LOCAL_PERIOD_LABELS Label calibration and held-out regions.

text(ax, 0.25, 0.88, "Calibration", 'Units', 'normalized', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontName', style.font_name, 'FontSize', style.annotation_font_size, 'Color', style.annotation_color, 'Interpreter', 'tex');

text(ax, 0.80, 0.88, "Held-out", 'Units', 'normalized', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontName', style.font_name, 'FontSize', style.annotation_font_size, 'Color', style.annotation_color, 'Interpreter', 'tex');

end

function local_shared_legend(ax, handles, labels, style, num_columns)
%LOCAL_SHARED_LEGEND Place a boxless legend in the outer south tile.

legend_handle = legend(ax, handles, labels, 'Box', 'off', 'FontName', style.font_name, 'FontSize', style.legend_font_size, 'NumColumns', num_columns, 'Interpreter', 'tex');
legend_handle.Layout.Tile = 'south';

end

function local_axes_legend(ax, handles, labels, style, num_columns)
%LOCAL_AXES_LEGEND Place a boxless legend outside a single axes.

legend(ax, handles, labels, 'Location', 'southoutside', 'Box', 'off', 'FontName', style.font_name, 'FontSize', style.legend_font_size, 'NumColumns', num_columns, 'Interpreter', 'tex');

end

function color = local_model_color(model, style)
%LOCAL_MODEL_COLOR Return the fixed colour for one model.

if model == "AR"
    color = style.model.AR;
else
    color = style.model.ARX;
end

end

function labels = local_model_labels(models, exo_modes)
%LOCAL_MODEL_LABELS Return readable model/exogenous labels.

labels = strings(numel(models), 1);

for row_index = 1:numel(models)
    if models(row_index) == "AR"
        labels(row_index) = "AR / None";
    else
        labels(row_index) = local_model_label(models(row_index), exo_modes(row_index));
    end
end

end

function label = local_model_label(model, exo_mode)
%LOCAL_MODEL_LABEL Return one readable model/exogenous label.

if model == "AR"
    label = "AR";
else
    label = model + "/" + exo_mode;
end

end

function labels = local_strategy_labels(strategies)
%LOCAL_STRATEGY_LABELS Return readable strategy labels.

labels = strings(numel(strategies), 1);

for row_index = 1:numel(strategies)
    labels(row_index) = local_pretty_identity(strategies(row_index));
end

end

function light_color = local_lighten_color(color, amount)
%LOCAL_LIGHTEN_COLOR Mix one model colour with white.

light_color = color + amount * (1 - color);

end

function style = local_style()
%LOCAL_STYLE Define the consistent real-data thesis figure style.

style = struct();

style.font_name = "Arial";
style.axis_font_size = 9;
style.tick_font_size = 8;
style.legend_font_size = 8;
style.panel_font_size = 9;
style.title_font_size = 10;
style.annotation_font_size = 8;

style.line_width = 1.25;
style.target_line_width = 1.15;
style.forecast_line_width = 1.35;
style.reference_line_width = 0.9;

style.marker_size = 4.5;
style.pairwise_marker_size = 5.5;

style.data_color = [0.10, 0.10, 0.10];
style.boundary_color = [0.45, 0.45, 0.45];
style.annotation_color = [0.35, 0.35, 0.35];
style.proxy_recovered = [0.000, 0.620, 0.451];
style.pairwise_color = [0.337, 0.706, 0.914];

style.model = struct('AR', [0.000, 0.447, 0.698], 'ARX', [0.835, 0.369, 0.000]);

style.strategy_colors = [
    0.000, 0.447, 0.698
    0.835, 0.369, 0.000
    0.400, 0.400, 0.400
    ];

end