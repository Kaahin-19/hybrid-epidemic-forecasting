%PARTA_05_GENERATE_FIGURES Generate and export Part A thesis figures.
%
%   Description:
%       Loads finalized Part A truth, forecast, evaluation, and table
%       artifacts, then generates presentation figures only. Evaluation
%       tables and .mat artifacts are produced by Part A 04.
%
%   Workflow:
%       1. Load finalized truth, evaluation, and summary-table artifacts.
%       2. Build plot specifications and generic panel data.
%       3. Draw reusable visualization panels and export figure files.
%
%   See also PARTA_CONFIG, PARTA_04_EVALUATE_FORECASTS, BUILD_PLOT_SPEC, ...
%            EXPORT_FIGURE.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-05

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Figure Generation ===\n');

cfg = partA_config();
data_dir = cfg.output.data_dir;
forecast_dir = cfg.output.forecast_dir;
evaluation_dir = cfg.output.score_dir;
table_dir = cfg.output.table_dir;
figure_dir = cfg.output.fig_dir;

if ~exist(figure_dir, 'dir'), mkdir(figure_dir); end
evaluation_artifact = fullfile(evaluation_dir, 'partA_04_evaluation_results.mat');
if exist(evaluation_artifact, 'file') ~= 2
    error('FIG:MissingEvaluationArtifact', ...
        ['Missing Part A 04 evaluation artifact: %s\n' ...
        'Run scripts/partA/partA_04_evaluate_forecasts.m first.'], ...
        evaluation_artifact);
end

%% 2. Load Existing Artifacts
evaluation_data = load(evaluation_artifact);

truth_scenarios = local_load_truth_scenarios(data_dir);


window_scores = evaluation_data.window_scores;

table_cache = struct();
table_cache.model_summary = local_read_table_required( ...
    fullfile(table_dir, 'partA_04_model_summary.csv'));
table_cache.horizon_summary = local_read_table_required( ...
    fullfile(table_dir, 'partA_04_horizon_summary.csv'));
table_cache.interval_summary = local_read_table_required( ...
    fullfile(table_dir, 'partA_04_interval_summary.csv'));


fprintf('Loaded %d truth artifacts from %s\n', numel(truth_scenarios), data_dir);

%% 3. Scenario Trajectories
rt_spec = build_plot_spec( ...
    'figure_name', "Part A Rt scenarios", ...
    'shared_x_label', "Time, $t$ (days)", ...
    'shared_y_label', "Effective reproduction number, $R_t$", ...
    'panel_labels', local_panel_labels(numel(truth_scenarios)), ...
    'panel_label_style', struct('FontSize', 10, 'FontWeight', 'bold'), ...
    'y_limits', cfg.Rt.bounds, ...
    'output_path', fullfile(figure_dir, 'partA_05_rt_scenarios.png'), ...
    'size_cm', [17.0, 10.5]);
rt_panels = local_rt_scenario_panels(truth_scenarios, rt_spec);
fig = plot_multi_panel_figure(rt_panels, rt_spec);
export_figure(fig, rt_spec);
close(fig);

%% 4. Model WIS Distribution
performance_spec = build_plot_spec( ...
    'figure_name', "Part A model WIS distribution", ...
    'x_label', "Model / exogenous mode", ...
    'y_label', "Window WIS", ...
    'x_tick_rotation', 30, ...
    'color_order', local_thesis_color_order(), ...
    'output_path', fullfile(figure_dir, 'partA_05_model_wis_distribution.png'), ...
    'legend', struct('location', "northoutside", 'orientation', "horizontal", ...
        'box', "off", 'font_size', 9), ...
    'size_cm', [17.0, 9.5]);
performance_panel = local_model_wis_distribution_panel(window_scores);
local_export_single_panel(performance_panel, performance_spec);

%% 5. Horizon-Wise WIS
horizon_legend = struct( ...
    'labels', local_model_exo_labels(table_cache.horizon_summary), ...
    'location', "northoutside", ...
    'num_columns', 3, ...
    'box', "off", ...
    'font_size', 9);
horizon_spec = build_plot_spec( ...
    'figure_name', "Part A mean WIS by horizon", ...
    'x_label', "Forecast horizon, $h$ (days)", ...
    'y_label', "Mean WIS", ...
    'color_order', local_thesis_color_order(), ...
    'legend', horizon_legend, ...
    'output_path', fullfile(figure_dir, 'partA_05_mean_wis_by_horizon.png'), ...
    'size_cm', [17.0, 9.0]);
