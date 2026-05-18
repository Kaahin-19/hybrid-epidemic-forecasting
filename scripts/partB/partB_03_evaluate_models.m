%PARTB_03_EVALUATE_MODELS Evaluate Part B Rt forecasts and SIRS projections.
%
%   Description:
%       Aggregates fixed Part B forecast artifacts, computes Rt Weighted
%       Interval Score summaries, and evaluates SIRS state projections
%       against the corresponding SEIR truth trajectories. The evaluation
%       uses the same WIS formula and acceptable/outlier classification
%       style as the Part A evaluation script.
%
%   Workflow:
%       1. Identify all Part B fixed forecast artifacts.
%       2. Compute Rt WIS summaries and pointwise details.
%       3. Compute SIRS-vs-SEIR S and I projection errors.
%       4. Persist CSV score artifacts and figures.
%
%   See also PARTB_CONFIG, GENDATA_SIRS, PLOT_MODEL_PERFORMANCE.

% A. M. Kaahin 2026-05-18

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part B Fixed Model Evaluation ===\n');

cfg = partB_config();
forecastDir = cfg.output.forecast_dir;
scoreDir    = cfg.output.score_dir;
figDir      = cfg.output.fig_dir;
dataDir     = cfg.output.data_dir;

if ~exist(scoreDir, 'dir'), mkdir(scoreDir); end
if ~exist(figDir, 'dir'),   mkdir(figDir); end

fprintf('Scanning forecast directory: %s\n', forecastDir);

filePattern = fullfile(forecastDir, 'partB_02_forecast_*.mat');
files       = dir(filePattern);

if isempty(files)
    error('EVAL:NoData', ...
        'No Part B forecast results found. Run partB_02_run_fixed_forecasts.m first.');
end

%% 2. Score Aggregation
score_blocks      = cell(length(files), 1);
detail_blocks     = cell(length(files), 1);
state_blocks      = cell(length(files), 1);
valid_configs     = ["AR_None", "ARX_S", "ARX_I", "ARX_Both"];

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
    file_state_blocks  = cell(length(results), 1);

    truth_path = fullfile(dataDir, sprintf('partB_01_truth_seir_%s.mat', scenario_id));
    if ~exist(truth_path, 'file')
        error('EVAL:MissingTruth', 'Missing SEIR truth file: %s.', truth_path);
    end
    truth_data = load(truth_path);

    for k = 1:length(results)
        [file_score_blocks{k}, file_detail_blocks{k}] = ...
            local_evaluate_window_result(results(k), scenario_id, model_type, exo_mode);
        file_state_blocks{k} = local_evaluate_projection_window( ...
            results(k), truth_data, cfg, scenario_id, model_type, exo_mode);
    end

    file_score_blocks = file_score_blocks(~cellfun('isempty', file_score_blocks));
    if ~isempty(file_score_blocks)
        score_blocks{i} = vertcat(file_score_blocks{:});
    end

    file_detail_blocks = file_detail_blocks(~cellfun('isempty', file_detail_blocks));
    if ~isempty(file_detail_blocks)
        detail_blocks{i} = vertcat(file_detail_blocks{:});
    end

    file_state_blocks = file_state_blocks(~cellfun('isempty', file_state_blocks));
    if ~isempty(file_state_blocks)
        state_blocks{i} = vertcat(file_state_blocks{:});
    end
end

score_blocks = score_blocks(~cellfun('isempty', score_blocks));
if isempty(score_blocks)
    error('EVAL:NoProbabilisticData', ...
        'No probabilistic forecast results were available for evaluation.');
end
score_registry = vertcat(score_blocks{:});
score_registry.Properties.VariableNames = ...
    {'Scenario', 'Model', 'ExoMode', 'WindowDay', 'WindowWIS'};

detail_blocks = detail_blocks(~cellfun('isempty', detail_blocks));
if isempty(detail_blocks)
    pointwise_details = local_empty_pointwise_table();
