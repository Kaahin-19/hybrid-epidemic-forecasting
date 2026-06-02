%PARTB_04_GENERATE_FIGURES Generate structural-mismatch figures.
%
%   Description:
%       Loads existing Part B structural-mismatch truth, forecast, and
%       evaluation artifacts, then generates visual diagnostics only. All
%       metric computation and table writing are handled by Part B 03.
%
%   Workflow:
%       1. Load computed evaluation, SEIR truth, and fixed forecast artifacts.
%       2. Build plot specifications with Part B presentation wording.
%       3. Draw reusable visualization functions and export figures.
%
%   See also PARTB_CONFIG, PARTB_03_EVALUATE_MODELS, BUILD_PLOT_SPEC, ...
%            PLOT_SINGLE_PANEL, PLOT_MULTI_PANEL_FIGURE, EXPORT_FIGURE.
%
% A. M. Kaahin 2026-06-02

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Structural-Mismatch Figure Generation ===\n');

cfg = partB_config();
data_dir = cfg.output.data_dir;
forecast_dir = cfg.output.forecast_dir;
evaluation_dir = cfg.output.score_dir;
figure_dir = cfg.output.fig_dir;

if ~exist(figure_dir, 'dir'), mkdir(figure_dir); end

evaluation_artifact = fullfile(evaluation_dir, ...
    sprintf('%s_evaluation_results.mat', char(cfg.experiment_id)));
if exist(evaluation_artifact, 'file') ~= 2
    error('FIG:MissingEvaluationArtifact', ...
        ['Missing Part B structural-mismatch evaluation artifact: %s\n' ...
        'Run scripts/partB/partB_03_evaluate_models.m first.'], ...
        evaluation_artifact);
end

%% 2. Load Existing Artifacts
evaluation_data = load(evaluation_artifact);
truth_scenarios = local_load_truth_scenarios(data_dir, cfg);
window_scores = evaluation_data.window_scores;
summary_tables = evaluation_data.summary_tables;

fprintf('Loaded %d truth artifacts from %s\n', numel(truth_scenarios), data_dir);

generated_figures = strings(0, 1);

%% 3. Fixed-Lead Rt Forecast Comparisons
forecast_cases = local_forecast_cases_from_scores(window_scores);
for c = 1:numel(forecast_cases)
    forecast_case = forecast_cases(c);
    panels = repmat(struct('series', [], 'plot_spec', struct()), ...
        numel(truth_scenarios), 1);

    for i = 1:numel(truth_scenarios)
        [forecast_results, forecast_path] = local_load_forecast_results( ...
            forecast_dir, truth_scenarios(i).scenario_id, ...
            forecast_case.Model, forecast_case.ExoMode, cfg);
        if isempty(forecast_results)
            warning('FIG:MissingForecastArtifact', ...
                'No forecast artifact found for %s / %s / %s.', ...
                truth_scenarios(i).scenario_id, forecast_case.Model, ...
                forecast_case.ExoMode);
            continue;
        end

        fprintf('Drawing comparison from %s\n', forecast_path);
        panel_spec = struct('title', local_panel_title(truth_scenarios(i)), ...
            'legend', struct('visible', i == 1, 'location', "northoutside", ...
            'orientation', "horizontal", 'box', "off", 'font_size', 8));
        panels(i).plot_spec = panel_spec;
        panels(i).series = local_forecast_comparison_series( ...
            forecast_results, truth_scenarios(i), cfg);
    end

    plot_name = sprintf('%s_rt_forecast_%s.png', char(cfg.experiment_id), ...
        char(local_model_token(forecast_case.Model, forecast_case.ExoMode)));
    forecast_spec = build_plot_spec( ...
        'figure_name', "Part B structural-mismatch Rt forecast", ...
        'title', "", ...
        'shared_x_label', "Time, $t$ (days)", ...
        'shared_y_label', "Effective reproduction number, $R_t$", ...
        'font_size', 9, ...
        'axis_label_font_size', 10, ...
        'tick_label_font_size', 8, ...
        'panel_labels', local_panel_labels(numel(truth_scenarios)), ...
        'panel_label_style', struct('FontSize', 10, 'FontWeight', 'bold'), ...
        'layout', struct('num_rows', 2, 'num_cols', 2), ...
        'x_limits', [cfg.time.tspan(1), cfg.time.tspan(end)], ...
        'y_limits', cfg.Rt.bounds, ...
        'lead_time', local_effective_lead_time(cfg), ...
        'plot_alphas', cfg.forecast.plot_alphas, ...
        'output_path', fullfile(figure_dir, plot_name), ...
        'size_cm', [17.0, 11.0]);

    fig = plot_multi_panel_figure(panels, forecast_spec);
    generated_figures = [generated_figures; export_figure(fig, forecast_spec)]; %#ok<AGROW>
    close(fig);
