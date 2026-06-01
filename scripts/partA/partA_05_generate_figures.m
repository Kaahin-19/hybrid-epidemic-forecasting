%PARTA_05_GENERATE_FIGURES Generate Part A thesis figures.
%
%   Description:
%       Loads existing Part A truth, model-selection, forecast, evaluation,
%       and table artifacts, then generates presentation figures only.
%       Evaluation tables and .mat artifacts are produced by Part A 04.
%
%   Workflow:
%       1. Load finalized Part A artifacts from data/results folders.
%       2. Build plot specifications with final labels and output paths.
%       3. Draw reusable visualization functions and export figures.
%
%   See also PARTA_CONFIG, PARTA_04_EVALUATE_FORECASTS, BUILD_PLOT_SPEC, ...
%            EXPORT_FIGURE.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-01

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A Figure Generation ===\n');

cfg = partA_config();
data_dir = cfg.output.data_dir;
selection_dir = cfg.output.model_selection_dir;
forecast_dir = cfg.output.forecast_dir;
evaluation_dir = cfg.output.score_dir;
table_dir = cfg.output.table_dir;
figure_dir = cfg.output.fig_dir;

if ~exist(figure_dir, 'dir'), mkdir(figure_dir); end

evaluation_artifact = fullfile(evaluation_dir, 'partA_04_evaluation_results.mat');
if exist(evaluation_artifact, 'file') ~= 2
    error('FIG:MissingEvaluationArtifact', ...
        ['Missing Part A 04 evaluation artifact: %s\n' ...
        'Run scripts/partA/partA_04_evaluate_forecasts.m first.'], ...
        evaluation_artifact);
end

%% 2. Load Existing Artifacts
evaluation_data = load(evaluation_artifact);
truth_scenarios = local_load_truth_scenarios(data_dir, cfg);
selection_index = local_file_index(selection_dir, 'partA_02_global_hyperparameters_*.mat');
forecast_index = local_file_index(forecast_dir, 'partA_03_forecast_*.mat');
table_index = local_file_index(table_dir, 'partA_04_*.csv');

window_scores = evaluation_data.window_scores;
summaries = evaluation_data.summaries;

table_cache = struct();
table_cache.model_summary = local_read_table_or_default( ...
    fullfile(table_dir, 'partA_04_model_summary.csv'), summaries.model_summary);
table_cache.horizon_summary = local_read_table_or_default( ...
    fullfile(table_dir, 'partA_04_horizon_summary.csv'), summaries.horizon_summary);
table_cache.interval_summary = local_read_table_or_default( ...
    fullfile(table_dir, 'partA_04_interval_summary.csv'), summaries.interval_summary);

fprintf('Loaded %d truth artifacts from %s\n', numel(truth_scenarios), data_dir);
fprintf('Indexed %d forecast artifacts, %d selection artifacts, and %d table files.\n', ...
    height(forecast_index), height(selection_index), height(table_index));

generated_figures = strings(0, 1);

%% 3. Scenario Trajectories
scenario_labels = local_scenario_labels(truth_scenarios);
rt_spec = build_plot_spec( ...
    'figure_name', "Part A Rt scenarios", ...
    'title', "Synthetic effective reproduction-number scenarios", ...
    'x_label', "Time (days)", ...
    'y_label', "$\mathcal{R}_t$", ...
    'scenario_labels', scenario_labels, ...
    'y_limits', cfg.Rt.bounds, ...
    'output_path', fullfile(figure_dir, 'partA_05_rt_scenarios.png'), ...
    'size_cm', [17.0, 12.0]);
fig = plot_rt_scenarios(truth_scenarios, rt_spec);
generated_figures = [generated_figures; export_figure(fig, rt_spec)]; %#ok<AGROW>
close(fig);

%% 4. Model WIS Distribution
performance_spec = build_plot_spec( ...
    'figure_name', "Part A model WIS distribution", ...
    'title', "Forecast WIS distribution by model configuration", ...
    'x_label', "Model / exogenous mode", ...
    'y_label', "Window WIS", ...
    'output_path', fullfile(figure_dir, 'partA_05_model_wis_distribution.png'), ...
    'legend', struct('location', "bestoutside"), ...
    'size_cm', [18.0, 9.5]);
fig = plot_model_performance(window_scores, performance_spec);
generated_figures = [generated_figures; export_figure(fig, performance_spec)]; %#ok<AGROW>
close(fig);

%% 5. Horizon-Wise WIS
horizon_legend = struct( ...
    'labels', local_model_exo_labels(table_cache.horizon_summary), ...
    'location', "bestoutside");
horizon_spec = build_plot_spec( ...
    'figure_name', "Part A mean WIS by horizon", ...
    'title', "Mean WIS by forecast horizon", ...
    'x_label', "Forecast horizon (days)", ...
    'y_label', "Mean WIS", ...
    'legend', horizon_legend, ...
    'output_path', fullfile(figure_dir, 'partA_05_mean_wis_by_horizon.png'), ...
    'size_cm', [18.0, 9.5]);
