%PARTB_04_GENERATE_FIGURES Generate Part B robustness-ladder figures.
%
%   Description:
%       Loads completed Part B robustness-ladder truth, forecast, and
%       evaluation artifacts, then generates case-level diagnostics and
%       thesis-level cross-case figures. Metric computation and table writing
%       remain isolated in Part B 03.
%
%   Workflow:
%       1. Load cross-case evaluation, truth, and forecast artifacts.
%       2. Generate case-level diagnostic figures under each case folder.
%       3. Generate thesis-level cross-case figures under results/partB/figures.
%
%   See also PARTB_CONFIG, PARTB_03_EVALUATE_MODELS, BUILD_PLOT_SPEC, ...
%            PLOT_SINGLE_PANEL, PLOT_MULTI_PANEL_FIGURE, EXPORT_FIGURE.
%
% A. M. Kaahin 2026-06-02
% Modified: 2026-06-09

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Robustness-Ladder Figure Generation ===\n');

cfg = partB_config();
figure_dir = cfg.output.fig_dir;
evaluation_dir = cfg.output.evaluation_dir;

if ~exist(figure_dir, 'dir'), mkdir(figure_dir); end

evaluation_artifact = fullfile(evaluation_dir, ...
    'partB_robustness_ladder_evaluation_results.mat');
if exist(evaluation_artifact, 'file') ~= 2
    error('FIG:MissingEvaluationArtifact', ...
        ['Missing Part B evaluation artifact: %s\n' ...
        'Run scripts/partB/partB_03_evaluate_models.m first.'], ...
        evaluation_artifact);
end

%% 2. Load Existing Artifacts
evaluation_data = load(evaluation_artifact);
summary_tables = evaluation_data.summary_tables;
window_scores = local_required_table(evaluation_data, 'window_scores', ...
    evaluation_artifact);
truth_records = local_load_truth_records(cfg);
forecast_records = local_load_forecast_records(cfg);

fprintf('Loaded %d truth artifact(s) and %d forecast artifact(s).\n', ...
    numel(truth_records), numel(forecast_records));

%% 3. Case-Level Diagnostics
local_generate_case_diagnostics(cfg, truth_records, forecast_records, ...
    window_scores, summary_tables);

%% 4. Thesis-Level Figures
local_draw_observation_noise_example(cfg, figure_dir, truth_records);
local_draw_process_noise_example(cfg, figure_dir, truth_records);
local_draw_structural_mismatch_truth(cfg, figure_dir, truth_records);
local_draw_robustness_mean_wis(cfg, figure_dir, summary_tables);
local_draw_robustness_wis_by_horizon(cfg, figure_dir, summary_tables);
local_draw_coverage_interval_width(cfg, figure_dir, summary_tables);

required_figures = local_required_thesis_figures(figure_dir);
missing_required = required_figures(~isfile(required_figures));
if ~isempty(missing_required)
    error('FIG:MissingRequiredThesisFigures', ...
        'Required Part B thesis figures were not generated: %s.', ...
        char(strjoin(missing_required, ', ')));
end

%% 5. Completion
fprintf('Thesis-level Part B figures are under: %s\n', figure_dir);
fprintf('=== Part B Robustness-Ladder Figure Generation Complete ===\n\n');

%% 6. Local Functions
function local_generate_case_diagnostics(cfg, truth_records, ...
    forecast_records, window_scores)
%LOCAL_GENERATE_CASE_DIAGNOSTICS Write case-specific diagnostic figures.
    if isempty(window_scores) || height(window_scores) == 0
        return;
    end

    case_ids = unique(window_scores.CaseID, 'stable');
    for i = 1:numel(case_ids)
        case_id = case_ids(i);
        case_dir = cfg.output.fig_dir;

        case_scores = window_scores(window_scores.CaseID == case_id, :);
        local_draw_case_wis_distribution(case_dir, case_id, case_scores);
        model_cases = local_fixed_model_cases(cfg);
        for m = 1:numel(model_cases)
            local_draw_case_representative_forecast(cfg, case_dir, case_id, ...
                model_cases(m), truth_records, forecast_records);
        end
    end
end

function output_path = local_draw_case_wis_distribution(case_dir, case_id, case_scores)
%LOCAL_DRAW_CASE_WIS_DISTRIBUTION Draw per-case model WIS distributions.
    spec = build_plot_spec( ...
        'figure_name', sprintf('Part B %s WIS distribution', char(case_id)), ...
        'title', "", ...
        'shared_x_label', "Fixed forecast configuration", ...
        'shared_y_label', "Window WIS", ...
        'font_size', 9, ...
        'axis_label_font_size', 10, ...
        'tick_label_font_size', 9, ...
        'x_tick_rotation', 20, ...
        'color_order', local_thesis_color_order(), ...
        'layout', struct('num_rows', 2, 'num_cols', 2), ...
        'legend', struct('visible', false), ...
        'output_path', fullfile(case_dir, sprintf('partB_%s_model_wis_distribution.png', ...
            char(case_id))), ...
        'size_cm', [17.0, 11.0]);

    if isempty(case_scores) || height(case_scores) == 0
        output_path = local_export_empty_panel(spec, "No case score data");
        return;
    end

    scenario_ids = unique(case_scores.ScenarioName, 'stable');
    num_scenarios = numel(scenario_ids);
    panel_labels = local_panel_labels(num_scenarios);
    panels = repmat(struct('series', local_empty_series(0), ...
        'plot_spec', struct()), num_scenarios, 1);

    for i = 1:num_scenarios
        rows = case_scores(case_scores.ScenarioName == scenario_ids(i), :);
        config_labels = local_model_exo_label(rows.Model, rows.ExoMode);
        panels(i).series = local_box_series(config_labels, rows.WindowWIS, ...
            rows.ScenarioName, "Window WIS", 1);
        panels(i).plot_spec = struct('panel_label', panel_labels(i));
    end

    fig = plot_multi_panel_figure(panels, spec);
    output_path = export_figure(fig, spec);
    close(fig);
