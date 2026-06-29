function [handles, labels] = plot_series(ax, spec)
%PLOT_SERIES Draw line, ribbon, and reference series into an axes.
%
%   Syntax:
%       [handles, labels] = plot_series(ax, spec)
%
%   Description:
%       Draws an ordered set of line, interval-ribbon, and reference-line
%       series into a caller-supplied axes, then applies shared panel styling
%       via APPLY_PANEL_STYLE. The function never creates figures or tiled
%       layouts, never sets a title, and never saves files. Series are drawn
%       in the order given, so callers place ribbon bands before line series
%       to keep the fills behind the lines in vector output.
%
%   Inputs:
%       ax   - Target axes handle.
%       spec - Struct with fields:
%                series - Struct array of series to draw. Each element has:
%                           type  - "line", "reference", or "ribbon".
%                           x     - X data (column).
%                           y     - Y data, line/reference (column).
%                           lower - Lower band, ribbon (column).
%                           upper - Upper band, ribbon (column).
%                           label - Legend text ("" omits from legend).
%                         Optional style fields: color, line_style,
%                         line_width, marker, marker_size (line/reference);
%                         face_color, face_alpha (ribbon).
%                style  - Style options forwarded to APPLY_PANEL_STYLE.
%
%   Outputs:
%       handles - Graphics handles of labelled series, for a shared legend.
%       labels  - Legend text matching handles.
%
%   See also APPLY_PANEL_STYLE, PLOT_DISTRIBUTION.
%
% A. M. Kaahin 2026-06-29

%% 1. Draw Series In Order
was_held = ishold(ax);
hold(ax, 'on');

n_series = numel(spec.series);
handles = gobjects(n_series, 1);
labels = strings(n_series, 1);
n_labelled = 0;

for i = 1:n_series
    s = spec.series(i);

    if s.type == "ribbon"
        h = local_draw_ribbon(ax, s);
    else
        h = local_draw_line(ax, s);
    end

    if isfield(s, 'label')
        label = string(s.label);

        if strlength(label) > 0
            n_labelled = n_labelled + 1;
            handles(n_labelled, 1) = h;
            labels(n_labelled, 1) = label;
        end
    end
end

handles = handles(1:n_labelled, 1);
labels = labels(1:n_labelled, 1);

if ~was_held
    hold(ax, 'off');
end

%% 2. Apply Shared Styling
if isfield(spec, 'style')
    apply_panel_style(ax, spec.style);
else
    apply_panel_style(ax, struct());
end
end

function h = local_draw_line(ax, s)
%LOCAL_DRAW_LINE Draw a single line or reference series.
args = {};

if isfield(s, 'color') && ~isempty(s.color)
    args = [args, {'Color', s.color}];
end
if isfield(s, 'line_style') && strlength(s.line_style) > 0
    args = [args, {'LineStyle', s.line_style}];
end
if isfield(s, 'line_width') && ~isempty(s.line_width)
    args = [args, {'LineWidth', s.line_width}];
end
if isfield(s, 'marker') && strlength(s.marker) > 0
    args = [args, {'Marker', s.marker}];
end
if isfield(s, 'marker_size') && ~isempty(s.marker_size)
    args = [args, {'MarkerSize', s.marker_size}];
end

h = plot(ax, s.x, s.y, args{:});
end

function h = local_draw_ribbon(ax, s)
%LOCAL_DRAW_RIBBON Draw a shaded interval band between lower and upper bounds.
x_patch = [s.x; flipud(s.x)];
y_patch = [s.lower; flipud(s.upper)];

face_color = local_series_field(s, 'face_color', [0.6, 0.6, 0.6]);
face_alpha = local_series_field(s, 'face_alpha', 1);

h = fill(ax, x_patch, y_patch, face_color, ...
    'FaceAlpha', face_alpha, 'EdgeColor', 'none');
end

function value = local_series_field(s, name, default_value)
%LOCAL_SERIES_FIELD Return a series field value or its default.
if isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = default_value;
end
end