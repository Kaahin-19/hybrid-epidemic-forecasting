%PARTC_03_EVALUATE_MODELS Evaluate Part C WHO-derived Rt forecasts.
%
%   Description:
%       Aggregates fixed Part C forecast artifacts and computes WIS summaries
%       for the WHO-derived Rt_est signal using the same WIS formula and
%       classification style as the Part A and Part B evaluation scripts. The
%       score outputs are restricted to AR/None and ARX/I by design. The
%       all-window WIS summary is the primary quantitative result; additional
%       Part C diagnostics identify explosive windows and stable-window scores
%       for interpretation only.
%
%   Workflow:
%       1. Identify the Part C fixed forecast artifacts.
%       2. Compute Rt WIS summaries and pointwise details.
%       3. Persist primary all-window CSV score artifacts.
%       4. Persist diagnostic explosive-window and stable-window artifacts.
%       5. Persist WIS boxplots.
%
%   See also PARTC_CONFIG, PLOT_MODEL_PERFORMANCE.

% A. M. Kaahin 2026-05-18

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Fixed Model Evaluation ===\n');

cfg = partC_config();
forecastDir = cfg.output.forecast_dir;
scoreDir    = cfg.output.score_dir;
figDir      = cfg.output.fig_dir;
explosive_wis_threshold = 1;

if ~exist(scoreDir, 'dir'), mkdir(scoreDir); end
if ~exist(figDir, 'dir'),   mkdir(figDir); end

fprintf('Scanning forecast directory: %s\n', forecastDir);

filePattern = fullfile(forecastDir, 'partC_02_forecast_real_*.mat');
files       = dir(filePattern);

if isempty(files)
    error('EVAL:NoData', ...
        'No Part C forecast results found. Run partC_02_run_forecasts.m first.');
end

%% 2. Score Aggregation
score_blocks  = cell(length(files), 1);
detail_blocks = cell(length(files), 1);
valid_configs = ["AR_None", "ARX_I"];

for i = 1:length(files)
    filename = files(i).name;
    fullPath = fullfile(forecastDir, filename);

    [scenario_id, model_type, exo_mode] = local_parse_forecast_name(filename);
    config_key = string(model_type) + "_" + string(exo_mode);
    if ~any(config_key == valid_configs)
        continue;
    end

    forecast_data = load(fullPath);
    if ~isfield(forecast_data, 'results') || isempty(forecast_data.results)
        continue;
    end
    results = forecast_data.results;

    file_score_blocks  = cell(length(results), 1);
    file_detail_blocks = cell(length(results), 1);

    for k = 1:length(results)
        [file_score_blocks{k}, file_detail_blocks{k}] = ...
            local_evaluate_window_result(results(k), scenario_id, ...
            model_type, exo_mode);
    end

    file_score_blocks = file_score_blocks(~cellfun('isempty', file_score_blocks));
    if ~isempty(file_score_blocks)
        score_blocks{i} = vertcat(file_score_blocks{:});
    end

    file_detail_blocks = file_detail_blocks(~cellfun('isempty', file_detail_blocks));
    if ~isempty(file_detail_blocks)
        detail_blocks{i} = vertcat(file_detail_blocks{:});
    end
end

score_blocks = score_blocks(~cellfun('isempty', score_blocks));
if isempty(score_blocks)
    error('EVAL:NoProbabilisticData', ...
        'No probabilistic Part C forecast results were available for evaluation.');
end
score_registry = vertcat(score_blocks{:});
score_registry.Properties.VariableNames = ...
    {'Scenario', 'Model', 'ExoMode', 'WindowDay', 'WindowWIS'};

local_require_exact_configs(score_registry);

detail_blocks = detail_blocks(~cellfun('isempty', detail_blocks));
if isempty(detail_blocks)
    pointwise_details = local_empty_pointwise_table();
else
    pointwise_details = vertcat(detail_blocks{:});
    pointwise_details.Properties.VariableNames = { ...
        'Scenario', 'Model', 'ExoMode', 'WindowDay', 'HorizonIdx', ...
        'ForecastDay', 'Truth_Rt', 'Median_Forecast', 'WIS'};
end

fprintf('Aggregated WIS scores for %d forecast windows.\n', height(score_registry));

%% 3. Rt WIS Summary
% The all-window WIS summary is the primary quantitative result for Part C.
wis_summary = groupsummary(score_registry, ...
    {'Scenario', 'Model', 'ExoMode'}, ...
    {'mean', 'median', 'std', 'min', 'max'}, ...
    'WindowWIS');

