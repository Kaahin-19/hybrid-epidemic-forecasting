%PARTC_04_LOCAL_REFINEMENT Recalibrate Part C AR/ARX orders on real data.
%
%   Description:
%       Extends Part C with a held-out sensitivity analysis. The existing
%       frozen Part C AR/None and ARX/I comparison remains the primary
%       transfer test. This script evaluates small local real-data order
%       grids around the Part A-selected AR/ARX configurations, selects the
%       lowest-WIS order on early forecast windows, and compares frozen versus
%       locally refined orders on later holdout WHO-derived windows.
%
%   Workflow:
%       1. Initialization and processed-data loading.
%       2. Forecast-origin construction and time-ordered calibration/holdout
%          split.
%       3. Calibration-grid WIS scoring and local order selection.
%       4. Diagnostic all-window WIS comparison for frozen and locally
%          refined orders.
%       5. Holdout WIS comparison for frozen and locally refined orders.
%       6. Artifact and figure persistence.
%
%   See also PARTC_CONFIG, FIT_AR_MODEL, FIT_ARX_MODEL.

% A. M. Kaahin 2026-05-19

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Local Refinement Extension ===\n');

cfg = partC_config();
processedPath = fullfile(cfg.output.data_processed_dir, ...
    'partC_01_real_data_processed.mat');
refinementDir = cfg.refinement.output_dir;
scoreDir      = cfg.output.score_dir;
figDir        = cfg.output.fig_dir;
wis_alphas    = cfg.forecast.wis_alphas;

if ~exist(processedPath, 'file')
    error('REFINE:MissingProcessedData', ...
        ['Missing processed WHO-derived real-data artifact. ' ...
        'Run partC_01_prepare_real_data.m first.']);
end

if ~exist(refinementDir, 'dir'), mkdir(refinementDir); end
if ~exist(scoreDir, 'dir'),      mkdir(scoreDir); end
if ~exist(figDir, 'dir'),        mkdir(figDir); end

selected_families = local_parse_selected_model_families( ...
    getenv('PARTC_REFINEMENT_MODELS'));

fprintf('Configuration: Refinement models = %s\n', ...
    strjoin(cellstr(selected_families), ', '));
fprintf('Configuration: Calibration fraction = %.2f\n', ...
    cfg.refinement.calibration_fraction);
fprintf('Configuration: Refinement output directory = %s\n', refinementDir);

loaded = load(processedPath);
local_validate_processed_data(loaded, processedPath);

date = loaded.date(:);
tspan = loaded.t(:);
Rt_true = loaded.Rt_est(:);
I_scaled = loaded.I_scaled(:);

fprintf('Loaded %d processed real-data observations.\n', numel(Rt_true));

[window_days, window_indices] = local_forecast_windows(tspan, Rt_true, cfg);
[calibration_pos, holdout_pos] = local_split_forecast_windows( ...
    window_days, cfg.refinement.calibration_fraction);

fprintf('Calibration windows: %d (%d to %d)\n', ...
    numel(calibration_pos), window_days(calibration_pos(1)), ...
    window_days(calibration_pos(end)));
fprintf('Holdout windows: %d (%d to %d)\n', ...
    numel(holdout_pos), window_days(holdout_pos(1)), ...
    window_days(holdout_pos(end)));

%% 2. Calibration Grid Evaluation
calibration_blocks = cell(numel(selected_families), 1);
selected_blocks    = cell(numel(selected_families), 1);
selected_params    = cell(numel(selected_families), 1);

for i = 1:numel(selected_families)
    model_family = char(selected_families(i));
    [candidate_models, exo_mode] = local_candidate_grid(cfg, model_family);

    fprintf('Stage: Calibrating %s/%s local order grid\n', ...
        model_family, exo_mode);

    [calibration_blocks{i}, selected_params{i}, selected_mean_wis] = ...
        local_calibrate_family(model_family, exo_mode, candidate_models, ...
        Rt_true, I_scaled, window_indices, calibration_pos, ...
        cfg, wis_alphas);

    selected_blocks{i} = local_selected_order_row(model_family, exo_mode, ...
        selected_params{i}, selected_mean_wis, numel(calibration_pos));
end

calibration_grid_scores = vertcat(calibration_blocks{:});
selected_orders = vertcat(selected_blocks{:});

calibrationGridFile = fullfile(refinementDir, ...
    'partC_04_calibration_grid_scores.csv');
writetable(calibration_grid_scores, calibrationGridFile);
fprintf('Calibration grid scores saved to: %s\n', calibrationGridFile);

selectedOrdersFile = fullfile(refinementDir, ...
    'partC_04_selected_orders.csv');
writetable(selected_orders, selectedOrdersFile);
fprintf('Selected local orders saved to: %s\n', selectedOrdersFile);

fprintf('Selected local orders:\n');
for i = 1:height(selected_orders)
    fprintf('  - %s/%s: %s (mean calibration WIS = %.6g)\n', ...
        char(selected_orders.Model(i)), char(selected_orders.ExoMode(i)), ...
        char(selected_orders.OrderText(i)), ...
        selected_orders.MeanCalibrationWIS(i));
end

%% 3. All-Window Diagnostic Evaluation
% This refined all-window comparison is diagnostic because local orders were
% selected with calibration windows. It does not replace the frozen Part C
% all-window transfer test or the fair holdout comparison below.
fprintf(['Stage: Evaluating frozen and locally refined configurations ' ...
    'on all forecast windows (diagnostic)\n']);

all_window_pos = (1:numel(window_days))';
all_window_score_blocks  = cell(2 * numel(selected_families), 1);
all_window_detail_blocks = cell(2 * numel(selected_families), 1);
block_idx = 1;

for i = 1:numel(selected_families)
    model_family = char(selected_families(i));
    frozen_cfg = local_frozen_model_cfg(cfg, model_family);
    exo_mode = frozen_cfg.exo_mode;
    frozen_params = double(frozen_cfg.selected_model);
    refined_params = selected_params{i};

    [all_window_score_blocks{block_idx}, ...
            all_window_detail_blocks{block_idx}] = ...
        local_evaluate_window_order(model_family, exo_mode, "Frozen", ...
        frozen_params, Rt_true, I_scaled, tspan, date, window_days, ...
        window_indices, all_window_pos, cfg, wis_alphas, ...
        "All-window diagnostic");
    block_idx = block_idx + 1;

    [all_window_score_blocks{block_idx}, ...
            all_window_detail_blocks{block_idx}] = ...
        local_evaluate_window_order(model_family, exo_mode, "Refined", ...
        refined_params, Rt_true, I_scaled, tspan, date, window_days, ...
        window_indices, all_window_pos, cfg, wis_alphas, ...
        "All-window diagnostic");
    block_idx = block_idx + 1;
end

all_window_score_blocks = all_window_score_blocks(~cellfun('isempty', ...
    all_window_score_blocks));
all_window_detail_blocks = all_window_detail_blocks(~cellfun('isempty', ...
    all_window_detail_blocks));

all_window_scores = vertcat(all_window_score_blocks{:});
if isempty(all_window_detail_blocks)
    all_window_pointwise_details = local_empty_holdout_pointwise_table();
else
    all_window_pointwise_details = vertcat(all_window_detail_blocks{:});
end

all_window_wis_summary = local_refinement_wis_summary(all_window_scores);

fprintf('\n  [ Part C All-Window Diagnostic WIS Summary ]\n');
disp(all_window_wis_summary);

allWindowSummaryFile = fullfile(scoreDir, ...
    'partC_04_all_window_wis_summary.csv');
writetable(all_window_wis_summary, allWindowSummaryFile);
fprintf('All-window diagnostic WIS summary saved to: %s\n', ...
    allWindowSummaryFile);

allWindowDetailFile = fullfile(scoreDir, ...
    'partC_04_all_window_wis_pointwise_details.csv');
writetable(all_window_pointwise_details, allWindowDetailFile);
fprintf('All-window diagnostic WIS pointwise details saved to: %s\n', ...
    allWindowDetailFile);