end

function output_path = local_draw_case_representative_forecast(cfg, case_dir, ...
    case_id, model_case, truth_records, forecast_records)
%LOCAL_DRAW_CASE_REPRESENTATIVE_FORECAST Draw fixed-lead forecasts across windows.
    model_label = local_model_case_label(model_case);
    model_token = local_model_case_token(model_case);
    spec = build_plot_spec( ...
        'figure_name', sprintf('Part B %s %s representative forecast', ...
            char(case_id), char(model_label)), ...
        'title', "", ...
        'x_label', "Time, $t$ (days)", ...
        'y_label', "Effective reproduction number, $R_t$", ...
        'font_size', 9, ...
        'axis_label_font_size', 10, ...
        'tick_label_font_size', 9, ...
        'y_limits', cfg.Rt.bounds, ...
        'legend', struct('location', "northoutside", ...
            'orientation', "horizontal", 'box', "off", 'font_size', 8), ...
        'output_path', fullfile(case_dir, ...
            sprintf('partB_%s_representative_rt_forecast_%s.png', ...
            char(case_id), char(model_token))), ...
        'size_cm', [16.0, 8.5]);

    forecast_idx = find([forecast_records.case_id] == case_id & ...
        [forecast_records.model_type] == model_case.model_type & ...
        [forecast_records.exo_mode] == model_case.exo_mode, 1);
    if isempty(forecast_idx)
        output_path = local_export_empty_panel(spec, "No forecast artifact");
        return;
    end

    forecast_record = forecast_records(forecast_idx);
    truth_idx = local_match_truth_record(truth_records, forecast_record);
    if isempty(truth_idx)
        output_path = local_export_empty_panel(spec, "No matching truth artifact");
        return;
    end

    loaded_forecast = load(forecast_record.path);
    if ~isfield(loaded_forecast, 'forecast_results') || ...
            isempty(loaded_forecast.forecast_results)
        output_path = local_export_empty_panel(spec, "No forecast windows");
        return;
    end

    panel.series = local_representative_forecast_series( ...
        loaded_forecast.forecast_results, truth_records(truth_idx), cfg, model_label);
    fig = plot_single_panel(panel, spec);
    output_path = export_figure(fig, spec);
    close(fig);
end

function output_path = local_draw_observation_noise_example(cfg, figure_dir, truth_records)
%LOCAL_DRAW_OBSERVATION_NOISE_EXAMPLE Draw latent versus observed Rt input.
    spec = build_plot_spec( ...
        'figure_name', "Part B observation-noise example", ...
        'title', "", ...
        'x_label', "Time, $t$ (days)", ...
        'y_label', "Effective reproduction number, $R_t$", ...
        'font_size', 9, ...
        'axis_label_font_size', 10, ...
        'tick_label_font_size', 9, ...
        'y_limits', cfg.Rt.bounds, ...
        'legend', struct('location', "northoutside", ...
            'orientation', "horizontal", 'box', "off", 'font_size', 9), ...
        'output_path', fullfile(figure_dir, 'partB_observation_noise.png'), ...
        'size_cm', [17.0, 8.5]);

    idx = find([truth_records.observation_noise_enabled], 1);
    if isempty(idx)
        output_path = local_export_empty_panel(spec, ...
            "Observation-noise case not present in this run");
        return;
    end

    truth = truth_records(idx);
    colors = local_thesis_color_order();
    panel.series = [ ...
        local_line_series(truth.tspan, truth.Rt_true, "Latent R_t", ...
            struct('Color', colors(1, :), 'LineWidth', 1.6), 1); ...
        local_line_series(truth.tspan, truth.Rt_model_input, "Model-input R_t", ...
            struct('Color', colors(2, :), 'LineWidth', 1.0), 2)];

    fig = plot_single_panel(panel, spec);
    output_path = export_figure(fig, spec);
    close(fig);
end

function output_path = local_draw_process_noise_example(~, figure_dir, truth_records)
%LOCAL_DRAW_PROCESS_NOISE_EXAMPLE Draw UDS reference versus SSA realizations.
    spec = build_plot_spec( ...
        'figure_name', "Part B process-noise example", ...
        'title', "", ...
        'x_label', "Time, $t$ (days)", ...
        'y_label', "Infected individuals, $I(t)$", ...
        'font_size', 9, ...
        'axis_label_font_size', 10, ...
        'tick_label_font_size', 9, ...
        'legend', struct('location', "northoutside", ...
            'orientation', "horizontal", 'box', "off", 'font_size', 8), ...
        'output_path', fullfile(figure_dir, 'partB_process_noise_uds_vs_ssa.png'), ...
        'size_cm', [17.0, 8.5]);

    ssa_idx = find([truth_records.process_noise_enabled] & ...
        [truth_records.truth_model] == "SIRS");
    if isempty(ssa_idx)
        output_path = local_export_empty_panel(spec, ...
            "Process-noise SIRS case not present in this run");
        return;
    end

    scenario_id = truth_records(ssa_idx(1)).scenario_id;
    uds_idx = find([truth_records.truth_model] == "SIRS" & ...
        [truth_records.solver] == "uds" & ...
        [truth_records.scenario_id] == scenario_id, 1);
    colors = local_thesis_color_order();
    series = local_empty_series(0);

    if ~isempty(uds_idx)
        series(end + 1, 1) = local_line_series( ...
            truth_records(uds_idx).tspan, truth_records(uds_idx).I_true, ...
            "UDS deterministic reference", ...
            struct('Color', colors(1, :), 'LineWidth', 1.8), 1);
    end

    ssa_idx = ssa_idx([truth_records(ssa_idx).scenario_id] == scenario_id);
    for i = 1:min(numel(ssa_idx), 4)
        rec = truth_records(ssa_idx(i));
        series(end + 1, 1) = local_line_series(rec.tspan, rec.I_true, ...
            "SSA stochastic trajectory", ...
            struct('Color', colors(1 + mod(i, size(colors, 1) - 1), :), ...
            'LineWidth', 1.0), 1 + i); %#ok<AGROW>
    end

    panel.series = series;
    fig = plot_single_panel(panel, spec);
    output_path = export_figure(fig, spec);
    close(fig);