wis_summary.Properties.VariableNames = regexprep(wis_summary.Properties.VariableNames, ...
    {'mean_', 'median_', 'std_', 'min_', 'max_'}, ...
    {'Mean_', 'Median_', 'Std_', 'Min_', 'Max_'});

wis_summary = local_classify_wis_summary(wis_summary);
score_registry = local_attach_comparison_flags(score_registry, wis_summary);

fprintf('\n  [ Part C Rt WIS Summary ]\n');
disp(wis_summary(:, {'Scenario', 'Model', 'ExoMode', 'Mean_WindowWIS', ...
    'Std_WindowWIS', 'IsAcceptable', 'FailureReason', 'IncludeInMainComparison'}));

summaryFile = fullfile(scoreDir, 'partC_03_wis_performance_summary.csv');
writetable(wis_summary, summaryFile);
fprintf('WIS summary saved to: %s\n', summaryFile);

detailFile = fullfile(scoreDir, 'partC_03_wis_pointwise_details.csv');
writetable(pointwise_details, detailFile);
fprintf('Pointwise WIS details saved to: %s\n', detailFile);

alpha_labels = string(strjoin(compose('%.2f', double(cfg.forecast.wis_alphas)), ', '));
settingsFile = fullfile(scoreDir, 'partC_03_wis_settings.csv');
writetable(table(alpha_labels, 'VariableNames', {'WIS_Alphas'}), settingsFile);
fprintf('WIS settings saved to: %s\n', settingsFile);

%% 4. Diagnostic WIS Reporting
% These outputs identify instability and provide stable-window views only.
% They do not alter the primary all-window WIS summary above.
explosive_windows = local_explosive_window_table(score_registry, ...
    pointwise_details, explosive_wis_threshold);

explosiveFile = fullfile(scoreDir, 'partC_03_wis_explosive_windows.csv');
writetable(explosive_windows, explosiveFile);
fprintf('Explosive-window diagnostic saved to: %s\n', explosiveFile);

explosive_window_days = unique(score_registry.WindowDay( ...
    score_registry.WindowWIS > explosive_wis_threshold));
stable_idx = ~ismember(score_registry.WindowDay, explosive_window_days);
stable_score_registry = score_registry(stable_idx, :);
stable_wis_summary = local_stable_wis_summary(stable_score_registry);

fprintf('\n  [ Part C Stable-Window Diagnostic WIS Summary ]\n');
disp(stable_wis_summary);

stableSummaryFile = fullfile(scoreDir, ...
    'partC_03_wis_stable_window_summary.csv');
writetable(stable_wis_summary, stableSummaryFile);
fprintf('Stable-window diagnostic summary saved to: %s\n', stableSummaryFile);

%% 5. Visualization
plot_saved = plot_model_performance(score_registry, cfg);
partA_plot_path = fullfile(figDir, 'partA_04_wis_performance_boxplot.png');
wisPlotPath = fullfile(figDir, 'partC_03_wis_performance_boxplot.png');
if plot_saved && exist(partA_plot_path, 'file')
    movefile(partA_plot_path, wisPlotPath, 'f');
end

if plot_saved
    fprintf('WIS figure saved to: %s\n', wisPlotPath);
else
    fprintf('WIS performance visualization skipped: no finite accepted values.\n');
end

stablePlotPath = fullfile(figDir, ...
    'partC_03_wis_stable_window_boxplot.png');
stable_plot_saved = local_plot_stable_window_boxplot(stable_score_registry, ...
    stablePlotPath);

if stable_plot_saved
    fprintf('Stable-window diagnostic WIS figure saved to: %s\n', ...
        stablePlotPath);
else
    fprintf(['Stable-window diagnostic visualization skipped: ' ...
        'no finite stable-window values.\n']);
end

fprintf('=== Part C Fixed Model Evaluation Complete ===\n\n');

%% 6. Local Functions
function [scenario_id, model_type, exo_mode] = local_parse_forecast_name(filename)
%LOCAL_PARSE_FORECAST_NAME Parse partC_02 forecast artifact names.
    [~, nameBody] = fileparts(filename);
    tokens = split(string(nameBody), "_");

    if numel(tokens) ~= 6 || tokens(1) ~= "partC" || ...
            tokens(2) ~= "02" || tokens(3) ~= "forecast"
        error('EVAL:InvalidForecastFilename', ...
            'Unexpected Part C forecast filename: %s.', filename);
    end

    scenario_id = char(tokens(4));
    model_type  = char(tokens(5));
    exo_mode    = char(tokens(6));
