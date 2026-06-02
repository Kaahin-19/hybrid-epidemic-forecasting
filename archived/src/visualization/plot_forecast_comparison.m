function fig = plot_forecast_comparison(forecast_results, truth_curve, plot_spec)
%PLOT_FORECAST_COMPARISON Draw fixed-lead forecast medians and intervals.
%
%   Syntax:
%       fig = plot_forecast_comparison(forecast_results, truth_curve, plot_spec)
%
%   Description:
%       Draws a fixed-lead forecast comparison against a supplied truth
%       trajectory. Presentation choices such as title text, labels, legend
%       text, lead time, intervals, limits, and export paths are supplied
%       through plot_spec.
%
%   Inputs:
%       forecast_results - Forecast window struct array.
%       truth_curve      - Struct with tspan/Rt_true or t/Rt fields.
%       plot_spec        - Plot specification from build_plot_spec.
%
%   Outputs:
%       fig - Figure handle.
%
%   See also BUILD_PLOT_SPEC, EXPORT_FIGURE.
%
% A. M. Kaahin 2026-06-01

    %% 1. Figure Setup
    if nargin < 3 || isempty(plot_spec)
        plot_spec = build_plot_spec();
    end

    fig = figure('Name', char(local_spec_field(plot_spec, 'figure_name', ...
        "Forecast comparison")), ...
        'Visible', char(local_spec_field(plot_spec, 'visible', "off")));
    local_apply_figure_size(fig, plot_spec);

    ax = axes(fig);
    hold(ax, 'on');

    %% 2. Data Extraction
    [truth_t, truth_rt] = local_truth_curve(truth_curve);
    lead_time = local_lead_time(plot_spec);
    plot_alphas = local_plot_alphas(forecast_results, plot_spec);

    [target_days, median_forecast, lower_forecast, upper_forecast] = ...
        local_extract_fixed_lead(forecast_results, lead_time, plot_alphas);

    %% 3. Plotting
    interval_handles = gobjects(0);
    interval_labels = local_interval_labels(plot_spec, plot_alphas);
    interval_colors = local_interval_colors(numel(plot_alphas));
    interval_face_alpha = linspace(0.14, 0.28, max(1, numel(plot_alphas)));

    for j = 1:numel(plot_alphas)
        valid_interval = isfinite(target_days) & ...
            isfinite(lower_forecast(:, j)) & isfinite(upper_forecast(:, j));
        if nnz(valid_interval) >= 2
            interval_handles(end + 1) = local_fill_interval(ax, ... %#ok<AGROW>
                target_days(valid_interval), lower_forecast(valid_interval, j), ...
                upper_forecast(valid_interval, j), interval_colors(j, :), ...
                interval_face_alpha(j), interval_labels(j));
        end
    end

    legend_spec = local_spec_field(plot_spec, 'legend', struct());
    truth_label = local_legend_field(legend_spec, 'truth_label', "Truth");
    median_label = local_legend_field(legend_spec, 'median_label', ...
        sprintf('%d-step-ahead median', lead_time));

    h_truth = plot(ax, truth_t, truth_rt, 'k-', 'LineWidth', 2.0, ...
        'DisplayName', char(truth_label));

    valid_median = isfinite(target_days) & isfinite(median_forecast);
    h_median = gobjects(0);
    if any(valid_median)
        h_median = plot(ax, target_days(valid_median), ...
            median_forecast(valid_median), 'b--o', 'LineWidth', 1.3, ...
            'MarkerSize', 3.2, 'DisplayName', char(median_label));
    end

    if isempty(h_median) && isempty(interval_handles)
        local_no_data_message(ax, plot_spec);
    end

    local_apply_labels(ax, plot_spec);
    local_apply_limits(ax, plot_spec);
    if isempty(local_spec_field(plot_spec, 'x_limits', []))
        xlim(ax, [truth_t(1), truth_t(end)]);
    end
    grid(ax, 'on');

    legend_handles = [h_truth, h_median, interval_handles];
    legend_handles = legend_handles(isgraphics(legend_handles));
    if ~isempty(legend_handles)
        location = local_legend_field(legend_spec, 'location', "best");
        legend(ax, legend_handles, 'Location', char(location));
    end
end

function [truth_t, truth_rt] = local_truth_curve(truth_curve)
%LOCAL_TRUTH_CURVE Extract a truth trajectory.
    if isfield(truth_curve, 'tspan')
        truth_t = double(truth_curve.tspan(:));
    else
        truth_t = double(truth_curve.t(:));
    end

    if isfield(truth_curve, 'Rt_true')
        truth_rt = double(truth_curve.Rt_true(:));
    else
        truth_rt = double(truth_curve.Rt(:));
    end
end

function lead_time = local_lead_time(plot_spec)
%LOCAL_LEAD_TIME Resolve fixed lead time.
    lead_time = local_spec_field(plot_spec, 'lead_time', 7);
    lead_time = round(double(lead_time));
    if ~isscalar(lead_time) || ~isfinite(lead_time) || lead_time < 1
        error('PLOT:InvalidLeadTime', ...
            'plot_spec.lead_time must be a positive scalar.');
    end
end

function plot_alphas = local_plot_alphas(forecast_results, plot_spec)
%LOCAL_PLOT_ALPHAS Resolve interval alphas to display.
    plot_alphas = double(local_spec_field(plot_spec, 'plot_alphas', []));
    plot_alphas = reshape(plot_alphas, 1, []);
    if isempty(plot_alphas)
        plot_alphas = local_first_available_alphas(forecast_results);
    end
    plot_alphas = sort(plot_alphas, 'ascend');
