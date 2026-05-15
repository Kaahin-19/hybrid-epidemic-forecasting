%PROFILE_ORIGINAL_PARTA_ARX_I_INNER_LOOP Targeted original Part A ARX-I timings.
%
% This helper profiles representative original Part A ARX-I operations without
% changing the production pipeline behavior. Outputs are written under
% results/profiling.

clear; close all; clc;

setenv('PARTA_MODEL_TYPE', 'ARX');
setenv('PARTA_EXO_MODE', 'I');

fprintf('=== Original Part A ARX-I Targeted Profiling ===\n');

cfg = partA_config();
horizon = cfg.forecast.horizon;
wis_alphas = cfg.forecast.wis_alphas;

script_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(script_dir));
profile_dir = fullfile(repo_root, 'results', 'profiling');
profile_fig_dir = fullfile(profile_dir, 'figures');
if ~exist(profile_dir, 'dir'), mkdir(profile_dir); end
if ~exist(profile_fig_dir, 'dir'), mkdir(profile_fig_dir); end

tuning_path = fullfile(cfg.output.tuning_dir, ...
    'partA_02_global_hyperparameters_ARX_I.mat');
if exist(tuning_path, 'file')
    tuning = load(tuning_path);
    selected_model = reshape(double(tuning.selected_model), 1, []);
else
    selected_model = [cfg.forecast.max_ar_order, ...
        cfg.forecast.max_exo_order, cfg.forecast.max_exo_delay];
end

fprintf('Selected ARX-I model: %s\n', mat2str(selected_model));

truth_files = dir(fullfile(cfg.output.data_dir, 'partA_01_truth_*.mat'));
if isempty(truth_files)
    error('PROFILE:NoTruthData', 'No Part A truth artifacts found.');
end
[~, sort_idx] = sort({truth_files.name});
truth_files = truth_files(sort_idx);

entries = local_build_profile_entries(truth_files, cfg, 3);
num_entries = numel(entries);
fprintf('Profiling %d representative forecast windows.\n', num_entries);

fit_seconds = nan(num_entries, 1);
fit_valid = false(num_entries, 1);
component_rows = cell(num_entries, 1);

for i = 1:num_entries
    entry = entries(i);
    num_exo = size(entry.U_past, 2);
    nb_vec = repmat(selected_model(2), 1, num_exo);
    nk_vec = repmat(selected_model(3), 1, num_exo);

    fit_tic = tic;
    [Rt_pred, ~, out_alphas, Rt_lower, Rt_upper] = fit_arimax( ...
        entry.Rt_past, entry.U_past, [], selected_model(1), 0, 0, ...
        nb_vec, nk_vec, horizon, wis_alphas, entry.sirs_state, ...
        cfg.sirs, 'I', cfg.sim.seed);
    fit_seconds(i) = toc(fit_tic);
    fit_valid(i) = local_is_valid_forecast(Rt_pred, out_alphas, Rt_lower, Rt_upper, horizon);

    timing = local_time_arx_components(entry, selected_model, cfg);
    component_rows{i} = table( ...
        string(entry.scenario_id), entry.window_day, numel(entry.Rt_past), ...
        timing.fit_iddata_seconds, timing.arx_seconds, ...
        timing.forecast_options_seconds, timing.predict_iddata_seconds, ...
        timing.predict_forecast_seconds, timing.sirs_seconds, ...
        timing.closed_loop_total_seconds, ...
        'VariableNames', {'Scenario', 'WindowDay', 'HistoryLength', ...
        'FitIddataSeconds', 'ArxSeconds', 'ForecastOptionsSeconds', ...
        'PredictIddataSeconds', 'PredictForecastSeconds', 'SirsSeconds', ...
        'ClosedLoopTotalSeconds'});

    fprintf('Window %d/%d (%s day %g): fit %.3fs, components %.3fs\n', ...
        i, num_entries, entry.scenario_id, entry.window_day, ...
        fit_seconds(i), timing.closed_loop_total_seconds + ...
        timing.fit_iddata_seconds + timing.arx_seconds);
