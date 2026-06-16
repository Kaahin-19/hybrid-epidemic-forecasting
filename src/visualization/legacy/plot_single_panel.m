function [fig, ax, handles] = plot_single_panel(varargin)
%PLOT_SINGLE_PANEL Draw one reusable visualization panel.
%
%   Syntax:
%       fig = plot_single_panel(panel_data, plot_spec)
%       [fig, ax, handles] = plot_single_panel(panel_data, plot_spec)
%       [fig, ax, handles] = plot_single_panel(ax, panel_data, plot_spec)
%
%   Description:
%       Draws a single axes from generic series definitions. The function is
%       intentionally domain-neutral: callers provide the data series,
%       labels, legend entries, axis limits, panel labels, and styling
%       through panel_data and plot_spec.
%
%   Inputs:
%       ax         - Optional target axes for tiled layouts.
%       panel_data - Structure with a series field containing line, scatter,
%                    or ribbon series definitions.
%       plot_spec  - Plot specification from build_plot_spec.
%
%   Outputs:
%       fig     - Figure handle.
%       ax      - Axes handle.
%       handles - Graphics handles drawn for data series.
%
%   See also PLOT_MULTI_PANEL_FIGURE, BUILD_PLOT_SPEC.
%
% A. M. Kaahin 2026-06-02

    %% 1. Input Parsing
    [ax, panel_data, plot_spec] = local_parse_inputs(varargin{:});

    %% 2. Figure and Axes Setup
    if isempty(ax)
        fig = figure('Name', char(local_spec_field(plot_spec, ...
            'figure_name', "Single panel")), ...
            'Visible', char(local_spec_field(plot_spec, 'visible', "off")));
        local_apply_figure_size(fig, plot_spec);
        ax = axes(fig);
    else
        fig = ancestor(ax, 'figure');
    end
    hold(ax, 'on');
    local_apply_color_order(ax, plot_spec);

    %% 3. Series Drawing
    series = local_panel_series(panel_data);
    handles = gobjects(0);
    legend_handles = gobjects(0);
    legend_ranks = zeros(0, 1);

    for i = 1:numel(series)
        [h, legend_rank] = local_draw_series(ax, series(i), i);
        if ~isempty(h) && all(isgraphics(h))
            handles = [handles; h(:)]; %#ok<AGROW>
            if local_series_in_legend(series(i))
                legend_handles = [legend_handles; h(:)]; %#ok<AGROW>
                legend_ranks = [legend_ranks; ...
                    repmat(legend_rank, numel(h), 1)]; %#ok<AGROW>
            end
        end
    end

    %% 4. Panel Decoration
    if isempty(handles)
        local_no_data_message(ax, plot_spec);
        return;
    end

    local_apply_fonts(ax, plot_spec);
    local_apply_labels(ax, plot_spec);
    local_apply_limits(ax, plot_spec);
    local_apply_grid(ax, plot_spec);
    local_apply_tick_rotation(ax, plot_spec);
    local_apply_panel_label(ax, plot_spec);
    local_apply_legend(ax, plot_spec, legend_handles, legend_ranks);
end

function local_apply_color_order(ax, plot_spec)
%LOCAL_APPLY_COLOR_ORDER Apply an optional axes colour order before drawing.
    color_order = local_spec_field(plot_spec, 'color_order', []);
    if ~isempty(color_order)
        set(ax, 'ColorOrder', double(color_order));
    end
end

function local_apply_tick_rotation(ax, plot_spec)
%LOCAL_APPLY_TICK_ROTATION Apply an optional x-tick-label rotation.
    rotation = local_spec_field(plot_spec, 'x_tick_rotation', []);
    if ~isempty(rotation)
        ax.XTickLabelRotation = double(rotation);
    end
end