end

function alphas = local_first_available_alphas(forecast_results)
%LOCAL_FIRST_AVAILABLE_ALPHAS Read interval alphas from the first result.
    alphas = [];
    for i = 1:numel(forecast_results)
        entry = local_normalize_result(forecast_results(i));
        if ~isempty(entry.alphas)
            alphas = reshape(double(entry.alphas), 1, []);
            return;
        end
    end
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
%LOCAL_NORMALIZE_RESULT Read canonical or legacy forecast-result fields.
    entry = struct();
    if isfield(raw_entry, 'Rt_pred')
        entry.pred_Rt = double(raw_entry.Rt_pred(:));
        entry.lower_Rt = double(raw_entry.lower_bounds);
        entry.upper_Rt = double(raw_entry.upper_bounds);
        entry.alphas = double(raw_entry.interval_alphas(:));
        entry.forecast_day = double(raw_entry.t_future(:));
        entry.window_day = local_numeric_scalar(raw_entry, 'forecast_origin');
    else
        entry.pred_Rt = double(raw_entry.forecast_median(:));
        entry.lower_Rt = double(raw_entry.forecast_lower);
        entry.upper_Rt = double(raw_entry.forecast_upper);
        entry.alphas = double(raw_entry.forecast_interval_alphas(:));
        entry.forecast_day = double(raw_entry.time_horizon(:));
        entry.window_day = local_numeric_scalar(raw_entry, 'window_day');
    end
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

function labels = local_interval_labels(plot_spec, plot_alphas)
%LOCAL_INTERVAL_LABELS Resolve interval legend text.
    legend_spec = local_spec_field(plot_spec, 'legend', struct());
    if isstruct(legend_spec) && isfield(legend_spec, 'interval_labels')
        if numel(legend_spec) > 1
            labels = string({legend_spec.interval_labels});
        else
            labels = string(legend_spec.interval_labels);
        end
        if numel(labels) >= numel(plot_alphas)
            labels = labels(1:numel(plot_alphas));
            return;
        end
    end
    labels = strings(numel(plot_alphas), 1);
    for i = 1:numel(plot_alphas)
        labels(i) = sprintf('%d%% interval', round((1 - plot_alphas(i)) * 100));
    end
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

function h = local_fill_interval(ax, t_fcst, lower_bound, upper_bound, ...
    face_color, face_alpha, display_name)
%LOCAL_FILL_INTERVAL Draw one predictive interval ribbon.
    h = fill(ax, [t_fcst(:); flipud(t_fcst(:))], ...
        [upper_bound(:); flipud(lower_bound(:))], face_color, ...
        'FaceAlpha', face_alpha, 'EdgeColor', 'none', ...
        'DisplayName', char(display_name));
end

function local_apply_labels(ax, plot_spec)
%LOCAL_APPLY_LABELS Apply optional title and axis labels.
    title_text = local_spec_field(plot_spec, 'title', "");
    if strlength(title_text) > 0
        title(ax, title_text, 'Interpreter', local_text_interpreter(title_text));
    end
    x_label = local_spec_field(plot_spec, 'x_label', "");
    y_label = local_spec_field(plot_spec, 'y_label', "");
    xlabel(ax, x_label, 'Interpreter', local_text_interpreter(x_label));
    ylabel(ax, y_label, 'Interpreter', local_text_interpreter(y_label));
end

function local_no_data_message(ax, plot_spec)
%LOCAL_NO_DATA_MESSAGE Draw an empty-data placeholder.
    text(ax, 0.5, 0.5, local_spec_field(plot_spec, 'no_data_text', ...
        "No finite forecast data"), 'HorizontalAlignment', 'center', ...
        'Units', 'normalized');
end

function value = local_spec_field(plot_spec, field_name, default_value)
%LOCAL_SPEC_FIELD Read a plot-spec field with fallback.
    if isfield(plot_spec, field_name) && ~isempty(plot_spec.(field_name))
        value = plot_spec.(field_name);
    else
        value = default_value;
    end
end

function value = local_legend_field(legend_spec, field_name, default_value)
%LOCAL_LEGEND_FIELD Read a legend field with fallback.
    if isstruct(legend_spec) && isfield(legend_spec, field_name) && ...
            ~isempty(legend_spec.(field_name))
        value = string(legend_spec.(field_name));
    else
        value = string(default_value);
    end
end

function interpreter = local_text_interpreter(text_value)
%LOCAL_TEXT_INTERPRETER Select text interpreter from label content.
    text_value = string(text_value);
    if any(contains(text_value, "$")) || any(contains(text_value, "\"))
        interpreter = 'latex';
    else
        interpreter = 'none';
    end
end

function local_apply_figure_size(fig, plot_spec)
%LOCAL_APPLY_FIGURE_SIZE Apply centimeter figure dimensions.
    size_cm = local_spec_field(plot_spec, 'size_cm', []);
    if isempty(size_cm) || numel(size_cm) ~= 2
        return;
    end
    fig.Units = 'centimeters';
    fig.Position(3:4) = double(size_cm);
end

function local_apply_limits(ax, plot_spec)
%LOCAL_APPLY_LIMITS Apply optional axis limits.
    x_limits = local_spec_field(plot_spec, 'x_limits', []);
    y_limits = local_spec_field(plot_spec, 'y_limits', []);
    if ~isempty(x_limits), xlim(ax, double(x_limits)); end
    if ~isempty(y_limits), ylim(ax, double(y_limits)); end
end
