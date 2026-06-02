function varargout = plot_rt_forecast_comparison(varargin)
%PLOT_RT_FORECAST_COMPARISON Draw an Rt truth/forecast comparison.
%
%   Syntax:
%       fig = plot_rt_forecast_comparison(forecast_results, truth_curve, plot_spec)
%       [fig, ax] = plot_rt_forecast_comparison(ax, forecast_results, truth_curve, plot_spec)
%       outPath = plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg)
%
%   Description:
%       Converts Rt truth and forecast results into generic panel-series data
%       and delegates rendering to plot_single_panel. The five-input syntax
%       is retained for older scripts.
%
%   Inputs:
%       forecast_results - Forecast window struct array, or empty for truth only.
%       truth_curve      - Struct with tspan/Rt_true or t/Rt fields.
%       plot_spec        - Plot specification from build_plot_spec.
%
%   Outputs:
%       fig     - Figure handle for the generic plotting syntax.
%       ax      - Axes handle when requested.
%       outPath - Saved path for the legacy five-input syntax.
%
%   See also PLOT_SINGLE_PANEL, BUILD_PLOT_SPEC, EXPORT_FIGURE.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-06-02

    %% 1. Input Parsing
    if local_is_legacy_call(varargin{:})
        outPath = local_plot_legacy(varargin{:});
        if nargout > 0
            varargout{1} = outPath;
        end
        return;
    end

    [ax, forecast_results, truth_curve, plot_spec] = ...
        local_parse_generic_inputs(varargin{:});

    %% 2. Generic Panel Assembly
    [panel_data, plot_spec] = local_forecast_panel_data( ...
        forecast_results, truth_curve, plot_spec);

    %% 3. Rendering
    if isempty(ax)
        [fig, ax] = plot_single_panel(panel_data, plot_spec);
    else
        [fig, ax] = plot_single_panel(ax, panel_data, plot_spec);
    end

    %% 4. Output Assembly
    if nargout > 0
        varargout{1} = fig;
    end
    if nargout > 1
        varargout{2} = ax;
    end
end

function [ax, forecast_results, truth_curve, plot_spec] = ...
    local_parse_generic_inputs(varargin)
%LOCAL_PARSE_GENERIC_INPUTS Parse reusable plotting syntax.
    ax = [];
    arg_idx = 1;
    if nargin >= 1 && local_is_axes(varargin{1})
        ax = varargin{1};
        arg_idx = 2;
    end

    if nargin < arg_idx + 1
        error('PLOT:InvalidInputs', ...
            ['Expected forecast results, truth curve, and optional ' ...
            'plot specification.']);
    end

    forecast_results = varargin{arg_idx};
    truth_curve = varargin{arg_idx + 1};
    if nargin >= arg_idx + 2 && ~isempty(varargin{arg_idx + 2})
        plot_spec = varargin{arg_idx + 2};
    else
        plot_spec = build_plot_spec();
    end

    if ~isstruct(plot_spec)
        error('PLOT:InvalidPlotSpec', 'plot_spec must be a structure.');
    end
end

function tf = local_is_legacy_call(varargin)
%LOCAL_IS_LEGACY_CALL Detect the older export-oriented call signature.
    tf = nargin == 5 && ~local_is_axes(varargin{1}) && ...
        isnumeric(varargin{2}) && isnumeric(varargin{3}) && ...
        (ischar(varargin{4}) || isstring(varargin{4})) && ...
        isstruct(varargin{5});
end

function tf = local_is_axes(value)
%LOCAL_IS_AXES Return true for axes-like graphics handles.
    tf = false;
    try
        candidate = isgraphics(value, 'axes');
        tf = isscalar(candidate) && candidate;
    catch
        tf = false;
    end
end

function [panel_data, plot_spec] = local_forecast_panel_data( ...
    forecast_results, truth_curve, plot_spec)
%LOCAL_FORECAST_PANEL_DATA Convert Rt forecasts into generic panel series.
    [truth_t, truth_rt] = local_truth_curve(truth_curve);
    has_forecasts = ~isempty(forecast_results);
    series = local_empty_series(0);

    if has_forecasts
        forecast_series = local_forecast_series(forecast_results, truth_t, ...
            plot_spec);
        [interval_series, median_series] = ...
            local_split_forecast_series(forecast_series);
        series = [series; interval_series]; %#ok<AGROW>
    end

    truth_series = local_empty_series(1);
    truth_series.type = "line";
    truth_series.x = truth_t;
    truth_series.y = truth_rt;
    truth_series.label = local_truth_label(plot_spec);
    truth_series.style = local_truth_style(plot_spec);
    truth_series.legend_rank = 1;
    series = [series; truth_series]; %#ok<AGROW>

    if has_forecasts
        series = [series; median_series]; %#ok<AGROW>
    end

    if has_forecasts && isempty(local_spec_field(plot_spec, 'x_limits', []))
        plot_spec.x_limits = [truth_t(1), truth_t(end)];
    end

    if ~isfield(plot_spec, 'figure_name') || strlength(string(plot_spec.figure_name)) == 0
        plot_spec.figure_name = "Rt forecast comparison";
    end
    panel_data = struct('series', series);