function [ax, panel_data, plot_spec] = local_parse_inputs(varargin)
%LOCAL_PARSE_INPUTS Parse axes-aware input syntax.
    ax = [];
    arg_idx = 1;
    if nargin >= 1 && local_is_axes(varargin{1})
        ax = varargin{1};
        arg_idx = 2;
    end

    if nargin < arg_idx
        panel_data = struct('series', []);
    else
        panel_data = varargin{arg_idx};
    end

    if nargin >= arg_idx + 1 && ~isempty(varargin{arg_idx + 1})
        plot_spec = varargin{arg_idx + 1};
    else
        plot_spec = build_plot_spec();
    end

    if isempty(panel_data)
        panel_data = struct('series', []);
    end
    if ~isstruct(panel_data)
        error('PLOT:InvalidPanelData', 'panel_data must be a structure.');
    end
    if ~isstruct(plot_spec)
        error('PLOT:InvalidPlotSpec', 'plot_spec must be a structure.');
    end
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

function series = local_panel_series(panel_data)
%LOCAL_PANEL_SERIES Resolve generic series definitions.
    if isfield(panel_data, 'series')
        series = panel_data.series;
    elseif all(isfield(panel_data, {'x', 'y'}))
        series = panel_data;
    else
        series = struct([]);
    end
end

function [h, legend_rank] = local_draw_series(ax, series, idx)
%LOCAL_DRAW_SERIES Draw one typed series definition.
    series_type = lower(char(local_series_field(series, 'type', "line")));
    legend_rank = double(local_series_field(series, 'legend_rank', idx));

    switch series_type
        case {'line', 'reference'}
            h = local_draw_line(ax, series);
        case 'scatter'
            h = local_draw_scatter(ax, series);
        case {'ribbon', 'fill_between', 'interval'}
            h = local_draw_ribbon(ax, series);
        case {'boxchart', 'box'}
            h = local_draw_boxchart(ax, series);
        otherwise
            error('PLOT:UnsupportedSeriesType', ...
                'Unsupported panel series type: %s.', series_type);
    end
end

function h = local_draw_line(ax, series)
%LOCAL_DRAW_LINE Draw a line series.
    [x_values, y_values] = local_xy_values(series);
    valid_idx = isfinite(x_values) & isfinite(y_values);
    h = gobjects(0);
    if ~any(valid_idx)
        return;
    end

    style = local_series_style(series);
    default_style = struct('LineStyle', '-', 'LineWidth', 1.3);
    style = local_merge_struct(default_style, style);
    style_args = local_style_args(style);
    h = plot(ax, x_values(valid_idx), y_values(valid_idx), style_args{:}, ...
        'DisplayName', char(local_series_label(series)));
end

function h = local_draw_scatter(ax, series)
%LOCAL_DRAW_SCATTER Draw a scatter series.
    [x_values, y_values] = local_xy_values(series);
    valid_idx = isfinite(x_values) & isfinite(y_values);
    h = gobjects(0);
    if ~any(valid_idx)
        return;
    end

    style = local_series_style(series);
    marker_size = local_style_field(style, 'MarkerSize', 18);
    color = local_style_field(style, 'Color', []);
    if isempty(color)
        h = scatter(ax, x_values(valid_idx), y_values(valid_idx), ...
            marker_size, 'DisplayName', char(local_series_label(series)));
    else
        h = scatter(ax, x_values(valid_idx), y_values(valid_idx), ...
            marker_size, color, 'DisplayName', char(local_series_label(series)));
    end
end

function h = local_draw_ribbon(ax, series)
%LOCAL_DRAW_RIBBON Draw a filled lower/upper interval series.
    x_values = double(local_series_field(series, 'x', []));
    lower_values = double(local_series_field(series, 'lower', []));
    upper_values = double(local_series_field(series, 'upper', []));
    x_values = x_values(:);
    lower_values = lower_values(:);
    upper_values = upper_values(:);

    n = min([numel(x_values), numel(lower_values), numel(upper_values)]);
    x_values = x_values(1:n);
    lower_values = lower_values(1:n);
    upper_values = upper_values(1:n);
    valid_idx = isfinite(x_values) & isfinite(lower_values) & ...
        isfinite(upper_values);

    h = gobjects(0);
    if nnz(valid_idx) < 2
        return;
    end

    style = local_series_style(series);
    face_color = local_style_field(style, 'FaceColor', ...
        local_style_field(style, 'Color', [0.30, 0.65, 0.95]));
    face_alpha = local_style_field(style, 'FaceAlpha', 0.20);
    edge_color = local_style_field(style, 'EdgeColor', 'none');

    x_plot = x_values(valid_idx);
    lower_plot = lower_values(valid_idx);
    upper_plot = upper_values(valid_idx);
    h = fill(ax, [x_plot(:); flipud(x_plot(:))], ...
        [upper_plot(:); flipud(lower_plot(:))], face_color, ...
        'FaceAlpha', face_alpha, 'EdgeColor', edge_color, ...
        'DisplayName', char(local_series_label(series)));