else
    pointwise_details = vertcat(detail_blocks{:});
    pointwise_details.Properties.VariableNames = { ...
        'Scenario', 'Model', 'ExoMode', 'WindowDay', 'HorizonIdx', ...
        'ForecastDay', 'Truth_Rt', 'Median_Forecast', 'WIS'};
end

state_blocks = state_blocks(~cellfun('isempty', state_blocks));
if isempty(state_blocks)
    error('STATEEVAL:NoProjectionData', ...
        'No state projection details were generated.');
end
state_details = vertcat(state_blocks{:});

fprintf('Aggregated WIS scores for %d forecast windows.\n', height(score_registry));
fprintf('Aggregated state projection errors for %d forecasted state points.\n', ...
    height(state_details));

%% 3. Rt WIS Summary
wis_summary = groupsummary(score_registry, ...
    {'Scenario', 'Model', 'ExoMode'}, ...
    {'mean', 'median', 'std', 'min', 'max'}, ...
    'WindowWIS');

wis_summary.Properties.VariableNames = regexprep(wis_summary.Properties.VariableNames, ...
    {'mean_', 'median_', 'std_', 'min_', 'max_'}, ...
    {'Mean_', 'Median_', 'Std_', 'Min_', 'Max_'});

wis_summary = local_classify_wis_summary(wis_summary);
score_registry = local_attach_comparison_flags(score_registry, wis_summary);

fprintf('\n  [ Part B Rt WIS Summary ]\n');
disp(wis_summary(:, {'Scenario', 'Model', 'ExoMode', 'Mean_WindowWIS', ...
    'Std_WindowWIS', 'IsAcceptable', 'FailureReason', 'IncludeInMainComparison'}));

summaryFile = fullfile(scoreDir, 'partB_03_wis_performance_summary.csv');
writetable(wis_summary, summaryFile);
fprintf('WIS summary saved to: %s\n', summaryFile);

detailFile = fullfile(scoreDir, 'partB_03_wis_pointwise_details.csv');
writetable(pointwise_details, detailFile);
fprintf('Pointwise WIS details saved to: %s\n', detailFile);

alpha_labels = string(strjoin(compose('%.2f', double(cfg.forecast.wis_alphas)), ', '));
settingsFile = fullfile(scoreDir, 'partB_03_wis_settings.csv');
writetable(table(alpha_labels, 'VariableNames', {'WIS_Alphas'}), settingsFile);
fprintf('WIS settings saved to: %s\n', settingsFile);

%% 4. State Projection Summary
state_summary = groupsummary(state_details, ...
    {'Scenario', 'Model', 'ExoMode'}, ...
    {'mean', 'median', 'std', 'min', 'max'}, ...
    {'AbsError_S', 'AbsError_I'});

state_summary.Properties.VariableNames = regexprep(state_summary.Properties.VariableNames, ...
    {'mean_', 'median_', 'std_', 'min_', 'max_'}, ...
    {'Mean_', 'Median_', 'Std_', 'Min_', 'Max_'});

fprintf('\n  [ Part B State Projection Error Summary ]\n');
disp(state_summary);

stateSummaryFile = fullfile(scoreDir, 'partB_03_state_projection_summary.csv');
writetable(state_summary, stateSummaryFile);
fprintf('State projection summary saved to: %s\n', stateSummaryFile);

stateDetailFile = fullfile(scoreDir, 'partB_03_state_projection_details.csv');
writetable(state_details, stateDetailFile);
fprintf('State projection details saved to: %s\n', stateDetailFile);

%% 5. Visualization
plot_saved = plot_model_performance(score_registry, cfg);
partA_plot_path = fullfile(figDir, 'partA_04_wis_performance_boxplot.png');
wisPlotPath = fullfile(figDir, 'partB_03_wis_performance_boxplot.png');
if plot_saved && exist(partA_plot_path, 'file')
    movefile(partA_plot_path, wisPlotPath, 'f');
end

if plot_saved
    fprintf('WIS figure saved to: %s\n', wisPlotPath);
else
    fprintf('WIS performance visualization skipped: no finite accepted values.\n');
end

iStateErrorPlotPath = fullfile(figDir, ...
    'partB_03_state_projection_I_error_boxplot.png');