end

%% 4. Model Comparison
comparison_spec = build_plot_spec( ...
    'figure_name', "Part B structural-mismatch model comparison", ...
    'title', "", ...
    'x_label', "Fixed forecast configuration", ...
    'y_label', "Window WIS", ...
    'font_size', 9, ...
    'axis_label_font_size', 10, ...
    'tick_label_font_size', 9, ...
    'x_tick_rotation', 15, ...
    'color_order', local_thesis_color_order(), ...
    'legend', struct('location', "northoutside", 'orientation', "horizontal", ...
        'box', "off", 'font_size', 9), ...
        'output_path', fullfile(figure_dir, ...
        sprintf('%s_model_comparison.png', char(cfg.experiment_id))), ...
    'size_cm', [17.0, 9.0]);
comparison_panel = local_model_wis_distribution_panel(window_scores);
fig = plot_single_panel(comparison_panel, comparison_spec);
generated_figures = [generated_figures; export_figure(fig, comparison_spec)]; %#ok<AGROW>
close(fig);

%% 5. Horizon-Wise WIS
if isfield(summary_tables, 'horizon_summary') && ...
        ~isempty(summary_tables.horizon_summary) && ...
        height(summary_tables.horizon_summary) > 0
    horizon_legend = struct( ...
        'labels', local_model_exo_labels(summary_tables.horizon_summary), ...
        'location', "northoutside", ...
        'orientation', "horizontal", ...
        'box', "off", ...
        'font_size', 9);
    horizon_spec = build_plot_spec( ...
        'figure_name', "Part B structural-mismatch mean WIS by horizon", ...
        'title', "", ...
        'x_label', "Forecast horizon, $h$ (days)", ...
        'y_label', "Mean WIS", ...
        'font_size', 9, ...
        'axis_label_font_size', 10, ...
        'tick_label_font_size', 9, ...
        'color_order', local_thesis_color_order(), ...
        'legend', horizon_legend, ...
        'output_path', fullfile(figure_dir, ...
            sprintf('%s_mean_wis_by_horizon.png', char(cfg.experiment_id))), ...
        'size_cm', [17.0, 8.5]);
    horizon_panel = local_horizon_wis_panel(summary_tables.horizon_summary);
    fig = plot_single_panel(horizon_panel, horizon_spec);
    generated_figures = [generated_figures; export_figure(fig, horizon_spec)]; %#ok<AGROW>
    close(fig);
end

%% 6. Completion
fprintf('Saved %d figure files under %s\n', numel(generated_figures), figure_dir);
fprintf('=== Part B Structural-Mismatch Figure Generation Complete ===\n\n');

%% 7. Local Functions
function scenarios = local_load_truth_scenarios(data_dir, cfg)
%LOCAL_LOAD_TRUTH_SCENARIOS Load Part B structural-mismatch truth artifacts.
    truth_files = dir(fullfile(data_dir, sprintf('%s_truth_*.mat', ...
        char(cfg.experiment_id))));
    truth_files = local_sort_dir_by_name(truth_files);
    if isempty(truth_files)
        error('FIG:NoTruthArtifacts', ...
            'No structural-mismatch truth artifacts found under %s.', data_dir);
    end

    scenarios = repmat(struct('scenario_id', "", 'scenario_name', "", ...
        'tspan', [], 'Rt_true', []), numel(truth_files), 1);
    for i = 1:numel(truth_files)
        artifact_path = fullfile(truth_files(i).folder, truth_files(i).name);
        loaded = load(artifact_path);
        scenarios(i).scenario_id = string(loaded.scenario_id);
        scenarios(i).scenario_name = string(loaded.scenario_name);
        scenarios(i).tspan = double(loaded.tspan(:));
        scenarios(i).Rt_true = double(loaded.Rt_true(:));
    end
end