horizon_panel = local_horizon_wis_panel(table_cache.horizon_summary, horizon_spec);
local_export_single_panel(horizon_panel, horizon_spec);

%% 6. Coverage Summary
coverage_legend = struct( ...
    'labels', local_model_exo_labels(table_cache.interval_summary), ...
    'reference_label', "Nominal coverage", ...
    'location', "northoutside", ...
    'num_columns', 4, ...
    'box', "off", ...
    'font_size', 9);
coverage_spec = build_plot_spec( ...
    'figure_name', "Part A coverage summary", ...
    'x_label', "Nominal coverage", ...
    'y_label', "Empirical coverage", ...
    'color_order', local_thesis_color_order(), ...
    'legend', coverage_legend, ...
    'x_limits', [0, 1], ...
    'y_limits', [0, 1], ...
    'output_path', fullfile(figure_dir, 'partA_05_coverage_summary.png'), ...
    'size_cm', [16.0, 10.0]);
coverage_panel = local_coverage_panel(table_cache.interval_summary, coverage_spec);
local_export_single_panel(coverage_panel, coverage_spec);

%% 7. Forecast Comparisons for Every Global Configuration
configurations = local_all_configurations(table_cache.model_summary);
if isempty(configurations)
    error('FIG:NoModelConfigurations', ...
        'No model/exogenous configurations found in the Part A 04 model summary.');
end

for c = 1:numel(configurations)
    config = configurations(c);
    for i = 1:numel(truth_scenarios)
        scenario_id = string(truth_scenarios(i).scenario_id);
        [forecast_results, forecast_path] = local_load_forecast_results( ...
            forecast_dir, scenario_id, config.Model, config.ExoMode);

        plot_name = sprintf('partA_05_forecast_comparison_%s_%s_%s.png', ...
            char(local_safe_token(scenario_id)), ...
            char(local_safe_token(config.Model)), ...
            char(local_safe_token(config.ExoMode)));
        interval_labels = string(compose('%d%% PI', ...
            round((1 - sort(double(cfg.forecast.plot_alphas(:)))) * 100)));
        interval_labels = interval_labels(:);
        legend_spec = struct( ...
            'truth_label', "Ground truth", ...
            'median_label', "Median forecast", ...
            'interval_labels', interval_labels, ...
            'location', "northoutside", ...
            'orientation', "horizontal", ...
            'box', "off");

        comparison_spec = build_plot_spec( ...
            'figure_name', "Part A forecast comparison", ...
            'x_label', "Time, $t$ (days)", ...
            'y_label', "Effective reproduction number, $R_t$", ...
            'lead_time', cfg.forecast.plot_lead_time, ...
            'plot_alphas', cfg.forecast.plot_alphas, ...
            'y_limits', cfg.Rt.bounds, ...
            'legend', legend_spec, ...
            'output_path', fullfile(figure_dir, plot_name), ...
            'size_cm', [17.0, 9.0]);

        fprintf('Drawing comparison from %s\n', forecast_path);
        [comparison_panel, comparison_spec] = local_forecast_comparison_panel( ...
            forecast_results, truth_scenarios(i), comparison_spec);
        local_export_single_panel(comparison_panel, comparison_spec);
    end
end

%% 8. Completion
fprintf('Figures saved under %s\n', figure_dir);
fprintf('=== Part A Figure Generation Complete ===\n\n');

%% 9. Local Functions - Artifact Loading
function scenarios = local_load_truth_scenarios(data_dir)
%LOCAL_LOAD_TRUTH_SCENARIOS Load canonical Part A truth artifacts.
    truth_files = dir(fullfile(data_dir, 'partA_01_truth_*.mat'));
    truth_files = local_sort_dir_by_name(truth_files);
    if isempty(truth_files)
        error('FIG:NoTruthArtifacts', ...
            'No Part A truth artifacts found under %s.', data_dir);
    end

    scenarios = repmat(struct('scenario_id', "", 'scenario_name', "", ...
        'tspan', [], 'Rt_true', []), numel(truth_files), 1);

    for i = 1:numel(truth_files)
        artifact_path = fullfile(truth_files(i).folder, truth_files(i).name);
        loaded = load(artifact_path);
        scenarios(i).scenario_id = string(loaded.scenario_id);
        scenarios(i).scenario_name = string(loaded.scenario_name);
        scenarios(i).tspan = loaded.tspan;
        scenarios(i).Rt_true = loaded.Rt_true;
    end