end

function h = local_draw_boxchart(ax, series)
%LOCAL_DRAW_BOXCHART Draw a grouped boxchart series.
    x_values = local_series_field(series, 'x', []);
    y_values = double(local_series_field(series, 'y', []));
    group_values = local_series_field(series, 'group', []);
    y_values = y_values(:);

    n = min(numel(x_values), numel(y_values));
    x_values = x_values(1:n);
    y_values = y_values(1:n);
    if ~isempty(group_values)
        group_values = group_values(1:n);
    end

    valid_idx = isfinite(y_values);
    h = gobjects(0);
    if ~any(valid_idx)
        return;
    end

    x_plot = categorical(string(x_values(valid_idx)));
    y_plot = y_values(valid_idx);
    style = local_series_style(series);
    style_args = local_style_args(style);

    if isempty(group_values)
        h = boxchart(ax, x_plot, y_plot, style_args{:});
    else
        group_plot = categorical(string(group_values(valid_idx)));
        h = boxchart(ax, x_plot, y_plot, 'GroupByColor', group_plot, ...
            style_args{:});
    end
end

function [x_values, y_values] = local_xy_values(series)
%LOCAL_XY_VALUES Read x/y vectors from a line-like series.
    x_values = double(local_series_field(series, 'x', []));
    y_values = double(local_series_field(series, 'y', []));
    x_values = x_values(:);
    y_values = y_values(:);
    n = min(numel(x_values), numel(y_values));
    x_values = x_values(1:n);
    y_values = y_values(1:n);
end

function label = local_series_label(series)
%LOCAL_SERIES_LABEL Resolve one legend label.
    label = "";
    if isfield(series, 'label') && ~isempty(series.label)
        label = string(series.label);
    end
end

function style = local_series_style(series)
%LOCAL_SERIES_STYLE Resolve one style structure.
    style = struct();
    if isfield(series, 'style') && isstruct(series.style)
        style = series.style;
    end
end

function tf = local_series_in_legend(series)
%LOCAL_SERIES_IN_LEGEND Resolve whether a series appears in the legend.
    label = local_series_label(series);
    default_value = strlength(label) > 0;
    visible = local_series_field(series, 'legend_visible', default_value);
    if ischar(visible) || isstring(visible)
        tf = ~any(strcmpi(string(visible), ["off", "false", "none", "no"]));
    else
        tf = logical(visible);
    end
end

function value = local_series_field(series, field_name, default_value)
%LOCAL_SERIES_FIELD Read a series field with fallback.
    if isfield(series, field_name) && ~isempty(series.(field_name))
        value = series.(field_name);
    else
        value = default_value;
    end
end

function value = local_spec_field(plot_spec, field_name, default_value)
%LOCAL_SPEC_FIELD Read a plot-spec field with fallback.
    if isfield(plot_spec, field_name) && ~isempty(plot_spec.(field_name))
        value = plot_spec.(field_name);
    else
        value = default_value;
    end
end

function value = local_style_field(style_spec, field_name, default_value)
%LOCAL_STYLE_FIELD Read a style field with fallback.
    if isstruct(style_spec) && isfield(style_spec, field_name) && ...
            ~isempty(style_spec.(field_name))
        value = style_spec.(field_name);
    else
        value = default_value;
    end
end

function args = local_style_args(style_spec)
%LOCAL_STYLE_ARGS Convert a style struct to MATLAB name-value arguments.
    args = {};
    if ~isstruct(style_spec)
        return;
    end

    fields = fieldnames(style_spec);
    for i = 1:numel(fields)
        value = style_spec.(fields{i});
        if isempty(value)
            continue;
        end
        if isstring(value) && isscalar(value)
            value = char(value);
        end
        args = [args, {char(local_style_property(fields{i})), value}]; %#ok<AGROW>
    end