function cases = local_forecast_cases_from_scores(window_scores)
%LOCAL_FORECAST_CASES_FROM_SCORES List model/exogenous cases in score order.
    if isempty(window_scores) || height(window_scores) == 0
        cases = struct('Model', {}, 'ExoMode', {});
        return;
    end

    config_id = string(window_scores.Model) + " / " + string(window_scores.ExoMode);
    [~, idx] = unique(config_id, 'stable');
    cases = repmat(struct('Model', "", 'ExoMode', ""), numel(idx), 1);
    for i = 1:numel(idx)
        cases(i).Model = string(window_scores.Model(idx(i)));
        cases(i).ExoMode = string(window_scores.ExoMode(idx(i)));
    end
end

function [forecast_results, forecast_path] = local_load_forecast_results( ...
    forecast_dir, scenario_id, model_type, exo_mode, cfg)
%LOCAL_LOAD_FORECAST_RESULTS Load canonical forecast result arrays.
    forecast_results = [];
    forecast_path = "";
    filename = sprintf('%s_forecast_%s_%s_%s.mat', char(cfg.experiment_id), ...
        char(scenario_id), char(model_type), char(exo_mode));
    candidate_path = fullfile(forecast_dir, filename);
    if exist(candidate_path, 'file') ~= 2
        return;
    end

    loaded = load(candidate_path);
    forecast_path = string(candidate_path);
    if isfield(loaded, 'forecast_results') && ~isempty(loaded.forecast_results)
        forecast_results = loaded.forecast_results;
    end
end

function title_text = local_panel_title(truth_scenario)
%LOCAL_PANEL_TITLE Build compact scenario panel title text.
    title_text = sprintf('%s: %s', char(truth_scenario.scenario_id), ...
        char(truth_scenario.scenario_name));
end

function series = local_forecast_comparison_series(forecast_results, truth_curve, cfg)
%LOCAL_FORECAST_COMPARISON_SERIES Build generic Rt forecast comparison series.
    truth_t = double(truth_curve.tspan(:));
    truth_rt = double(truth_curve.Rt_true(:));
    lead_time = local_effective_lead_time(cfg);
    plot_alphas = sort(double(cfg.forecast.plot_alphas(:)))';

    [target_days, median_forecast, lower_forecast, upper_forecast] = ...
        local_extract_fixed_lead(forecast_results, lead_time, plot_alphas);

    series = local_empty_series(0);
    interval_labels = string(compose('%d%% PI', ...
        round((1 - plot_alphas(:)) * 100)));
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
    truth_series.label = "SEIR truth";
    truth_series.style = struct('Color', [0, 0, 0], 'LineStyle', '-', ...
        'LineWidth', 1.4, 'Marker', 'none');
    truth_series.legend_rank = 1;
    series(end + 1, 1) = truth_series; %#ok<AGROW>

    valid_median = isfinite(target_days) & isfinite(median_forecast);
    if any(valid_median)
        median_series = local_empty_series(1);
        median_series.type = "line";
        median_series.x = target_days(valid_median);
        median_series.y = median_forecast(valid_median);
        median_series.label = sprintf('%d-day median', lead_time);
        median_series.style = struct('Color', [0, 0.447, 0.698], ...
            'LineStyle', '--', 'LineWidth', 1.3, 'Marker', 'o', ...
            'MarkerSize', 3.0);
        median_series.legend_rank = 2;
        series(end + 1, 1) = median_series; %#ok<AGROW>
    end
end

function panel = local_model_wis_distribution_panel(window_scores)
%LOCAL_MODEL_WIS_DISTRIBUTION_PANEL Build a generic WIS boxchart panel.
    panel = struct('series', []);
    if isempty(window_scores) || ~istable(window_scores) || height(window_scores) == 0
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
    series.group = string(plot_data.Scenario);
    series.legend_visible = true;
    panel.series = series;
end

function panel = local_horizon_wis_panel(horizon_scores)
%LOCAL_HORIZON_WIS_PANEL Build generic line series for horizon-wise WIS.
    panel = struct('series', []);
    if isempty(horizon_scores) || height(horizon_scores) == 0 || ...
            ~ismember('HorizonIdx', horizon_scores.Properties.VariableNames)
        return;
    end

    group_ids = string(horizon_scores.Model) + " / " + string(horizon_scores.ExoMode);
    groups = unique(group_ids, 'stable');
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
        next_series.label = groups(i);
        next_series.style = struct('LineStyle', '-', 'LineWidth', 1.3, ...
            'Marker', local_series_marker(i), 'MarkerSize', 3.2);
        next_series.legend_rank = i;
        series(end + 1, 1) = next_series; %#ok<AGROW>
    end
    panel.series = series;