end

function output_path = local_draw_structural_mismatch_truth(~, figure_dir, truth_records)
%LOCAL_DRAW_STRUCTURAL_MISMATCH_TRUTH Draw SEIR compartment trajectories.
    spec = build_plot_spec( ...
        'figure_name', "Part B SEIR structural-mismatch truth", ...
        'title', "", ...
        'shared_x_label', "Time, $t$ (days)", ...
        'shared_y_label', "Individuals", ...
        'font_size', 9, ...
        'axis_label_font_size', 10, ...
        'tick_label_font_size', 8, ...
        'panel_labels', ["A", "B", "C", "D"], ...
        'panel_label_style', struct('FontSize', 10, 'FontWeight', 'bold'), ...
        'layout', struct('num_rows', 2, 'num_cols', 2), ...
        'legend', struct('visible', false), ...
        'output_path', fullfile(figure_dir, 'partB_structural_mismatch_seir_truth.png'), ...
        'size_cm', [17.0, 10.0]);

    idx = find([truth_records.case_id] == "structural_mismatch" & ...
        [truth_records.truth_model] == "SEIR", 1);
    if isempty(idx)
        panels = repmat(struct('series', local_empty_series(0), ...
            'plot_spec', struct('no_data_text', ...
            "Structural-mismatch SEIR case not present in this run")), 4, 1);
    else
        truth = truth_records(idx);
        colors = local_thesis_color_order();
        compartment_names = ["Susceptible, $S(t)$", "Exposed, $E(t)$", ...
            "Infectious, $I(t)$", "Recovered, $R(t)$"];
        compartment_values = {truth.S_true, truth.E_true, truth.I_true, truth.R_true};
        panels = repmat(struct('series', local_empty_series(0), ...
            'plot_spec', struct()), 4, 1);
        for i = 1:4
            panels(i).series = local_line_series(truth.tspan, ...
                compartment_values{i}, compartment_names(i), ...
                struct('Color', colors(i, :), 'LineWidth', 1.4), 1);
            panels(i).plot_spec = struct('title', compartment_names(i));
        end
    end

    fig = plot_multi_panel_figure(panels, spec);
    output_path = export_figure(fig, spec);
    close(fig);
end

function output_path = local_draw_robustness_mean_wis(cfg, figure_dir, summary_tables)
%LOCAL_DRAW_ROBUSTNESS_MEAN_WIS Draw main mean-WIS robustness comparison.
    spec = build_plot_spec( ...
        'figure_name', "Part B robustness mean WIS", ...
        'title', "", ...
        'x_label', "Robustness setting", ...
        'y_label', "Mean WIS", ...
        'font_size', 9, ...
        'axis_label_font_size', 10, ...
        'tick_label_font_size', 8, ...
        'x_tick_rotation', 0, ...
        'color_order', local_thesis_color_order(), ...
        'legend', struct('location', "northoutside", ...
            'orientation', "horizontal", 'box', "off", 'font_size', 9), ...
        'output_path', fullfile(figure_dir, 'partB_robustness_mean_wis.png'), ...
        'size_cm', [17.0, 8.5]);

    case_model_summary = local_summary_table(summary_tables, 'case_model_summary');
    baseline_summary = local_summary_table(summary_tables, 'partA_baseline_summary');
    [x_positions, x_labels] = local_robustness_axis(cfg);
    model_cases = local_fixed_model_cases(cfg);

    series = local_empty_series(0);
    colors = local_thesis_color_order();
    for i = 1:numel(model_cases)
        y = local_mean_wis_by_case(case_model_summary, baseline_summary, ...
            model_cases(i), cfg);
        series(end + 1, 1) = local_line_series(x_positions, y, ...
            local_model_case_label(model_cases(i)), ...
            struct('Color', colors(i, :), 'LineWidth', 1.5, 'Marker', 'o', ...
            'MarkerSize', 5), i); %#ok<AGROW>
    end

    panel.series = series;
    fig = plot_single_panel(panel, spec);
    local_apply_categorical_x_axis(fig, x_positions, x_labels);
    output_path = export_figure(fig, spec);
    close(fig);
end

