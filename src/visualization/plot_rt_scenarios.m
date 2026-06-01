function fig = plot_rt_scenarios(scenarios, plot_spec)
%PLOT_RT_SCENARIOS Draw synthetic effective-Rt scenario trajectories.
%
%   Syntax:
%       fig = plot_rt_scenarios(scenarios, plot_spec)
%
%   Description:
%       Draws a tiled figure of scenario Rt trajectories. Presentation choices
%       such as title text, axis labels, scenario labels, and axis limits are
%       read from plot_spec so the function remains reusable.
%
%   Inputs:
%       scenarios - Struct array with tspan/Rt_true or t/Rt fields.
%       plot_spec - Plot specification from build_plot_spec.
%
%   Outputs:
%       fig - Figure handle.
%
%   See also BUILD_PLOT_SPEC, EXPORT_FIGURE.
%
% A. M. Kaahin 2026-02-18
% Modified: 2026-06-01

    %% 1. Figure Setup
    if nargin < 2 || isempty(plot_spec)
        plot_spec = build_plot_spec();
    end

    fig = figure('Name', char(local_spec_field(plot_spec, 'figure_name', "Rt scenarios")), ...
        'Visible', char(local_spec_field(plot_spec, 'visible', "off")));
    local_apply_figure_size(fig, plot_spec);

    num_scenarios = numel(scenarios);
    num_rows = max(1, ceil(sqrt(num_scenarios)));
    num_cols = max(1, ceil(num_scenarios / num_rows));
    layout = tiledlayout(fig, num_rows, num_cols, ...
        'Padding', 'compact', 'TileSpacing', 'compact');

    title_text = local_spec_field(plot_spec, 'title', "");
    if strlength(title_text) > 0
        title(layout, title_text, 'Interpreter', local_text_interpreter(title_text));
    end

    %% 2. Scenario Panels
    for i = 1:num_scenarios
        ax = nexttile(layout);
        hold(ax, 'on');

        [t_values, rt_values] = local_scenario_curve(scenarios(i));
        plot(ax, t_values, rt_values, 'LineWidth', 1.8);

        scenario_label = local_scenario_label(scenarios(i), plot_spec, i);
        if strlength(scenario_label) > 0
            title(ax, scenario_label, ...
                'Interpreter', local_text_interpreter(scenario_label));
        end
        x_label = local_spec_field(plot_spec, 'x_label', "");
        y_label = local_spec_field(plot_spec, 'y_label', "");
        xlabel(ax, x_label, 'Interpreter', local_text_interpreter(x_label));
        ylabel(ax, y_label, 'Interpreter', local_text_interpreter(y_label));
        grid(ax, 'on');
        local_apply_limits(ax, plot_spec);
    end
end

function [t_values, rt_values] = local_scenario_curve(scenario)
%LOCAL_SCENARIO_CURVE Extract a scenario trajectory.
    if isfield(scenario, 'tspan')
        t_values = double(scenario.tspan(:));
    else
        t_values = double(scenario.t(:));
    end

    if isfield(scenario, 'Rt_true')
        rt_values = double(scenario.Rt_true(:));
    else
        rt_values = double(scenario.Rt(:));
    end
end

function label = local_scenario_label(scenario, plot_spec, idx)
%LOCAL_SCENARIO_LABEL Resolve one panel label.
    labels = local_spec_field(plot_spec, 'scenario_labels', strings(0, 1));
    if numel(labels) >= idx && strlength(labels(idx)) > 0
        label = labels(idx);
        return;
    end

    if isfield(scenario, 'scenario_id')
        label = string(scenario.scenario_id);
    elseif isfield(scenario, 'id')
        label = string(scenario.id);
    else
        label = "";
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

function interpreter = local_text_interpreter(text_value)
%LOCAL_TEXT_INTERPRETER Select text interpreter from label content.
    text_value = string(text_value);
    if any(contains(text_value, "$")) || any(contains(text_value, "\"))
        interpreter = 'latex';
    else
        interpreter = 'none';
    end
end