fig = plot_wis_by_horizon(table_cache.horizon_summary, horizon_spec);
generated_figures = [generated_figures; export_figure(fig, horizon_spec)]; %#ok<AGROW>
close(fig);

%% 6. Coverage Summary
coverage_legend = struct( ...
    'labels', local_model_exo_labels(table_cache.interval_summary), ...
    'reference_label', "Nominal coverage", ...
    'location', "bestoutside");
coverage_spec = build_plot_spec( ...
    'figure_name', "Part A coverage summary", ...
    'title', "Empirical predictive-interval coverage", ...
    'x_label', "Nominal coverage", ...
    'y_label', "Empirical coverage", ...
    'legend', coverage_legend, ...
    'x_limits', [0, 1], ...
    'y_limits', [0, 1], ...
    'output_path', fullfile(figure_dir, 'partA_05_coverage_summary.png'), ...
    'size_cm', [18.0, 9.5]);
fig = plot_coverage_summary(table_cache.interval_summary, coverage_spec);
generated_figures = [generated_figures; export_figure(fig, coverage_spec)]; %#ok<AGROW>
close(fig);

%% 7. Forecast Comparisons for Best Global Configuration
best_config = local_best_configuration(table_cache.model_summary);
if isempty(best_config)
    warning('FIG:NoBestConfiguration', ...
        'Skipping forecast comparison figures: no finite model summary was available.');
else
    for i = 1:numel(truth_scenarios)
        scenario_id = string(truth_scenarios(i).scenario_id);
        [forecast_results, forecast_path] = local_load_forecast_results( ...
            forecast_dir, scenario_id, best_config.Model, best_config.ExoMode);
        if isempty(forecast_results)
            warning('FIG:MissingForecastComparisonArtifact', ...
                'No forecast artifact found for %s / %s / %s.', ...
                scenario_id, best_config.Model, best_config.ExoMode);
            continue;
        end

        plot_name = sprintf('partA_05_forecast_comparison_%s_%s_%s.png', ...
            char(local_safe_token(scenario_id)), ...
            char(local_safe_token(best_config.Model)), ...
            char(local_safe_token(best_config.ExoMode)));
        comparison_title = sprintf('%d-day-ahead forecast comparison: %s, %s / %s', ...
            cfg.forecast.plot_lead_time, char(truth_scenarios(i).scenario_name), ...
            char(best_config.Model), char(best_config.ExoMode));
        interval_labels = string(compose('%d%% predictive interval', ...
            round((1 - sort(double(cfg.forecast.plot_alphas(:)))) * 100)));
        interval_labels = interval_labels(:);
        legend_spec = struct( ...
            'truth_label', "Ground truth", ...
            'median_label', sprintf('%d-day-ahead median forecast', ...
            cfg.forecast.plot_lead_time), ...
            'interval_labels', interval_labels, ...
            'location', "northwest");

        comparison_spec = build_plot_spec( ...
            'figure_name', "Part A forecast comparison", ...
            'title', comparison_title, ...
            'x_label', "Time (days)", ...
            'y_label', "$\mathcal{R}_t$", ...
            'lead_time', cfg.forecast.plot_lead_time, ...
            'plot_alphas', cfg.forecast.plot_alphas, ...
            'y_limits', cfg.Rt.bounds, ...
            'legend', legend_spec, ...
            'output_path', fullfile(figure_dir, plot_name), ...
            'size_cm', [17.0, 9.5]);

        fprintf('Drawing comparison from %s\n', forecast_path);
        fig = plot_forecast_comparison(forecast_results, truth_scenarios(i), ...
            comparison_spec);
        generated_figures = [generated_figures; ...
            export_figure(fig, comparison_spec)]; %#ok<AGROW>
        close(fig);
    end
end

%% 8. Completion
fprintf('Saved %d figure files under %s\n', numel(generated_figures), figure_dir);
fprintf('=== Part A Figure Generation Complete ===\n\n');

%% 9. Local Functions
function scenarios = local_load_truth_scenarios(data_dir, cfg)
%LOCAL_LOAD_TRUTH_SCENARIOS Load Part A truth artifacts.
    truth_files = dir(fullfile(data_dir, 'partA_01_truth_*.mat'));
    truth_files = local_sort_dir_by_name(truth_files);
    if isempty(truth_files)
        error('FIG:NoTruthArtifacts', ...
            'No Part A truth artifacts found under %s.', data_dir);
    end

    scenarios = repmat(struct('scenario_id', "", 'scenario_name', "", ...
        'tspan', [], 'Rt_true', []), numel(truth_files), 1);

    for i = 1:numel(truth_files)
        artifact_path = fullfile(truth_files(i).folder, truth_files(i).name);
        loaded = load(artifact_path);
        scenario_id = local_loaded_string(loaded, 'scenario_id', ...
            local_parse_truth_scenario_id(truth_files(i).name));
        scenarios(i).scenario_id = scenario_id;
        scenarios(i).scenario_name = local_loaded_string(loaded, ...
            'scenario_name', local_scenario_name_from_config(cfg, scenario_id));
        scenarios(i).tspan = loaded.tspan;
        scenarios(i).Rt_true = loaded.Rt_true;
    end