end

function local_require_exact_configs(score_registry)
%LOCAL_REQUIRE_EXACT_CONFIGS Ensure Part C score outputs remain frozen.
    observed_configs = unique(score_registry(:, {'Model', 'ExoMode'}), 'rows');
    observed_keys = sort(string(observed_configs.Model) + "_" + ...
        string(observed_configs.ExoMode));
    expected_keys = sort(["AR_None"; "ARX_I"]);

    if ~isequal(observed_keys, expected_keys)
        error('EVAL:UnexpectedPartCConfigs', ...
            'Part C evaluation must contain exactly AR/None and ARX/I.');
    end
end

function [score_row, detail_rows] = local_evaluate_window_result( ...
    result_entry, scenario_id, model_type, exo_mode)
%LOCAL_EVALUATE_WINDOW_RESULT Compute WIS summaries for a forecast window.
    truth_Rt = double(result_entry.truth_Rt_window(:));
    pred_Rt  = double(result_entry.forecast_median(:));
    alphas   = reshape(double(result_entry.forecast_interval_alphas), 1, []);
    lower_Rt = double(result_entry.forecast_lower);
    upper_Rt = double(result_entry.forecast_upper);

    window_wis = inf;
    detail_rows = local_empty_pointwise_table();

    is_valid_shape = ...
        numel(truth_Rt) == numel(pred_Rt) && ...
        size(lower_Rt, 1) == numel(truth_Rt) && ...
        size(upper_Rt, 1) == numel(truth_Rt) && ...
        size(lower_Rt, 2) == numel(alphas) && ...
        size(upper_Rt, 2) == numel(alphas) && ...
        ~isempty(alphas);

    if is_valid_shape
        pointwise_wis = local_compute_wis(truth_Rt, pred_Rt, ...
            lower_Rt, upper_Rt, alphas);
        if any(~isfinite(pointwise_wis))
            pointwise_wis = inf(numel(truth_Rt), 1);
        else
            window_wis = mean(pointwise_wis);
        end

        if numel(result_entry.time_horizon(:)) == numel(truth_Rt)
            horizon_idx = (1:numel(truth_Rt))';
            detail_rows = table( ...
                repmat(categorical(string(scenario_id)), numel(truth_Rt), 1), ...
                repmat(categorical(string(model_type)), numel(truth_Rt), 1), ...
                repmat(categorical(string(exo_mode)), numel(truth_Rt), 1), ...
                repmat(result_entry.window_day, numel(truth_Rt), 1), ...
                horizon_idx, ...
                double(result_entry.time_horizon(:)), ...
                truth_Rt, ...
                pred_Rt, ...
                pointwise_wis, ...
                'VariableNames', {'Scenario', 'Model', 'ExoMode', 'WindowDay', ...
                'HorizonIdx', 'ForecastDay', 'Truth_Rt', 'Median_Forecast', 'WIS'});
        end
    end

    score_row = table( ...
        categorical(string(scenario_id)), ...
        categorical(string(model_type)), ...
        categorical(string(exo_mode)), ...
        result_entry.window_day, ...
        window_wis);
end