local_plot_state_error_boxplot(state_details, 'AbsError_I', iStateErrorPlotPath, ...
    'Absolute Error in I', 'Part B Infected-State Projection Error', ...
    'SIRS Infected-State Projection Error Against SEIR Truth');
fprintf('I-error boxplot saved to: %s\n', iStateErrorPlotPath);

sStateErrorPlotPath = fullfile(figDir, ...
    'partB_03_state_projection_S_error_boxplot.png');
local_plot_state_error_boxplot(state_details, 'AbsError_S', sStateErrorPlotPath, ...
    'Absolute Error in S', 'Part B Susceptible-State Projection Error', ...
    'SIRS Susceptible-State Projection Error Against SEIR Truth');
fprintf('S-error boxplot saved to: %s\n', sStateErrorPlotPath);

examplePlotPath = fullfile(figDir, ...
    'partB_03_state_projection_example_paths.png');
if exist(examplePlotPath, 'file')
    delete(examplePlotPath);
end

statePathPlotPaths = local_plot_scenario_projection_paths( ...
    state_details, dataDir, figDir, cfg);
fprintf('Scenario-wise state projection path figures saved:\n');
for i = 1:numel(statePathPlotPaths)
    fprintf('  %s\n', statePathPlotPaths(i));
end

fprintf('=== Part B Fixed Model Evaluation Complete ===\n\n');

%% 6. Local Functions
function [scenario_id, model_type, exo_mode] = local_parse_forecast_name(filename)
%LOCAL_PARSE_FORECAST_NAME Parse partB_02 forecast artifact names.
    [~, nameBody] = fileparts(filename);
    tokens = split(string(nameBody), "_");

    if numel(tokens) ~= 6 || tokens(1) ~= "partB" || ...
            tokens(2) ~= "02" || tokens(3) ~= "forecast"
        error('EVAL:InvalidForecastFilename', ...
            'Unexpected Part B forecast filename: %s.', filename);
    end

    scenario_id = char(tokens(4));
    model_type  = char(tokens(5));
    exo_mode    = char(tokens(6));
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

function detail_rows = local_evaluate_projection_window( ...
    result_entry, truth_data, cfg, scenario_id, model_type, exo_mode)
%LOCAL_EVALUATE_PROJECTION_WINDOW Compute SIRS-vs-SEIR state errors.
    forecast_Rt = double(result_entry.forecast_median(:));
    forecast_days = double(result_entry.time_horizon(:));
    horizon = numel(forecast_Rt);

    detail_rows = table();
    if horizon == 0 || numel(forecast_days) ~= horizon
        return;
    end

    idx_T = result_entry.window_day_idx;
    idx_end = idx_T + horizon;

    if idx_T < 1 || idx_end > numel(truth_data.S_true)
        return;
    end

    current_S = truth_data.S_true(idx_T);
    current_I = truth_data.I_true(idx_T);
    current_R = cfg.sirs_projection.pop_size - current_S - current_I;

    if current_R < 0
        warning('STATEEVAL:InvalidProjectionState', ...
            'Projection state has negative remainder for %s window %d.', ...
            scenario_id, result_entry.window_day);
        return;
    end

    try
        projected_state = local_project_sirs_state( ...
            forecast_Rt, current_S, current_I, current_R, cfg);
    catch ME
        warning('STATEEVAL:ProjectionFailure', ...
            'SIRS projection failed for %s window %d: %s', ...
            scenario_id, result_entry.window_day, ME.message);
        return;
    end

    truth_S = double(truth_data.S_true(idx_T+1:idx_end));
    truth_I = double(truth_data.I_true(idx_T+1:idx_end));
    projected_S = projected_state(1, :).';
    projected_I = projected_state(2, :).';

    horizon_idx = (1:horizon)';
    detail_rows = table( ...
        repmat(categorical(string(scenario_id)), horizon, 1), ...
        repmat(categorical(string(model_type)), horizon, 1), ...
        repmat(categorical(string(exo_mode)), horizon, 1), ...
        repmat(result_entry.window_day, horizon, 1), ...
        horizon_idx, ...
        forecast_days, ...
        truth_S(:), ...
        projected_S(:), ...
        abs(projected_S(:) - truth_S(:)), ...
        truth_I(:), ...
        projected_I(:), ...
        abs(projected_I(:) - truth_I(:)), ...
        'VariableNames', {'Scenario', 'Model', 'ExoMode', 'WindowDay', ...
        'HorizonIdx', 'ForecastDay', 'Truth_S', 'Projected_S', 'AbsError_S', ...
        'Truth_I', 'Projected_I', 'AbsError_I'});