function output_path = local_draw_robustness_wis_by_horizon(cfg, figure_dir, summary_tables)
%LOCAL_DRAW_ROBUSTNESS_WIS_BY_HORIZON Draw horizon-wise WIS across cases.
    spec = build_plot_spec( ...
        'figure_name', "Part B robustness WIS by horizon", ...
        'title', "", ...
        'shared_x_label', "Forecast horizon, $h$ (days)", ...
        'shared_y_label', "Mean WIS", ...
        'font_size', 9, ...
        'axis_label_font_size', 10, ...
        'tick_label_font_size', 8, ...
        'panel_labels', ["A", "B"], ...
        'panel_label_style', struct('FontSize', 10, 'FontWeight', 'bold'), ...
        'layout', struct('num_rows', 1, 'num_cols', 2), ...
        'legend', struct('visible', false), ...
        'output_path', fullfile(figure_dir, 'partB_robustness_wis_by_horizon.png'), ...
        'size_cm', [17.0, 8.5]);

    horizon_summary = local_summary_table(summary_tables, 'case_horizon_summary');
    model_cases = local_fixed_model_cases(cfg);
    panels = repmat(struct('series', local_empty_series(0), ...
        'plot_spec', struct()), numel(model_cases), 1);

    for i = 1:numel(model_cases)
        if isempty(horizon_summary) || height(horizon_summary) == 0
            panels(i).series = local_empty_series(0);
        else
            model_idx = horizon_summary.Model == model_cases(i).model_type & ...
                horizon_summary.ExoMode == model_cases(i).exo_mode;
            panels(i).series = local_case_horizon_series(horizon_summary(model_idx, :), cfg);
        end
        panels(i).plot_spec = struct('title', local_model_case_label(model_cases(i)));
    end

    [fig, ~, axes_handles] = plot_multi_panel_figure(panels, spec);
    lgd = legend(axes_handles(1), 'Location', 'north', ...
        'Orientation', 'horizontal', 'Box', 'off', 'FontSize', 8);
    lgd.Layout.Tile = 'north';
    output_path = export_figure(fig, spec);
    close(fig);
end

function output_path = local_draw_coverage_interval_width(cfg, figure_dir, summary_tables)
%LOCAL_DRAW_COVERAGE_INTERVAL_WIDTH Draw coverage and interval-width diagnostics.
    spec = build_plot_spec( ...
        'figure_name', "Part B coverage and interval width", ...
        'title', "", ...
        'shared_x_label', "Robustness setting", ...
        'font_size', 9, ...
        'axis_label_font_size', 10, ...
        'tick_label_font_size', 8, ...
        'panel_labels', ["A", "B"], ...
        'panel_label_style', struct('FontSize', 10, 'FontWeight', 'bold'), ...
        'layout', struct('num_rows', 1, 'num_cols', 2), ...
        'legend', struct('visible', false), ...
        'output_path', fullfile(figure_dir, ...
            'partB_robustness_coverage_interval_width.png'), ...
        'size_cm', [17.0, 8.5]);

    case_model_summary = local_summary_table(summary_tables, 'case_model_summary');
    [x_positions, x_labels] = local_case_only_axis(cfg);
    model_cases = local_fixed_model_cases(cfg);
    metric_names = ["MeanCoverage", "MeanIntervalWidth"];
    y_labels = ["Empirical coverage", "Mean interval width"];
    panels = repmat(struct('series', local_empty_series(0), ...
        'plot_spec', struct()), 2, 1);

    colors = local_thesis_color_order();
    for p = 1:2
        series = local_empty_series(0);
        for i = 1:numel(model_cases)
            y = local_case_metric_values(case_model_summary, model_cases(i), ...
                cfg, metric_names(p));
            series(end + 1, 1) = local_line_series(x_positions, y, ...
                local_model_case_label(model_cases(i)), ...
                struct('Color', colors(i, :), 'LineWidth', 1.5, ...
                'Marker', 'o', 'MarkerSize', 5), i); %#ok<AGROW>
        end
        panels(p).series = series;
        panels(p).plot_spec = struct('title', y_labels(p), 'y_label', y_labels(p));
    end

    [fig, ~, axes_handles] = plot_multi_panel_figure(panels, spec);
    for i = 1:numel(axes_handles)
        local_apply_axis_ticks(axes_handles(i), x_positions, x_labels);
    end
    lgd = legend(axes_handles(1), 'Location', 'north', ...
        'Orientation', 'horizontal', 'Box', 'off', 'FontSize', 8);
    lgd.Layout.Tile = 'north';
    output_path = export_figure(fig, spec);
    close(fig);
end

function truth_records = local_load_truth_records(cfg)
%LOCAL_LOAD_TRUTH_RECORDS Load all active truth artifacts.
    cases = local_active_cases(cfg);
    active_scenarios = local_active_scenario_ids(cfg);
    truth_records = local_empty_truth_record(0);
    for i = 1:numel(cases)
        case_id = string(cases(i).case_id);
        for j = 1:numel(active_scenarios)
            artifact_path = fullfile(cfg.output.data_root_dir, ...
                sprintf('partB_%s_truth_%s.mat', char(case_id), ...
                char(active_scenarios(j))));
            if exist(artifact_path, 'file') == 2
                loaded = load(artifact_path);
                record = local_truth_record_from_loaded(loaded, artifact_path);
                truth_records(end + 1, 1) = record; %#ok<AGROW>
            end
        end
    end
end

function forecast_records = local_load_forecast_records(cfg)
%LOCAL_LOAD_FORECAST_RECORDS Index all active forecast artifacts.
    cases = local_active_cases(cfg);
    active_scenarios = local_active_scenario_ids(cfg);
    active_forecast_cases = local_active_forecast_cases(cfg);
    forecast_records = local_empty_forecast_record(0);
    for i = 1:numel(cases)
        case_id = string(cases(i).case_id);
        for s = 1:numel(active_scenarios)
            for f = 1:numel(active_forecast_cases)
                artifact_path = fullfile(cfg.output.forecast_dir, ...
                    sprintf('partB_%s_forecast_%s_%s_%s.mat', ...
                    char(case_id), char(active_scenarios(s)), ...
                    char(active_forecast_cases(f).model_type), ...
                    char(active_forecast_cases(f).exo_mode)));
                if exist(artifact_path, 'file') == 2
                    loaded = load(artifact_path);
                    record = local_forecast_record_from_loaded(loaded, artifact_path);
                    forecast_records(end + 1, 1) = record; %#ok<AGROW>
                end
            end
        end
    end