end

function [interval_series, median_series] = local_split_forecast_series( ...
    forecast_series)
%LOCAL_SPLIT_FORECAST_SERIES Separate ribbons from the median line.
    interval_series = local_empty_series(0);
    median_series = local_empty_series(0);
    if isempty(forecast_series)
        return;
    end

    ranks = double([forecast_series.legend_rank]);
    median_idx = ranks == 2;
    interval_series = forecast_series(~median_idx);
    median_series = forecast_series(median_idx);
end

function forecast_series = local_forecast_series(forecast_results, truth_t, ...
    plot_spec)
%LOCAL_FORECAST_SERIES Build interval and median series.
    lead_time = local_lead_time(plot_spec);
    plot_alphas = local_plot_alphas(forecast_results, plot_spec);
    [target_days, median_forecast, lower_forecast, upper_forecast] = ...
        local_extract_fixed_lead(forecast_results, lead_time, plot_alphas);

    forecast_series = local_empty_series(0);
    interval_labels = local_interval_labels(plot_spec, plot_alphas);
    interval_colors = local_interval_colors(numel(plot_alphas), plot_spec);
    interval_face_alpha = local_interval_face_alpha(numel(plot_alphas), ...
        plot_spec);

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
        interval_series.legend_rank = 2 + j;
        forecast_series(end + 1, 1) = interval_series; %#ok<AGROW>
    end

    valid_median = isfinite(target_days) & isfinite(median_forecast);
    if any(valid_median)
        median_series = local_empty_series(1);
        median_series.type = "line";
        median_series.x = target_days(valid_median);
        median_series.y = median_forecast(valid_median);
        median_series.label = local_median_label(plot_spec, lead_time);
        median_series.style = local_median_style(plot_spec);
        median_series.legend_rank = 2;
        forecast_series(end + 1, 1) = median_series; %#ok<AGROW>
    elseif ~isempty(truth_t)
        forecast_series = forecast_series(:);
    end
end

function series = local_empty_series(n)
%LOCAL_EMPTY_SERIES Create generic panel-series placeholders.
    series = repmat(struct('type', "line", 'x', [], 'y', [], ...
        'lower', [], 'upper', [], 'label', "", 'style', struct(), ...
        'legend_visible', true, 'legend_rank', 1), n, 1);
end

function [truth_t, truth_rt] = local_truth_curve(truth_curve)
%LOCAL_TRUTH_CURVE Extract an Rt trajectory.
    if isfield(truth_curve, 'tspan')
        truth_t = double(truth_curve.tspan(:));
    elseif isfield(truth_curve, 't')
        truth_t = double(truth_curve.t(:));
    else
        error('PLOT:MissingTruthTime', ...
            'truth_curve must contain tspan or t.');
    end

    if isfield(truth_curve, 'Rt_true')
        truth_rt = double(truth_curve.Rt_true(:));
    elseif isfield(truth_curve, 'Rt')
        truth_rt = double(truth_curve.Rt(:));
    else
        error('PLOT:MissingTruthRt', ...
            'truth_curve must contain Rt_true or Rt.');
    end

    if numel(truth_t) ~= numel(truth_rt) || isempty(truth_t)
        error('PLOT:InvalidTruthCurve', ...
            'Truth time and Rt vectors must be nonempty and equally sized.');
    end
end

function label = local_truth_label(plot_spec)
%LOCAL_TRUTH_LABEL Resolve truth legend text.
    legend_spec = local_spec_field(plot_spec, 'legend', struct());
    label = local_legend_field(legend_spec, 'truth_label', "Truth");
end

function label = local_median_label(plot_spec, lead_time)
%LOCAL_MEDIAN_LABEL Resolve median forecast legend text.
    legend_spec = local_spec_field(plot_spec, 'legend', struct());
    label = local_legend_field(legend_spec, 'median_label', ...
        sprintf('%d-step-ahead median', lead_time));
end

function style = local_truth_style(plot_spec)
%LOCAL_TRUTH_STYLE Resolve truth-line style.
    default_style = struct('Color', [0, 0, 0], 'LineStyle', '-', ...
        'LineWidth', 2.0, 'Marker', 'none');
    style = local_merge_struct(default_style, ...
        local_spec_field(plot_spec, 'truth_style', struct()));
end

function style = local_median_style(plot_spec)
%LOCAL_MEDIAN_STYLE Resolve median-line style.
    default_style = struct('Color', [0, 0, 1], 'LineStyle', '--', ...
        'LineWidth', 1.3, 'Marker', 'o', 'MarkerSize', 3.2);
    style = local_merge_struct(default_style, ...
        local_spec_field(plot_spec, 'median_style', struct()));
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