allWindowFigPath = fullfile(figDir, ...
    'partC_04_all_window_wis_boxplot.png');
all_window_plot_saved = local_plot_refinement_wis_boxplot( ...
    all_window_scores, allWindowFigPath, ...
    'Part C All-Window Diagnostic WIS', ...
    'Part C All-Window Diagnostic WIS');

if all_window_plot_saved
    fprintf('All-window diagnostic WIS figure saved to: %s\n', ...
        allWindowFigPath);
else
    fprintf(['All-window diagnostic WIS visualization skipped: ' ...
        'no finite values.\n']);
end

arx_refinement_idx = find(selected_families == "ARX", 1);
if ~isempty(arx_refinement_idx)
    refined_arx_params = selected_params{arx_refinement_idx};
    refined_arx_order_text = local_order_text('ARX', refined_arx_params);
    refined_arx_results = local_run_refined_forecasts('ARX', 'I', ...
        refined_arx_params, Rt_true, I_scaled, tspan, date, window_days, ...
        window_indices, all_window_pos, cfg, wis_alphas);

    refinedArxPlotPath = fullfile(figDir, ...
        'partC_04_forecast_plot_real_ARX_I_refined.png');
    local_plot_refined_arx_forecast_comparison(refined_arx_results, ...
        Rt_true, tspan, refined_arx_order_text, cfg, refinedArxPlotPath, ...
        false);
    fprintf('Refined ARX/I forecast visualization saved to: %s\n', ...
        refinedArxPlotPath);

    refinedArxZoomedPlotPath = fullfile(figDir, ...
        'partC_04_forecast_plot_real_ARX_I_refined_zoomed.png');
    local_plot_refined_arx_forecast_comparison(refined_arx_results, ...
        Rt_true, tspan, refined_arx_order_text, cfg, ...
        refinedArxZoomedPlotPath, true);
    fprintf(['Refined ARX/I capped forecast visualization saved to: ' ...
        '%s\n'], refinedArxZoomedPlotPath);
end

%% 4. Holdout Evaluation
% Frozen outputs remain untouched; these holdout scores are a sensitivity
% extension comparing the frozen Part A-selected orders to local real-data
% recalibration.
fprintf('Stage: Evaluating frozen and locally refined configurations on holdout windows\n');

holdout_score_blocks  = cell(2 * numel(selected_families), 1);
holdout_detail_blocks = cell(2 * numel(selected_families), 1);
block_idx = 1;

for i = 1:numel(selected_families)
    model_family = char(selected_families(i));
    frozen_cfg = local_frozen_model_cfg(cfg, model_family);
    exo_mode = frozen_cfg.exo_mode;
    frozen_params = double(frozen_cfg.selected_model);
    refined_params = selected_params{i};

    [holdout_score_blocks{block_idx}, holdout_detail_blocks{block_idx}] = ...
        local_evaluate_holdout_order(model_family, exo_mode, "Frozen", ...
        frozen_params, Rt_true, I_scaled, tspan, date, window_days, ...
        window_indices, holdout_pos, cfg, wis_alphas);
    block_idx = block_idx + 1;

    [holdout_score_blocks{block_idx}, holdout_detail_blocks{block_idx}] = ...
        local_evaluate_holdout_order(model_family, exo_mode, "Refined", ...
        refined_params, Rt_true, I_scaled, tspan, date, window_days, ...
        window_indices, holdout_pos, cfg, wis_alphas);
    block_idx = block_idx + 1;
end

holdout_score_blocks = holdout_score_blocks(~cellfun('isempty', ...
    holdout_score_blocks));
holdout_detail_blocks = holdout_detail_blocks(~cellfun('isempty', ...
    holdout_detail_blocks));

holdout_scores = vertcat(holdout_score_blocks{:});
if isempty(holdout_detail_blocks)
    holdout_pointwise_details = local_empty_holdout_pointwise_table();
else
    holdout_pointwise_details = vertcat(holdout_detail_blocks{:});
end

holdout_wis_summary = groupsummary(holdout_scores, ...
    {'Scenario', 'Model', 'ExoMode', 'Configuration', 'OrderText'}, ...
    {'mean', 'median', 'std', 'min', 'max'}, ...
    'WindowWIS');

holdout_wis_summary.Properties.VariableNames = regexprep( ...
    holdout_wis_summary.Properties.VariableNames, ...
    {'mean_', 'median_', 'std_', 'min_', 'max_'}, ...
    {'Mean_', 'Median_', 'Std_', 'Min_', 'Max_'});

holdout_wis_summary = holdout_wis_summary(:, ...
    {'Scenario', 'Model', 'ExoMode', 'Configuration', 'OrderText', ...
    'GroupCount', 'Mean_WindowWIS', 'Median_WindowWIS', ...
    'Std_WindowWIS', 'Min_WindowWIS', 'Max_WindowWIS'});

fprintf('\n  [ Part C Holdout WIS Summary ]\n');
disp(holdout_wis_summary);

holdoutSummaryFile = fullfile(scoreDir, ...
    'partC_04_holdout_wis_summary.csv');
writetable(holdout_wis_summary, holdoutSummaryFile);
fprintf('Holdout WIS summary saved to: %s\n', holdoutSummaryFile);

holdoutDetailFile = fullfile(scoreDir, ...
    'partC_04_holdout_wis_pointwise_details.csv');
writetable(holdout_pointwise_details, holdoutDetailFile);
fprintf('Holdout WIS pointwise details saved to: %s\n', holdoutDetailFile);

holdoutFigPath = fullfile(figDir, ...
    'partC_04_holdout_wis_boxplot.png');
holdout_plot_saved = local_plot_holdout_wis_boxplot(holdout_scores, ...
    holdoutFigPath);

if holdout_plot_saved
    fprintf('Holdout WIS comparison figure saved to: %s\n', holdoutFigPath);
else
    fprintf('Holdout WIS comparison visualization skipped: no finite values.\n');
end

%% 5. Holdout Projected Infection Proxy Diagnostics
% These figures translate forecasted Rt_est paths into projected I_scaled
% infection proxy paths. They are explanatory diagnostics only and do not
% affect the primary Part C Rt WIS evaluation above.
fprintf('Stage: Plotting holdout projected infection proxy diagnostics\n');

frozenProjectedIPath = fullfile(figDir, ...
    'partC_04_projected_I_proxy_frozen.png');
local_plot_holdout_projected_i_proxy_comparison( ...
    "Frozen", cfg, selected_families, selected_params, Rt_true, I_scaled, ...
    tspan, date, window_days, window_indices, holdout_pos, wis_alphas, ...
    frozenProjectedIPath);
fprintf('Frozen projected infection proxy figure saved to: %s\n', ...
    frozenProjectedIPath);

refinedProjectedIPath = fullfile(figDir, ...
    'partC_04_projected_I_proxy_refined.png');
local_plot_holdout_projected_i_proxy_comparison( ...
    "Refined", cfg, selected_families, selected_params, Rt_true, I_scaled, ...
    tspan, date, window_days, window_indices, holdout_pos, wis_alphas, ...
    refinedProjectedIPath);
fprintf('Refined projected infection proxy figure saved to: %s\n', ...
    refinedProjectedIPath);

fprintf('=== Part C Local Refinement Extension Complete ===\n\n');

%% 6. Local Functions
function selected_families = local_parse_selected_model_families(raw_value)
%LOCAL_PARSE_SELECTED_MODEL_FAMILIES Read PARTC_REFINEMENT_MODELS.
    raw_value = strtrim(string(raw_value));
    if strlength(raw_value) == 0
        raw_value = "AR,ARX";
    end

    raw_tokens = upper(strtrim(split(raw_value, ",")));
    selected_families = strings(0, 1);

    for i = 1:numel(raw_tokens)
        token = raw_tokens(i);
        if strlength(token) == 0
            continue;
        end

        if ~any(token == ["AR", "ARX"])
            error('REFINE:InvalidModelSelection', ...
                ['PARTC_REFINEMENT_MODELS must be AR, ARX, or AR,ARX. ' ...
                'Received: %s.'], char(raw_value));
        end

        if ~any(selected_families == token)
            selected_families(end + 1, 1) = token; %#ok<AGROW>
        end
    end

    if isempty(selected_families)
        error('REFINE:InvalidModelSelection', ...
            'PARTC_REFINEMENT_MODELS did not contain any selected models.');
    end