end

function projected_state = local_project_sirs_state( ...
    forecast_Rt, current_S, current_I, current_R, cfg)
%LOCAL_PROJECT_SIRS_STATE Run one SIRS projection from a forecast origin.
    forecast_Rt = double(forecast_Rt(:));
    horizon = numel(forecast_Rt);

    params = cfg.sirs_projection;
    params.I0 = current_I;
    params.R0_init = current_R;
    params.solver = 'uds';
    params.compile = 0;
    params.Rt = [forecast_Rt; forecast_Rt(end)].';

    projection_tspan = 0:horizon;
    [umod, ~] = genData_SIRS(projection_tspan, params, cfg.sim.seed);

    projected_state = umod.U(:, 2:end);

    if size(projected_state, 2) ~= horizon
        error('STATEEVAL:ProjectionLength', ...
            'Projected SIRS trajectory has an invalid horizon length.');
    end

    if abs(umod.U(1, 1) - current_S) > max(1e-6 * params.pop_size, 1e-6)
        error('STATEEVAL:ProjectionInitialState', ...
            'Projected SIRS trajectory did not preserve the requested S0.');
    end
end

function local_plot_state_error_boxplot(state_details, errorColumn, outPath, ...
    yLabelText, figureName, titleText)
%LOCAL_PLOT_STATE_ERROR_BOXPLOT Visualize state projection errors.
    valid_idx = isfinite(state_details.(errorColumn));
    if ~any(valid_idx)
        warning('PLOT:NoStateErrorData', ...
            'No finite %s projection errors were available.', errorColumn);
        return;
    end

    plot_data = state_details(valid_idx, :);
    config_id = string(plot_data.Model) + " (" + string(plot_data.ExoMode) + ")";
    error_values = plot_data.(errorColumn);

    fig = figure('Name', figureName, 'Visible', 'off');
    fig.Units = 'centimeters';
    fig.Position(3) = 17.0;
    fig.Position(4) = 8.5;

    ax = axes(fig);
    hold(ax, 'on');
    axtoolbar(ax, {'export'});

    boxchart(ax, categorical(config_id), error_values, ...
        'GroupByColor', plot_data.Scenario);
    ylabel(ax, yLabelText);
    title(ax, titleText);
    legend(ax, 'Location', 'bestoutside');
    grid(ax, 'on');

    exportgraphics(fig, outPath, 'Resolution', 300);
end

function saved_paths = local_plot_scenario_projection_paths( ...
    state_details, dataDir, figDir, cfg)
%LOCAL_PLOT_SCENARIO_PROJECTION_PATHS Plot full-timespan state paths.
    saved_paths = strings(0, 1);

    if isempty(state_details)
        warning('PLOT:NoStatePathData', 'No state projection paths were available.');
        return;
    end

    scenario_ids = strings(numel(cfg.scenarios), 1);
    for i = 1:numel(cfg.scenarios)
        scenario_ids(i) = string(cfg.scenarios(i).id);
    end

    for i = 1:numel(scenario_ids)
        scenario_id = scenario_ids(i);
        truth_path = fullfile(dataDir, ...
            sprintf('partB_01_truth_seir_%s.mat', scenario_id));

        if ~exist(truth_path, 'file')
            warning('PLOT:MissingTruth', ...
                'Missing truth file for state path figure: %s.', truth_path);
            continue;
        end

        scenario_idx = string(state_details.Scenario) == scenario_id;
        scenario_rows = state_details(scenario_idx, :);
        if isempty(scenario_rows)
            warning('PLOT:NoScenarioStatePathData', ...
                'No state projection paths were available for %s.', scenario_id);
            continue;
        end

        truth_data = load(truth_path, 'S_true', 'I_true', 'tspan');
        outPath = fullfile(figDir, ...
            sprintf('partB_03_state_projection_paths_%s.png', scenario_id));
        local_plot_one_scenario_projection_path(scenario_rows, truth_data, ...
            scenario_id, outPath);
        saved_paths(end + 1, 1) = string(outPath);
    end
