function [handles, labels] = plot_distribution(ax, spec)
%PLOT_DISTRIBUTION Draw a grouped boxchart distribution into an axes.
%
%   Syntax:
%       [handles, labels] = plot_distribution(ax, spec)
%
%   Description:
%       Draws a grouped boxchart (one box per category, colored by an
%       optional grouping variable) into a caller-supplied axes, then applies
%       shared panel styling via APPLY_PANEL_STYLE. The function never creates
%       figures, never sets a title, and never saves files.
%
%   Inputs:
%       ax   - Target axes handle.
%       spec - Struct with fields:
%                x           - Per-observation category labels (string).
%                y           - Per-observation numeric values.
%                group       - Per-observation grouping labels (string), or [].
%                color_order - N-by-3 RGB color order for the groups.
%                style       - Style options forwarded to APPLY_PANEL_STYLE.
%
%   Outputs:
%       handles - BoxChart handles (one per color group) for a shared legend.
%       labels  - Group labels matching handles.
%
%   See also APPLY_PANEL_STYLE, PLOT_SERIES.
%
% A. M. Kaahin 2026-06-22

%% 1. Draw Grouped Boxchart
if isfield(spec, 'color_order') && ~isempty(spec.color_order)
    colororder(ax, spec.color_order);
end

x_cat = categorical(spec.x);
if isfield(spec, 'group') && ~isempty(spec.group)
    group_cat = categorical(spec.group);
    handles = boxchart(ax, x_cat, spec.y, 'GroupByColor', group_cat, 'MarkerStyle', '.', 'MarkerSize', 3);
    labels = string(categories(group_cat));
else
    handles = boxchart(ax, x_cat, spec.y, 'MarkerStyle', '.', 'MarkerSize', 3);
    labels = strings(0, 1);
end

%% 2. Apply Shared Styling
if isfield(spec, 'style')
    apply_panel_style(ax, spec.style);
else
    apply_panel_style(ax, struct());
end
end