end

function table_data = local_read_table_required(table_path)
%LOCAL_READ_TABLE_REQUIRED Read a required Part A table artifact.
    if exist(table_path, 'file') ~= 2
        error('FIG:MissingTableArtifact', ...
            ['Missing Part A 04 table artifact: %s\n' ...
            'Run scripts/partA/partA_04_evaluate_forecasts.m first.'], ...
            table_path);
    end
    table_data = readtable(table_path);
end

function [forecast_results, forecast_path] = local_load_forecast_results( ...
    forecast_dir, scenario_id, model_type, exo_mode)
%LOCAL_LOAD_FORECAST_RESULTS Load canonical forecast result arrays.
    filename = sprintf('partA_03_forecast_%s_%s_%s.mat', ...
        char(scenario_id), char(model_type), char(exo_mode));
    candidate_path = fullfile(forecast_dir, filename);
    if exist(candidate_path, 'file') ~= 2
        error('FIG:MissingForecastComparisonArtifact', ...
            'Missing forecast artifact for %s / %s / %s: %s', ...
            scenario_id, model_type, exo_mode, candidate_path);
    end

    loaded = load(candidate_path);
    forecast_path = string(candidate_path);
    if ~isfield(loaded, 'forecast_results') || isempty(loaded.forecast_results)
        error('FIG:InvalidForecastArtifact', ...
            'Forecast artifact has no forecast_results: %s', candidate_path);
    end
    forecast_results = loaded.forecast_results;
end

%% 10. Local Functions - Figure Export
function local_export_single_panel(panel_data, plot_spec)
%LOCAL_EXPORT_SINGLE_PANEL Draw, export, and close a single-panel figure.
    fig = plot_single_panel(panel_data, plot_spec);
    export_figure(fig, plot_spec);
    close(fig);
end

%% 11. Local Functions - Panel Assembly
function panels = local_rt_scenario_panels(scenarios, ~)
%LOCAL_RT_SCENARIO_PANELS Build generic panels for scenario trajectories.
    panels = repmat(struct('series', [], 'plot_spec', struct()), ...
        numel(scenarios), 1);

    for i = 1:numel(scenarios)
        [t_values, rt_values] = local_truth_curve(scenarios(i));
        series = local_empty_series(1);
        series.type = "line";
        series.x = t_values;
        series.y = rt_values;
        series.legend_visible = false;
        series.style = struct('Color', [], 'LineWidth', 1.3);

        panels(i).series = series;
        panels(i).plot_spec = struct('legend', struct('visible', false));
    end
end

function panel = local_model_wis_distribution_panel(window_scores)
%LOCAL_MODEL_WIS_DISTRIBUTION_PANEL Build a WIS boxchart panel.
    panel = struct('series', []);
    required_vars = {'WindowWIS', 'Model', 'ExoMode', 'Scenario'};
    if isempty(window_scores) || ~istable(window_scores) || ...
            height(window_scores) == 0 || ...
            ~all(ismember(required_vars, window_scores.Properties.VariableNames))
        return;
    end

    valid_idx = isfinite(window_scores.WindowWIS);
    if ~any(valid_idx)
        return;
    end

    plot_data = window_scores(valid_idx, :);
    config_label = string(plot_data.Model) + " / " + string(plot_data.ExoMode);

    series = local_empty_series(1);
    series.type = "boxchart";
    series.x = config_label;
    series.y = double(plot_data.WindowWIS);
    series.legend_rank = 1;
    series.group = string(plot_data.Scenario);
    series.legend_visible = true;
    panel.series = series;
end