end

fit_table = table( ...
    string({entries.scenario_id})', [entries.window_day]', ...
    [entries.history_length]', fit_seconds, fit_valid, ...
    'VariableNames', {'Scenario', 'WindowDay', 'HistoryLength', ...
    'FitArimaxSeconds', 'ForecastValid'});
writetable(fit_table, fullfile(profile_dir, ...
    'original_partA_arx_I_fit_arimax_timing.csv'));

component_table = vertcat(component_rows{:});
writetable(component_table, fullfile(profile_dir, ...
    'original_partA_arx_I_component_timing.csv'));

component_summary = local_component_summary(component_table, fit_table, horizon);
writetable(component_summary, fullfile(profile_dir, ...
    'original_partA_arx_I_component_summary.csv'));

profile clear;
profile on;
for i = 1:min(2, num_entries)
    entry = entries(i);
    num_exo = size(entry.U_past, 2);
    nb_vec = repmat(selected_model(2), 1, num_exo);
    nk_vec = repmat(selected_model(3), 1, num_exo);
    fit_arimax(entry.Rt_past, entry.U_past, [], selected_model(1), ...
        0, 0, nb_vec, nk_vec, horizon, wis_alphas, entry.sirs_state, ...
        cfg.sirs, 'I', cfg.sim.seed);
end
profile off;
profile_info = profile('info');
profile_table = local_profile_top_table(profile_info, 25);
writetable(profile_table, fullfile(profile_dir, ...
    'original_partA_arx_I_matlab_profile_top.csv'));

plot_eval_table = local_time_plot_and_eval(cfg, profile_fig_dir);
writetable(plot_eval_table, fullfile(profile_dir, ...
    'original_partA_arx_I_plot_eval_timing.csv'));

fprintf('\nComponent summary:\n');
disp(component_summary);

fprintf('\nPlot/evaluation timing:\n');
disp(plot_eval_table);

fprintf('Profiling outputs saved to: %s\n', profile_dir);
fprintf('=== Targeted Profiling Complete ===\n');

function entries = local_build_profile_entries(truth_files, cfg, windows_per_scenario)
    horizon = cfg.forecast.horizon;
    entries = struct( ...
        'scenario_id', {}, ...
        'window_day', {}, ...
        'history_length', {}, ...
        'Rt_past', {}, ...
        'U_past', {}, ...
        'sirs_state', {});

    for i = 1:numel(truth_files)
        full_path = fullfile(truth_files(i).folder, truth_files(i).name);
        loaded = load(full_path);
        [~, name_core] = fileparts(truth_files(i).name);
        scenario_id = strrep(name_core, 'partA_01_truth_', '');

        Rt_true = loaded.Rt_true(:);
        tspan = loaded.tspan(:);
        U_true = loaded.I_true(:) / cfg.sirs.pop_size;
        max_T = numel(Rt_true) - horizon;
        windows = cfg.forecast.min_window:cfg.forecast.step_size:max_T;
        sample_idx = unique(round(linspace(1, numel(windows), windows_per_scenario)));

        for j = 1:numel(sample_idx)
            window_day = windows(sample_idx(j));
            idx_T = find(tspan == window_day, 1);
            if isempty(idx_T)
                continue;
            end

            current_S = loaded.S_true(idx_T);
            current_I = loaded.I_true(idx_T);
            current_R = cfg.sirs.pop_size - current_S - current_I;

            entries(end + 1).scenario_id = scenario_id; %#ok<AGROW>
            entries(end).window_day = window_day;
            entries(end).history_length = idx_T;
            entries(end).Rt_past = Rt_true(1:idx_T);
            entries(end).U_past = U_true(1:idx_T, :);
            entries(end).sirs_state = [current_S, current_I, current_R];
        end
    end