end

function record = local_truth_record_from_loaded(loaded, artifact_path)
%LOCAL_TRUTH_RECORD_FROM_LOADED Normalize truth artifact metadata.
    record = local_empty_truth_record(1);
    record.path = artifact_path;
    record.case_id = local_loaded_string(loaded, 'case_id', "");
    record.case_name = local_loaded_string(loaded, 'case_name', "");
    record.truth_model = local_loaded_string(loaded, 'truth_model', "");
    record.solver = local_loaded_string(loaded, 'solver', "");
    record.structural_mismatch_enabled = local_loaded_logical(loaded, ...
        'structural_mismatch_enabled', false);
    record.observation_noise_enabled = local_loaded_logical(loaded, ...
        'observation_noise_enabled', false);
    record.process_noise_enabled = local_loaded_logical(loaded, ...
        'process_noise_enabled', false);
    record.scenario_id = local_loaded_string(loaded, 'scenario_id', "");
    record.scenario_name = local_loaded_string(loaded, 'scenario_name', "");
    record.tspan = local_loaded_vector(loaded, 'tspan');
    record.Rt_true = local_loaded_vector(loaded, 'Rt_true');
    record.Rt_model_input = local_loaded_vector(loaded, 'Rt_model_input');
    record.I_true = local_loaded_vector(loaded, 'I_true');
    record.I_model_input = local_loaded_vector(loaded, 'I_model_input');
    record.S_true = local_loaded_vector(loaded, 'S_true');
    record.E_true = local_loaded_vector(loaded, 'E_true');
    record.R_true = local_loaded_vector(loaded, 'R_true');
end

function record = local_forecast_record_from_loaded(loaded, artifact_path)
%LOCAL_FORECAST_RECORD_FROM_LOADED Normalize forecast artifact metadata.
    record = local_empty_forecast_record(1);
    record.path = artifact_path;
    record.case_id = local_loaded_string(loaded, 'case_id', "");
    record.scenario_id = local_loaded_string(loaded, 'scenario_id', "");
    record.model_type = local_loaded_string(loaded, 'model_type', "");
    record.exo_mode = local_loaded_string(loaded, 'exo_mode', "");
    record.source_truth_artifact = local_loaded_string(loaded, ...
        'source_truth_artifact', "");
end

function idx = local_match_truth_record(truth_records, forecast_record)
%LOCAL_MATCH_TRUTH_RECORD Find the truth artifact behind a forecast artifact.
    idx = [];
    if isempty(truth_records)
        return;
    end

    path_match = find([truth_records.path] == forecast_record.source_truth_artifact, 1);
    if ~isempty(path_match)
        idx = path_match;
        return;
    end

    idx = find([truth_records.case_id] == forecast_record.case_id & ...
        [truth_records.scenario_id] == forecast_record.scenario_id, 1);
end

function series = local_representative_forecast_series(forecast_results, truth_record, cfg, model_label)
%LOCAL_REPRESENTATIVE_FORECAST_SERIES Build a fixed-lead comparison panel.
    colors = local_thesis_color_order();
    series = local_empty_series(0);

    series(end + 1, 1) = local_line_series(truth_record.tspan, ...
        truth_record.Rt_true, "Target", ...
        struct('Color', colors(1, :), 'LineWidth', 1.6), 1);

    if any(abs(truth_record.Rt_model_input - truth_record.Rt_true) > 1e-12)
        series(end + 1, 1) = local_line_series(truth_record.tspan, ...
            truth_record.Rt_model_input, "Input", ...
            struct('Color', [0.55, 0.55, 0.55], 'LineWidth', 0.9, ...
            'LineStyle', ':'), 2);
    end

    if isempty(forecast_results)
        return;
    end

    lead_time = local_plot_lead_time(cfg);
    alphas = local_struct_vector(forecast_results(1), 'interval_alphas');
    plot_alphas = local_plot_alphas(cfg, alphas);
    [target_days, pred, lower, upper] = local_extract_fixed_lead( ...
        forecast_results, lead_time, plot_alphas);
    labels = local_interval_labels(plot_alphas);
    interval_colors = local_interval_colors(numel(plot_alphas));

    for i = 1:numel(plot_alphas)
        valid_interval = isfinite(target_days) & isfinite(lower(:, i)) & ...
            isfinite(upper(:, i));
        if nnz(valid_interval) < 2
            continue;
        end
        interval_series = local_empty_series(1);
        interval_series.type = "ribbon";
        interval_series.x = target_days(valid_interval);
        interval_series.lower = lower(valid_interval, i);
        interval_series.upper = upper(valid_interval, i);
        interval_series.label = labels(i);
        interval_series.style = struct('FaceColor', interval_colors(i, :), ...
            'FaceAlpha', 0.16 + 0.08 * i, 'EdgeColor', 'none');
        interval_series.legend_rank = 5 + i;
        series(end + 1, 1) = interval_series; %#ok<AGROW>
    end

    valid_median = isfinite(target_days) & isfinite(pred);
    if any(valid_median)
        series(end + 1, 1) = local_line_series(target_days(valid_median), ...
            pred(valid_median), model_label, ...
            struct('Color', colors(2, :), 'LineWidth', 1.5, ...
            'LineStyle', '--', 'Marker', 'o', 'MarkerSize', 3.0), 4);
    end
end

function [target_days, median_forecast, lower_forecast, upper_forecast] = ...
    local_extract_fixed_lead(forecast_results, lead_time, plot_alphas)