function panel = local_horizon_wis_panel(horizon_scores, plot_spec)
%LOCAL_HORIZON_WIS_PANEL Build line series for horizon-wise WIS.
    panel = struct('series', []);
    required_vars = {'Model', 'ExoMode', 'HorizonIdx', 'MeanWIS'};
    if isempty(horizon_scores) || height(horizon_scores) == 0 || ...
            ~all(ismember(required_vars, horizon_scores.Properties.VariableNames))
        return;
    end

    group_ids = local_group_ids(horizon_scores);
    groups = unique(group_ids, 'stable');
    legend_labels = local_legend_labels(plot_spec, groups);
    series = local_empty_series(0);

    for i = 1:numel(groups)
        idx = group_ids == groups(i);
        x_values = double(horizon_scores.HorizonIdx(idx));
        y_values = double(horizon_scores.MeanWIS(idx));
        [x_values, y_values] = local_sorted_finite_xy(x_values, y_values);
        if isempty(x_values)
            continue;
        end

        next_series = local_empty_series(1);
        next_series.type = "line";
        next_series.x = x_values;
        next_series.y = y_values;
        next_series.label = legend_labels(i);
        next_series.style = struct('LineStyle', '-', 'LineWidth', 1.3, ...
            'Marker', local_series_marker(i), 'MarkerSize', 3.2);
        next_series.legend_rank = i;
        series(end + 1, 1) = next_series; %#ok<AGROW>
    end

    panel.series = series;
end

function panel = local_coverage_panel(interval_summary, plot_spec)
%LOCAL_COVERAGE_PANEL Build line series for empirical coverage.
    panel = struct('series', []);
    required_vars = {'Model', 'ExoMode', 'NominalCoverage', 'MeanCoverage'};
    if isempty(interval_summary) || height(interval_summary) == 0 || ...
            ~all(ismember(required_vars, interval_summary.Properties.VariableNames))
        return;
    end

    nominal_coverage = double(interval_summary.NominalCoverage);
    group_ids = local_group_ids(interval_summary);
    groups = unique(group_ids, 'stable');
    legend_labels = local_legend_labels(plot_spec, groups);
    series = local_empty_series(0);

    for i = 1:numel(groups)
        idx = group_ids == groups(i);
        x_values = double(nominal_coverage(idx));
        y_values = double(interval_summary.MeanCoverage(idx));
        [x_values, y_values] = local_sorted_finite_xy(x_values, y_values);
        if isempty(x_values)
            continue;
        end

        next_series = local_empty_series(1);
        next_series.type = "line";
        next_series.x = x_values;
        next_series.y = y_values;
        next_series.label = legend_labels(i);
        next_series.style = struct('LineStyle', '-', 'LineWidth', 1.3, ...
            'Marker', local_series_marker(i), 'MarkerSize', 3.2);
        next_series.legend_rank = i;
        series(end + 1, 1) = next_series; %#ok<AGROW>
    end

    valid_nominal = nominal_coverage(isfinite(nominal_coverage));
    if ~isempty(valid_nominal)
        reference_series = local_empty_series(1);
        reference_series.type = "line";
        reference_series.x = [min(valid_nominal), max(valid_nominal)];
        reference_series.y = reference_series.x;
        reference_series.label = string(plot_spec.legend.reference_label);
        reference_series.style = struct('Color', [0, 0, 0], ...
            'LineStyle', '--', 'LineWidth', 1.0);
        reference_series.legend_rank = numel(series) + 1;
        series(end + 1, 1) = reference_series;
    end

    panel.series = series;
end

function [panel, plot_spec] = local_forecast_comparison_panel( ...
    forecast_results, truth_curve, plot_spec)
