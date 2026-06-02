function fig = plot_rt_scenarios(scenarios, plot_spec)
%PLOT_RT_SCENARIOS Draw synthetic effective-Rt scenario trajectories.
%
%   Syntax:
%       fig = plot_rt_scenarios(scenarios, plot_spec)
%
%   Description:
%       Converts scenario Rt trajectories into generic panel data and
%       delegates tiled rendering to plot_multi_panel_figure. Presentation
%       choices such as title text, axis labels, panel labels, scenario
%       labels, styles, and axis limits are read from plot_spec.
%
%   Inputs:
%       scenarios - Struct array with tspan/Rt_true or t/Rt fields.
%       plot_spec - Plot specification from build_plot_spec.
%
%   Outputs:
%       fig - Figure handle.
%
%   See also PLOT_MULTI_PANEL_FIGURE, PLOT_SINGLE_PANEL, BUILD_PLOT_SPEC.
%
% A. M. Kaahin 2026-02-18
% Modified: 2026-06-02

    %% 1. Input Handling
    if nargin < 2 || isempty(plot_spec)
        plot_spec = build_plot_spec();
    end

    %% 2. Generic Panel Assembly
    panel_data = local_scenario_panel_data(scenarios, plot_spec);

    %% 3. Rendering
    fig = plot_multi_panel_figure(panel_data, plot_spec);
end

function panel_data = local_scenario_panel_data(scenarios, plot_spec)
%LOCAL_SCENARIO_PANEL_DATA Convert scenarios into generic line panels.
    num_scenarios = numel(scenarios);
    panel_data = repmat(struct('series', [], 'plot_spec', struct()), ...
        num_scenarios, 1);

    for i = 1:num_scenarios
        [t_values, rt_values] = local_scenario_curve(scenarios(i));
        series = local_empty_series(1);
        series.type = "line";
        series.x = t_values;
        series.y = rt_values;
        series.label = "";
        series.legend_visible = false;
        series.style = local_truth_style(plot_spec);

        panel_data(i).series = series;
        panel_data(i).plot_spec = struct( ...
            'title', local_scenario_title(scenarios(i), plot_spec, i), ...
            'panel_label', local_panel_label(plot_spec, i), ...
            'legend', local_panel_legend(plot_spec));
    end
end

function series = local_empty_series(n)
%LOCAL_EMPTY_SERIES Create generic panel-series placeholders.
    series = repmat(struct('type', "line", 'x', [], 'y', [], ...
        'lower', [], 'upper', [], 'label', "", 'style', struct(), ...
        'legend_visible', true, 'legend_rank', 1), n, 1);
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

function style = local_truth_style(plot_spec)
%LOCAL_TRUTH_STYLE Resolve scenario-line style.
    style = local_spec_field(plot_spec, 'truth_style', struct());
    if isempty(fieldnames(style))
        style.Color = [];
        style.LineWidth = 1.8;
    end
end

function title_text = local_scenario_title(scenario, plot_spec, idx)
%LOCAL_SCENARIO_TITLE Resolve one scenario-panel title.
    titles = local_spec_field(plot_spec, 'panel_titles', strings(0, 1));
    if numel(titles) >= idx && strlength(titles(idx)) > 0
        title_text = titles(idx);
        return;
    end

    labels = local_spec_field(plot_spec, 'scenario_labels', strings(0, 1));
    if numel(labels) >= idx && strlength(labels(idx)) > 0
        title_text = labels(idx);
        return;
    end

    if isfield(scenario, 'scenario_id')
        title_text = string(scenario.scenario_id);
    elseif isfield(scenario, 'id')
        title_text = string(scenario.id);
    else
        title_text = "";
    end
end

function panel_label = local_panel_label(plot_spec, idx)
%LOCAL_PANEL_LABEL Resolve optional panel annotation text.
    panel_labels = local_spec_field(plot_spec, 'panel_labels', strings(0, 1));
    if numel(panel_labels) >= idx
        panel_label = panel_labels(idx);
    else
        panel_label = "";
    end
end

function legend_spec = local_panel_legend(plot_spec)
%LOCAL_PANEL_LEGEND Resolve scenario-panel legend settings.
    legend_spec = local_spec_field(plot_spec, 'legend', struct());
    if ~isstruct(legend_spec)
        legend_spec = struct();
    end
    if ~isfield(legend_spec, 'visible') || isempty(legend_spec.visible)
        legend_spec.visible = false;
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