end

function local_validate_processed_data(data, processedPath)
%LOCAL_VALIDATE_PROCESSED_DATA Verify processed Part C artifact fields.
    required_fields = {'date', 't', 'Rt_est', 'I_proxy', 'I_scaled'};
    if ~all(isfield(data, required_fields))
        error('REFINE:InvalidProcessedData', ...
            'Processed artifact is missing required fields: %s.', processedPath);
    end

    n = numel(data.Rt_est(:));
    if n == 0 || numel(data.t(:)) ~= n || numel(data.I_proxy(:)) ~= n || ...
            numel(data.I_scaled(:)) ~= n || numel(data.date(:)) ~= n
        error('REFINE:InvalidProcessedData', ...
            'Processed Part C vectors must be nonempty and have equal length.');
    end

    values = [double(data.t(:)); double(data.Rt_est(:)); ...
        double(data.I_proxy(:)); double(data.I_scaled(:))];
    if any(~isfinite(values)) || any(double(data.Rt_est(:)) <= 0) || ...
            any(double(data.I_proxy(:)) < 0) || any(double(data.I_scaled(:)) < 0)
        error('REFINE:InvalidProcessedData', ...
            ['Processed Part C data must have finite positive Rt_est and ' ...
            'finite nonnegative I_proxy/I_scaled values.']);
    end
end

function [window_days, window_indices] = local_forecast_windows(tspan, Rt_true, cfg)
%LOCAL_FORECAST_WINDOWS Construct the same Part C forecast origins.
    horizon = cfg.forecast.horizon;
    max_origin = tspan(end) - horizon;
    candidate_days = (cfg.forecast.min_window : cfg.forecast.step_size : ...
        max_origin)';

    window_days = zeros(0, 1);
    window_indices = zeros(0, 1);

    for i = 1:numel(candidate_days)
        idx_T = find(tspan == candidate_days(i), 1);
        if isempty(idx_T)
            continue;
        end

        idx_end = idx_T + horizon;
        if idx_end > numel(Rt_true)
            continue;
        end

        window_days(end + 1, 1) = candidate_days(i); %#ok<AGROW>
        window_indices(end + 1, 1) = idx_T; %#ok<AGROW>
    end

    if numel(window_days) < 2
        error('REFINE:NoValidWindows', ...
            ['At least two valid Part C forecast windows are required for ' ...
            'calibration and holdout splitting.']);
    end
end

function [calibration_pos, holdout_pos] = local_split_forecast_windows( ...
    window_days, calibration_fraction)
%LOCAL_SPLIT_FORECAST_WINDOWS Split forecast origins by time order.
    if ~isscalar(calibration_fraction) || ~isfinite(calibration_fraction) || ...
            calibration_fraction <= 0 || calibration_fraction >= 1
        error('REFINE:InvalidCalibrationFraction', ...
            'Calibration fraction must be a scalar in (0, 1).');
    end

    num_windows = numel(window_days);
    num_calibration = floor(num_windows * calibration_fraction);
    num_calibration = max(1, min(num_calibration, num_windows - 1));

    calibration_pos = (1:num_calibration)';
    holdout_pos = (num_calibration + 1:num_windows)';
end

function [candidate_models, exo_mode] = local_candidate_grid(cfg, model_family)
%LOCAL_CANDIDATE_GRID Construct the Part C local refinement grid.
    switch model_family
        case 'AR'
            candidate_models = cfg.refinement.ar_grid.p(:);
            exo_mode = 'None';

        case 'ARX'
            [NA, NB, NK] = ndgrid(cfg.refinement.arx_i_grid.na, ...
                cfg.refinement.arx_i_grid.nb, ...
                cfg.refinement.arx_i_grid.nk);
            candidate_models = [NA(:), NB(:), NK(:)];
            exo_mode = 'I';

        otherwise
            error('REFINE:UnknownModelFamily', ...
                'Unsupported local refinement model family: %s.', model_family);
    end
end

function [grid_table, selected_params, selected_mean_wis] = ...
    local_calibrate_family(model_family, exo_mode, candidate_models, ...
    Rt_true, I_scaled, window_indices, calibration_pos, ...
    cfg, wis_alphas)
%LOCAL_CALIBRATE_FAMILY Score one family grid on calibration windows.
    num_candidates = size(candidate_models, 1);
    candidate_index = (1:num_candidates)';
    candidate_count = repmat(num_candidates, num_candidates, 1);
    scenario = repmat("real", num_candidates, 1);
    model = repmat(string(model_family), num_candidates, 1);
    exo = repmat(string(exo_mode), num_candidates, 1);
    order_text = strings(num_candidates, 1);
    p_col = nan(num_candidates, 1);
    na_col = nan(num_candidates, 1);
    nb_col = nan(num_candidates, 1);
    nk_col = nan(num_candidates, 1);
    mean_calibration_wis = inf(num_candidates, 1);
    calibration_windows = repmat(numel(calibration_pos), num_candidates, 1);

    for i = 1:num_candidates
        params = candidate_models(i, :);
        mean_calibration_wis(i) = local_score_candidate_windows( ...
            model_family, params, Rt_true, I_scaled, window_indices, ...
            calibration_pos, cfg, wis_alphas);

        order_text(i) = local_order_text(model_family, params);
        [p_col(i), na_col(i), nb_col(i), nk_col(i)] = ...
            local_order_columns(model_family, params);

        fprintf('Progress: candidate %d/%d | %s/%s %s | mean calibration WIS = %.6g\n', ...
            i, num_candidates, model_family, exo_mode, char(order_text(i)), ...
            mean_calibration_wis(i));
    end

    [selected_mean_wis, selected_idx] = min(mean_calibration_wis);
    if ~isfinite(selected_mean_wis)
        error('REFINE:NoValidCandidate', ...
            'All %s/%s local candidates produced invalid calibration WIS.', ...
            model_family, exo_mode);
    end

    selected_params = candidate_models(selected_idx, :);

    grid_table = table( ...
        scenario, model, exo, candidate_index, candidate_count, order_text, ...
        p_col, na_col, nb_col, nk_col, calibration_windows, ...
        mean_calibration_wis, ...
        'VariableNames', {'Scenario', 'Model', 'ExoMode', ...
        'CandidateIndex', 'CandidateCount', 'OrderText', 'p', 'na', ...
        'nb', 'nk', 'CalibrationWindows', 'MeanCalibrationWIS'});
end

function mean_wis = local_score_candidate_windows(model_family, params, ...
    Rt_true, I_scaled, window_indices, selected_pos, cfg, wis_alphas)
%LOCAL_SCORE_CANDIDATE_WINDOWS Compute mean calibration WIS for one order.
    horizon = cfg.forecast.horizon;
    window_wis = inf(numel(selected_pos), 1);

    for i = 1:numel(selected_pos)
        idx_T = window_indices(selected_pos(i));
        idx_end = idx_T + horizon;
        truth_Rt = Rt_true(idx_T+1:idx_end);

        [Rt_pred, out_alphas, Rt_lower, Rt_upper] = local_fit_partC_model( ...
            model_family, params, Rt_true(1:idx_T), I_scaled, idx_T, ...
            idx_end, horizon, wis_alphas, cfg);

        if ~local_is_valid_forecast(Rt_pred, out_alphas, Rt_lower, ...
                Rt_upper, truth_Rt)
            continue;
        end

        pointwise_wis = local_compute_wis(truth_Rt, Rt_pred, ...
            Rt_lower, Rt_upper, out_alphas);
        if all(isfinite(pointwise_wis))
            window_wis(i) = mean(pointwise_wis);
        end
    end

    mean_wis = mean(window_wis);
end

function selected_row = local_selected_order_row(model_family, exo_mode, ...
    params, mean_calibration_wis, calibration_windows)