%LOCAL_EXTRACT_FIXED_LEAD Extract one forecast lead across all windows.
    num_results = numel(forecast_results);
    num_alphas = numel(plot_alphas);
    target_days = nan(num_results, 1);
    median_forecast = nan(num_results, 1);
    lower_forecast = nan(num_results, num_alphas);
    upper_forecast = nan(num_results, num_alphas);

    for i = 1:num_results
        pred = local_struct_vector(forecast_results(i), 'Rt_pred');
        t_future = local_struct_vector(forecast_results(i), 't_future');
        lower = local_struct_matrix(forecast_results(i), 'lower_bounds');
        upper = local_struct_matrix(forecast_results(i), 'upper_bounds');
        alphas = local_struct_vector(forecast_results(i), 'interval_alphas');

        if numel(pred) < lead_time || numel(t_future) < lead_time
            continue;
        end

        target_days(i) = t_future(lead_time);
        median_forecast(i) = pred(lead_time);
        for j = 1:num_alphas
            alpha_idx = local_alpha_index(alphas, plot_alphas(j));
            if isempty(alpha_idx)
                continue;
            end
            if size(lower, 1) >= lead_time && size(upper, 1) >= lead_time && ...
                    size(lower, 2) >= alpha_idx && size(upper, 2) >= alpha_idx
                lower_forecast(i, j) = lower(lead_time, alpha_idx);
                upper_forecast(i, j) = upper(lead_time, alpha_idx);
            end
        end
    end
end

function series = local_case_horizon_series(horizon_rows, cfg)
%LOCAL_CASE_HORIZON_SERIES Build horizon-wise series by robustness case.
    series = local_empty_series(0);
    if isempty(horizon_rows) || height(horizon_rows) == 0
        return;
    end

    cases = cfg.robustness_cases;
    colors = local_thesis_color_order();
    for i = 1:numel(cases)
        case_id = string(cases(i).case_id);
        rows = horizon_rows(horizon_rows.CaseID == case_id, :);
        if isempty(rows) || height(rows) == 0
            continue;
        end
        [horizon, order] = sort(double(rows.HorizonIdx));
        series(end + 1, 1) = local_line_series(horizon, ...
            double(rows.MeanWIS(order)), local_case_short_label(case_id), ...
            struct('Color', colors(1 + mod(i - 1, size(colors, 1)), :), ...
            'LineWidth', 1.3), i); %#ok<AGROW>
    end
end

function values = local_mean_wis_by_case(case_model_summary, baseline_summary, ...
    model_case, cfg)
%LOCAL_MEAN_WIS_BY_CASE Return Part A baseline plus Part B case WIS values.
    values = nan(numel(cfg.robustness_cases) + 1, 1);
    if ~isempty(baseline_summary) && height(baseline_summary) > 0
        idx = baseline_summary.Model == model_case.model_type & ...
            baseline_summary.ExoMode == model_case.exo_mode;
        if any(idx)
            values(1) = baseline_summary.PartAMeanWIS(find(idx, 1));
        end
    end
    for i = 1:numel(cfg.robustness_cases)
        values(i + 1) = local_case_metric_value(case_model_summary, ...
            model_case, string(cfg.robustness_cases(i).case_id), "MeanWIS");
    end
end

function values = local_case_metric_values(case_model_summary, model_case, ...
    cfg, metric_name)
%LOCAL_CASE_METRIC_VALUES Return one metric across Part B cases.
    values = nan(numel(cfg.robustness_cases), 1);
    for i = 1:numel(cfg.robustness_cases)
        values(i) = local_case_metric_value(case_model_summary, model_case, ...
            string(cfg.robustness_cases(i).case_id), metric_name);
    end
end

function value = local_case_metric_value(case_model_summary, model_case, ...
    case_id, metric_name)
%LOCAL_CASE_METRIC_VALUE Read a case/model summary metric.
    value = nan;
    if isempty(case_model_summary) || height(case_model_summary) == 0 || ...
            ~ismember(metric_name, case_model_summary.Properties.VariableNames)
        return;
    end

    idx = case_model_summary.CaseID == case_id & ...
        case_model_summary.Model == model_case.model_type & ...
        case_model_summary.ExoMode == model_case.exo_mode;
    if any(idx)
        values = double(case_model_summary.(metric_name)(idx));
        value = local_mean_finite(values);
    end
end

function [x_positions, x_labels] = local_robustness_axis(cfg)
%LOCAL_ROBUSTNESS_AXIS Return x-axis positions for Part A plus Part B cases.
    x_positions = (1:(numel(cfg.robustness_cases) + 1))';
    x_labels = ["Part A"; local_case_axis_labels(cfg)];
end

function [x_positions, x_labels] = local_case_only_axis(cfg)
%LOCAL_CASE_ONLY_AXIS Return x-axis positions for Part B cases only.
    x_positions = (1:numel(cfg.robustness_cases))';
    x_labels = local_case_axis_labels(cfg);
end

function labels = local_case_axis_labels(cfg)
%LOCAL_CASE_AXIS_LABELS Return compact case tick labels.
    labels = strings(numel(cfg.robustness_cases), 1);
    for i = 1:numel(cfg.robustness_cases)
        labels(i) = local_case_short_label(string(cfg.robustness_cases(i).case_id));
    end
end

function local_apply_categorical_x_axis(fig, x_positions, x_labels)
%LOCAL_APPLY_CATEGORICAL_X_AXIS Apply compact categorical x ticks.
    axes_handles = findobj(fig, 'Type', 'axes');
    for i = 1:numel(axes_handles)
        local_apply_axis_ticks(axes_handles(i), x_positions, x_labels);
    end
end