%LOCAL_FORECAST_COMPARISON_PANEL Build Rt forecast-comparison series.
    [truth_t, truth_rt] = local_truth_curve(truth_curve);
    lead_time = round(double(plot_spec.lead_time));
    plot_alphas = sort(double(plot_spec.plot_alphas(:)))';

    [target_days, median_forecast, lower_forecast, upper_forecast] = ...
        local_extract_fixed_lead(forecast_results, lead_time, plot_alphas);

    series = local_empty_series(0);
    interval_labels = local_interval_labels(plot_spec, plot_alphas);
    interval_colors = local_interval_colors(numel(plot_alphas));
    interval_face_alpha = linspace(0.14, 0.28, max(1, numel(plot_alphas)));

    for j = 1:numel(plot_alphas)
        valid_interval = isfinite(target_days) & ...
            isfinite(lower_forecast(:, j)) & isfinite(upper_forecast(:, j));
        if nnz(valid_interval) < 2
            continue;
        end

        interval_series = local_empty_series(1);
        interval_series.type = "ribbon";
        interval_series.x = target_days(valid_interval);
        interval_series.lower = lower_forecast(valid_interval, j);
        interval_series.upper = upper_forecast(valid_interval, j);
        interval_series.label = interval_labels(j);
        interval_series.style = struct('FaceColor', interval_colors(j, :), ...
            'FaceAlpha', interval_face_alpha(j), 'EdgeColor', 'none');
        interval_series.legend_rank = 3 + j;
        series(end + 1, 1) = interval_series; %#ok<AGROW>
    end

    truth_series = local_empty_series(1);
    truth_series.type = "line";
    truth_series.x = truth_t;
    truth_series.y = truth_rt;
    truth_series.label = string(plot_spec.legend.truth_label);
    truth_series.style = struct('Color', [0, 0, 0], 'LineStyle', '-', ...
        'LineWidth', 1.4, 'Marker', 'none');
    truth_series.legend_rank = 1;
    series(end + 1, 1) = truth_series;

    valid_median = isfinite(target_days) & isfinite(median_forecast);
    if any(valid_median)
        median_series = local_empty_series(1);
        median_series.type = "line";
        median_series.x = target_days(valid_median);
        median_series.y = median_forecast(valid_median);
        median_series.label = string(plot_spec.legend.median_label);
        median_series.style = struct('Color', [0, 0, 1], 'LineStyle', '--', ...
            'LineWidth', 1.3, 'Marker', 'o', 'MarkerSize', 3.2);
        median_series.legend_rank = 2;
        series(end + 1, 1) = median_series;
    end

    if ~isfield(plot_spec, 'x_limits') || isempty(plot_spec.x_limits)
        plot_spec.x_limits = [truth_t(1), truth_t(end)];
    end
    panel = struct('series', series);
end

%% 12. Local Functions - Forecast Extraction
function [target_days, median_forecast, lower_forecast, upper_forecast] = ...
    local_extract_fixed_lead(forecast_results, lead_time, plot_alphas)
%LOCAL_EXTRACT_FIXED_LEAD Extract one forecast lead across windows.
    num_results = numel(forecast_results);
    num_alphas = numel(plot_alphas);

    target_days = nan(num_results, 1);
    median_forecast = nan(num_results, 1);
    lower_forecast = nan(num_results, num_alphas);
    upper_forecast = nan(num_results, num_alphas);

    for i = 1:num_results
        entry = local_normalize_result(forecast_results(i));
        if numel(entry.pred_Rt) < lead_time || numel(entry.forecast_day) < lead_time
            continue;
        end

        median_forecast(i) = entry.pred_Rt(lead_time);
        target_days(i) = entry.forecast_day(lead_time);

        for j = 1:num_alphas
            idx_alpha = local_alpha_index(entry.alphas, plot_alphas(j));
            if isempty(idx_alpha)
                continue;
            end
            if size(entry.lower_Rt, 1) >= lead_time && ...
                    size(entry.upper_Rt, 1) >= lead_time && ...
                    size(entry.lower_Rt, 2) >= idx_alpha && ...
                    size(entry.upper_Rt, 2) >= idx_alpha
                lower_forecast(i, j) = entry.lower_Rt(lead_time, idx_alpha);
                upper_forecast(i, j) = entry.upper_Rt(lead_time, idx_alpha);
            end
        end
    end
end

function entry = local_normalize_result(raw_entry)
%LOCAL_NORMALIZE_RESULT Read canonical forecast-result fields.
    entry = struct();
    entry.pred_Rt = double(raw_entry.Rt_pred(:));
    entry.lower_Rt = double(raw_entry.lower_bounds);
    entry.upper_Rt = double(raw_entry.upper_bounds);
    entry.alphas = double(raw_entry.interval_alphas(:));
    entry.forecast_day = double(raw_entry.t_future(:));
end

function idx = local_alpha_index(stored_alphas, target_alpha)
%LOCAL_ALPHA_INDEX Match a displayed alpha to stored intervals.
    stored_alphas = double(stored_alphas(:));
    [min_diff, idx] = min(abs(stored_alphas - target_alpha));
    if isempty(idx) || min_diff > 1e-8
        idx = [];
    end
end

%% 13. Local Functions - Plot Labels and Series Helpers
function series = local_empty_series(n)
%LOCAL_EMPTY_SERIES Create generic panel-series placeholders.
    series = repmat(struct('type', "line", 'x', [], 'y', [], ...
        'lower', [], 'upper', [], 'group', [], 'label', "", ...
        'style', struct(), 'legend_visible', true, 'legend_rank', 1), n, 1);
end

