function output = plot_model_performance(window_scores, plot_spec)
%PLOT_MODEL_PERFORMANCE Draw model-level WIS distributions.
%
%   Syntax:
%       fig = plot_model_performance(window_scores, plot_spec)
%       was_saved = plot_model_performance(score_registry, cfg)
%
%   Description:
%       Draws a box chart of window-level WIS distributions by model and
%       exogenous mode. Titles, labels, legend wording, and axis limits are
%       supplied by plot_spec. The legacy cfg call signature is retained for
%       Part B/C compatibility and exports through export_figure.
%
%   Inputs:
%       window_scores - Per-window score table from Part A 04.
%       plot_spec     - Plot specification from build_plot_spec, or legacy cfg.
%
%   Outputs:
%       output - Figure handle for plot_spec calls, or saved-flag for legacy
%                cfg calls.
%
%   See also BUILD_PLOT_SPEC, EXPORT_FIGURE.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-06-01

    %% 1. Figure Setup
    if nargin < 2 || isempty(plot_spec)
        plot_spec = build_plot_spec();
    end

    if isstruct(plot_spec) && isfield(plot_spec, 'output')
        output = local_legacy_plot_and_export(window_scores, plot_spec);
        return;
    end

    output = local_draw_model_performance(window_scores, plot_spec);
end

function fig = local_draw_model_performance(window_scores, plot_spec)
%LOCAL_DRAW_MODEL_PERFORMANCE Draw model-level WIS distributions.
    if ~istable(window_scores)
        error('PLOT:InvalidScoreTable', 'window_scores must be a table.');
    end

    fig = figure('Name', char(local_spec_field(plot_spec, 'figure_name', "Model performance")), ...
        'Visible', char(local_spec_field(plot_spec, 'visible', "off")));
    local_apply_figure_size(fig, plot_spec);

    ax = axes(fig);
    hold(ax, 'on');

    %% 2. Data Filtering and Plotting
    comparison_idx = true(height(window_scores), 1);
    if ismember('IncludeInMainComparison', window_scores.Properties.VariableNames)
        comparison_idx = logical(window_scores.IncludeInMainComparison);
    end

    valid_idx = isfinite(window_scores.WindowWIS) & comparison_idx;
    if ~any(valid_idx)
        local_no_data_message(ax, plot_spec);
        return;
    end

    plot_data = window_scores(valid_idx, :);
    config_label = string(plot_data.Model) + " / " + string(plot_data.ExoMode);

    if ismember('Scenario', plot_data.Properties.VariableNames)
        boxchart(ax, categorical(config_label), plot_data.WindowWIS, ...
            'GroupByColor', categorical(plot_data.Scenario));
    else
        boxchart(ax, categorical(config_label), plot_data.WindowWIS);
    end

    local_apply_labels(ax, plot_spec);
    local_apply_limits(ax, plot_spec);
    local_apply_scale(ax, plot_spec, plot_data.WindowWIS);
    grid(ax, 'on');
    local_apply_legend(ax, plot_spec);
end

function was_saved = local_legacy_plot_and_export(score_registry, cfg)
%LOCAL_LEGACY_PLOT_AND_EXPORT Preserve older Part B/C plotting behavior.
    was_saved = false;

    fig_dir = fullfile(pwd, 'results', 'partA', 'figures');
    if isfield(cfg, 'output') && isfield(cfg.output, 'fig_dir')
        fig_dir = cfg.output.fig_dir;
    end

    if ~local_has_finite_plot_data(score_registry)
        warning('PLOT:NoData', ...
            'No finite accepted WIS values were available. Skipping visualization.');
        return;
    end

    legacy_spec = build_plot_spec( ...
        'figure_name', "WIS Performance Comparison", ...
        'title', "Model WIS Distribution by Configuration", ...
        'y_label', "WIS ($\mathcal{R}_t$)", ...
        'output_path', fullfile(fig_dir, 'partA_04_wis_performance_boxplot.png'), ...
        'legend', struct('location', "bestoutside"), ...
        'use_log_if_large', true);

    fig = local_draw_model_performance(score_registry, legacy_spec);
    export_figure(fig, legacy_spec);
    close(fig);
    was_saved = true;
end

function has_data = local_has_finite_plot_data(score_registry)
%LOCAL_HAS_FINITE_PLOT_DATA Check for accepted finite WIS values.
    if ~istable(score_registry) || ~ismember('WindowWIS', score_registry.Properties.VariableNames)
        has_data = false;
        return;
    end

    comparison_idx = true(height(score_registry), 1);
    if ismember('IncludeInMainComparison', score_registry.Properties.VariableNames)
        comparison_idx = logical(score_registry.IncludeInMainComparison);
    end

    has_data = any(isfinite(score_registry.WindowWIS) & comparison_idx);
end

function local_apply_legend(ax, plot_spec)
%LOCAL_APPLY_LEGEND Apply optional legend location.
    legend_spec = local_spec_field(plot_spec, 'legend', struct());
    location = "bestoutside";
    if isstruct(legend_spec) && isfield(legend_spec, 'location') && ...
            strlength(string(legend_spec.location)) > 0
        location = string(legend_spec.location);
    end
    legend(ax, 'Location', char(location));
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

function local_apply_scale(ax, plot_spec, values)
%LOCAL_APPLY_SCALE Apply optional y-axis scaling.
    y_scale = local_spec_field(plot_spec, 'y_scale', "");
    if strlength(string(y_scale)) > 0
        set(ax, 'YScale', char(string(y_scale)));
        return;
    end

    use_log_if_large = false;
    if isfield(plot_spec, 'use_log_if_large') && ~isempty(plot_spec.use_log_if_large)
        use_log_if_large = logical(plot_spec.use_log_if_large);
    end
    if use_log_if_large && any(values > 100)
        set(ax, 'YScale', 'log');
    end
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
