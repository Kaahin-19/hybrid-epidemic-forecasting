function fig = plot_wis_by_horizon(horizon_scores, plot_spec)
%PLOT_WIS_BY_HORIZON Draw WIS summaries by forecast horizon.
%
%   Syntax:
%       fig = plot_wis_by_horizon(horizon_scores, plot_spec)
%
%   Description:
%       Draws mean WIS by forecast horizon. Grouping and legend labels are
%       derived from the supplied table and plot specification, so the
%       function can be reused outside thesis-specific figure generation.
%
%   Inputs:
%       horizon_scores - Summary table with HorizonIdx and MeanWIS columns.
%       plot_spec      - Plot specification from build_plot_spec.
%
%   Outputs:
%       fig - Figure handle.
%
%   See also BUILD_PLOT_SPEC, EXPORT_FIGURE.
%
% A. M. Kaahin 2026-06-01

    %% 1. Figure Setup
    if nargin < 2 || isempty(plot_spec)
        plot_spec = build_plot_spec();
    end

    fig = figure('Name', char(local_spec_field(plot_spec, 'figure_name', ...
        "WIS by horizon")), ...
        'Visible', char(local_spec_field(plot_spec, 'visible', "off")));
    local_apply_figure_size(fig, plot_spec);

    ax = axes(fig);
    hold(ax, 'on');

    %% 2. Plotting
    if isempty(horizon_scores) || height(horizon_scores) == 0 || ...
            ~ismember('HorizonIdx', horizon_scores.Properties.VariableNames)
        local_no_data_message(ax, plot_spec);
        return;
    end

    y_var = local_score_variable(horizon_scores);
    if strlength(y_var) == 0
        local_no_data_message(ax, plot_spec);
        return;
    end

    group_ids = local_group_ids(horizon_scores);
    groups = unique(group_ids, 'stable');
    legend_labels = local_legend_labels(plot_spec, groups);

    for i = 1:numel(groups)
        idx = group_ids == groups(i);
        x_values = double(horizon_scores.HorizonIdx(idx));
        y_values = double(horizon_scores.(char(y_var))(idx));
        valid_idx = isfinite(x_values) & isfinite(y_values);
        if ~any(valid_idx)
            continue;
        end

        x_values = x_values(valid_idx);
        y_values = y_values(valid_idx);
        [x_values, order] = sort(x_values);
        y_values = y_values(order);

        plot(ax, x_values, y_values, '-o', 'LineWidth', 1.3, ...
            'MarkerSize', 3.2, 'DisplayName', char(legend_labels(i)));
    end

    if isempty(ax.Children)
        local_no_data_message(ax, plot_spec);
        return;
    end

    local_apply_labels(ax, plot_spec);
    local_apply_limits(ax, plot_spec);
    grid(ax, 'on');
    local_apply_legend(ax, plot_spec);
end

function y_var = local_score_variable(horizon_scores)
%LOCAL_SCORE_VARIABLE Resolve WIS column name.
    if ismember('MeanWIS', horizon_scores.Properties.VariableNames)
        y_var = "MeanWIS";
    elseif ismember('WIS', horizon_scores.Properties.VariableNames)
        y_var = "WIS";
    else
        y_var = "";
    end
end

function group_ids = local_group_ids(scores)
%LOCAL_GROUP_IDS Build reusable group identifiers.
    vars = scores.Properties.VariableNames;
    if all(ismember({'Model', 'ExoMode'}, vars))
        group_ids = string(scores.Model) + " / " + string(scores.ExoMode);
    elseif ismember('Scenario', vars)
        group_ids = string(scores.Scenario);
    else
        group_ids = repmat("All forecasts", height(scores), 1);
    end
end

function labels = local_legend_labels(plot_spec, groups)
%LOCAL_LEGEND_LABELS Resolve plotted group labels.
    legend_spec = local_spec_field(plot_spec, 'legend', struct());
    if isstruct(legend_spec) && isfield(legend_spec, 'labels')
        labels = string(legend_spec.labels);
        if numel(labels) >= numel(groups)
            labels = labels(1:numel(groups));
            return;
        end
    end
    labels = string(groups);
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

function local_apply_legend(ax, plot_spec)
%LOCAL_APPLY_LEGEND Apply optional legend location.
    legend_spec = local_spec_field(plot_spec, 'legend', struct());
    location = "best";
    if isstruct(legend_spec) && isfield(legend_spec, 'location')
        location = string(legend_spec.location);
    end
    legend(ax, 'Location', char(location));
end

function local_no_data_message(ax, plot_spec)
%LOCAL_NO_DATA_MESSAGE Draw an empty-data placeholder.
    axis(ax, 'off');
    title_text = local_spec_field(plot_spec, 'title', "");
    if strlength(title_text) > 0, title(ax, title_text); end
    text(ax, 0.5, 0.5, local_spec_field(plot_spec, 'no_data_text', "No finite data"), ...
        'HorizontalAlignment', 'center');
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