function local_apply_axis_ticks(ax, x_positions, x_labels)
%LOCAL_APPLY_AXIS_TICKS Apply x ticks and labels to one axes.
    if isempty(ax) || ~isgraphics(ax)
        return;
    end
    ax.XTick = double(x_positions(:));
    ax.XTickLabel = cellstr(x_labels(:));
    xlim(ax, [min(x_positions) - 0.35, max(x_positions) + 0.35]);
end

function model_cases = local_fixed_model_cases(cfg)
%LOCAL_FIXED_MODEL_CASES Return fixed forecast cases in configured order.
    fixed = cfg.fixed_forecast_cases;
    model_cases = repmat(struct('model_type', "", 'exo_mode', ""), ...
        1, numel(fixed));
    for i = 1:numel(fixed)
        model_cases(i).model_type = string(fixed(i).model_type);
        model_cases(i).exo_mode = string(fixed(i).exo_mode);
    end
end

function label = local_model_case_label(model_case)
%LOCAL_MODEL_CASE_LABEL Return display label for a configured model case.
    label = local_model_exo_label(model_case.model_type, model_case.exo_mode);
end

function token = local_model_case_token(model_case)
%LOCAL_MODEL_CASE_TOKEN Return filename token for a configured model case.
    token = string(model_case.model_type) + "_" + string(model_case.exo_mode);
    token = regexprep(token, '[^A-Za-z0-9_]+', '_');
end

function label = local_model_exo_label(model_type, exo_mode)
%LOCAL_MODEL_EXO_LABEL Return compact model/exogenous label text.
    model_type = string(model_type);
    exo_mode = string(exo_mode);
    label = model_type + " / " + exo_mode;
end

function label = local_case_short_label(case_id)
%LOCAL_CASE_SHORT_LABEL Return compact robustness-case label.
    switch char(string(case_id))
        case 'observation_noise'
            label = "Obs. noise";
        case 'process_noise'
            label = "Process";
        case 'structural_mismatch'
            label = "SEIR";
        case 'combined_stress'
            label = "Combined";
        otherwise
            label = string(case_id);
    end
end

function output_path = local_export_empty_panel(spec, message)
%LOCAL_EXPORT_EMPTY_PANEL Export a no-data single-panel figure.
    spec = build_plot_spec(spec, 'no_data_text', message);
    panel.series = local_empty_series(0);
    fig = plot_single_panel(panel, spec);
    output_path = export_figure(fig, spec);
    close(fig);
end

function required = local_required_thesis_figures(figure_dir)
%LOCAL_REQUIRED_THESIS_FIGURES Return required thesis-level figure paths.
    names = ["partB_observation_noise.png"; ...
        "partB_process_noise_uds_vs_ssa.png"; ...
        "partB_structural_mismatch_seir_truth.png"; ...
        "partB_robustness_mean_wis.png"; ...
        "partB_robustness_wis_by_horizon.png"; ...
        "partB_robustness_coverage_interval_width.png"];
    required = fullfile(figure_dir, names);
end

function output = local_required_table(s, field_name, artifact_path)
%LOCAL_REQUIRED_TABLE Read a required table field from an artifact.
    if isfield(s, field_name) && istable(s.(field_name))
        output = s.(field_name);
    else
        error('FIG:InvalidEvaluationArtifact', ...
            'Evaluation artifact %s is missing required table field: %s.', ...
            artifact_path, field_name);
    end
end

function table_data = local_summary_table(summary_tables, field_name)
%LOCAL_SUMMARY_TABLE Read a summary table field or return empty table.
    if isstruct(summary_tables) && isfield(summary_tables, field_name) && ...
            istable(summary_tables.(field_name))
        table_data = summary_tables.(field_name);
    else
        table_data = table();
    end
end

function cases = local_active_cases(cfg)
%LOCAL_ACTIVE_CASES Apply optional smoke-test case limiting.
    cases = cfg.robustness_cases;
    if cfg.smoke_test.enabled
        cases = cases(1:min(numel(cases), cfg.smoke_test.num_cases));
    end
end

function scenario_ids = local_active_scenario_ids(cfg)
%LOCAL_ACTIVE_SCENARIO_IDS Return active scenario ids.
    scenarios = cfg.scenarios;
    if cfg.smoke_test.enabled
        scenarios = scenarios(1:min(numel(scenarios), cfg.smoke_test.num_scenarios));
    end
    scenario_ids = strings(numel(scenarios), 1);
    for i = 1:numel(scenarios)
        scenario_ids(i) = string(scenarios(i).id);
    end
end

function forecast_cases = local_active_forecast_cases(cfg)
%LOCAL_ACTIVE_FORECAST_CASES Return active fixed forecast cases.
    forecast_cases = cfg.fixed_forecast_cases;
    if cfg.smoke_test.enabled
        forecast_cases = forecast_cases(1:min(numel(forecast_cases), ...
            cfg.smoke_test.num_forecast_cases));
    end
end

function record = local_empty_truth_record(n)
%LOCAL_EMPTY_TRUTH_RECORD Construct empty truth-record structs.
    record = repmat(struct( ...
        'path', "", ...
        'case_id', "", ...
        'case_name', "", ...
        'truth_model', "", ...
        'solver', "", ...
        'structural_mismatch_enabled', false, ...
        'observation_noise_enabled', false, ...
        'process_noise_enabled', false, ...
        'scenario_id', "", ...
        'scenario_name', "", ...
        'tspan', [], ...
        'Rt_true', [], ...
        'Rt_model_input', [], ...
        'I_true', [], ...
        'I_model_input', [], ...
        'S_true', [], ...
        'E_true', [], ...
        'R_true', []), n, 1);
end

function record = local_empty_forecast_record(n)
%LOCAL_EMPTY_FORECAST_RECORD Construct empty forecast-record structs.
    record = repmat(struct( ...
        'path', "", ...
        'case_id', "", ...
        'scenario_id', "", ...
        'model_type', "", ...
        'exo_mode', "", ...
        'source_truth_artifact', ""), n, 1);