end

function property_name = local_style_property(field_name)
%LOCAL_STYLE_PROPERTY Map shorthand style names to MATLAB properties.
    key = lower(strrep(char(field_name), '_', ''));
    switch key
        case 'color'
            property_name = "Color";
        case 'linestyle'
            property_name = "LineStyle";
        case 'linewidth'
            property_name = "LineWidth";
        case 'marker'
            property_name = "Marker";
        case 'markersize'
            property_name = "MarkerSize";
        case 'markerfacecolor'
            property_name = "MarkerFaceColor";
        case 'markeredgecolor'
            property_name = "MarkerEdgeColor";
        otherwise
            property_name = string(field_name);
    end
end

function merged = local_merge_struct(base, override)
%LOCAL_MERGE_STRUCT Merge scalar structures.
    merged = base;
    if ~isstruct(override)
        return;
    end
    fields = fieldnames(override);
    for i = 1:numel(fields)
        merged.(fields{i}) = override.(fields{i});
    end
end

function local_apply_fonts(ax, plot_spec)
%LOCAL_APPLY_FONTS Apply base font name and tick-label font sizes to an axes.
    base_size = local_spec_field(plot_spec, 'font_size', 9);
    tick_size = local_spec_field(plot_spec, 'tick_label_font_size', base_size);
    set(ax, 'FontName', local_font_name(plot_spec), 'FontSize', double(tick_size), ...
        'LabelFontSizeMultiplier', 1.0, 'TitleFontSizeMultiplier', 1.0);
end

function font_name = local_font_name(plot_spec)
%LOCAL_FONT_NAME Resolve a consistent figure font name.
    font_name = string(local_spec_field(plot_spec, 'font_name', "Helvetica"));
    if strlength(font_name) == 0
        font_name = "Helvetica";
    end
    font_name = char(font_name);
end

function local_apply_labels(ax, plot_spec)
%LOCAL_APPLY_LABELS Apply optional title and axis labels.
    label_size = local_axis_label_font_size(plot_spec);
    title_size = local_spec_field(plot_spec, 'title_font_size', label_size);
    title_text = local_spec_field(plot_spec, 'title', "");
    if strlength(title_text) > 0
        title(ax, title_text, 'Interpreter', local_text_interpreter(title_text), ...
            'FontWeight', 'normal', 'FontSize', double(title_size));
    end
    x_label = local_spec_field(plot_spec, 'x_label', "");
    y_label = local_spec_field(plot_spec, 'y_label', "");
    xlabel(ax, x_label, 'Interpreter', local_text_interpreter(x_label), ...
        'FontSize', double(label_size));
    ylabel(ax, y_label, 'Interpreter', local_text_interpreter(y_label), ...
        'FontSize', double(label_size));
end

function label_size = local_axis_label_font_size(plot_spec)
%LOCAL_AXIS_LABEL_FONT_SIZE Resolve the axis-label font size.
    label_size = local_spec_field(plot_spec, 'axis_label_font_size', ...
        local_spec_field(plot_spec, 'font_size', 10));
end

function local_apply_limits(ax, plot_spec)
%LOCAL_APPLY_LIMITS Apply optional axis limits.
    x_limits = local_spec_field(plot_spec, 'x_limits', []);
    y_limits = local_spec_field(plot_spec, 'y_limits', []);
    if ~isempty(x_limits), xlim(ax, double(x_limits)); end
    if ~isempty(y_limits), ylim(ax, double(y_limits)); end
end

function local_apply_grid(ax, plot_spec)
%LOCAL_APPLY_GRID Resolve grid visibility.
    grid_value = local_spec_field(plot_spec, 'grid', true);
    if ischar(grid_value) || isstring(grid_value)
        enabled = ~any(strcmpi(string(grid_value), ...
            ["off", "false", "none", "no"]));
    else
        enabled = logical(grid_value);
    end
    if enabled
        grid(ax, 'on');
    else
        grid(ax, 'off');
    end
end