function [t_values, rt_values] = local_truth_curve(truth_curve)
%LOCAL_TRUTH_CURVE Extract a truth Rt trajectory.
    t_values = double(truth_curve.tspan(:));
    rt_values = double(truth_curve.Rt_true(:));
end

function labels = local_panel_labels(num_panels)
%LOCAL_PANEL_LABELS Build compact alphabetical panel labels.
    labels = strings(num_panels, 1);
    for i = 1:num_panels
        labels(i) = sprintf('(%s)', char('a' + i - 1));
    end
end

function labels = local_legend_labels(plot_spec, groups)
%LOCAL_LEGEND_LABELS Resolve plotted group labels.
    labels = string(plot_spec.legend.labels);
    labels = labels(1:numel(groups));
end

function labels = local_interval_labels(plot_spec, plot_alphas)
%LOCAL_INTERVAL_LABELS Resolve forecast-interval legend text.
    labels = string(plot_spec.legend.interval_labels);
    labels = labels(1:numel(plot_alphas));
end

function labels = local_model_exo_labels(summary_table)
%LOCAL_MODEL_EXO_LABELS Build model/exogenous legend labels.
    group_ids = local_group_ids(summary_table);
    labels = unique(group_ids, 'stable');
end

function marker = local_series_marker(idx)
%LOCAL_SERIES_MARKER Cycle distinguishable line markers.
    markers = {'o', 's', '^', 'd', 'v', '>', '<', 'p', 'h'};
    marker = markers{mod(idx - 1, numel(markers)) + 1};
end

function colors = local_thesis_color_order()
%LOCAL_THESIS_COLOR_ORDER Return the Part A figure colour order.
    colors = [
        0.902, 0.624, 0.000;   % orange
        0.337, 0.706, 0.914;   % sky blue
        0.000, 0.620, 0.451;   % bluish green
        0.000, 0.447, 0.698;   % blue
        0.835, 0.369, 0.000;   % vermillion
        0.800, 0.475, 0.655];  % reddish purple
end

function colors = local_interval_colors(num_intervals)
%LOCAL_INTERVAL_COLORS Build stable forecast-interval colours.
    base_colors = [0.30, 0.65, 0.95; 0.10, 0.45, 0.85; ...
        0.08, 0.32, 0.66; 0.04, 0.20, 0.46];
    if num_intervals <= size(base_colors, 1)
        colors = base_colors(1:num_intervals, :);
    else
        colors = lines(num_intervals);
    end
end

%% 14. Local Functions - Summary Tables and Utilities
function configurations = local_all_configurations(model_summary)
%LOCAL_ALL_CONFIGURATIONS List model/exogenous configurations.
    configurations = struct('Model', {}, 'ExoMode', {});
    if isempty(model_summary) || height(model_summary) == 0
        return;
    end

    config_ids = local_group_ids(model_summary);
    [~, unique_idx] = unique(config_ids, 'stable');
    num_configs = numel(unique_idx);
    configurations = repmat(struct('Model', "", 'ExoMode', ""), 1, num_configs);
    for k = 1:num_configs
        row_idx = unique_idx(k);
        configurations(k).Model = string(model_summary.Model(row_idx));
        configurations(k).ExoMode = string(model_summary.ExoMode(row_idx));
    end
end

function group_ids = local_group_ids(summary_table)
%LOCAL_GROUP_IDS Build model/exogenous group identifiers.
    group_ids = string(summary_table.Model) + " / " + string(summary_table.ExoMode);
end

function [x_values, y_values] = local_sorted_finite_xy(x_values, y_values)
%LOCAL_SORTED_FINITE_XY Filter finite points and sort by x value.
    x_values = double(x_values(:));
    y_values = double(y_values(:));
    valid_idx = isfinite(x_values) & isfinite(y_values);
    x_values = x_values(valid_idx);
    y_values = y_values(valid_idx);
    [x_values, order] = sort(x_values);
    y_values = y_values(order);
end

function token = local_safe_token(value)
%LOCAL_SAFE_TOKEN Convert values into filename-safe tokens.
    token = regexprep(string(value), '[^A-Za-z0-9]+', '_');
    token = regexprep(token, '^_+|_+$', '');
end

function sorted_files = local_sort_dir_by_name(files)
%LOCAL_SORT_DIR_BY_NAME Sort a dir struct by file name.
    if isempty(files)
        sorted_files = files;
        return;
    end
    [~, order] = sort({files.name});
    sorted_files = files(order);
end