end

function is_valid = local_is_valid_forecast(Rt_pred, alphas, lower_Rt, upper_Rt, horizon)
    is_valid = numel(Rt_pred) == horizon && ~isempty(alphas) && ...
        size(lower_Rt, 1) == horizon && size(upper_Rt, 1) == horizon && ...
        size(lower_Rt, 2) == numel(alphas) && ...
        size(upper_Rt, 2) == numel(alphas) && ...
        all(isfinite(Rt_pred(:))) && all(isfinite(lower_Rt(:))) && ...
        all(isfinite(upper_Rt(:))) && all(lower_Rt(:) <= upper_Rt(:));
end

function timing = local_time_arx_components(entry, selected_model, cfg)
    p = selected_model(1);
    num_exo = size(entry.U_past, 2);
    nb_vec = repmat(selected_model(2), 1, num_exo);
    nk_vec = repmat(selected_model(3), 1, num_exo);

    y = log(max(entry.Rt_past(:), eps));
    U = double(entry.U_past);

    timing = struct();

    iddata_tic = tic;
    data = iddata(y, U, 1);
    timing.fit_iddata_seconds = toc(iddata_tic);

    arx_tic = tic;
    sys = arx(data, [p, nb_vec, nk_vec]);
    timing.arx_seconds = toc(arx_tic);

    opt_tic = tic;
    opt = forecastOptions('InitialCondition', 'e');
    timing.forecast_options_seconds = toc(opt_tic);

    rolling_Rt = zeros(numel(entry.Rt_past) + cfg.forecast.horizon, 1);
    rolling_U = zeros(size(U, 1) + cfg.forecast.horizon, size(U, 2));
    rolling_Rt(1:numel(entry.Rt_past)) = entry.Rt_past(:);
    rolling_U(1:size(U, 1), :) = U;
    current_state = local_sanitize_sirs_state(entry.sirs_state, cfg.sirs.pop_size);

    timing.predict_iddata_seconds = 0;
    timing.predict_forecast_seconds = 0;
    timing.sirs_seconds = 0;
    loop_tic = tic;

    for h = 1:cfg.forecast.horizon
        current_idx = numel(entry.Rt_past) + h - 1;
        step_y = log(max(rolling_Rt(1:current_idx), eps));
        step_U = rolling_U(1:current_idx, :);

        step_iddata_tic = tic;
        data_step = iddata(step_y, step_U, 1);
        fit_u_next = step_U(end, :);
        timing.predict_iddata_seconds = timing.predict_iddata_seconds + toc(step_iddata_tic);

        forecast_tic = tic;
        [yf, ~, ~, yf_sd] = forecast(sys, data_step, 1, fit_u_next, opt);
        timing.predict_forecast_seconds = timing.predict_forecast_seconds + toc(forecast_tic);

        step_fit = local_extract_output(yf);
        step_sd = local_extract_output(yf_sd);
        if isempty(step_fit) || isempty(step_sd) || ~isfinite(step_sd(1))
            error('PROFILE:InvalidForecast', 'Component forecast produced invalid output.');
        end

        Rt_next = exp(step_fit(1));
        sirs_tic = tic;
        current_state = local_advance_sirs_one_day(Rt_next, current_state, cfg.sirs, cfg.sim.seed);
        timing.sirs_seconds = timing.sirs_seconds + toc(sirs_tic);

        rolling_Rt(current_idx + 1) = Rt_next;
        rolling_U(current_idx + 1, :) = current_state(2) / cfg.sirs.pop_size;
    end

    timing.closed_loop_total_seconds = toc(loop_tic);
end

function values = local_extract_output(data)
    if isa(data, 'iddata')
        values = double(data.OutputData(:));
    else
        values = double(data(:));
    end
end