end

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
        if numel(entry.pred_Rt) < lead_time
            continue;
        end

        median_forecast(i) = entry.pred_Rt(lead_time);
        if numel(entry.forecast_day) >= lead_time
            target_days(i) = entry.forecast_day(lead_time);
        elseif isfinite(entry.window_day)
            target_days(i) = entry.window_day + lead_time;
        end

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
    entry.window_day = local_numeric_scalar(raw_entry, 'forecast_origin');
end

function value = local_numeric_scalar(raw_entry, field_name)
%LOCAL_NUMERIC_SCALAR Read a scalar numeric struct field.
    value = nan;
    if isfield(raw_entry, field_name) && ~isempty(raw_entry.(field_name))
        values = double(raw_entry.(field_name));
        value = values(1);
    end
end

function idx = local_alpha_index(stored_alphas, target_alpha)
%LOCAL_ALPHA_INDEX Match a displayed alpha to stored intervals.
    stored_alphas = double(stored_alphas(:));
    [min_diff, idx] = min(abs(stored_alphas - target_alpha));
    if isempty(idx) || min_diff > 1e-8
        idx = [];
    end
end

function lead_time = local_effective_lead_time(cfg)
%LOCAL_EFFECTIVE_LEAD_TIME Resolve displayed lead time.
    lead_time = min(cfg.forecast.plot_lead_time, cfg.forecast.horizon);
    if cfg.smoke_test.enabled
        lead_time = min(lead_time, cfg.smoke_test.horizon);
    end
end

function series = local_empty_series(n)
%LOCAL_EMPTY_SERIES Create generic panel-series placeholders.
    series = repmat(struct('type', "line", 'x', [], 'y', [], ...
        'lower', [], 'upper', [], 'group', [], 'label', "", ...
        'style', struct(), 'legend_visible', true, 'legend_rank', 1), n, 1);
end

function colors = local_thesis_color_order()
%LOCAL_THESIS_COLOR_ORDER Colour-blind-safe series palette.
    colors = [
        0.902, 0.624, 0.000;
        0.337, 0.706, 0.914;
        0.000, 0.620, 0.451;
        0.000, 0.447, 0.698;
        0.835, 0.369, 0.000;
        0.800, 0.475, 0.655];
end

function colors = local_interval_colors(num_intervals)
%LOCAL_INTERVAL_COLORS Build stable interval colors.
    base_colors = [0.30, 0.65, 0.95; 0.10, 0.45, 0.85; ...
        0.08, 0.32, 0.66; 0.04, 0.20, 0.46];
    if num_intervals <= size(base_colors, 1)
        colors = base_colors(1:num_intervals, :);
    else
        colors = lines(num_intervals);
    end
end

function marker = local_series_marker(idx)
%LOCAL_SERIES_MARKER Cycle distinguishable markers.
    markers = {'o', 's', '^', 'd', 'v', '>', '<', 'p', 'h'};
    marker = markers{mod(idx - 1, numel(markers)) + 1};
end

function labels = local_model_exo_labels(summary_table)
%LOCAL_MODEL_EXO_LABELS Build model/exogenous legend labels.
    if isempty(summary_table) || height(summary_table) == 0 || ...
            ~all(ismember({'Model', 'ExoMode'}, summary_table.Properties.VariableNames))
        labels = strings(0, 1);
        return;
    end
    group_ids = string(summary_table.Model) + " / " + string(summary_table.ExoMode);
    labels = unique(group_ids, 'stable');
end

function labels = local_panel_labels(num_panels)
%LOCAL_PANEL_LABELS Build compact alphabetical panel labels.
    labels = strings(num_panels, 1);
    for i = 1:num_panels
        labels(i) = sprintf('(%s)', char('a' + i - 1));
    end
end

function token = local_model_token(model_type, exo_mode)
%LOCAL_MODEL_TOKEN Build filename token for a model/exogenous case.
    if string(model_type) == "AR" && string(exo_mode) == "None"
        token = "ar";
    else
        token = lower(regexprep(string(model_type) + "_" + string(exo_mode), ...
            '[^A-Za-z0-9]+', '_'));
    end
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

function files = local_sort_dir_by_name(files)
%LOCAL_SORT_DIR_BY_NAME Sort a dir struct by file name.
    [~, order] = sort({files.name});
    files = files(order);
end