%LOCAL_SELECTED_ORDER_ROW Build one selected-order output row.
    [p_value, na_value, nb_value, nk_value] = ...
        local_order_columns(model_family, params);

    selected_row = table( ...
        "real", ...
        string(model_family), ...
        string(exo_mode), ...
        local_order_text(model_family, params), ...
        p_value, ...
        na_value, ...
        nb_value, ...
        nk_value, ...
        mean_calibration_wis, ...
        calibration_windows, ...
        'VariableNames', {'Scenario', 'Model', 'ExoMode', 'OrderText', ...
        'p', 'na', 'nb', 'nk', 'MeanCalibrationWIS', ...
        'CalibrationWindows'});
end

function model_cfg = local_frozen_model_cfg(cfg, model_family)
%LOCAL_FROZEN_MODEL_CFG Return the unchanged frozen Part C configuration.
    model_names = string({cfg.models.model_type});
    idx = find(model_names == string(model_family), 1);
    if isempty(idx)
        error('REFINE:MissingFrozenModel', ...
            'No frozen Part C configuration found for %s.', model_family);
    end

    model_cfg = cfg.models(idx);
end

function [score_table, detail_table] = local_evaluate_holdout_order( ...
    model_family, exo_mode, configuration_label, params, Rt_true, I_scaled, ...
    tspan, date, window_days, window_indices, holdout_pos, cfg, wis_alphas)
%LOCAL_EVALUATE_HOLDOUT_ORDER Score one frozen/refined order on holdout.
    [score_table, detail_table] = local_evaluate_window_order( ...
        model_family, exo_mode, configuration_label, params, Rt_true, ...
        I_scaled, tspan, date, window_days, window_indices, holdout_pos, ...
        cfg, wis_alphas, "Holdout");
end

function [score_table, detail_table] = local_evaluate_window_order( ...
    model_family, exo_mode, configuration_label, params, Rt_true, I_scaled, ...
    tspan, date, window_days, window_indices, selected_pos, cfg, ...
    wis_alphas, evaluation_label)
%LOCAL_EVALUATE_WINDOW_ORDER Score one frozen/refined order on windows.
    horizon = cfg.forecast.horizon;
    score_blocks = cell(numel(selected_pos), 1);
    detail_blocks = cell(numel(selected_pos), 1);
    order_text = local_order_text(model_family, params);

    fprintf('Stage: %s %s/%s %s %s\n', char(evaluation_label), ...
        model_family, exo_mode, char(configuration_label), ...
        char(order_text));

    for i = 1:numel(selected_pos)
        idx_T = window_indices(selected_pos(i));
        idx_end = idx_T + horizon;
        truth_Rt = Rt_true(idx_T+1:idx_end);

        [Rt_pred, out_alphas, Rt_lower, Rt_upper] = local_fit_partC_model( ...
            model_family, params, Rt_true(1:idx_T), I_scaled, idx_T, ...
            idx_end, horizon, wis_alphas, cfg);

        [score_blocks{i}, detail_blocks{i}] = local_window_wis_tables( ...
            model_family, exo_mode, configuration_label, order_text, ...
            window_days(selected_pos(i)), truth_Rt, Rt_pred, out_alphas, ...
            Rt_lower, Rt_upper, tspan(idx_T+1:idx_end), ...
            date(idx_T+1:idx_end));
    end

    score_table = vertcat(score_blocks{:});
    detail_blocks = detail_blocks(~cellfun('isempty', detail_blocks));
    if isempty(detail_blocks)
        detail_table = local_empty_holdout_pointwise_table();
    else
        detail_table = vertcat(detail_blocks{:});
    end
end

function wis_summary = local_refinement_wis_summary(score_table)
%LOCAL_REFINEMENT_WIS_SUMMARY Summarize frozen/refined WIS scores.
    wis_summary = groupsummary(score_table, ...
        {'Scenario', 'Model', 'ExoMode', 'Configuration', 'OrderText'}, ...
        {'mean', 'median', 'std', 'min', 'max'}, ...
        'WindowWIS');

    wis_summary.Properties.VariableNames = regexprep( ...
        wis_summary.Properties.VariableNames, ...
        {'mean_', 'median_', 'std_', 'min_', 'max_'}, ...
        {'Mean_', 'Median_', 'Std_', 'Min_', 'Max_'});

    wis_summary = wis_summary(:, ...
        {'Scenario', 'Model', 'ExoMode', 'Configuration', 'OrderText', ...
        'GroupCount', 'Mean_WindowWIS', 'Median_WindowWIS', ...
        'Std_WindowWIS', 'Min_WindowWIS', 'Max_WindowWIS'});
end

function results = local_run_refined_forecasts(model_family, exo_mode, ...
    params, Rt_true, I_scaled, tspan, date, window_days, window_indices, ...
    selected_pos, cfg, wis_alphas)
%LOCAL_RUN_REFINED_FORECASTS Build forecast results for diagnostic plotting.
    horizon = cfg.forecast.horizon;
    results = repmat(struct( ...
        'window_day', [], ...
        'window_day_idx', [], ...
        'window_date', [], ...
        'forecast_median', [], ...
        'forecast_interval_alphas', [], ...
        'forecast_lower', [], ...
        'forecast_upper', [], ...
        'best_model', [], ...
        'aic_landscape', [], ...
        'truth_Rt_window', [], ...
        'truth_I_scaled_window', [], ...
        'time_horizon', [], ...
        'date_horizon', []), numel(selected_pos), 1);

    for i = 1:numel(selected_pos)
        idx_T = window_indices(selected_pos(i));
        idx_end = idx_T + horizon;

        [Rt_pred, out_alphas, Rt_lower, Rt_upper] = local_fit_partC_model( ...
            model_family, params, Rt_true(1:idx_T), I_scaled, idx_T, ...
            idx_end, horizon, wis_alphas, cfg);

        results(i).window_day      = window_days(selected_pos(i));
        results(i).window_day_idx  = idx_T;
        results(i).window_date     = date(idx_T);
        results(i).forecast_median = Rt_pred;
        results(i).forecast_interval_alphas = out_alphas;
        results(i).forecast_lower  = Rt_lower;
        results(i).forecast_upper  = Rt_upper;
        results(i).best_model      = params;
        results(i).aic_landscape   = params;
        results(i).truth_Rt_window = Rt_true(idx_T+1:idx_end);
        results(i).truth_I_scaled_window = I_scaled(idx_T+1:idx_end);
        results(i).time_horizon    = tspan(idx_T+1:idx_end);
        results(i).date_horizon    = date(idx_T+1:idx_end);
    end

    if isempty(results)
        error('REFINE:NoDiagnosticForecasts', ...
            'No refined forecast windows were available for plotting.');
    end

    fprintf('Stage: Diagnostic forecast path %s/%s Refined %s\n', ...
        model_family, exo_mode, char(local_order_text(model_family, params)));
end

function [Rt_pred, out_alphas, Rt_lower, Rt_upper] = local_fit_partC_model( ...
    model_family, params, Rt_past, I_scaled, idx_T, idx_end, horizon, ...
    wis_alphas, cfg)
%LOCAL_FIT_PARTC_MODEL Dispatch AR/ARX fits using Part C conventions.
    switch model_family
        case 'AR'
            [Rt_pred, ~, out_alphas, Rt_lower, Rt_upper] = ...
                fit_arima(Rt_past, params(1), 0, 0, horizon, wis_alphas);

        case 'ARX'
            % This unchanged Rt WIS path uses the retrospective Part C ARX/I
            % setup. Projected infection proxy diagnostics use the no-future
            % I_scaled helper below instead.
            U_past = I_scaled(1:idx_T);
            U_future = I_scaled(idx_T+1:idx_end);
            nb_vec = params(2);
            nk_vec = params(3);

            [Rt_pred, ~, out_alphas, Rt_lower, Rt_upper] = ...
                fit_arimax(Rt_past, U_past, U_future, params(1), 0, 0, ...
                nb_vec, nk_vec, horizon, wis_alphas, [], [], '', ...
                cfg.sim.seed);

        otherwise
            error('REFINE:UnknownModelFamily', ...
                'Unsupported local refinement model family: %s.', model_family);
    end