end

function series = local_empty_series(n)
%LOCAL_EMPTY_SERIES Construct generic plotting series structs.
    series = repmat(struct( ...
        'type', "line", ...
        'x', [], ...
        'y', [], ...
        'lower', [], ...
        'upper', [], ...
        'group', [], ...
        'label', "", ...
        'style', struct(), ...
        'legend_rank', 1, ...
        'legend_visible', true), n, 1);
end

function series = local_line_series(x, y, label, style, rank)
%LOCAL_LINE_SERIES Build one generic line series.
    series = local_empty_series(1);
    series.type = "line";
    series.x = double(x(:));
    series.y = double(y(:));
    series.label = string(label);
    series.style = style;
    series.legend_rank = rank;
    series.legend_visible = strlength(series.label) > 0;
end

function series = local_box_series(x, y, group, label, rank)
%LOCAL_BOX_SERIES Build one generic boxchart series.
    series = local_empty_series(1);
    series.type = "boxchart";
    series.x = string(x(:));
    series.y = double(y(:));
    series.group = string(group(:));
    series.label = string(label);
    series.legend_rank = rank;
end

function values = local_loaded_vector(loaded, field_name)
%LOCAL_LOADED_VECTOR Read a numeric vector from a loaded artifact.
    values = [];
    if isfield(loaded, field_name) && ~isempty(loaded.(field_name))
        values = double(loaded.(field_name)(:));
    end
end

function value = local_loaded_string(loaded, field_name, default_value)
%LOCAL_LOADED_STRING Read a string-compatible field.
    value = string(default_value);
    if isfield(loaded, field_name) && ~isempty(loaded.(field_name))
        value = string(loaded.(field_name));
    end
end

function value = local_loaded_logical(loaded, field_name, default_value)
%LOCAL_LOADED_LOGICAL Read a logical-compatible field.
    value = logical(default_value);
    if isfield(loaded, field_name) && ~isempty(loaded.(field_name))
        value = logical(loaded.(field_name));
    end
end

function values = local_struct_vector(s, field_name)
%LOCAL_STRUCT_VECTOR Read a numeric vector from a struct.
    values = [];
    if isfield(s, field_name) && ~isempty(s.(field_name))
        values = double(s.(field_name)(:));
    end
end

function values = local_struct_matrix(s, field_name)
%LOCAL_STRUCT_MATRIX Read a numeric matrix from a struct.
    values = [];
    if isfield(s, field_name) && ~isempty(s.(field_name))
        values = double(s.(field_name));
    end
end

function plot_alphas = local_plot_alphas(cfg, available_alphas)
%LOCAL_PLOT_ALPHAS Return requested interval alphas available for plotting.
    if isfield(cfg.forecast, 'plot_alphas') && ~isempty(cfg.forecast.plot_alphas)
        plot_alphas = double(cfg.forecast.plot_alphas(:));
    else
        plot_alphas = double(available_alphas(:));
    end
end

function lead_time = local_plot_lead_time(cfg)
%LOCAL_PLOT_LEAD_TIME Return the displayed fixed forecast lead.
    if isfield(cfg.forecast, 'plot_lead_time') && ~isempty(cfg.forecast.plot_lead_time)
        lead_time = round(double(cfg.forecast.plot_lead_time));
    else
        lead_time = min(7, round(double(cfg.forecast.horizon)));
    end
    lead_time = max(1, min(lead_time, round(double(cfg.forecast.horizon))));
end

function labels = local_interval_labels(plot_alphas)
%LOCAL_INTERVAL_LABELS Build interval labels for selected alphas.
    labels = strings(numel(plot_alphas), 1);
    for i = 1:numel(plot_alphas)
        labels(i) = sprintf('%d%% PI', round((1 - plot_alphas(i)) * 100));
    end
end

function idx = local_alpha_index(stored_alphas, target_alpha)
%LOCAL_ALPHA_INDEX Match a requested alpha to a stored alpha.
    stored_alphas = double(stored_alphas(:));
    [distance, idx] = min(abs(stored_alphas - double(target_alpha)));
    if isempty(idx) || ~isfinite(distance) || distance > 1e-8
        idx = [];
    end
end

function colors = local_interval_colors(n)
%LOCAL_INTERVAL_COLORS Return interval ribbon colors.
    base = [0.35, 0.62, 0.80; 0.55, 0.72, 0.86; 0.75, 0.84, 0.91];
    colors = base(1:min(max(n, 1), size(base, 1)), :);
    if n > size(base, 1)
        colors = [colors; repmat(base(end, :), n - size(base, 1), 1)];
    end
end

function colors = local_thesis_color_order()
%LOCAL_THESIS_COLOR_ORDER Return thesis-friendly categorical colors.
    colors = [ ...
        0.0000, 0.4470, 0.7410; ...
        0.8500, 0.3250, 0.0980; ...
        0.4660, 0.6740, 0.1880; ...
        0.4940, 0.1840, 0.5560; ...
        0.3010, 0.7450, 0.9330; ...
        0.6350, 0.0780, 0.1840];
end

function value = local_mean_finite(values)
%LOCAL_MEAN_FINITE Mean over finite values only.
    values = double(values(:));
    values = values(isfinite(values));
    if isempty(values)
        value = nan;
    else
        value = mean(values);
    end
end

function labels = local_panel_labels(num_panels)
%LOCAL_PANEL_LABELS Build lowercase alphabetical panel labels.
    labels = strings(num_panels, 1);
    for i = 1:num_panels
        labels(i) = sprintf('(%s)', char('a' + i - 1));
    end
end
