%PARTA_05_GENERATE_FIGURES Generate synthetic-validation thesis figures.
%
%   Description:
%       Exports thesis figures from the saved Part A datasets, forecast
%       artifacts, and evaluation artifact: the synthetic Rt trajectories of
%       every dataset role, representative fixed-lead forecasts of the
%       transfer and assessment stages, window-level and horizon-wise WIS,
%       empirical interval coverage, infectious-population projection error
%       relative to Rt persistence, model-selection diagnostics, preliminary
%       versus final performance on the refinement data, and forecast
%       feasibility. Evaluation figures use logarithmic WIS scales and a
%       fixed model/input ordering, and are annotated with the configurations
%       without a feasible candidate and when the evaluated configuration set
%       is incomplete. Selection panels without a feasible candidate are drawn
%       and labelled as such.
%
%       The representative forecast figures are configuration-specific and
%       are drawn for the configurations of cfg.figures (all configurations,
%       or the selected ones) from the forecast artifacts that the evaluation
%       artifact records as completed; figures outside that scope, and stages
%       that are not applicable, are left without a new figure. All other
%       figures are comparative and always use every accumulated result.
%       Plotting categories without data in a panel are not drawn, and shared
%       legends list the categories drawn in any panel.
%
%   Workflow:
%       1. Initialize figure paths, source artifacts, and shared styling.
%       2. Generate the synthetic Rt trajectory panels.
%       3. Generate the representative fixed-lead forecast figures.
%       4. Generate the Rt evaluation and infectious-projection figures.
%       5. Generate the model-selection and feasibility figures.
%
%   See also PARTA_CONFIG, PARTA_04_EVALUATE_FORECASTS, PLOT_SERIES,
%            PLOT_DISTRIBUTION, APPLY_PANEL_STYLE.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-11-27

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Figure Generation ===\n');

cfg = partA_config();

forecast_dir   = cfg.output.forecast_dir;
evaluation_dir = cfg.output.score_dir;
figure_dir     = cfg.output.fig_dir;

if ~exist(figure_dir, 'dir'), mkdir(figure_dir); end

style     = local_style();
rt_bounds = cfg.Rt.bounds;
stages    = ["transfer"; "assessment"];

strata_ids   = [[cfg.design.development.strata.id]'; [cfg.scenarios.id]'];
strata_names = [[cfg.design.development.strata.name]'; [cfg.scenarios.name]'];
family_ids   = [cfg.scenarios.id]';
family_names = [cfg.scenarios.name]';

figure_configurations = cfg.figures.configurations;
evaluation_artifact   = fullfile(evaluation_dir, 'partA_04_evaluation_results.mat');
has_evaluation        = exist(evaluation_artifact, 'file') == 2;

fprintf('Figure scope: %s (%s)\n', cfg.figures.scope, strjoin(figure_configurations(:, 1) + "/" + figure_configurations(:, 2), ", "));

if has_evaluation
    evaluation = load(evaluation_artifact);
    configuration_status = evaluation.configuration_status;

    in_scope       = ismember(configuration_status.Model + "/" + configuration_status.ExoMode, figure_configurations(:, 1) + "/" + figure_configurations(:, 2));
    suffixes       = configuration_status.Model + "_" + configuration_status.ExoMode;
    has_transfer   = in_scope & configuration_status.Transfer == "completed";
    has_assessment = in_scope & configuration_status.Assessment == "completed";

    forecast_files = [fullfile(forecast_dir, "partA_02_forecast_transfer_" + suffixes(has_transfer) + ".mat"); fullfile(forecast_dir, "partA_03_forecast_assessment_" + suffixes(has_assessment) + ".mat")];
    forecast_ids   = [configuration_status.SelectionId(has_transfer); configuration_status.SelectionId(has_assessment)];

    for c = find(in_scope & configuration_status.SelectionOutcome == "no_feasible_candidate").'
        fprintf('No representative forecast figure for the stages that are not applicable to %s / %s: no feasible candidate in %s.\n', configuration_status.Model(c), configuration_status.ExoMode(c), configuration_status.FailedStage(c));
    end
end

%% 2. Synthetic Rt Trajectories
if exist(cfg.output.dataset_manifest, 'file') ~= 2
    fprintf('Skipping Rt trajectory figure - no dataset manifest in %s.\n', cfg.output.data_dir);