function next_state = local_advance_sirs_one_day(Rt_next, current_state, sirs_params, sim_seed)
    uds_params = sirs_params;
    uds_params.I0 = current_state(2);
    uds_params.R0_init = current_state(3);
    uds_params.solver = 'uds';
    uds_params.compile = 0;
    uds_params.Rt = [Rt_next, Rt_next];

    [uds_mod, ~] = genData_SIRS([0, 1], uds_params, sim_seed);
    next_state = local_sanitize_sirs_state(uds_mod.U(:, end), sirs_params.pop_size);
end

function state = local_sanitize_sirs_state(raw_state, pop_size)
    state = reshape(double(raw_state), [], 1);
    if numel(state) ~= 3 || any(~isfinite(state))
        error('PROFILE:InvalidSirsState', 'SIRS state must contain three finite values.');
    end

    tolerance = max(1e-7 * pop_size, 1e-9);
    state(abs(state) < tolerance) = 0;
    state = max(state, 0);
    state(1) = max(state(1), max(1, 1e-6 * pop_size));

    total = sum(state);
    if total <= 0
        error('PROFILE:InvalidSirsState', 'SIRS state total must be positive.');
    end

    state = state * (pop_size / total);
end

function summary = local_component_summary(component_table, fit_table, horizon)
    n = height(component_table);
    total_fit_seconds = sum(fit_table.FitArimaxSeconds, 'omitnan');
    total_component_seconds = sum(component_table.FitIddataSeconds + ...
        component_table.ArxSeconds + component_table.ForecastOptionsSeconds + ...
        component_table.PredictIddataSeconds + ...
        component_table.PredictForecastSeconds + component_table.SirsSeconds, 'omitnan');

    metric = [ ...
        "fit_arimax_end_to_end"; ...
        "fit_iddata"; ...
        "arx_fit"; ...
        "forecast_options"; ...
        "predict_iddata"; ...
        "predict_forecast"; ...
        "sirs_uds"; ...
        "closed_loop_total"; ...
        "component_accounted"];

    total_seconds = [ ...
        total_fit_seconds; ...
        sum(component_table.FitIddataSeconds, 'omitnan'); ...
        sum(component_table.ArxSeconds, 'omitnan'); ...
        sum(component_table.ForecastOptionsSeconds, 'omitnan'); ...
        sum(component_table.PredictIddataSeconds, 'omitnan'); ...
        sum(component_table.PredictForecastSeconds, 'omitnan'); ...
        sum(component_table.SirsSeconds, 'omitnan'); ...
        sum(component_table.ClosedLoopTotalSeconds, 'omitnan'); ...
        total_component_seconds];

    mean_seconds_per_window = total_seconds / max(n, 1);
    mean_seconds_per_horizon_step = [ ...
        NaN; NaN; NaN; NaN; ...
        sum(component_table.PredictIddataSeconds, 'omitnan') / max(n * horizon, 1); ...
        sum(component_table.PredictForecastSeconds, 'omitnan') / max(n * horizon, 1); ...
        sum(component_table.SirsSeconds, 'omitnan') / max(n * horizon, 1); ...
        sum(component_table.ClosedLoopTotalSeconds, 'omitnan') / max(n * horizon, 1); ...
        NaN];

    share_of_component_seconds = total_seconds / max(total_component_seconds, eps);

    summary = table(metric, total_seconds, mean_seconds_per_window, ...
        mean_seconds_per_horizon_step, share_of_component_seconds, ...
        'VariableNames', {'Metric', 'TotalSeconds', 'MeanSecondsPerWindow', ...
        'MeanSecondsPerHorizonStep', 'ShareOfComponentSeconds'});
end

