function fig = plot_coverage_summary(interval_summary, plot_spec)
%PLOT_COVERAGE_SUMMARY Draw empirical coverage by nominal interval level.
%
%   Syntax:
%       fig = plot_coverage_summary(interval_summary, plot_spec)
%
%   Description:
%       Converts empirical coverage summaries into generic line-series panel
%       data and delegates rendering to plot_single_panel. Titles, labels,
%       legend wording, and axis limits are supplied by plot_spec.
%
%   Inputs:
%       interval_summary - Summary table with Alpha/NominalCoverage and
%                          MeanCoverage columns.
%       plot_spec        - Plot specification from build_plot_spec.
%
%   Outputs:
%       fig - Figure handle.
%
%   See also PLOT_SINGLE_PANEL, BUILD_PLOT_SPEC, EXPORT_FIGURE.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-02

    %% 1. Input Handling
    if nargin < 2 || isempty(plot_spec)
        plot_spec = build_plot_spec();
    end

    %% 2. Generic Panel Assembly
    panel_data = local_coverage_panel_data(interval_summary, plot_spec);

    %% 3. Rendering
    fig = plot_single_panel(panel_data, plot_spec);
end

function panel_data = local_coverage_panel_data(interval_summary, plot_spec)
%LOCAL_COVERAGE_PANEL_DATA Convert coverage summaries into line series.
    panel_data = struct('series', []);
    if isempty(interval_summary) || height(interval_summary) == 0 || ...
            ~ismember('MeanCoverage', interval_summary.Properties.VariableNames)
        return;
    end

    nominal_coverage = local_nominal_coverage(interval_summary);
    group_ids = local_group_ids(interval_summary);
    groups = unique(group_ids, 'stable');
    legend_labels = local_legend_labels(plot_spec, groups);

    series = local_empty_series(0);
    for i = 1:numel(groups)
        idx = group_ids == groups(i);
        x_values = double(nominal_coverage(idx));
        y_values = double(interval_summary.MeanCoverage(idx));
        valid_idx = isfinite(x_values) & isfinite(y_values);
        if ~any(valid_idx)
            continue;
        end

        x_values = x_values(valid_idx);
        y_values = y_values(valid_idx);
        [x_values, order] = sort(x_values);
        y_values = y_values(order);

        next_series = local_empty_series(1);
        next_series.type = "line";
        next_series.x = x_values;
        next_series.y = y_values;
        next_series.label = legend_labels(i);
        next_series.style = struct('LineStyle', '-', 'LineWidth', 1.3, ...
            'Marker', 'o', 'MarkerSize', 3.2);
        next_series.legend_rank = i;
        series(end + 1, 1) = next_series; %#ok<AGROW>
    end

    valid_nominal = nominal_coverage(isfinite(nominal_coverage));
    if ~isempty(valid_nominal)
        reference_series = local_empty_series(1);
        reference_series.type = "line";
        reference_series.x = [min(valid_nominal), max(valid_nominal)];
        reference_series.y = reference_series.x;
        reference_series.label = local_reference_label(plot_spec);
        reference_series.style = struct('Color', [0, 0, 0], ...
            'LineStyle', '--', 'LineWidth', 1.0);
        reference_series.legend_rank = numel(series) + 1;
        series(end + 1, 1) = reference_series; %#ok<AGROW>
    end

    panel_data.series = series;
end

function series = local_empty_series(n)
%LOCAL_EMPTY_SERIES Create generic panel-series placeholders.
    series = repmat(struct('type', "line", 'x', [], 'y', [], ...
        'lower', [], 'upper', [], 'label', "", 'style', struct(), ...
        'legend_visible', true, 'legend_rank', 1), n, 1);
end

function nominal_coverage = local_nominal_coverage(interval_summary)
%LOCAL_NOMINAL_COVERAGE Resolve nominal coverage levels.
    if ismember('NominalCoverage', interval_summary.Properties.VariableNames)
        nominal_coverage = double(interval_summary.NominalCoverage);
    elseif ismember('Alpha', interval_summary.Properties.VariableNames)
        nominal_coverage = 1 - double(interval_summary.Alpha);
    else
        nominal_coverage = nan(height(interval_summary), 1);
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
        group_ids = repmat("All intervals", height(scores), 1);
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

function label = local_reference_label(plot_spec)
%LOCAL_REFERENCE_LABEL Resolve nominal-reference legend text.
    legend_spec = local_spec_field(plot_spec, 'legend', struct());
    label = "Nominal coverage";
    if isstruct(legend_spec) && isfield(legend_spec, 'reference_label') && ...
            ~isempty(legend_spec.reference_label)
        label = string(legend_spec.reference_label);
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