function colors = local_interval_colors(num_intervals, plot_spec)
%LOCAL_INTERVAL_COLORS Build stable interval colors.
    colors = local_spec_field(plot_spec, 'interval_colors', []);
    if ~isempty(colors)
        colors = double(colors);
        if size(colors, 1) >= num_intervals && size(colors, 2) == 3
            colors = colors(1:num_intervals, :);
            return;
        end
    end

    base_colors = [0.30, 0.65, 0.95; 0.10, 0.45, 0.85; ...
        0.08, 0.32, 0.66; 0.04, 0.20, 0.46];
    if num_intervals <= size(base_colors, 1)
        colors = base_colors(1:num_intervals, :);
    else
        colors = lines(num_intervals);
    end
end

function face_alpha = local_interval_face_alpha(num_intervals, plot_spec)
%LOCAL_INTERVAL_FACE_ALPHA Resolve interval transparency.
    face_alpha = local_spec_field(plot_spec, 'interval_face_alpha', []);
    if ~isempty(face_alpha)
        face_alpha = reshape(double(face_alpha), 1, []);
        if numel(face_alpha) >= num_intervals
            face_alpha = face_alpha(1:num_intervals);
            return;
        end
    end
    face_alpha = linspace(0.14, 0.28, max(1, num_intervals));
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

function merged = local_merge_struct(base, override)
%LOCAL_MERGE_STRUCT Merge scalar style/spec structures.
    merged = base;
    if ~isstruct(override)
        return;
    end
    fields = fieldnames(override);
    for i = 1:numel(fields)
        merged.(fields{i}) = override.(fields{i});
    end
end

function outPath = local_plot_legacy(results, Rt_true, tspan, plot_name, cfg)
%LOCAL_PLOT_LEGACY Preserve the older export-oriented interface.
    fig_dir = local_legacy_fig_dir(cfg);
    lead_time = local_legacy_lead_time(cfg);
    plot_alphas = local_legacy_plot_alphas(cfg);
    y_limits = local_legacy_y_limits(cfg);
    outPath = fullfile(fig_dir, sprintf('forecast_plot_%s.png', ...
        char(local_safe_token(plot_name))));

    plot_spec = build_plot_spec( ...
        'figure_name', "Rt forecast comparison", ...
        'title', sprintf('%d-step-ahead forecast comparison: %s', ...
            lead_time, strrep(char(string(plot_name)), '_', ' ')), ...
        'x_label', "Time (days)", ...
        'y_label', "$\mathcal{R}_t$", ...
        'output_path', outPath, ...
        'lead_time', lead_time, ...
        'plot_alphas', plot_alphas, ...
        'y_limits', y_limits, ...
        'legend', struct('truth_label', "Truth", ...
        'median_label', sprintf('%d-step-ahead median', lead_time), ...
        'location', "northwest"));

    truth_curve = struct('tspan', tspan, 'Rt_true', Rt_true);
    fig = plot_rt_forecast_comparison(results, truth_curve, plot_spec);
    output_paths = export_figure(fig, plot_spec);
    close(fig);
    outPath = char(output_paths(1));
end

function fig_dir = local_legacy_fig_dir(cfg)
%LOCAL_LEGACY_FIG_DIR Resolve legacy output directory.
    if isfield(cfg, 'output') && isfield(cfg.output, 'fig_dir')
        fig_dir = cfg.output.fig_dir;
    else
        fig_dir = fullfile(pwd, 'results', 'figures');
    end
end

function lead_time = local_legacy_lead_time(cfg)
%LOCAL_LEGACY_LEAD_TIME Resolve legacy fixed lead time.
    lead_time = 7;
    if isfield(cfg, 'forecast') && isfield(cfg.forecast, 'plot_lead_time')
        lead_time = double(cfg.forecast.plot_lead_time);
    end

    if ~isscalar(lead_time) || ~isfinite(lead_time) || lead_time < 1
        error('PLOT:InvalidLeadTime', ...
            'Forecast plot lead time must be a positive scalar.');
    end

    lead_time = round(lead_time);
end

function plot_alphas = local_legacy_plot_alphas(cfg)
%LOCAL_LEGACY_PLOT_ALPHAS Resolve legacy interval alphas.
    plot_alphas = [];
    if isfield(cfg, 'forecast') && isfield(cfg.forecast, 'plot_alphas')
        plot_alphas = cfg.forecast.plot_alphas;
    end
end

function y_limits = local_legacy_y_limits(cfg)
%LOCAL_LEGACY_Y_LIMITS Resolve legacy Rt limits.
    y_limits = [];
    if isfield(cfg, 'Rt') && isfield(cfg.Rt, 'bounds')
        y_limits = cfg.Rt.bounds;
    end
end

function token = local_safe_token(value)
%LOCAL_SAFE_TOKEN Convert display values into filename-safe tokens.
    token = regexprep(string(value), '[^A-Za-z0-9]+', '_');
    token = regexprep(token, '^_+|_+$', '');
end