function detail_rows = local_empty_pointwise_table()
%LOCAL_EMPTY_POINTWISE_TABLE Construct an empty pointwise WIS table.
    detail_rows = table( ...
        categorical.empty(0, 1), ...
        categorical.empty(0, 1), ...
        categorical.empty(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        'VariableNames', {'Scenario', 'Model', 'ExoMode', 'WindowDay', ...
        'HorizonIdx', 'ForecastDay', 'Truth_Rt', 'Median_Forecast', 'WIS'});
end

function wis = local_compute_wis(truth_Rt, median_Rt, lower_Rt, upper_Rt, alphas)
%LOCAL_COMPUTE_WIS Compute pointwise weighted interval score values.
    num_intervals = numel(alphas);
    wis = 0.5 * abs(truth_Rt - median_Rt);

    for j = 1:num_intervals
        alpha = alphas(j);
        interval_score = (upper_Rt(:, j) - lower_Rt(:, j)) ...
            + (2 / alpha) * max(lower_Rt(:, j) - truth_Rt, 0) ...
            + (2 / alpha) * max(truth_Rt - upper_Rt(:, j), 0);
        wis = wis + (alpha / 2) * interval_score;
    end

    wis = wis / (num_intervals + 0.5);
end

function summary_stats = local_classify_wis_summary(summary_stats)
%LOCAL_CLASSIFY_WIS_SUMMARY Mark out-of-scale WIS scores before plotting.
    num_rows = height(summary_stats);
    mean_wis = summary_stats.Mean_WindowWIS;

    is_acceptable = true(num_rows, 1);
    failure_reason = strings(num_rows, 1);

    invalid_idx = ~isfinite(mean_wis) | mean_wis <= 0;
    is_acceptable(invalid_idx) = false;
    failure_reason(invalid_idx) = "nonfinite_or_nonpositive_wis";

    finite_positive_idx = isfinite(mean_wis) & mean_wis > 0;
    finite_positive_wis = mean_wis(finite_positive_idx);

    if numel(finite_positive_wis) >= 3
        log_wis = log10(finite_positive_wis);
        center_log_wis = median(log_wis);
        robust_spread = median(abs(log_wis - center_log_wis));
        outlier_threshold = center_log_wis + max(6 * robust_spread, 3);

        all_log_wis = nan(num_rows, 1);
        all_log_wis(finite_positive_idx) = log10(mean_wis(finite_positive_idx));
        outlier_idx = finite_positive_idx & all_log_wis > outlier_threshold;

        is_acceptable(outlier_idx) = false;
        failure_reason(outlier_idx) = "robust_log_outlier";
    end

    include_in_main = false(num_rows, 1);
    config_table = unique(summary_stats(:, {'Model', 'ExoMode'}), 'rows');

    for i = 1:height(config_table)
        config_idx = summary_stats.Model == config_table.Model(i) & ...
            summary_stats.ExoMode == config_table.ExoMode(i);
        include_in_main(config_idx) = all(is_acceptable(config_idx));
    end

    summary_stats.IsAcceptable = is_acceptable;
    summary_stats.FailureReason = failure_reason;
    summary_stats.IncludeInMainComparison = include_in_main;
end

function score_registry = local_attach_comparison_flags(score_registry, summary_stats)
%LOCAL_ATTACH_COMPARISON_FLAGS Propagate configuration-level plotting status.
    include_in_main = false(height(score_registry), 1);
    config_table = unique(summary_stats(:, ...
        {'Model', 'ExoMode', 'IncludeInMainComparison'}), 'rows');

    for i = 1:height(config_table)
        config_idx = score_registry.Model == config_table.Model(i) & ...
            score_registry.ExoMode == config_table.ExoMode(i);
        include_in_main(config_idx) = config_table.IncludeInMainComparison(i);
    end

    score_registry.IncludeInMainComparison = include_in_main;
end

function explosive_windows = local_explosive_window_table(score_registry, ...
    pointwise_details, explosive_wis_threshold)
%LOCAL_EXPLOSIVE_WINDOW_TABLE Identify diagnostic Part C explosive windows.
    explosive_scores = score_registry( ...
        score_registry.WindowWIS > explosive_wis_threshold, ...
        {'Scenario', 'Model', 'ExoMode', 'WindowDay', 'WindowWIS'});

    explosive_windows = local_empty_explosive_window_table();
    for i = 1:height(explosive_scores)
        detail_idx = ...
            string(pointwise_details.Scenario) == ...
            string(explosive_scores.Scenario(i)) & ...
            string(pointwise_details.Model) == ...
            string(explosive_scores.Model(i)) & ...
            string(pointwise_details.ExoMode) == ...
            string(explosive_scores.ExoMode(i)) & ...
            pointwise_details.WindowDay == explosive_scores.WindowDay(i);

        window_details = pointwise_details(detail_idx, :);
        worst_pointwise_wis = NaN;
        worst_horizon_idx   = NaN;
        worst_forecast_day  = NaN;
        truth_Rt            = NaN;
        median_forecast     = NaN;

        if ~isempty(window_details)
            [worst_pointwise_wis, worst_idx] = max(window_details.WIS);
            worst_horizon_idx = window_details.HorizonIdx(worst_idx);
            worst_forecast_day = window_details.ForecastDay(worst_idx);
            truth_Rt = window_details.Truth_Rt(worst_idx);
            median_forecast = window_details.Median_Forecast(worst_idx);
        end

        row = table( ...
            explosive_scores.Scenario(i), ...
            explosive_scores.Model(i), ...
            explosive_scores.ExoMode(i), ...
            explosive_scores.WindowDay(i), ...
            explosive_scores.WindowWIS(i), ...
            worst_pointwise_wis, ...
            worst_horizon_idx, ...
            worst_forecast_day, ...
            truth_Rt, ...
            median_forecast, ...
            'VariableNames', {'Scenario', 'Model', 'ExoMode', ...
            'WindowDay', 'WindowWIS', 'WorstPointwiseWIS', ...
            'WorstHorizonIdx', 'WorstForecastDay', 'Truth_Rt', ...
            'Median_Forecast'});
        if i == 1
            explosive_windows = row;
        else
            explosive_windows = [explosive_windows; row]; %#ok<AGROW>
        end
    end
end

function explosive_windows = local_empty_explosive_window_table()
%LOCAL_EMPTY_EXPLOSIVE_WINDOW_TABLE Build an empty diagnostic table.
    explosive_windows = table( ...
        categorical.empty(0, 1), ...
        categorical.empty(0, 1), ...
        categorical.empty(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        'VariableNames', {'Scenario', 'Model', 'ExoMode', ...
        'WindowDay', 'WindowWIS', 'WorstPointwiseWIS', ...
        'WorstHorizonIdx', 'WorstForecastDay', 'Truth_Rt', ...
        'Median_Forecast'});
end

function stable_wis_summary = local_stable_wis_summary(stable_score_registry)
%LOCAL_STABLE_WIS_SUMMARY Summarize windows after diagnostic exclusion.
    if isempty(stable_score_registry)
        stable_wis_summary = local_empty_stable_wis_summary();
        return;
    end

    stable_wis_summary = groupsummary(stable_score_registry, ...
        {'Scenario', 'Model', 'ExoMode'}, ...
        {'mean', 'median', 'std', 'min', 'max'}, ...
        'WindowWIS');

    stable_wis_summary.Properties.VariableNames = regexprep( ...
        stable_wis_summary.Properties.VariableNames, ...
        {'mean_', 'median_', 'std_', 'min_', 'max_'}, ...
        {'Mean_', 'Median_', 'Std_', 'Min_', 'Max_'});

    stable_wis_summary = stable_wis_summary(:, ...
        {'Scenario', 'Model', 'ExoMode', 'GroupCount', ...
        'Mean_WindowWIS', 'Median_WindowWIS', 'Std_WindowWIS', ...
        'Min_WindowWIS', 'Max_WindowWIS'});
end

function stable_wis_summary = local_empty_stable_wis_summary()
%LOCAL_EMPTY_STABLE_WIS_SUMMARY Build an empty stable-window summary table.
    stable_wis_summary = table( ...
        categorical.empty(0, 1), ...
        categorical.empty(0, 1), ...
        categorical.empty(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        'VariableNames', {'Scenario', 'Model', 'ExoMode', ...
        'GroupCount', 'Mean_WindowWIS', 'Median_WindowWIS', ...
        'Std_WindowWIS', 'Min_WindowWIS', 'Max_WindowWIS'});
end

function was_saved = local_plot_stable_window_boxplot(stable_score_registry, ...
    out_path)
%LOCAL_PLOT_STABLE_WINDOW_BOXPLOT Plot diagnostic stable-window WIS values.
    was_saved = false;

    if isempty(stable_score_registry) || ...
            ~any(isfinite(stable_score_registry.WindowWIS))
        return;
    end

    fig = figure('Name', 'Stable-Window WIS Diagnostic', 'Visible', 'off');
    fig.Units = 'centimeters';
    fig.Position(3) = 17.0;
    fig.Position(4) = 8.5;

    tlo = tiledlayout(1, 1, 'Padding', 'compact');

    ax = nexttile(tlo);
    hold(ax, 'on');

    axtoolbar(ax, {'export'});

    valid_idx = isfinite(stable_score_registry.WindowWIS);
    plot_data = stable_score_registry(valid_idx, :);
    plot_config = string(plot_data.Model) + " (" + ...
        string(plot_data.ExoMode) + ")";

    boxchart(ax, categorical(plot_config), plot_data.WindowWIS, ...
        'GroupByColor', plot_data.Scenario);

    ylabel(ax, 'WIS ($\mathcal{R}_t$)', 'Interpreter', 'latex');
    title(ax, 'Part C Stable-Window WIS');
    legend(ax, 'Location', 'bestoutside');
    grid(ax, 'on');

    exportgraphics(fig, out_path, 'Resolution', 300);
    close(fig);
    was_saved = true;
end