end

function table_data = local_file_index(folder_path, pattern)
%LOCAL_FILE_INDEX Return a table of files matching a folder pattern.
    files = dir(fullfile(folder_path, pattern));
    files = local_sort_dir_by_name(files);
    table_data = table(strings(numel(files), 1), strings(numel(files), 1), ...
        'VariableNames', {'Name', 'Path'});
    for i = 1:numel(files)
        table_data.Name(i) = string(files(i).name);
        table_data.Path(i) = string(fullfile(files(i).folder, files(i).name));
    end
end

function table_data = local_read_table_or_default(table_path, fallback_table)
%LOCAL_READ_TABLE_OR_DEFAULT Read a table artifact when available.
    if exist(table_path, 'file') == 2
        table_data = readtable(table_path);
    else
        table_data = fallback_table;
    end
end

function labels = local_scenario_labels(scenarios)
%LOCAL_SCENARIO_LABELS Build Part A scenario panel labels.
    labels = strings(numel(scenarios), 1);
    for i = 1:numel(scenarios)
        labels(i) = string(scenarios(i).scenario_id) + " - " + ...
            string(scenarios(i).scenario_name);
    end
end

function labels = local_model_exo_labels(summary_table)
%LOCAL_MODEL_EXO_LABELS Build Part A model/exogenous legend labels.
    if isempty(summary_table) || height(summary_table) == 0 || ...
            ~all(ismember({'Model', 'ExoMode'}, summary_table.Properties.VariableNames))
        labels = strings(0, 1);
        return;
    end
    group_ids = string(summary_table.Model) + " / " + string(summary_table.ExoMode);
    labels = unique(group_ids, 'stable');
end

function best_config = local_best_configuration(model_summary)
%LOCAL_BEST_CONFIGURATION Select the finite lowest-WIS model configuration.
    best_config = struct([]);
    required_vars = {'Model', 'ExoMode', 'MeanWIS'};
    if isempty(model_summary) || height(model_summary) == 0 || ...
            ~all(ismember(required_vars, model_summary.Properties.VariableNames))
        return;
    end

    mean_wis = double(model_summary.MeanWIS);
    finite_idx = find(isfinite(mean_wis));
    if isempty(finite_idx)
        return;
    end

    [~, local_idx] = min(mean_wis(finite_idx));
    row_idx = finite_idx(local_idx);
    best_config = struct( ...
        'Model', string(model_summary.Model(row_idx)), ...
        'ExoMode', string(model_summary.ExoMode(row_idx)), ...
        'MeanWIS', mean_wis(row_idx));
end

function [forecast_results, forecast_path] = local_load_forecast_results( ...
    forecast_dir, scenario_id, model_type, exo_mode)
%LOCAL_LOAD_FORECAST_RESULTS Load canonical or legacy forecast result arrays.
    forecast_results = [];
    forecast_path = "";
    filename = sprintf('partA_03_forecast_%s_%s_%s.mat', ...
        char(scenario_id), char(model_type), char(exo_mode));
    candidate_path = fullfile(forecast_dir, filename);
    if exist(candidate_path, 'file') ~= 2
        return;
    end

    loaded = load(candidate_path);
    forecast_path = string(candidate_path);
    if isfield(loaded, 'forecast_results') && ~isempty(loaded.forecast_results)
        forecast_results = loaded.forecast_results;
    elseif isfield(loaded, 'results') && ~isempty(loaded.results)
        forecast_results = loaded.results;
    end
end

function scenario_id = local_parse_truth_scenario_id(filename)
%LOCAL_PARSE_TRUTH_SCENARIO_ID Parse scenario id from truth artifact name.
    [~, name_body] = fileparts(filename);
    tokens = split(string(name_body), "_");
    scenario_id = tokens(end);
end

function scenario_name = local_scenario_name_from_config(cfg, scenario_id)
%LOCAL_SCENARIO_NAME_FROM_CONFIG Read scenario display name from config.
    scenario_name = string(scenario_id);
    for i = 1:numel(cfg.scenarios)
        if string(cfg.scenarios(i).id) == string(scenario_id)
            scenario_name = string(cfg.scenarios(i).name);
            return;
        end
    end
end

function value = local_loaded_string(loaded, field_name, default_value)
%LOCAL_LOADED_STRING Read a string scalar from a loaded MAT struct.
    if isfield(loaded, field_name) && ~isempty(loaded.(field_name))
        value = string(loaded.(field_name));
    else
        value = string(default_value);
    end
end

function token = local_safe_token(value)
%LOCAL_SAFE_TOKEN Convert display values into filename-safe tokens.
    token = regexprep(string(value), '[^A-Za-z0-9]+', '_');
    token = regexprep(token, '^_+|_+$', '');
end

function sorted_files = local_sort_dir_by_name(files)
%LOCAL_SORT_DIR_BY_NAME Sort a dir struct by file name.
    if isempty(files)
        sorted_files = files;
        return;
    end
    [~, order] = sort({files.name});
    sorted_files = files(order);
end