else
    fprintf('Drawing synthetic Rt trajectories of every dataset role...\n');

    manifest = load(cfg.output.dataset_manifest);
    datasets = manifest.datasets;
    kinds    = ["Development"; "Canonical"; "Refinement variant"; "Assessment variant"];
    colors   = [style.palette(2, :); 0, 0, 0; style.palette(4, :); style.palette(5, :)];
    widths   = [style.line_width; style.truth_line_width + 0.4; 0.9; 0.9];
    lines    = ["-"; "-"; "-"; "--"];

    fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.0, 15.0], 'Color', 'w');
    tl  = tiledlayout(fig, 3, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    legend_handles = gobjects(numel(kinds), 1);
    legend_found   = false(numel(kinds), 1);

    for p = 1:numel(strata_ids)
        ax   = nexttile(tl);
        rows = datasets(datasets.Stratum == strata_ids(p), :);
        kind = ones(height(rows), 1);
        kind(rows.IsCanonical) = 2;
        kind(rows.Role == "refinement" & ~rows.IsCanonical) = 3;
        kind(rows.Role == "assessment") = 4;
        [~, order] = sort(kind, 'descend');

        series = repmat(local_series_template(), height(rows), 1);

        for r = 1:height(rows)
            row    = order(r);
            loaded = load(fullfile(cfg.output.data_dir, rows.File(row)), 'tspan', 'Rt_true');

            series(r).type       = "line";
            series(r).x          = loaded.tspan;
            series(r).y          = loaded.Rt_true;
            series(r).color      = colors(kind(row), :);
            series(r).line_style = lines(kind(row));
            series(r).line_width = widths(kind(row));
            series(r).label      = kinds(kind(row));
        end

        spec = struct('series', series, 'style', struct('y_limits', rt_bounds, 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));
        [h, labels] = plot_series(ax, spec);

        for k = 1:numel(kinds)
            match = find(labels == kinds(k), 1);
            if ~legend_found(k) && ~isempty(match)
                legend_handles(k) = h(match);
                legend_found(k)   = true;
            end
        end

        title(ax, sprintf('(%c) %s', 'a' + p - 1, strata_names(p)), 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size, 'FontWeight', 'normal');
    end

    xlabel(tl, "Time, {\it t} (days)", 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
    ylabel(tl, "Effective reproduction number, {\it R}_t", 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
    local_tile_legend(legend_handles(legend_found), kinds(legend_found), style);

    exportgraphics(fig, fullfile(figure_dir, 'partA_05_rt_scenarios.pdf'), 'ContentType', 'vector');
    close(fig);
end

%% 3. Representative Fixed-Lead Forecasts
if ~has_evaluation
    fprintf('Skipping forecast comparisons - no evaluation artifact in %s identifies the evaluated forecast artifacts.\n', evaluation_dir);
elseif isempty(forecast_files)
    fprintf('Skipping forecast comparisons - no completed forecast stage in the figure scope.\n');
else
    lead        = cfg.forecast.plot_lead_time;
    plot_alphas = sort(cfg.forecast.plot_alphas);

    fprintf('Drawing %d representative forecast figure(s) at lead %d day(s)...\n', numel(forecast_files), lead);

    for f = 1:numel(forecast_files)
        loaded = load(forecast_files(f));

        if loaded.selection_id ~= forecast_ids(f)
            error('PARTA_05:StaleEvaluation', 'The forecast artifact %s (selection %s) is not the one evaluated in %s (selection %s). Rerun partA_04.', forecast_files(f), loaded.selection_id, evaluation_artifact, forecast_ids(f));
        end

        fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.0, 11.5], 'Color', 'w');
        tl  = tiledlayout(fig, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

        legend_handles = gobjects(0, 1);
        legend_labels  = strings(0, 1);

        for p = 1:numel(family_ids)
            ax = nexttile(tl);
            in_family = find([loaded.forecasts.family] == family_ids(p));

            if loaded.stage == "transfer"
                representative = in_family([loaded.forecasts(in_family).is_canonical]);
            else
                representative = in_family(1);
            end

            forecast = loaded.forecasts(representative);
            fc = local_fixed_lead(forecast, loaded.wis_alphas, lead, plot_alphas);

            spec = struct('series', local_series_with_data(local_forecast_series(fc, plot_alphas, style)), 'style', struct('y_limits', rt_bounds, 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));
            [h, labels] = plot_series(ax, spec);
            [legend_handles, legend_labels] = local_merge_legend(legend_handles, legend_labels, h, labels);

            title(ax, sprintf('(%c) %s (%s)', 'a' + p - 1, family_names(p), strrep(forecast.dataset_id, "_", "\_")), 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size, 'FontWeight', 'normal');
        end

        xlabel(tl, "Time, {\it t} (days)", 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
        ylabel(tl, "Effective reproduction number, {\it R}_t", 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
        local_tile_legend(legend_handles, legend_labels, style);

        plot_name = sprintf('partA_05_forecast_comparison_%s_%s_%s.pdf', loaded.stage, loaded.model_type, loaded.exo_mode);
        exportgraphics(fig, fullfile(figure_dir, plot_name), 'ContentType', 'vector');
        close(fig);
    end
end

%% 4. Rt Evaluation and Infectious-Projection Figures
if ~has_evaluation
    fprintf('Skipping evaluation figures - no evaluation artifact in %s.\n', evaluation_dir);
else
    fprintf('Drawing evaluation figures from partA_04 artifact...\n');

    summaries = evaluation.summaries;
    note      = local_status_note(configuration_status, evaluation.is_complete);

    for s = 1:numel(stages)
        window_scores = evaluation.window_scores(evaluation.window_scores.Stage == stages(s) & evaluation.window_scores.Status == "ok", :);

        if isempty(window_scores)
            continue;
        end

        num_zero          = nnz(window_scores.WindowWIS == 0);
        window_scores     = window_scores(window_scores.WindowWIS > 0, :);
        distribution_note = note;

        if num_zero > 0
            distribution_note = strtrim(sprintf("%d origins with zero WIS (exact persistence) omitted from the log scale. %s", num_zero, note));
        end

        [~, family_pos] = ismember(window_scores.Family, family_ids);
        configuration_labels = local_configuration_order(window_scores.Model, window_scores.ExoMode);
        positive_wis = window_scores.WindowWIS;

        fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.0, 9.5], 'Color', 'w');
        ax  = axes('Parent', fig);

        dist_spec = struct('x', categorical(local_configuration_label(window_scores.Model, window_scores.ExoMode), configuration_labels), 'y', window_scores.WindowWIS, 'group', categorical(family_names(family_pos), family_names), 'color_order', style.palette, 'style', struct('x_label', "Model / exogenous mode", 'y_label', "Window WIS (log scale)", 'y_limits', 10 .^ [floor(log10(min(positive_wis))), ceil(log10(max(positive_wis)))], 'x_tick_rotation', 30, 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));

        [h, labels] = plot_distribution(ax, dist_spec);
        set(ax, 'YScale', 'log', 'YMinorGrid', 'off');
        xlabel(ax, local_noted_label("Model / exogenous mode", distribution_note), 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
        local_apply_legend(ax, h, labels, style, 2);

        exportgraphics(fig, fullfile(figure_dir, "partA_05_model_wis_distribution_" + stages(s) + ".pdf"), 'ContentType', 'vector');
        close(fig);

        horizon_summary = summaries.horizon_summary(summaries.horizon_summary.Stage == stages(s), :);

        fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.0, 9.0], 'Color', 'w');
        ax  = axes('Parent', fig);

        spec = struct('series', local_grouped_line_series(horizon_summary, 'HorizonIdx', 'MeanWIS', style), 'style', struct('x_label', "Forecast horizon, {\it h} (days)", 'y_label', "Mean WIS (log scale)", 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));

        [h, labels] = plot_series(ax, spec);
        set(ax, 'YScale', 'log', 'YMinorGrid', 'off');
        xlabel(ax, local_noted_label("Forecast horizon, {\it h} (days)", note), 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
        local_apply_legend(ax, h, labels, style, 4);

        exportgraphics(fig, fullfile(figure_dir, "partA_05_mean_wis_by_horizon_" + stages(s) + ".pdf"), 'ContentType', 'vector');
        close(fig);

        interval_summary = summaries.interval_summary(summaries.interval_summary.Stage == stages(s), :);

        reference = local_series_template();
        reference.type       = "reference";
        reference.x          = [0; 1];
        reference.y          = [0; 1];
        reference.color      = [0, 0, 0];
        reference.line_style = "--";
        reference.line_width = 1.0;
        reference.label      = "Nominal = empirical";

        fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 16.0, 10.0], 'Color', 'w');
        ax  = axes('Parent', fig);

        spec = struct('series', [local_grouped_line_series(interval_summary, 'NominalCoverage', 'MeanCoverage', style); reference], 'style', struct('x_label', "Nominal coverage", 'y_label', "Empirical coverage", 'x_limits', [0, 1], 'y_limits', [0, 1], 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));

        [h, labels] = plot_series(ax, spec);
        xlabel(ax, local_noted_label("Nominal coverage", note), 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
        local_apply_legend(ax, h, labels, style, 4);

        exportgraphics(fig, fullfile(figure_dir, "partA_05_coverage_summary_" + stages(s) + ".pdf"), 'ContentType', 'vector');
        close(fig);
    end

    projection_summary = summaries.i_projection_horizon_summary;

    if ~isempty(projection_summary)
        projection_groups = local_configuration_order(projection_summary.Model, projection_summary.ExoMode);
        n_panels = numel(projection_groups);
        n_cols   = ceil(sqrt(n_panels));
        n_rows   = ceil(n_panels / n_cols);

        projection_y_max = 1.05 * max([projection_summary.MeanForecastDrivenAbsoluteError; projection_summary.MeanPersistenceRtAbsoluteError]);

        fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.0, 11.5], 'Color', 'w');
        tl  = tiledlayout(fig, n_rows, n_cols, 'Padding', 'compact', 'TileSpacing', 'compact');

        for i = 1:n_panels
            ax = nexttile(tl);
            group_summary = projection_summary(local_configuration_label(projection_summary.Model, projection_summary.ExoMode) == projection_groups(i), :);

            spec = struct('series', local_i_projection_series(group_summary, style), 'style', struct('x_limits', [1, cfg.forecast.horizon], 'y_limits', [0, projection_y_max], 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));

            [h, labels] = plot_series(ax, spec);
            title(ax, projection_groups(i), 'Interpreter', 'none', 'FontName', style.font_name, 'FontSize', style.axis_font_size, 'FontWeight', 'normal');
        end

        xlabel(tl, local_noted_label("Forecast horizon, {\it h} (days)", note), 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
        ylabel(tl, "Mean absolute error in infected population, {\it I}(t)", 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
        local_tile_legend(h, labels, style);

        exportgraphics(fig, fullfile(figure_dir, 'partA_05_infected_projection_mae_by_horizon.pdf'), 'ContentType', 'vector');
        close(fig);
    end

    %% 5. Model-Selection and Feasibility Figures
    selection_stages = ["development"; "refinement"];
    candidates       = evaluation.candidate_diagnostics;

    for s = 1:numel(selection_stages)
        stage_candidates = candidates(candidates.SelectionStage == selection_stages(s), :);

        if isempty(stage_candidates)
            continue;
        end

        groups   = local_configuration_order(stage_candidates.Model, stage_candidates.ExoMode);
        n_panels = numel(groups);
        n_cols   = ceil(sqrt(n_panels));
        n_rows   = ceil(n_panels / n_cols);

        fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.0, 4.2 * n_rows + 2.0], 'Color', 'w');
        tl  = tiledlayout(fig, n_rows, n_cols, 'Padding', 'compact', 'TileSpacing', 'compact');

        legend_handles = gobjects(0, 1);
        legend_labels  = strings(0, 1);

        for i = 1:n_panels
            ax = nexttile(tl);
            group_candidates = stage_candidates(local_configuration_label(stage_candidates.Model, stage_candidates.ExoMode) == groups(i), :);
            threshold = evaluation.selection_summary.Threshold(local_configuration_label(evaluation.selection_summary.Model, evaluation.selection_summary.ExoMode) == groups(i) & evaluation.selection_summary.SelectionStage == selection_stages(s));
            panel_style = struct('x_limits', [min(group_candidates.Complexity) - 0.5, max(group_candidates.Complexity) + 0.5], 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name);

            if any(group_candidates.Feasible)
                plotted_wis = [group_candidates.GlobalWIS(group_candidates.Feasible); threshold];
                panel_style.y_limits = [min(plotted_wis) / 1.5, max(plotted_wis) * 1.5];

                [h, labels] = plot_series(ax, struct('series', local_series_with_data(local_selection_series(group_candidates, threshold, style)), 'style', panel_style));
                [legend_handles, legend_labels] = local_merge_legend(legend_handles, legend_labels, h, labels);
                set(ax, 'YScale', 'log', 'YMinorGrid', 'off');
            else
                apply_panel_style(ax, panel_style);
                set(ax, 'YTick', []);
                text(ax, 0.5, 0.5, sprintf('No feasible candidate (0/%d)', height(group_candidates)), 'Units', 'normalized', 'HorizontalAlignment', 'center', 'FontName', style.font_name, 'FontSize', style.tick_font_size);
            end

            title(ax, groups(i), 'Interpreter', 'none', 'FontName', style.font_name, 'FontSize', style.axis_font_size, 'FontWeight', 'normal');
        end

        xlabel(tl, local_noted_label("Candidate complexity (estimated coefficients)", note), 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
        ylabel(tl, "Global mean WIS (log scale)", 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);

        if ~isempty(legend_labels)
            local_tile_legend(legend_handles, legend_labels, style);
        end

        exportgraphics(fig, fullfile(figure_dir, "partA_05_selection_diagnostics_" + selection_stages(s) + ".pdf"), 'ContentType', 'vector');
        close(fig);
    end

    refinement_summary = summaries.scenario_summary(summaries.scenario_summary.Stage == "refinement", :);
    executed           = configuration_status(configuration_status.SelectionOutcome ~= "not_executed", :);
    comparison_strata  = [family_ids; "All"];
    comparison_names   = [family_names; "Equal-family global mean"];
    groups             = local_configuration_order(executed.Model, executed.ExoMode);
    roles              = ["preliminary"; "final"];
    role_labels        = ["Preliminary configuration"; "Final configuration"];
    role_markers       = ["o"; "s"];

    if ~isempty(refinement_summary)
        fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.0, 16.0], 'Color', 'w');
        tl  = tiledlayout(fig, numel(comparison_strata), 1, 'Padding', 'compact', 'TileSpacing', 'compact');

        legend_handles = gobjects(0, 1);
        legend_labels  = strings(0, 1);

        for p = 1:numel(comparison_strata)
            ax     = nexttile(tl);
            series = repmat(local_series_template(), numel(roles), 1);

            for r = 1:numel(roles)
                rows = refinement_summary(refinement_summary.Stratum == comparison_strata(p) & refinement_summary.ConfigurationRole == roles(r), :);
                [~, position] = ismember(local_configuration_label(rows.Model, rows.ExoMode), groups);

                series(r).type        = "line";
                series(r).x           = position;
                series(r).y           = rows.MeanWIS;
                series(r).color       = style.palette(2 * r, :);
                series(r).line_style  = "none";
                series(r).marker      = role_markers(r);
                series(r).marker_size = style.marker_size + 1.5;
                series(r).label       = role_labels(r);
            end

            plotted_wis = vertcat(series.y);
            spec = struct('series', local_series_with_data(series), 'style', struct('x_limits', [0.5, numel(groups) + 0.5], 'y_limits', [min(plotted_wis) / 1.5, max(plotted_wis) * 1.5], 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));

            [h, labels] = plot_series(ax, spec);
            [legend_handles, legend_labels] = local_merge_legend(legend_handles, legend_labels, h, labels);
            set(ax, 'YScale', 'log', 'YMinorGrid', 'off', 'XTick', 1:numel(groups), 'XTickLabel', []);
            title(ax, comparison_names(p), 'Interpreter', 'none', 'FontName', style.font_name, 'FontSize', style.axis_font_size, 'FontWeight', 'normal');
        end

        infeasible = evaluation.selection_summary(evaluation.selection_summary.SelectionStage == "refinement" & isnan(evaluation.selection_summary.PreliminaryWIS), :);
        comparison_note = note;

        if ~isempty(infeasible)
            comparison_note = strtrim(sprintf("Preliminary configuration infeasible on the refinement data (means over available origins): %s. %s", strjoin(local_configuration_label(infeasible.Model, infeasible.ExoMode), ", "), note));
        end

        set(ax, 'XTickLabel', groups, 'XTickLabelRotation', 30);
        xlabel(tl, local_noted_label("Model / exogenous mode", comparison_note), 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
        ylabel(tl, "Mean WIS on the refinement data (log scale)", 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
        local_tile_legend(legend_handles, legend_labels, style);

        exportgraphics(fig, fullfile(figure_dir, 'partA_05_preliminary_vs_final.pdf'), 'ContentType', 'vector');
        close(fig);
    end

    feasibility = evaluation.feasibility_summary;
    groups      = local_configuration_order(feasibility.Model, feasibility.ExoMode);
    measures    = struct('stage', {"development"; "refinement"; "transfer"; "assessment"}, 'label', {"Feasible candidates, development"; "Feasible candidates, refinement"; "Available origins, transfer"; "Available origins, assessment"}, 'marker', {"o"; "s"; "^"; "d"});
    series      = repmat(local_series_template(), numel(measures), 1);

    for k = 1:numel(measures)
        rows = feasibility(feasibility.Stage == measures(k).stage, :);
        [~, position] = ismember(local_configuration_label(rows.Model, rows.ExoMode), groups);

        if any(measures(k).stage == selection_stages)
            fraction = rows.NumFeasibleCandidates ./ rows.NumCandidates;
        else
            fraction = rows.Availability;
        end

        series(k).type        = "line";
        series(k).x           = position;
        series(k).y           = fraction;
        series(k).color       = style.palette(k, :);
        series(k).line_style  = "none";
        series(k).marker      = measures(k).marker;
        series(k).marker_size = style.marker_size + 1.5;
        series(k).label       = measures(k).label;
    end

    fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2, 2, 17.0, 9.5], 'Color', 'w');
    ax  = axes('Parent', fig);

    spec = struct('series', local_series_with_data(series), 'style', struct('x_label', "Model / exogenous mode", 'y_label', "Fraction",'x_limits', [0.5, numel(groups) + 0.5], 'y_limits', [0, 1.05], 'grid', true, 'axis_font_size', style.axis_font_size, 'tick_font_size', style.tick_font_size, 'font_name', style.font_name));

    [h, labels] = plot_series(ax, spec);
    set(ax, 'XTick', 1:numel(groups), 'XTickLabel', groups, 'XTickLabelRotation', 30);
    xlabel(ax, local_noted_label("Model / exogenous mode", note), 'Interpreter', 'tex', 'FontName', style.font_name, 'FontSize', style.axis_font_size);
    local_apply_legend(ax, h, labels, style, 2);

    exportgraphics(fig, fullfile(figure_dir, 'partA_05_feasibility_summary.pdf'), 'ContentType', 'vector');
    close(fig);