end

function [score_row, detail_rows] = local_window_wis_tables( ...
    model_family, exo_mode, configuration_label, order_text, window_day, ...
    truth_Rt, pred_Rt, alphas, lower_Rt, upper_Rt, time_horizon, date_horizon)
%LOCAL_WINDOW_WIS_TABLES Compute refinement WIS tables for one window.
    truth_Rt = double(truth_Rt(:));
    pred_Rt = double(pred_Rt(:));
    alphas = reshape(double(alphas), 1, []);
    lower_Rt = double(lower_Rt);
    upper_Rt = double(upper_Rt);
    window_wis = inf;
    detail_rows = local_empty_holdout_pointwise_table();

    if local_is_valid_forecast(pred_Rt, alphas, lower_Rt, upper_Rt, truth_Rt)
        pointwise_wis = local_compute_wis(truth_Rt, pred_Rt, ...
            lower_Rt, upper_Rt, alphas);
        if all(isfinite(pointwise_wis))
            window_wis = mean(pointwise_wis);

            horizon_idx = (1:numel(truth_Rt))';
            detail_rows = table( ...
                repmat("real", numel(truth_Rt), 1), ...
                repmat(string(model_family), numel(truth_Rt), 1), ...
                repmat(string(exo_mode), numel(truth_Rt), 1), ...
                repmat(string(configuration_label), numel(truth_Rt), 1), ...
                repmat(string(order_text), numel(truth_Rt), 1), ...
                repmat(window_day, numel(truth_Rt), 1), ...
                horizon_idx, ...
                double(time_horizon(:)), ...
                date_horizon(:), ...
                truth_Rt, ...
                pred_Rt, ...
                pointwise_wis, ...
                'VariableNames', {'Scenario', 'Model', 'ExoMode', ...
                'Configuration', 'OrderText', 'WindowDay', 'HorizonIdx', ...
                'ForecastDay', 'ForecastDate', 'Truth_Rt', ...
                'Median_Forecast', 'WIS'});
        end
    end

    score_row = table( ...
        "real", ...
        string(model_family), ...
        string(exo_mode), ...
        string(configuration_label), ...
        string(order_text), ...
        window_day, ...
        window_wis, ...
        'VariableNames', {'Scenario', 'Model', 'ExoMode', 'Configuration', ...
        'OrderText', 'WindowDay', 'WindowWIS'});
end