function top_table = local_profile_top_table(profile_info, max_rows)
    function_table = profile_info.FunctionTable;
    if isempty(function_table)
        top_table = table();
        return;
    end

    total_time = [function_table.TotalTime]';
    if isfield(function_table, 'ChildrenTotalTime')
        self_time = [function_table.TotalTime]' - [function_table.ChildrenTotalTime]';
    else
        self_time = nan(size(total_time));
    end
    num_calls = [function_table.NumCalls]';
    function_names = string({function_table.FunctionName})';
    file_names = string({function_table.FileName})';

    [~, sort_idx] = sort(total_time, 'descend');
    keep = sort_idx(1:min(max_rows, numel(sort_idx)));

    top_table = table(function_names(keep), file_names(keep), num_calls(keep), ...
        total_time(keep), self_time(keep), ...
        'VariableNames', {'FunctionName', 'FileName', 'NumCalls', ...
        'TotalTimeSeconds', 'SelfTimeSeconds'});
end

function timing_table = local_time_plot_and_eval(cfg, profile_fig_dir)
    forecast_files = dir(fullfile(cfg.output.forecast_dir, 'partA_03_forecast_*_ARX_I.mat'));
    [~, sort_idx] = sort({forecast_files.name});
    forecast_files = forecast_files(sort_idx);

    plot_seconds = zeros(numel(forecast_files), 1);
    scenario_names = strings(numel(forecast_files), 1);
    score_rows = cell(numel(forecast_files), 1);

    eval_tic = tic;
    for i = 1:numel(forecast_files)
        forecast_path = fullfile(forecast_files(i).folder, forecast_files(i).name);
        data = load(forecast_path);
        tokens = split(erase(forecast_files(i).name, '.mat'), '_');
        scenario_id = string(tokens{4});
        scenario_names(i) = scenario_id;

        score_rows{i} = local_score_forecast_results(data.results, scenario_id);

        truth_path = fullfile(cfg.output.data_dir, ...
            sprintf('partA_01_truth_%s.mat', scenario_id));
        truth = load(truth_path);
        plot_cfg = cfg;
        plot_cfg.output.fig_dir = profile_fig_dir;
        plot_tic = tic;
        plot_rt_forecast_comparison(data.results, truth.Rt_true(:), truth.tspan(:), ...
            sprintf('%s_ARX_I_profile', scenario_id), plot_cfg);
        plot_seconds(i) = toc(plot_tic);
        close all;
    end
    eval_without_plot_seconds = toc(eval_tic) - sum(plot_seconds);

    score_registry = vertcat(score_rows{:});
    score_registry.IncludeInMainComparison = true(height(score_registry), 1);
    perf_cfg = cfg;
    perf_cfg.output.fig_dir = profile_fig_dir;
    perf_plot_tic = tic;
    plot_model_performance(score_registry, perf_cfg);
    performance_plot_seconds = toc(perf_plot_tic);
    close all;

    timing_table = table( ...
        ["forecast_plot_total"; "forecast_plot_mean"; ...
        "wis_eval_without_plots"; "performance_boxplot"], ...
        [sum(plot_seconds); mean(plot_seconds); ...
        eval_without_plot_seconds; performance_plot_seconds], ...
        'VariableNames', {'Metric', 'Seconds'});
end

function score_table = local_score_forecast_results(results, scenario_id)
    rows = cell(numel(results), 1);
    for k = 1:numel(results)
        truth_Rt = double(results(k).truth_Rt_window(:));
        pred_Rt = double(results(k).forecast_median(:));
        alphas = reshape(double(results(k).forecast_interval_alphas), 1, []);
        lower_Rt = double(results(k).forecast_lower);
        upper_Rt = double(results(k).forecast_upper);
        pointwise_wis = local_compute_wis(truth_Rt, pred_Rt, lower_Rt, upper_Rt, alphas);
        rows{k} = table(categorical(string(scenario_id)), categorical("ARX"), ...
            categorical("I"), results(k).window_day, mean(pointwise_wis), ...
            'VariableNames', {'Scenario', 'Model', 'ExoMode', 'WindowDay', 'WindowWIS'});
    end
    score_table = vertcat(rows{:});
end

function wis = local_compute_wis(truth_Rt, median_Rt, lower_Rt, upper_Rt, alphas)
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