end

fprintf('Figures saved under %s\n', figure_dir);
fprintf('=== Part A Figure Generation Complete ===\n\n');

%% 6. Local Functions
function fc = local_fixed_lead(forecast, interval_alphas, lead, plot_alphas)
%LOCAL_FIXED_LEAD Collect fixed-lead forecasts at the available origins and the full truth trajectory.
ok      = forecast.status == "ok";
columns = arrayfun(@(alpha) find(abs(interval_alphas - alpha) <= 1e-8, 1), plot_alphas);

fc = struct('truth_days', forecast.tspan, 'truth_Rt', forecast.Rt_true, 'target_days', forecast.window_day(ok) + lead, 'median', forecast.forecast_median(lead, ok).', 'lower', reshape(forecast.forecast_lower(lead, columns, ok), numel(columns), []).', 'upper', reshape(forecast.forecast_upper(lead, columns, ok), numel(columns), []).');
end

function series = local_forecast_series(fc, plot_alphas, style)
%LOCAL_FORECAST_SERIES Build interval bands, truth, and median forecast.
num_alphas = numel(plot_alphas);

band_colors = [
    0.80, 0.88, 0.97;
    0.62, 0.76, 0.92;
    0.45, 0.64, 0.86;
    0.30, 0.52, 0.78];

band_labels = compose("%d%% PI", round((1 - plot_alphas) * 100));

series = repmat(local_series_template(), num_alphas + 2, 1);

for k = 1:num_alphas
    series(k).type       = "ribbon";
    series(k).x          = fc.target_days;
    series(k).lower      = fc.lower(:, k);
    series(k).upper      = fc.upper(:, k);
    series(k).face_color = band_colors(k, :);
    series(k).label      = band_labels(k);
end

truth_idx = num_alphas + 1;
series(truth_idx).type       = "line";
series(truth_idx).x          = fc.truth_days;
series(truth_idx).y          = fc.truth_Rt;
series(truth_idx).color      = [0, 0, 0];
series(truth_idx).line_width = style.truth_line_width;
series(truth_idx).label      = "Ground truth";

median_idx = num_alphas + 2;
series(median_idx).type        = "line";
series(median_idx).x           = fc.target_days;
series(median_idx).y           = fc.median;
series(median_idx).color       = style.palette(4, :);
series(median_idx).line_style  = "--";
series(median_idx).line_width  = style.line_width;
series(median_idx).marker      = "o";
series(median_idx).marker_size = style.marker_size;
series(median_idx).label       = "Median forecast";
end

function series = local_grouped_line_series(tbl, x_var, y_var, style)
%LOCAL_GROUPED_LINE_SERIES Build one line series per model/exogenous group in fixed configuration order.
group_ids = local_configuration_label(tbl.Model, tbl.ExoMode);
groups    = local_configuration_order(tbl.Model, tbl.ExoMode);
markers   = ["o", "s", "^", "d", "v", ">", "<", "p", "h"];

series = repmat(local_series_template(), numel(groups), 1);

for i = 1:numel(groups)
    idx = group_ids == groups(i);

    [x_values, order] = sort(tbl.(x_var)(idx));
    y_values = tbl.(y_var)(idx);

    series(i).type        = "line";
    series(i).x           = x_values;
    series(i).y           = y_values(order);
    series(i).color       = style.palette(mod(i - 1, size(style.palette, 1)) + 1, :);
    series(i).line_width  = style.line_width;
    series(i).marker      = markers(mod(i - 1, numel(markers)) + 1);
    series(i).marker_size = style.marker_size;
    series(i).label       = groups(i);

    if groups(i) == "Persistence"
        series(i).color      = [0, 0, 0];
        series(i).line_style = "--";
    end
end
end

function series = local_selection_series(candidates, threshold, style)
%LOCAL_SELECTION_SERIES Candidate WIS against complexity with eligibility, selection, and the one-SE threshold.
feasible  = candidates(candidates.Feasible, :);
groups    = {~feasible.Eligible, feasible.Eligible, feasible.IsMinimumWIS, feasible.Selected};
labels    = ["Feasible candidate"; "Within one SE"; "Minimum WIS"; "Selected"];
colors    = [0.65, 0.65, 0.65; style.palette(3, :); style.palette(5, :); 0, 0, 0];
markers   = ["o"; "o"; "d"; "p"];
sizes     = style.marker_size + [0; 0; 2; 3];

series = repmat(local_series_template(), numel(groups) + 1, 1);

for k = 1:numel(groups)
    series(k).type        = "line";
    series(k).x           = feasible.Complexity(groups{k});
    series(k).y           = feasible.GlobalWIS(groups{k});
    series(k).color       = colors(k, :);
    series(k).line_style  = "none";
    series(k).marker      = markers(k);
    series(k).marker_size = sizes(k);
    series(k).label       = labels(k);
end

series(end).type       = "reference";
series(end).x          = [min(candidates.Complexity); max(candidates.Complexity)];
series(end).y          = [threshold; threshold];
series(end).color      = [0, 0, 0];
series(end).line_style = "--";
series(end).line_width = 0.8;
series(end).label      = "One-SE threshold";
end

function labels = local_configuration_label(models, exo_modes)
%LOCAL_CONFIGURATION_LABEL Model/input label; the persistence reference carries no input mode.
labels = models + " / " + exo_modes;
labels(models == "Persistence") = "Persistence";
end

function labels = local_configuration_order(models, exo_modes)
%LOCAL_CONFIGURATION_ORDER Return present model/input labels in fixed family and input order.
model_order = ["AR"; "ARX"; "N4SID"; "SSEST"; "Persistence"];
exo_order   = ["None"; "S"; "I"; "Both"];

[~, model_rank] = ismember(models, model_order);
[~, exo_rank]   = ismember(exo_modes, exo_order);
ranked = unique([model_rank, exo_rank], 'rows');

labels = local_configuration_label(model_order(ranked(:, 1)), exo_order(ranked(:, 2)));
end

function series = local_i_projection_series(summary, style)
%LOCAL_I_PROJECTION_SERIES Build forecast-driven and persistence-Rt error series.
[horizon_idx, order] = sort(summary.HorizonIdx);

series = repmat(local_series_template(), 2, 1);

series(1).type        = "line";
series(1).x           = horizon_idx;
series(1).y           = summary.MeanForecastDrivenAbsoluteError(order);
series(1).color       = style.palette(4, :);
series(1).line_width  = style.line_width;
series(1).marker      = "o";
series(1).marker_size = style.marker_size;
series(1).label       = "Forecast-driven projection";

series(2).type        = "line";
series(2).x           = horizon_idx;
series(2).y           = summary.MeanPersistenceRtAbsoluteError(order);
series(2).color       = style.palette(1, :);
series(2).line_style  = "--";
series(2).line_width  = style.line_width;
series(2).marker      = "s";
series(2).marker_size = style.marker_size;
series(2).label       = "Persistence-{\it R}_t projection";
end

function series = local_series_template()
%LOCAL_SERIES_TEMPLATE Return an empty plot-series struct.
series = struct('type', "line", 'x', [], 'y', [], 'lower', [], 'upper', [], 'color', [], 'line_style', "-", 'line_width', 1.0, 'marker', "none", 'marker_size', 4, 'face_color', [], 'face_alpha', 1, 'label', "");
end

function style = local_style()
%LOCAL_STYLE Return synthetic-validation figure style constants.
style = struct();
style.font_name        = "Arial";
style.axis_font_size   = 9;
style.tick_font_size   = 8;
style.legend_font_size = 8;
style.panel_font_size  = 9;
style.line_width       = 1.2;
style.truth_line_width = 1.3;
style.marker_size      = 3.5;
style.palette          = [
    0.902, 0.624, 0.000;
    0.337, 0.706, 0.914;
    0.000, 0.620, 0.451;
    0.000, 0.447, 0.698;
    0.835, 0.369, 0.000;
    0.800, 0.475, 0.655];
end

function series = local_series_with_data(series)
%LOCAL_SERIES_WITH_DATA Drop plotting categories without data; they draw nothing and take no legend entry.
series = series(arrayfun(@(s) ~isempty(s.x), series));
end

function [legend_handles, legend_labels] = local_merge_legend(legend_handles, legend_labels, handles, labels)
%LOCAL_MERGE_LEGEND Add a panel's legend entries missing from the shared legend, after the entry preceding them in the panel.
for k = 1:numel(labels)
    if ~any(legend_labels == labels(k))
        position = max([0; find(ismember(legend_labels, labels(1:k - 1)))]);
        legend_handles = [legend_handles(1:position); handles(k); legend_handles(position + 1:end)];
        legend_labels  = [legend_labels(1:position); labels(k); legend_labels(position + 1:end)];
    end
end
end

function local_apply_legend(ax, handles, labels, style, num_columns)
%LOCAL_APPLY_LEGEND Attach a horizontal legend above an axes.
if isempty(handles)
    return;
end

lg = legend(ax, handles, labels);
lg.Interpreter = 'tex';
lg.FontName    = style.font_name;
lg.FontSize    = style.legend_font_size;
lg.Box         = 'off';
lg.Location    = 'northoutside';
lg.Orientation = 'horizontal';
lg.NumColumns  = num_columns;
end

function local_tile_legend(handles, labels, style)
%LOCAL_TILE_LEGEND Attach one horizontal legend above a tiled layout.
lg = legend(handles, labels);
lg.Interpreter = 'tex';
lg.FontName    = style.font_name;
lg.FontSize    = style.legend_font_size;
lg.Box         = 'off';
lg.Orientation = 'horizontal';
lg.NumColumns  = min(numel(labels), 4);
lg.Layout.Tile = 'north';
end

function note = local_status_note(configuration_status, is_complete)
%LOCAL_STATUS_NOTE Note naming the configurations without a feasible candidate and stating the evaluated configurations when the set is incomplete.
unsuccessful = configuration_status.SelectionOutcome == "no_feasible_candidate";
note = "";

if ~is_complete || any(unsuccessful)
    note = sprintf("Evaluated configurations: selection %d/%d, transfer %d/%d, assessment %d/%d.", nnz(configuration_status.SelectionOutcome ~= "not_executed"), height(configuration_status), nnz(configuration_status.Transfer == "completed"), height(configuration_status), nnz(configuration_status.Assessment == "completed"), height(configuration_status));
end

if any(unsuccessful)
    note = note + " No feasible candidate: " + strjoin(local_configuration_label(configuration_status.Model(unsuccessful), configuration_status.ExoMode(unsuccessful)) + " (" + configuration_status.FailedStage(unsuccessful) + ")", ", ") + ".";
end
end

function label = local_noted_label(label, note)
%LOCAL_NOTED_LABEL Append a note as a small second line of an axis label.
if strlength(note) > 0
    label = [label; "\fontsize{7}" + note];
end
end