end

function local_plot_one_scenario_projection_path(scenario_rows, truth_data, ...
    scenario_id, outPath)
%LOCAL_PLOT_ONE_SCENARIO_PROJECTION_PATH Plot one scenario state path summary.
    fig = figure('Name', sprintf('Part B State Projection Paths %s', scenario_id), ...
        'Visible', 'off');
    fig.Units = 'centimeters';
    fig.Position(3) = 17.0;
    fig.Position(4) = 11.0;

    tlo = tiledlayout(fig, 2, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
    axS = nexttile(tlo);
    axI = nexttile(tlo);
    hold(axS, 'on');
    hold(axI, 'on');
    axtoolbar(axS, {'export'});
    axtoolbar(axI, {'export'});

    plot(axS, truth_data.tspan(:), truth_data.S_true(:), 'k-', ...
        'LineWidth', 2.0, 'DisplayName', 'SEIR Truth');
    plot(axI, truth_data.tspan(:), truth_data.I_true(:), 'k-', ...
        'LineWidth', 2.0, 'DisplayName', 'SEIR Truth');

    model_order = ["AR"; "ARX"; "ARX"; "ARX"];
    exo_order   = ["None"; "S"; "I"; "Both"];
    colors = lines(numel(model_order));

    for i = 1:numel(model_order)
        row_idx = string(scenario_rows.Model) == model_order(i) & ...
            string(scenario_rows.ExoMode) == exo_order(i);
        rows = scenario_rows(row_idx, :);
        if isempty(rows)
            continue;
        end

        rows = rows(isfinite(rows.ForecastDay) & ...
            isfinite(rows.Projected_S) & isfinite(rows.Projected_I), :);
        if isempty(rows)
            continue;
        end

        [forecast_days, median_S, median_I] = local_median_projection_by_day(rows);
        label = sprintf('%s (%s)', model_order(i), exo_order(i));

        plot(axS, forecast_days, median_S, '--', ...
            'Color', colors(i, :), 'LineWidth', 1.2, 'DisplayName', label);
        plot(axI, forecast_days, median_I, '--', ...
            'Color', colors(i, :), 'LineWidth', 1.2, 'DisplayName', label);
    end

    title(axS, sprintf('Scenario %s Susceptible-State Projection Paths', ...
        scenario_id));
    ylabel(axS, 'S');
    xlim(axS, [min(truth_data.tspan(:)), max(truth_data.tspan(:))]);
    grid(axS, 'on');
    legend(axS, 'Location', 'bestoutside');

    xlabel(axI, 'Time (days)');
    ylabel(axI, 'I');
    title(axI, sprintf('Scenario %s Infected-State Projection Paths', ...
        scenario_id));
    xlim(axI, [min(truth_data.tspan(:)), max(truth_data.tspan(:))]);
    grid(axI, 'on');
    legend(axI, 'Location', 'bestoutside');

    exportgraphics(fig, outPath, 'Resolution', 300);
end

function [forecast_days, median_S, median_I] = local_median_projection_by_day(rows)
%LOCAL_MEDIAN_PROJECTION_BY_DAY Collapse rolling forecasts by calendar day.
    [group_id, forecast_days] = findgroups(rows.ForecastDay);
    median_S = splitapply(@median, rows.Projected_S, group_id);
    median_I = splitapply(@median, rows.Projected_I, group_id);

    [forecast_days, sort_idx] = sort(forecast_days);
    median_S = median_S(sort_idx);
    median_I = median_I(sort_idx);
end