function local_apply_panel_label(ax, plot_spec)
%LOCAL_APPLY_PANEL_LABEL Draw an optional panel annotation.
    panel_label = local_spec_field(plot_spec, 'panel_label', "");
    if strlength(string(panel_label)) == 0
        return;
    end

    label_style = local_spec_field(plot_spec, 'panel_label_style', struct());
    font_size = local_style_field(label_style, 'FontSize', 10);
    font_weight = local_style_field(label_style, 'FontWeight', 'bold');
    text(ax, 0.02, 0.95, panel_label, 'Units', 'normalized', ...
        'VerticalAlignment', 'top', 'HorizontalAlignment', 'left', ...
        'FontName', local_font_name(plot_spec), ...
        'FontSize', font_size, 'FontWeight', font_weight, ...
        'Interpreter', local_text_interpreter(panel_label));
end

function local_apply_legend(ax, plot_spec, legend_handles, legend_ranks)
%LOCAL_APPLY_LEGEND Draw a legend when requested.
    legend_spec = local_spec_field(plot_spec, 'legend', struct());
    if ~local_legend_visible(legend_spec) || isempty(legend_handles)
        return;
    end

    [~, order] = sort(legend_ranks, 'ascend');
    legend_handles = legend_handles(order);
    legend_handles = legend_handles(isgraphics(legend_handles));
    if isempty(legend_handles)
        return;
    end

    location = local_legend_field(legend_spec, 'location', "best");
    lgd = legend(ax, legend_handles, 'Location', char(location));

    orientation = local_legend_field(legend_spec, 'orientation', "");
    if strlength(orientation) > 0
        lgd.Orientation = char(orientation);
    end
    if isstruct(legend_spec) && isfield(legend_spec, 'box') && ...
            ~isempty(legend_spec.box)
        lgd.Box = local_on_off(legend_spec.box);
    end
    if isstruct(legend_spec) && isfield(legend_spec, 'num_columns') && ...
            ~isempty(legend_spec.num_columns)
        lgd.NumColumns = double(legend_spec.num_columns);
    end
    if isstruct(legend_spec) && isfield(legend_spec, 'font_size') && ...
            ~isempty(legend_spec.font_size)
        lgd.FontSize = double(legend_spec.font_size);
    else
        lgd.FontSize = double(local_spec_field(plot_spec, 'tick_label_font_size', ...
            local_spec_field(plot_spec, 'font_size', 9)));
    end
    lgd.FontName = local_font_name(plot_spec);
end

function value = local_on_off(flag)
%LOCAL_ON_OFF Convert a logical or string flag to an 'on'/'off' value.
    if ischar(flag) || isstring(flag)
        if any(strcmpi(string(flag), ["off", "false", "none", "no"]))
            value = 'off';
        else
            value = 'on';
        end
    elseif logical(flag)
        value = 'on';
    else
        value = 'off';
    end
end

function visible = local_legend_visible(legend_spec)
%LOCAL_LEGEND_VISIBLE Resolve legend visibility.
    visible = true;
    if ~isstruct(legend_spec) || ~isfield(legend_spec, 'visible') || ...
            isempty(legend_spec.visible)
        return;
    end

    visible_value = legend_spec.visible;
    if ischar(visible_value) || isstring(visible_value)
        visible = ~any(strcmpi(string(visible_value), ...
            ["off", "false", "none", "no"]));
    else
        visible = logical(visible_value);
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

function local_no_data_message(ax, plot_spec)
%LOCAL_NO_DATA_MESSAGE Draw an empty-data placeholder.
    axis(ax, 'off');
    title_text = local_spec_field(plot_spec, 'title', "");
    if strlength(title_text) > 0
        title(ax, title_text, 'Interpreter', local_text_interpreter(title_text));
    end
    text(ax, 0.5, 0.5, local_spec_field(plot_spec, 'no_data_text', ...
        "No finite data"), 'HorizontalAlignment', 'center', ...
        'Units', 'normalized');
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

function interpreter = local_text_interpreter(text_value)
%LOCAL_TEXT_INTERPRETER Select text interpreter from label content.
    text_value = string(text_value);
    if any(contains(text_value, "$")) || any(contains(text_value, "\"))
        interpreter = 'latex';
    else
        interpreter = 'none';
    end
end