function detail_rows = local_empty_holdout_pointwise_table()
%LOCAL_EMPTY_HOLDOUT_POINTWISE_TABLE Construct an empty pointwise table.
    detail_rows = table( ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        datetime.empty(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        'VariableNames', {'Scenario', 'Model', 'ExoMode', 'Configuration', ...
        'OrderText', 'WindowDay', 'HorizonIdx', 'ForecastDay', ...
        'ForecastDate', 'Truth_Rt', 'Median_Forecast', 'WIS'});
end

function is_valid = local_is_valid_forecast(Rt_pred, out_alphas, Rt_lower, ...
    Rt_upper, truth_Rt)
%LOCAL_IS_VALID_FORECAST Verify forecast output dimensions and finiteness.
    out_alphas = reshape(double(out_alphas), 1, []);
    Rt_pred = double(Rt_pred(:));
    Rt_lower = double(Rt_lower);
    Rt_upper = double(Rt_upper);
    truth_Rt = double(truth_Rt(:));

    is_valid = ...
        ~isempty(out_alphas) && ...
        numel(Rt_pred) == numel(truth_Rt) && ...
        size(Rt_lower, 1) == numel(truth_Rt) && ...
        size(Rt_upper, 1) == numel(truth_Rt) && ...
        size(Rt_lower, 2) == numel(out_alphas) && ...
        size(Rt_upper, 2) == numel(out_alphas) && ...
        all(isfinite(Rt_pred)) && ...
        all(isfinite(Rt_lower(:))) && ...
        all(isfinite(Rt_upper(:))) && ...
        all(Rt_lower(:) <= Rt_upper(:));
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

function order_text = local_order_text(model_family, params)
%LOCAL_ORDER_TEXT Format a model-order label.
    switch model_family
        case 'AR'
            order_text = sprintf('p=%d', params(1));

        case 'ARX'
            order_text = sprintf('na=%d, nb=%d, nk=%d', ...
                params(1), params(2), params(3));

        otherwise
            error('REFINE:UnknownModelFamily', ...
                'Unsupported local refinement model family: %s.', model_family);
    end

    order_text = string(order_text);
end

function [p_value, na_value, nb_value, nk_value] = ...
    local_order_columns(model_family, params)
%LOCAL_ORDER_COLUMNS Store order parameters in uniform numeric columns.
    p_value = NaN;
    na_value = NaN;
    nb_value = NaN;
    nk_value = NaN;

    switch model_family
        case 'AR'
            p_value = params(1);

        case 'ARX'
            na_value = params(1);
            nb_value = params(2);
            nk_value = params(3);

        otherwise
            error('REFINE:UnknownModelFamily', ...
                'Unsupported local refinement model family: %s.', model_family);
    end
end

function was_saved = local_plot_holdout_wis_boxplot(score_registry, out_path)
%LOCAL_PLOT_HOLDOUT_WIS_BOXPLOT Plot frozen versus locally refined WIS.
    was_saved = local_plot_refinement_wis_boxplot(score_registry, out_path, ...
        'Part C Holdout WIS Comparison', 'Part C Holdout WIS');
end

function was_saved = local_plot_refinement_wis_boxplot(score_registry, ...
    out_path, figure_name, plot_title)
%LOCAL_PLOT_REFINEMENT_WIS_BOXPLOT Plot frozen versus refined WIS values.
    was_saved = false;

    if isempty(score_registry) || ~any(isfinite(score_registry.WindowWIS))
        return;
    end

    fig = figure('Name', figure_name, 'Visible', 'off');
    fig.Units = 'centimeters';
    fig.Position(3) = 17.0;
    fig.Position(4) = 8.5;

    tlo = tiledlayout(1, 1, 'Padding', 'compact');

    ax = nexttile(tlo);
    hold(ax, 'on');

    axtoolbar(ax, {'export'});

    valid_idx = isfinite(score_registry.WindowWIS);
    plot_data = score_registry(valid_idx, :);
    plot_config = string(plot_data.Model) + " (" + ...
        string(plot_data.ExoMode) + ") " + ...
        string(plot_data.Configuration) + " " + ...
        string(plot_data.OrderText);

    boxchart(ax, categorical(plot_config), plot_data.WindowWIS, ...
        'GroupByColor', categorical(plot_data.Configuration));

    ylabel(ax, 'WIS ($\mathcal{R}_t$)', 'Interpreter', 'latex');
    title(ax, plot_title);
    legend(ax, 'Location', 'bestoutside');
    grid(ax, 'on');
    xtickangle(ax, 20);

    if max(plot_data.WindowWIS) > 100
        set(ax, 'YScale', 'log');
        ylabel(ax, 'WIS ($\mathcal{R}_t$) [Log Scale]', ...
            'Interpreter', 'latex');
    end

    exportgraphics(fig, out_path, 'Resolution', 300);
    close(fig);
    was_saved = true;
end

function local_plot_refined_arx_forecast_comparison(results, Rt_true, tspan, ...
    order_text, cfg, out_path, use_zoomed_axis)
%LOCAL_PLOT_REFINED_ARX_FORECAST_COMPARISON Save refined ARX/I forecast path.
    fig = figure('Name', 'Part C Refined ARX/I Forecast', 'Visible', 'off');
    fig.Units = 'centimeters';
    fig.Position(3) = 17.0;
    fig.Position(4) = 8.5;

    ax = axes(fig);
    hold(ax, 'on');

    axtoolbar(ax, {'export'});

    plot_alphas = sort(double(cfg.forecast.plot_alphas(:)'), 'ascend');
    lead_time = local_plot_lead_time(cfg);
    num_intervals = min(numel(plot_alphas), 2);
    interval_colors = [0.30, 0.65, 0.95; 0.10, 0.45, 0.85];
    interval_face_alpha = [0.14, 0.28];
    interval_handles = gobjects(1, num_intervals);
    interval_labels = cellstr(compose('%d%% Predictive Interval', ...
        round((1 - plot_alphas(1:num_intervals)) * 100)));
    hMed = gobjects(0);

    [target_days, median_forecast, lower_forecast, upper_forecast] = ...
        local_extract_fixed_lead(results, lead_time, plot_alphas);

    for j = 1:num_intervals
        valid_interval = isfinite(target_days) & ...
            isfinite(lower_forecast(:, j)) & isfinite(upper_forecast(:, j));

        if nnz(valid_interval) >= 2
            interval_handles(j) = local_fill_interval(ax, ...
                target_days(valid_interval), ...
                lower_forecast(valid_interval, j), ...
                upper_forecast(valid_interval, j), ...
                interval_colors(j, :), interval_face_alpha(j), ...
                interval_labels{j});
        end
    end

    hTruth = plot(ax, tspan, Rt_true, 'k-', 'LineWidth', 2.2, ...
        'DisplayName', 'Ground Truth');

    valid_median = isfinite(target_days) & isfinite(median_forecast);
    if any(valid_median)
        hMed = plot(ax, target_days(valid_median), ...
            median_forecast(valid_median), 'b--o', 'LineWidth', 1.3, ...
            'MarkerSize', 3.2, ...
            'DisplayName', sprintf('%d-Day-Ahead Median Forecast', ...
            lead_time));
    end

    title_lines = {sprintf('%d-Day-Ahead Forecast vs Truth: real ARX/I refined', ...
        lead_time), sprintf('Refined order: %s', char(order_text))};
    if use_zoomed_axis
        title_lines{end + 1} = 'Rt axis capped at 5.5 for readability';
    end
    title(ax, title_lines);
    xlabel(ax, 'Time (days)');
    ylabel(ax, '$\mathcal{R}_t$', 'Interpreter', 'latex');
    grid(ax, 'on');

    if use_zoomed_axis
        ylim(ax, [0, 5.5]);
    end

    xlim(ax, [tspan(1), tspan(end)]);

    max_legend_items = 1 + double(~isempty(hMed)) + num_intervals;
    legend_handles = gobjects(1, max_legend_items);
    legend_labels = cell(1, max_legend_items);
    legend_count = 1;

    legend_handles(legend_count) = hTruth;
    legend_labels{legend_count} = 'Ground Truth';

    if ~isempty(hMed)
        legend_count = legend_count + 1;
        legend_handles(legend_count) = hMed;
        legend_labels{legend_count} = ...
            sprintf('%d-Day-Ahead Median Forecast', lead_time);
    end

    for j = 1:num_intervals
        if isgraphics(interval_handles(j))
            legend_count = legend_count + 1;
            legend_handles(legend_count) = interval_handles(j);
            legend_labels{legend_count} = interval_labels{j};
        end
    end

    legend_handles = legend_handles(1:legend_count);
    legend_labels = legend_labels(1:legend_count);
    legend(ax, legend_handles, legend_labels, 'Location', 'northwest');

    exportgraphics(fig, out_path, 'Resolution', 300);
    close(fig);
end

function lead_time = local_plot_lead_time(cfg)
%LOCAL_PLOT_LEAD_TIME Read the configured fixed-lead forecast horizon.
    lead_time = 7;
    if isfield(cfg, 'forecast') && isfield(cfg.forecast, 'plot_lead_time')
        lead_time = double(cfg.forecast.plot_lead_time);
    end

    if ~isscalar(lead_time) || ~isfinite(lead_time) || lead_time < 1
        error('PLOT:InvalidLeadTime', ...
            'Forecast plot lead time must be a positive scalar.');
    end

    lead_time = round(lead_time);
end

function [target_days, median_forecast, lower_forecast, upper_forecast] = ...
    local_extract_fixed_lead(results, lead_time, plot_alphas)
%LOCAL_EXTRACT_FIXED_LEAD Extract a fixed forecast lead for plotting.
    num_results = numel(results);
    num_alphas = numel(plot_alphas);

    target_days = nan(num_results, 1);
    median_forecast = nan(num_results, 1);
    lower_forecast = nan(num_results, num_alphas);
    upper_forecast = nan(num_results, num_alphas);

    if isempty(results) || ~isfield(results, 'forecast_interval_alphas')
        return;
    end

    for i = 1:num_results
        t_f = results(i).time_horizon(:);
        y_f = results(i).forecast_median(:);

        if numel(t_f) < lead_time || numel(y_f) < lead_time
            continue;
        end

        target_days(i) = t_f(lead_time);
        median_forecast(i) = y_f(lead_time);

        stored_alphas = double(results(i).forecast_interval_alphas(:)');
        for j = 1:num_alphas
            idx_alpha = local_alpha_index(stored_alphas, plot_alphas(j));
            if isempty(idx_alpha)
                continue;
            end

            if size(results(i).forecast_lower, 1) >= lead_time && ...
                    size(results(i).forecast_upper, 1) >= lead_time && ...
                    size(results(i).forecast_lower, 2) >= idx_alpha && ...
                    size(results(i).forecast_upper, 2) >= idx_alpha
                lower_forecast(i, j) = ...
                    results(i).forecast_lower(lead_time, idx_alpha);
                upper_forecast(i, j) = ...
                    results(i).forecast_upper(lead_time, idx_alpha);
            end
        end
    end
end

function idx = local_alpha_index(stored_alphas, target_alpha)
%LOCAL_ALPHA_INDEX Find a stored predictive interval alpha.
    [min_diff, idx] = min(abs(stored_alphas - target_alpha));
    if isempty(idx) || min_diff > 1e-8
        idx = [];
    end
end

function h = local_fill_interval(ax, t_fcst, lower_bound, upper_bound, ...
    face_color, face_alpha, display_name)
%LOCAL_FILL_INTERVAL Draw one predictive interval ribbon.
    lower_bound = lower_bound(:);
    upper_bound = upper_bound(:);
    t_fcst = t_fcst(:);

    if isempty(display_name)
        h = fill(ax, [t_fcst; flipud(t_fcst)], ...
            [upper_bound; flipud(lower_bound)], face_color, ...
            'FaceAlpha', face_alpha, 'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
    else
        h = fill(ax, [t_fcst; flipud(t_fcst)], ...
            [upper_bound; flipud(lower_bound)], face_color, ...
            'FaceAlpha', face_alpha, 'EdgeColor', 'none', ...
            'DisplayName', display_name);
    end
end

function local_plot_holdout_projected_i_proxy_comparison( ...
    configuration_label, cfg, selected_families, selected_params, Rt_true, ...
    I_scaled, tspan, date, window_days, window_indices, holdout_pos, ...
    wis_alphas, out_path)
%LOCAL_PLOT_HOLDOUT_PROJECTED_I_PROXY_COMPARISON Plot holdout I_scaled paths.
    [ar_params, ar_order_text] = local_projection_params_for_family( ...
        'AR', configuration_label, cfg, selected_families, selected_params);
    [arx_params, arx_order_text] = local_projection_params_for_family( ...
        'ARX', configuration_label, cfg, selected_families, selected_params);

    ar_rows = local_projected_i_proxy_rows_for_order( ...
        'AR', 'None', configuration_label, ar_params, Rt_true, I_scaled, ...
        tspan, date, window_days, window_indices, holdout_pos, cfg, ...
        wis_alphas);
    arx_rows = local_projected_i_proxy_rows_for_order( ...
        'ARX', 'I', configuration_label, arx_params, Rt_true, I_scaled, ...
        tspan, date, window_days, window_indices, holdout_pos, cfg, ...
        wis_alphas);

    [observed_dates, observed_i_scaled] = local_observed_holdout_i_proxy( ...
        I_scaled, date, window_indices, holdout_pos, cfg);
    [ar_dates, ar_i_scaled] = local_median_projected_i_proxy_by_date(ar_rows);
    [arx_dates, arx_i_scaled] = local_median_projected_i_proxy_by_date(arx_rows);

    fig = figure('Name', sprintf('Part C Projected I_proxy %s', ...
        char(configuration_label)), 'Visible', 'off');
    fig.Units = 'centimeters';
    fig.Position(3) = 17.0;
    fig.Position(4) = 8.5;

    ax = axes(fig);
    hold(ax, 'on');
    axtoolbar(ax, {'export'});

    hObserved = plot(ax, observed_dates, observed_i_scaled, 'k-', ...
        'LineWidth', 2.0, 'DisplayName', 'Observed infection proxy');

    if isempty(ar_dates)
        hAR = plot(ax, observed_dates(1), NaN, '--', ...
            'Color', [0.00, 0.45, 0.74], 'LineWidth', 1.7, ...
            'DisplayName', 'Projected infection proxy from AR/None');
    else
        hAR = plot(ax, ar_dates, ar_i_scaled, '--', ...
            'Color', [0.00, 0.45, 0.74], 'LineWidth', 1.7, ...
            'DisplayName', 'Projected infection proxy from AR/None');
    end

    if isempty(arx_dates)
        hARX = plot(ax, observed_dates(1), NaN, '-.', ...
            'Color', [0.85, 0.33, 0.10], 'LineWidth', 1.7, ...
            'DisplayName', 'Projected infection proxy from ARX/I');
    else
        hARX = plot(ax, arx_dates, arx_i_scaled, '-.', ...
            'Color', [0.85, 0.33, 0.10], 'LineWidth', 1.7, ...
            'DisplayName', 'Projected infection proxy from ARX/I');
    end

    [y_limits, y_axis_bounded] = local_projected_i_proxy_ylim( ...
        observed_i_scaled, ar_i_scaled, arx_i_scaled);
    ylim(ax, y_limits);
    xlim(ax, [observed_dates(1), observed_dates(end)]);

    title_lines = {sprintf(['Part C Holdout Projected Infection Proxy ' ...
        '(%s Orders)'], char(configuration_label)), ...
        sprintf('AR/None %s | ARX/I %s', char(ar_order_text), ...
        char(arx_order_text))};
    if y_axis_bounded
        title_lines{end + 1} = 'I_scaled axis bounded for readability';
    end
    title(ax, title_lines);
    xlabel(ax, 'Date');
    ylabel(ax, 'I_scaled infection proxy');
    grid(ax, 'on');
    xtickformat(ax, 'yyyy-MM');
    legend(ax, [hObserved, hAR, hARX], ...
        {'Observed infection proxy', ...
        'Projected infection proxy from AR/None', ...
        'Projected infection proxy from ARX/I'}, ...
        'Location', 'best');

    exportgraphics(fig, out_path, 'Resolution', 300);
    close(fig);
end

function [params, order_text] = local_projection_params_for_family( ...
    model_family, configuration_label, cfg, selected_families, selected_params)
%LOCAL_PROJECTION_PARAMS_FOR_FAMILY Choose frozen or refined order values.
    if string(configuration_label) == "Frozen"
        model_cfg = local_frozen_model_cfg(cfg, model_family);
        params = double(model_cfg.selected_model);
        order_text = local_order_text(model_family, params);
        return;
    end

    family_idx = find(selected_families == string(model_family), 1);
    if isempty(family_idx)
        warning('REFINE:MissingRefinedIProxyProjectionOrder', ...
            ['No locally refined %s order was selected. The refined ' ...
            'projected infection proxy figure uses the frozen %s order ' ...
            'for that curve.'], model_family, model_family);
        model_cfg = local_frozen_model_cfg(cfg, model_family);
        params = double(model_cfg.selected_model);
    else
        params = double(selected_params{family_idx});
    end

    order_text = local_order_text(model_family, params);
end

function rows = local_projected_i_proxy_rows_for_order( ...
    model_family, exo_mode, configuration_label, params, Rt_true, I_scaled, ...
    tspan, date, window_days, window_indices, selected_pos, cfg, wis_alphas)
%LOCAL_PROJECTED_I_PROXY_ROWS_FOR_ORDER Project I_scaled over holdout windows.
    horizon = cfg.forecast.horizon;
    row_blocks = cell(numel(selected_pos), 1);
    order_text = local_order_text(model_family, params);

    fprintf('Stage: Projected infection proxy %s %s/%s %s\n', ...
        char(configuration_label), model_family, exo_mode, char(order_text));

    for i = 1:numel(selected_pos)
        idx_T = window_indices(selected_pos(i));
        idx_end = idx_T + horizon;

        if idx_T < 1 || idx_end > numel(I_scaled)
            continue;
        end

        try
            [forecast_Rt, projected_i_scaled] = ...
                local_fit_partC_model_for_i_proxy_projection( ...
                model_family, params, Rt_true(1:idx_T), ...
                I_scaled(1:idx_T), horizon, wis_alphas, cfg);
        catch ME
            warning('REFINE:IProxyProjectionFailure', ...
                ['Projected infection proxy failed for %s/%s window %d: ' ...
                '%s'], model_family, exo_mode, window_days(selected_pos(i)), ...
                ME.message);
            forecast_Rt = nan(horizon, 1);
            projected_i_scaled = nan(horizon, 1);
        end

        forecast_Rt = double(forecast_Rt(:));
        projected_i_scaled = double(projected_i_scaled(:));
        num_rows = min([horizon, numel(forecast_Rt), ...
            numel(projected_i_scaled), numel(I_scaled) - idx_T]);
        if num_rows < 1
            continue;
        end

        horizon_idx = (1:num_rows)';
        target_idx = idx_T + horizon_idx;

        row_blocks{i} = table( ...
            repmat("real", num_rows, 1), ...
            repmat(string(model_family), num_rows, 1), ...
            repmat(string(exo_mode), num_rows, 1), ...
            repmat(string(configuration_label), num_rows, 1), ...
            repmat(string(order_text), num_rows, 1), ...
            repmat(window_days(selected_pos(i)), num_rows, 1), ...
            repmat(date(idx_T), num_rows, 1), ...
            horizon_idx, ...
            double(tspan(target_idx)), ...
            date(target_idx), ...
            I_scaled(target_idx), ...
            projected_i_scaled(1:num_rows), ...
            forecast_Rt(1:num_rows), ...
            'VariableNames', {'Scenario', 'Model', 'ExoMode', ...
            'Configuration', 'OrderText', 'WindowDay', 'OriginDate', ...
            'HorizonIdx', 'ForecastDay', 'ForecastDate', ...
            'Observed_I_scaled', 'Projected_I_scaled', 'Forecast_Rt'});
    end

    row_blocks = row_blocks(~cellfun('isempty', row_blocks));
    if isempty(row_blocks)
        rows = local_empty_projected_i_proxy_table();
    else
        rows = vertcat(row_blocks{:});
    end
end

function [Rt_pred, projected_i_scaled] = ...
    local_fit_partC_model_for_i_proxy_projection(model_family, params, ...
    Rt_past, I_scaled_history, horizon, wis_alphas, cfg)
%LOCAL_FIT_PARTC_MODEL_FOR_I_PROXY_PROJECTION Forecast Rt without future I_scaled.
    switch model_family
        case 'AR'
            [Rt_pred, ~, ~, ~, ~] = fit_arima(Rt_past, params(1), ...
                0, 0, horizon, wis_alphas);
            projected_i_scaled = local_project_i_scaled_renewal( ...
                I_scaled_history, Rt_pred, cfg);

        case 'ARX'
            [Rt_pred, projected_i_scaled] = local_fit_arx_i_no_future_proxy( ...
                Rt_past, I_scaled_history, params, horizon, wis_alphas, cfg);

        otherwise
            error('REFINE:UnknownModelFamily', ...
                'Unsupported projected infection proxy model family: %s.', ...
                model_family);
    end
end

function [Rt_pred, projected_i_scaled] = local_fit_arx_i_no_future_proxy( ...
    Rt_past, I_scaled_history, params, horizon, wis_alphas, cfg)
%LOCAL_FIT_ARX_I_NO_FUTURE_PROXY Forecast ARX/I using projected I_scaled input.
    nb_vec = params(2);
    nk_vec = params(3);
    max_iterations = 6;
    convergence_tol = 1e-5;

    U_future = local_initial_projected_i_proxy_input( ...
        I_scaled_history, Rt_past, horizon, cfg);
    if any(~isfinite(U_future))
        U_future = repmat(I_scaled_history(end), horizon, 1);
    end

    for iter = 1:max_iterations
        [Rt_candidate, ~, ~, ~, ~] = fit_arimax( ...
            Rt_past, I_scaled_history, U_future, params(1), 0, 0, ...
            nb_vec, nk_vec, horizon, wis_alphas, [], [], '', cfg.sim.seed);
        projected_candidate = local_project_i_scaled_renewal( ...
            I_scaled_history, Rt_candidate, cfg);

        if any(~isfinite(Rt_candidate(:))) || ...
                any(~isfinite(projected_candidate(:)))
            Rt_pred = Rt_candidate;
            projected_i_scaled = projected_candidate;
            return;
        end

        denominator = max(1, max(abs(U_future(:))));
        relative_change = max(abs(projected_candidate(:) - ...
            U_future(:))) / denominator;
        U_future = projected_candidate;

        if relative_change < convergence_tol
            break;
        end
    end

    [Rt_pred, ~, ~, ~, ~] = fit_arimax( ...
        Rt_past, I_scaled_history, U_future, params(1), 0, 0, nb_vec, ...
        nk_vec, horizon, wis_alphas, [], [], '', cfg.sim.seed);
    projected_i_scaled = local_project_i_scaled_renewal( ...
        I_scaled_history, Rt_pred, cfg);
end

function U_future = local_initial_projected_i_proxy_input( ...
    I_scaled_history, Rt_past, horizon, cfg)
%LOCAL_INITIAL_PROJECTED_I_PROXY_INPUT Seed ARX/I with persistence Rt projection.
    last_Rt = Rt_past(end);
    Rt_seed = repmat(last_Rt, horizon, 1);
    U_future = local_project_i_scaled_renewal(I_scaled_history, Rt_seed, cfg);
end

function projected_i_scaled = local_project_i_scaled_renewal( ...
    I_scaled_history, forecast_Rt, cfg)
%LOCAL_PROJECT_I_SCALED_RENEWAL Apply the Part C renewal ratio recursively.
    I_scaled_history = double(I_scaled_history(:));
    forecast_Rt = double(forecast_Rt(:));
    horizon = numel(forecast_Rt);

    weights = local_partC_serial_interval_weights(cfg);
    max_lag = numel(weights);
    if numel(I_scaled_history) < max_lag
        error('REFINE:InsufficientIProxyHistory', ...
            ['Projected infection proxy needs at least %d historical ' ...
            'I_scaled values.'], max_lag);
    end

    rolling_i_scaled = [I_scaled_history; nan(horizon, 1)];
    for h = 1:horizon
        current_idx = numel(I_scaled_history) + h;
        lagged_i_scaled = rolling_i_scaled(current_idx - (1:max_lag));
        renewal_lambda = sum(weights .* lagged_i_scaled);
        rolling_i_scaled(current_idx) = forecast_Rt(h) * renewal_lambda;
    end

    projected_i_scaled = rolling_i_scaled(numel(I_scaled_history)+1:end);
end

function weights = local_partC_serial_interval_weights(cfg)
%LOCAL_PARTC_SERIAL_INTERVAL_WEIGHTS Match Part C preprocessing weights.
    mean_days = cfg.input.serial_interval_mean_days;
    sd_days = cfg.input.serial_interval_sd_days;
    max_lag = cfg.input.serial_interval_max_lag_days;

    if mean_days <= 0 || sd_days <= 0 || max_lag < 1
        error('REFINE:InvalidSerialInterval', ...
            ['Serial interval mean, standard deviation, and max lag must ' ...
            'be positive.']);
    end

    lag_days = (1:max_lag)';
    shape = (mean_days / sd_days)^2;
    scale = (sd_days^2) / mean_days;
    weights = (lag_days.^(shape - 1) .* exp(-lag_days / scale)) ./ ...
        (gamma(shape) * scale^shape);
    weights = weights / sum(weights);
end

function rows = local_empty_projected_i_proxy_table()
%LOCAL_EMPTY_PROJECTED_I_PROXY_TABLE Empty projected I_scaled diagnostic table.
    rows = table( ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        zeros(0, 1), ...
        datetime.empty(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        datetime.empty(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        'VariableNames', {'Scenario', 'Model', 'ExoMode', ...
        'Configuration', 'OrderText', 'WindowDay', 'OriginDate', ...
        'HorizonIdx', 'ForecastDay', 'ForecastDate', ...
        'Observed_I_scaled', 'Projected_I_scaled', 'Forecast_Rt'});
end

function [observed_dates, observed_i_scaled] = local_observed_holdout_i_proxy( ...
    I_scaled, date, window_indices, holdout_pos, cfg)
%LOCAL_OBSERVED_HOLDOUT_I_PROXY Extract observed I_scaled over holdout dates.
    horizon = cfg.forecast.horizon;
    holdout_origins = window_indices(holdout_pos);
    start_idx = holdout_origins(1);
    end_idx = min(max(holdout_origins + horizon), numel(I_scaled));
    observed_dates = date(start_idx:end_idx);
    observed_i_scaled = I_scaled(start_idx:end_idx);
end

function [forecast_dates, median_projected_i_scaled] = ...
    local_median_projected_i_proxy_by_date(rows)
%LOCAL_MEDIAN_PROJECTED_I_PROXY_BY_DATE Collapse overlapping projections.
    forecast_dates = datetime.empty(0, 1);
    median_projected_i_scaled = zeros(0, 1);

    if isempty(rows)
        return;
    end

    valid_idx = isfinite(rows.Projected_I_scaled);
    if ~any(valid_idx)
        return;
    end

    [forecast_dates, ~, group_id] = unique(rows.ForecastDate(valid_idx));
    median_projected_i_scaled = splitapply(@median, ...
        rows.Projected_I_scaled(valid_idx), group_id);
end

function [y_limits, y_axis_bounded] = local_projected_i_proxy_ylim( ...
    observed_i_scaled, ar_i_scaled, arx_i_scaled)
%LOCAL_PROJECTED_I_PROXY_YLIM Choose a readable I_scaled axis range.
    observed_values = observed_i_scaled(isfinite(observed_i_scaled));
    projected_values = [ar_i_scaled(:); arx_i_scaled(:)];
    projected_values = projected_values(isfinite(projected_values));
    all_values = [observed_values(:); projected_values(:)];

    if isempty(all_values)
        y_limits = [0, 1];
        y_axis_bounded = false;
        return;
    end

    all_values = all_values(all_values >= 0);
    if isempty(all_values)
        y_limits = [0, 1];
        y_axis_bounded = false;
        return;
    end

    full_max = max(all_values);
    observed_max = 0;
    if ~isempty(observed_values)
        observed_max = max(observed_values);
    end

    projected_nonnegative = projected_values(projected_values >= 0);
    if isempty(projected_nonnegative)
        robust_projected_max = 0;
    else
        robust_projected_max = local_percentile(projected_nonnegative, 75);
    end
    display_max = max([observed_max, robust_projected_max, 1e-6]) * 1.25;
    y_axis_bounded = full_max > display_max * 1.5;

    if ~y_axis_bounded
        display_max = max(full_max * 1.10, 1e-6);
    end

    y_limits = [0, display_max];
end

function pct_value = local_percentile(values, pct)
%LOCAL_PERCENTILE Compute a simple nearest-rank percentile.
    values = sort(double(values(:)));
    values = values(isfinite(values));

    if isempty(values)
        pct_value = NaN;
        return;
    end

    pct = min(max(double(pct), 0), 100);
    rank_idx = max(1, ceil((pct / 100) * numel(values)));
    pct_value = values(rank_idx);
end
