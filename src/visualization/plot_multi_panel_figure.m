function [fig, layout, axes_handles] = plot_multi_panel_figure(panel_data, plot_spec)
%PLOT_MULTI_PANEL_FIGURE Draw a reusable tiled multi-panel figure.
%
%   Syntax:
%       fig = plot_multi_panel_figure(panel_data, plot_spec)
%       [fig, layout, axes_handles] = plot_multi_panel_figure(panel_data, plot_spec)
%
%   Description:
%       Arranges a set of generic panel definitions in a tiled figure and
%       delegates each tile to plot_single_panel. The function is
%       domain-neutral: callers provide panel data, panel titles, panel
%       labels, layout dimensions, and display text through inputs.
%
%   Inputs:
%       panel_data - Struct array of panel definitions accepted by
%                    plot_single_panel. A panel may include a plot_spec field
%                    for panel-specific overrides.
%       plot_spec  - Plot specification from build_plot_spec.
%
%   Outputs:
%       fig          - Figure handle.
%       layout       - Tiled layout handle.
%       axes_handles - Axes handles for each tile.
%
%   See also PLOT_SINGLE_PANEL, BUILD_PLOT_SPEC.
%
% A. M. Kaahin 2026-06-02

    %% 1. Figure Setup
    if nargin < 1 || isempty(panel_data)
        panel_data = struct('series', []);
    end
    if nargin < 2 || isempty(plot_spec)
        plot_spec = build_plot_spec();
    end

    fig = figure('Name', char(local_spec_field(plot_spec, 'figure_name', ...
        "Multi-panel figure")), ...
        'Visible', char(local_spec_field(plot_spec, 'visible', "off")));
    local_apply_figure_size(fig, plot_spec);

    num_panels = numel(panel_data);
    [num_rows, num_cols] = local_layout_dimensions(num_panels, plot_spec);
    layout = tiledlayout(fig, num_rows, num_cols, ...
        'Padding', 'compact', 'TileSpacing', 'compact');

    label_size = local_spec_field(plot_spec, 'axis_label_font_size', ...
        local_spec_field(plot_spec, 'font_size', 10));

    title_text = local_spec_field(plot_spec, 'title', "");
    if strlength(title_text) > 0
        title(layout, title_text, 'Interpreter', local_text_interpreter(title_text), ...
            'FontWeight', 'normal', 'FontSize', double(label_size));
    end

    %% 2. Panel Drawing
    axes_handles = gobjects(num_panels, 1);
    for i = 1:num_panels
        ax = nexttile(layout);
        axes_handles(i) = ax;
        panel_spec = local_panel_plot_spec(panel_data(i), plot_spec, i);
        plot_single_panel(ax, panel_data(i), panel_spec);
    end

    %% 3. Shared Axis Labels
    local_apply_shared_labels(layout, plot_spec, label_size);
end

function local_apply_shared_labels(layout, plot_spec, label_size)
%LOCAL_APPLY_SHARED_LABELS Draw shared x/y labels on the tiled layout.
    shared_x = string(local_spec_field(plot_spec, 'shared_x_label', ""));
    shared_y = string(local_spec_field(plot_spec, 'shared_y_label', ""));
    if strlength(shared_x) > 0
        xlabel(layout, shared_x, 'Interpreter', local_text_interpreter(shared_x), ...
            'FontSize', double(label_size));
    end
    if strlength(shared_y) > 0
        ylabel(layout, shared_y, 'Interpreter', local_text_interpreter(shared_y), ...
            'FontSize', double(label_size));
    end
end

function [num_rows, num_cols] = local_layout_dimensions(num_panels, plot_spec)
%LOCAL_LAYOUT_DIMENSIONS Resolve tiled layout dimensions.
    layout_spec = local_spec_field(plot_spec, 'layout', struct());
    num_rows = local_layout_field(layout_spec, 'num_rows', []);
    num_cols = local_layout_field(layout_spec, 'num_cols', []);

    if isempty(num_rows)
        num_rows = local_spec_field(plot_spec, 'num_rows', []);
    end
    if isempty(num_cols)
        num_cols = local_spec_field(plot_spec, 'num_cols', []);
    end

    if isempty(num_rows) || isempty(num_cols)
        num_rows = max(1, ceil(sqrt(num_panels)));
        num_cols = max(1, ceil(num_panels / num_rows));
    else
        num_rows = max(1, round(double(num_rows)));
        num_cols = max(1, round(double(num_cols)));
    end
end

function panel_spec = local_panel_plot_spec(panel_data, plot_spec, idx)
%LOCAL_PANEL_PLOT_SPEC Merge global and panel-specific plot settings.
    panel_spec = plot_spec;
    panel_spec.title = local_panel_title(panel_data, plot_spec, idx);
    panel_spec.panel_label = local_panel_label(panel_data, plot_spec, idx);

    % Shared labels are drawn once on the layout, so suppress the per-panel
    % copies to avoid repeating long axis labels on every tile.
    if strlength(string(local_spec_field(plot_spec, 'shared_x_label', ""))) > 0
        panel_spec.x_label = "";
    end
    if strlength(string(local_spec_field(plot_spec, 'shared_y_label', ""))) > 0
        panel_spec.y_label = "";
    end

    if isfield(panel_data, 'plot_spec') && isstruct(panel_data.plot_spec)
        panel_spec = local_merge_struct(panel_spec, panel_data.plot_spec);
    end
end

function title_text = local_panel_title(panel_data, plot_spec, idx)
%LOCAL_PANEL_TITLE Resolve panel title text.
    if isfield(panel_data, 'plot_spec') && isstruct(panel_data.plot_spec) && ...
            isfield(panel_data.plot_spec, 'title') && ...
            ~isempty(panel_data.plot_spec.title)
        title_text = panel_data.plot_spec.title;
        return;
    end

    titles = local_spec_field(plot_spec, 'panel_titles', strings(0, 1));
    if numel(titles) >= idx && strlength(titles(idx)) > 0
        title_text = titles(idx);
    else
        title_text = "";
    end
end

function panel_label = local_panel_label(panel_data, plot_spec, idx)
%LOCAL_PANEL_LABEL Resolve optional panel label text.
    if isfield(panel_data, 'plot_spec') && isstruct(panel_data.plot_spec) && ...
            isfield(panel_data.plot_spec, 'panel_label') && ...
            ~isempty(panel_data.plot_spec.panel_label)
        panel_label = panel_data.plot_spec.panel_label;
        return;
    end

    panel_labels = local_spec_field(plot_spec, 'panel_labels', strings(0, 1));
    if numel(panel_labels) >= idx
        panel_label = panel_labels(idx);
    else
        panel_label = "";
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

function value = local_layout_field(layout_spec, field_name, default_value)
%LOCAL_LAYOUT_FIELD Read a layout-spec field with fallback.
    if isstruct(layout_spec) && isfield(layout_spec, field_name) && ...
            ~isempty(layout_spec.(field_name))
        value = layout_spec.(field_name);
    else
        value = default_value;
    end
end

function merged = local_merge_struct(base, override)
%LOCAL_MERGE_STRUCT Merge scalar structures.
    merged = base;
    fields = fieldnames(override);
    for i = 1:numel(fields)
        merged.(fields{i}) = override.(fields{i});
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

function interpreter = local_text_interpreter(text_value)
%LOCAL_TEXT_INTERPRETER Select text interpreter from label content.
    text_value = string(text_value);
    if any(contains(text_value, "$")) || any(contains(text_value, "\"))
        interpreter = 'latex';
    else
        interpreter = 'none';
    end
end
