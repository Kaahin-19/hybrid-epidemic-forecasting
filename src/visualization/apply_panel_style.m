function apply_panel_style(ax, opts)

%APPLY_PANEL_STYLE Apply shared conservative panel styling to an axes.
%
%   Syntax:
%       apply_panel_style(ax, opts)
%
%   Description:
%       Applies the shared thesis panel style to a caller-supplied axes,
%       including fonts, labels, limits, color order, tick rotation, and grid
%       settings. PLOT_SERIES and PLOT_DISTRIBUTION apply this style after
%       drawing their data.
%
%   Inputs:
%       ax   - Target axes handle.
%       opts - Struct of optional style fields:
%                x_label, y_label   - Axis label text (tex interpreter).
%                x_limits, y_limits - Axis limits, [min max].
%                grid               - Logical; light grid when true.
%                color_order        - N-by-3 RGB color order.
%                x_tick_rotation    - X tick label rotation in degrees.
%                font_name          - Font family (default "Arial").
%                axis_font_size     - Axis label font size (default 9).
%                tick_font_size     - Tick label font size (default 8).
%
%   Outputs:
%       None.
%
%   See also PARTB_04_GENERATE_FIGURES, PLOT_SERIES, PLOT_DISTRIBUTION.
%
% A. M. Kaahin 2026-06-22
% Modified: 2026-08-23

%% 1. Resolve Style Options
font_name      = local_opt(opts, 'font_name', "Arial");
axis_font_size = local_opt(opts, 'axis_font_size', 9);
tick_font_size = local_opt(opts, 'tick_font_size', 8);

%% 2. Base Axis Styling
set(ax, 'FontName', font_name, 'FontSize', tick_font_size, 'TickLabelInterpreter', 'tex', 'Box', 'on', 'Layer', 'top');

if isfield(opts, 'color_order') && ~isempty(opts.color_order)
    colororder(ax, opts.color_order);
end

%% 3. Labels, Limits, and Tick Rotation
if isfield(opts, 'x_label') && strlength(opts.x_label) > 0
    xlabel(ax, opts.x_label, 'Interpreter', 'tex', 'FontName', font_name, 'FontSize', axis_font_size);
end
if isfield(opts, 'y_label') && strlength(opts.y_label) > 0
    ylabel(ax, opts.y_label, 'Interpreter', 'tex', 'FontName', font_name, 'FontSize', axis_font_size);
end
if isfield(opts, 'x_limits') && ~isempty(opts.x_limits)
    xlim(ax, opts.x_limits);
end
if isfield(opts, 'y_limits') && ~isempty(opts.y_limits)
    ylim(ax, opts.y_limits);
end
if isfield(opts, 'x_tick_rotation') && ~isempty(opts.x_tick_rotation)
    ax.XTickLabelRotation = opts.x_tick_rotation;
end

%% 4. Grid
if isfield(opts, 'grid') && opts.grid
    grid(ax, 'on');
    ax.GridAlpha = 0.12;
    ax.GridLineStyle = ':';
else
    grid(ax, 'off');
end
end

%% 5. Local Functions
function value = local_opt(opts, name, default_value)
%LOCAL_OPT Return an option field value or its default.
if isfield(opts, name) && ~isempty(opts.(name))
    value = opts.(name);
else
    value = default_value;
end
end
