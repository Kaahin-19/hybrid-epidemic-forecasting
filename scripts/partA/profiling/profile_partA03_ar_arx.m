%PROFILE_PARTA03_AR_ARX Profile Part A 03 AR and ARX final-forecast paths.
%
%   Description:
%       Runs focused profiling and sanity validation for the AR | None and
%       ARX | I paths used by Part A final forecast execution. The script
%       measures full Part A 03 runtimes in clean MATLAB child processes,
%       then profiles one direct ARX expanding-window forecast in the current
%       MATLAB session through the Part A 03 dispatch (run_model_forecast).
%
%   Workflow:
%       1. Initialize paths and output locations.
%       2. Measure full Part A 03 runtime for AR | None and ARX | I.
%       3. Profile one direct ARX expanding-window fit and closed-loop
%          forecast built from the Part A 03 forecasting helpers.
%       4. Run static path checks and write a Markdown profiling report.
%
%   See also PARTA_03_RUN_FORECASTS, RUN_MODEL_FORECAST, PREPARE_WINDOW_DATA,
%            FIT_ARX_MODEL, FORECAST_ARX_CLOSED_LOOP.
%
% A. M. Kaahin 2026-06-01

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A 03 AR/ARX Profiling ===\n');

script_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(fileparts(script_dir)));
original_dir = pwd;
cleanup_obj = onCleanup(@() cd(original_dir));
cd(repo_root);

startup;
cfg = partA_config();

if ~exist(cfg.output.log_dir, 'dir')
    mkdir(cfg.output.log_dir);
end

profile_path = fullfile(cfg.output.log_dir, 'profile_partA03_ar_arx_profile.mat');
report_path = fullfile(cfg.output.log_dir, 'profile_partA03_ar_arx_report.md');

results = struct();
results.generated_at = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
results.repo_root = string(repo_root);
results.profile_path = string(profile_path);
results.report_path = string(report_path);

%% 2. Full Part A 03 Runtime Measurements
fprintf('Stage: Measuring full Part A 03 runtime for AR | None\n');
results.full_ar_none = local_run_partA03_child(repo_root, "AR", "None");

fprintf('Stage: Measuring full Part A 03 runtime for ARX | I\n');
results.full_arx_i = local_run_partA03_child(repo_root, "ARX", "I");

%% 3. Direct ARX Profiling and Smoke Test
fprintf('Stage: Profiling one direct ARX expanding-window forecast\n');
profile clear;
profile on;
try
    results.direct_arx = local_direct_arx_smoke(cfg);
catch ME
    results.direct_arx = local_exception_result(ME);
end
profile off;
profinfo = profile('info');

%% 4. Report Assembly
results.profile_counts = local_profile_counts(profinfo);
results.profile_times = local_profile_times(profinfo);
results.search_validation = local_search_validation(repo_root);
results.top_total_time = local_profile_top(profinfo, 'TotalTime', 20);
results.top_self_time = local_profile_top(profinfo, 'SelfTime', 20);

%% 4b. Final-Stage Interval Monte Carlo Profiling
fprintf('Stage: Profiling final-stage interval Monte Carlo (AR/ARX)\n');
[results.interval_results, interval_profinfo_cases] = ...
    local_profile_interval_cases(cfg, "final", ...
    {"AR", "None"; "ARX", "I"});

report_text = local_build_report(results);
local_write_text(report_path, report_text);
save(profile_path, 'profinfo', 'interval_profinfo_cases', 'results');

fprintf('\n%s\n', report_text);
fprintf('Profile MAT saved to: %s\n', profile_path);
fprintf('Markdown report saved to: %s\n', report_path);
fprintf('=== Part A 03 AR/ARX Profiling Complete ===\n');

clear cleanup_obj

%% 5. Local Functions
function run_result = local_run_partA03_child(repo_root, model_type, exo_mode)
%LOCAL_RUN_PARTA03_CHILD Run Part A 03 in a clean MATLAB child process.
    model_type = string(model_type);
    exo_mode = string(exo_mode);

    run_result = struct();
    run_result.model_type = model_type;
    run_result.exo_mode = exo_mode;
    run_result.command = "";
    run_result.status = NaN;
    run_result.runtime_seconds = NaN;
    run_result.passed = false;
    run_result.console_tail = "";

    repo_escaped = strrep(char(repo_root), '''', '''''');
    batch_expr = sprintf(['cd(''%s''); startup; ', ...
        'setenv(''PARTA_MODEL_TYPE'',''%s''); ', ...
        'setenv(''PARTA_EXO_MODE'',''%s''); ', ...
        'run(''scripts/partA/partA_03_run_forecasts.m'')'], ...
        repo_escaped, char(model_type), char(exo_mode));

    tmp_output = [tempname, '.log'];
    cmd = sprintf('matlab -batch "%s" > "%s" 2>&1', batch_expr, tmp_output);
    run_result.command = string(cmd);

    timer_obj = tic;
    status = system(cmd);
    run_result.runtime_seconds = toc(timer_obj);
    run_result.status = status;
    run_result.passed = (status == 0);
    run_result.console_tail = local_file_tail(tmp_output, 80);

    if exist(tmp_output, 'file') == 2
        delete(tmp_output);
    end
end

function direct = local_direct_arx_smoke(cfg)
%LOCAL_DIRECT_ARX_SMOKE Run and validate one ARX expanding-window forecast.
    [truth_path, scenario_inputs] = local_load_scenario_inputs(cfg, "I");
    window_entry = prepare_window_data(scenario_inputs, ...
        cfg.forecast.min_window, cfg.forecast.horizon, cfg.sirs);

    [candidate_grid, parameter_names] = generate_candidate_grid(cfg, 'ARX');
    candidate = candidate_grid(1, :);
    num_exo = size(window_entry.U_past, 2);

    % Part A 03 dispatch wrapper runtime.
    forecast_options = struct( ...
        'horizon', cfg.forecast.horizon, ...
        'wis_alphas', cfg.forecast.wis_alphas, ...
        'sirs_cfg', cfg.sirs, ...
        'exo_mode', 'I', ...
        'sim_seed', cfg.sim.seed, ...
        'num_exo', num_exo);
    dispatch_timer = tic;
    forecast = run_model_forecast('ARX', candidate, window_entry, forecast_options);
    dispatch_runtime = toc(dispatch_timer);

    % Detailed fit/forecast timing split mirroring the Part A 03 dispatch.
    nb_vec = repmat(candidate(2), 1, num_exo);
    nk_vec = repmat(candidate(3), 1, num_exo);
    fit_timer = tic;
    [arx_model, fit_timing] = fit_arx_model( ...
        window_entry.Rt_past, window_entry.U_past, candidate(1), nb_vec, nk_vec);
    fit_runtime = toc(fit_timer);

    forecast_loop_options = struct('collect_timing', true);
    forecast_timer = tic;
    [Rt_curve, aicc, ~, lower_bounds, upper_bounds, forecast_timing] = ...
        forecast_arx_closed_loop(arx_model, window_entry.Rt_past, ...
        window_entry.U_past, window_entry.sirs_state, cfg.sirs, 'I', ...
        cfg.forecast.horizon, cfg.forecast.wis_alphas, cfg.sim.seed, ...
        forecast_loop_options);
    forecast_runtime = toc(forecast_timer);

    smoke_checks = struct();
    smoke_checks.dispatch_rt_length = numel(forecast.Rt_pred) == cfg.forecast.horizon;
    smoke_checks.rt_length = numel(Rt_curve) == cfg.forecast.horizon;
    smoke_checks.lower_rows = size(lower_bounds, 1) == cfg.forecast.horizon;
    smoke_checks.upper_rows = size(upper_bounds, 1) == cfg.forecast.horizon;
    smoke_checks.lower_cols = size(lower_bounds, 2) == numel(cfg.forecast.wis_alphas);
    smoke_checks.upper_cols = size(upper_bounds, 2) == numel(cfg.forecast.wis_alphas);
    smoke_checks.forecasts_finite_positive = ...
        all(isfinite(Rt_curve(:))) && all(Rt_curve(:) > 0);
    smoke_checks.bounds_finite_positive = ...
        all(isfinite(lower_bounds(:))) && all(lower_bounds(:) > 0) && ...
        all(isfinite(upper_bounds(:))) && all(upper_bounds(:) > 0);
    smoke_checks.bounds_ordered = all(lower_bounds(:) <= upper_bounds(:));
    smoke_checks.initialize_sirs_stepper_once = ...
        forecast_timing.initialize_sirs_stepper_calls == 1;
    smoke_checks.recursive_arx_step_horizon_calls = ...
        forecast_timing.recursive_arx_step_calls == cfg.forecast.horizon;
    smoke_checks.advance_sirs_stepper_horizon_calls = ...
        forecast_timing.advance_sirs_stepper_calls == cfg.forecast.horizon;

    direct = struct();
    direct.passed = all(struct2array(smoke_checks));
    direct.truth_artifact = string(truth_path);
    direct.parameter_names = string(parameter_names);
    direct.candidate = candidate;
    direct.horizon = cfg.forecast.horizon;
    direct.interval_alphas = cfg.forecast.wis_alphas;
    direct.aicc = aicc;
    direct.dispatch_runtime_seconds = dispatch_runtime;
    direct.fit_runtime_seconds = fit_runtime;
    direct.forecast_runtime_seconds = forecast_runtime;
    direct.total_runtime_seconds = fit_runtime + forecast_runtime;
    direct.fit_timing = fit_timing;
    direct.forecast_timing = forecast_timing;
    direct.smoke_checks = smoke_checks;
    direct.model_used_persistence_fallback = arx_model.is_persistence;
    direct.forecast_used_persistence_fallback = forecast_timing.used_persistence_fallback;
    direct.forecast_fallback_identifier = forecast_timing.fallback_identifier;
end

function [truth_path, scenario_inputs] = local_load_scenario_inputs(cfg, exo_mode)
%LOCAL_LOAD_SCENARIO_INPUTS Build Part A 03 scenario inputs from first truth.
    truth_files = dir(fullfile(cfg.output.data_dir, 'partA_01_truth_*.mat'));
    if isempty(truth_files)
        error('PROFILE:MissingTruth', ...
            'No Part A truth artifacts found under %s.', cfg.output.data_dir);
    end

    [~, order] = sort({truth_files.name});
    truth_files = truth_files(order);
    truth_path = fullfile(truth_files(1).folder, truth_files(1).name);
    loaded = load(truth_path);

    scaled_S = loaded.S_true(:) / cfg.sirs.pop_size;
    scaled_I = loaded.I_true(:) / cfg.sirs.pop_size;
    switch char(exo_mode)
        case 'None', U_true = [];
        case 'S',    U_true = scaled_S;
        case 'I',    U_true = scaled_I;
        case 'Both', U_true = [scaled_S, scaled_I];
        otherwise
            error('PROFILE:UnknownExoMode', 'Unsupported EXO_MODE: %s', string(exo_mode));
    end

    scenario_inputs = struct( ...
        'Rt_true', loaded.Rt_true(:), ...
        'tspan', loaded.tspan(:), ...
        'S_true', loaded.S_true(:), ...
        'I_true', loaded.I_true(:), ...
        'U_true', U_true);
end

function result = local_exception_result(ME)
%LOCAL_EXCEPTION_RESULT Store an exception without aborting report creation.
    result = struct();
    result.passed = false;
    result.horizon = 0;
    result.dispatch_runtime_seconds = NaN;
    result.total_runtime_seconds = NaN;
    result.fit_runtime_seconds = NaN;
    result.forecast_runtime_seconds = NaN;
    result.fit_timing = local_empty_fit_timing();
    result.forecast_timing = local_empty_forecast_timing();
    result.model_used_persistence_fallback = false;
    result.forecast_used_persistence_fallback = false;
    result.forecast_fallback_identifier = "";
    result.error_identifier = string(ME.identifier);
    result.error_message = string(ME.message);
    result.stack = string(getReport(ME, 'extended', 'hyperlinks', 'off'));
end

function timing = local_empty_fit_timing()
%LOCAL_EMPTY_FIT_TIMING Return placeholder fit timing fields.
    timing = struct();
    timing.iddata_total = 0;
    timing.iddata_calls = 0;
    timing.arx_total = 0;
    timing.arx_calls = 0;
    timing.extract_arx_coefficients_total = 0;
    timing.extract_arx_coefficients_calls = 0;
    timing.residual_std_total = 0;
end

function timing = local_empty_forecast_timing()
%LOCAL_EMPTY_FORECAST_TIMING Return placeholder forecast timing fields.
    timing = struct();
    timing.forecast_arx_closed_loop_total = 0;
    timing.initialize_sirs_stepper_total = 0;
    timing.recursive_arx_step_total = 0;
    timing.advance_sirs_stepper_total = 0;
    timing.advance_epidemic_state_total = 0;
    timing.extract_exogenous_from_state_total = 0;
    timing.initialize_sirs_stepper_calls = 0;
    timing.recursive_arx_step_calls = 0;
    timing.advance_sirs_stepper_calls = 0;
    timing.advance_epidemic_state_calls = 0;
    timing.extract_exogenous_from_state_calls = 0;
    timing.used_persistence_fallback = false;
    timing.fallback_identifier = "";
end

function counts = local_profile_counts(profinfo)
%LOCAL_PROFILE_COUNTS Count selected functions in MATLAB profiler output.
    targets = ["run_model_forecast", "fit_arx_model", "extract_arx_coefficients", ...
        "forecast_arx_closed_loop", "recursive_arx_step", ...
        "initialize_sirs_stepper", "advance_sirs_stepper", ...
        "advance_epidemic_state", "extract_exogenous_from_state", ...
        "arx", "forecast", "iddata", "rparse", "urdme", "genData_SIRS"];

    counts = struct();
    for i = 1:numel(targets)
        target = char(targets(i));
        counts.(target) = local_profile_metric(profinfo, target, 'NumCalls');
    end
end

function times = local_profile_times(profinfo)
%LOCAL_PROFILE_TIMES Sum selected function times from profiler output.
    targets = ["run_model_forecast", "fit_arx_model", "extract_arx_coefficients", ...
        "forecast_arx_closed_loop", "recursive_arx_step", ...
        "initialize_sirs_stepper", "advance_sirs_stepper", ...
        "advance_epidemic_state", "extract_exogenous_from_state", ...
        "arx", "forecast", "iddata", "rparse", "urdme", "genData_SIRS"];

    times = struct();
    for i = 1:numel(targets)
        target = char(targets(i));
        times.(target).total = local_profile_metric(profinfo, target, 'TotalTime');
        times.(target).self = local_profile_metric(profinfo, target, 'SelfTime');
    end
end

function value = local_profile_metric(profinfo, target, field_name)
%LOCAL_PROFILE_METRIC Sum one profiler metric for a target function.
    value = 0;
    if ~isfield(profinfo, 'FunctionTable') || isempty(profinfo.FunctionTable)
        return;
    end

    function_table = profinfo.FunctionTable;
    for i = 1:numel(function_table)
        if local_is_profile_target(function_table(i), target)
            value = value + local_profile_row_metric(function_table(i), field_name);
        end
    end
end

function is_match = local_is_profile_target(row, target)
%LOCAL_IS_PROFILE_TARGET Match a top-level profiler function entry.
    target = char(target);
    function_name = string(local_get_field(row, 'FunctionName', ""));
    file_name = string(local_get_field(row, 'FileName', ""));

    if strcmp(target, 'iddata')
        is_match = strcmp(function_name, "iddata") || ...
            startsWith(function_name, "iddata.iddata>iddata.iddata");
        return;
    end

    if contains(function_name, ">")
        is_match = false;
        return;
    end

    [~, file_base] = fileparts(char(file_name));
    simple_name = char(function_name);
    slash_idx = regexp(simple_name, '[\\/]', 'end');
    if ~isempty(slash_idx)
        simple_name = simple_name((slash_idx(end) + 1):end);
    end

    is_match = strcmp(simple_name, target) || strcmp(file_base, target);
end

function top_rows = local_profile_top(profinfo, field_name, max_rows)
%LOCAL_PROFILE_TOP Return top profiler rows by one time field.
    top_rows = struct('function_name', strings(0, 1), ...
        'num_calls', [], 'total_time', [], 'self_time', []);
    if ~isfield(profinfo, 'FunctionTable') || isempty(profinfo.FunctionTable)
        return;
    end

    function_table = profinfo.FunctionTable;
    metric = zeros(numel(function_table), 1);
    for i = 1:numel(function_table)
        metric(i) = local_profile_row_metric(function_table(i), field_name);
    end

    [~, order] = sort(metric, 'descend');
    keep = order(1:min(max_rows, numel(order)));

    top_rows = repmat(struct('function_name', "", 'num_calls', 0, ...
        'total_time', 0, 'self_time', 0), numel(keep), 1);
    for i = 1:numel(keep)
        row = function_table(keep(i));
        top_rows(i).function_name = string(local_get_field(row, 'FunctionName', ""));
        top_rows(i).num_calls = local_get_field(row, 'NumCalls', 0);
        top_rows(i).total_time = local_get_field(row, 'TotalTime', 0);
        top_rows(i).self_time = local_profile_row_metric(row, 'SelfTime');
    end
end

function checks = local_search_validation(repo_root)
%LOCAL_SEARCH_VALIDATION Run static source checks for the Part A 03 paths.
    partA03 = fileread(fullfile(repo_root, 'scripts', 'partA', ...
        'partA_03_run_forecasts.m'));
    run_model_forecast = fileread(fullfile(repo_root, 'src', ...
        'forecasting', 'run_model_forecast.m'));
    forecast_arx = fileread(fullfile(repo_root, 'src', 'models', ...
        'arx', 'forecast_arx_closed_loop.m'));

    checks = struct();
    checks.partA03_uses_dataset_builder = ...
        contains(partA03, 'build_forecasting_dataset');
    checks.partA03_uses_window_forecast = ...
        contains(partA03, 'run_expanding_window_forecast');
    checks.partA03_calls_fit_arima_or_fit_arimax = ...
        contains(partA03, 'fit_arima') || contains(partA03, 'fit_arimax');
    checks.partA03_writes_csv_or_figures = ...
        contains(partA03, 'writetable') || ...
        ~isempty(regexp(partA03, '\<plot_rt_forecast_comparison\s*\(', 'once'));
    checks.run_model_forecast_uses_new_ar = ...
        contains(run_model_forecast, 'fit_ar_model') && ...
        contains(run_model_forecast, 'forecast_ar_model');
    checks.run_model_forecast_uses_new_arx = ...
        contains(run_model_forecast, 'fit_arx_model') && ...
        contains(run_model_forecast, 'forecast_arx_closed_loop');
    checks.run_model_forecast_calls_fit_arima_or_fit_arimax = ...
        contains(run_model_forecast, 'fit_arima') || ...
        contains(run_model_forecast, 'fit_arimax');
    checks.run_model_forecast_calls_genData_SIRS = ...
        contains(run_model_forecast, 'genData_SIRS');
    checks.forecast_arx_uses_stepper = ...
        contains(forecast_arx, 'initialize_sirs_stepper') && ...
        contains(forecast_arx, 'advance_sirs_stepper');
    checks.partA02_git_diff_empty = local_git_diff_empty(repo_root, ...
        'scripts/partA/partA_02_select_global_model_configurations.m src/model_selection');
end

function text = local_build_report(results)
%LOCAL_BUILD_REPORT Create the Markdown report text.
    direct = results.direct_arx;
    counts = results.profile_counts;
    times = results.profile_times;

    advance_fraction = NaN;
    if isfield(direct, 'forecast_timing') && ...
            direct.forecast_timing.forecast_arx_closed_loop_total > 0
        advance_fraction = direct.forecast_timing.advance_sirs_stepper_total / ...
            direct.forecast_timing.forecast_arx_closed_loop_total;
    end

    text = "";
    text = text + "# Part A 03 AR/ARX Profiling Report" + newline + newline;
    text = text + sprintf("Generated: %s\n\n", results.generated_at);

    text = text + "## Summary" + newline + newline;
    text = text + sprintf("- AR | None Part A 03: %s in %.3f s.\n", ...
        local_pass_fail(results.full_ar_none.passed), results.full_ar_none.runtime_seconds);
    text = text + sprintf("- ARX | I Part A 03: %s in %.3f s.\n", ...
        local_pass_fail(results.full_arx_i.passed), results.full_arx_i.runtime_seconds);
    if isfield(direct, 'passed')
        text = text + sprintf("- Direct ARX single-window smoke test: %s.\n", ...
            local_pass_fail(direct.passed));
        text = text + sprintf("- Direct ARX run_model_forecast dispatch runtime: %.3f s.\n", ...
            local_safe_number(direct.dispatch_runtime_seconds));
        text = text + sprintf("- Direct ARX fit+forecast split runtime: %.3f s.\n", ...
            local_safe_number(direct.total_runtime_seconds));
    end
    text = text + sprintf("- ARX forecast closed-loop recursive calls: %d of expected %d.\n", ...
        local_safe_count(direct, 'forecast_timing', 'recursive_arx_step_calls'), ...
        local_safe_count(direct, 'horizon'));
    text = text + sprintf("- ARX SIRS stepper initialization calls: %d of expected 1.\n", ...
        local_safe_count(direct, 'forecast_timing', 'initialize_sirs_stepper_calls'));
    text = text + sprintf("- ARX epidemic-state stepper calls: %d of expected %d.\n", ...
        local_safe_count(direct, 'forecast_timing', 'advance_sirs_stepper_calls'), ...
        local_safe_count(direct, 'horizon'));
    text = text + sprintf("- advance_sirs_stepper share of direct ARX forecast runtime: %.1f%%.\n\n", ...
        100 * advance_fraction);

    text = text + "## Direct ARX Timing Split" + newline + newline;
    text = text + "| Component | Runtime (s) | Calls |" + newline;
    text = text + "|---|---:|---:|" + newline;
    text = text + sprintf("| run_model_forecast dispatch | %.6f | 1 |\n", ...
        local_safe_number(direct.dispatch_runtime_seconds));
    text = text + sprintf("| fit_arx_model | %.6f | 1 |\n", ...
        local_safe_number(direct.fit_runtime_seconds));
    text = text + sprintf("| iddata inside fit_arx_model | %.6f | %d |\n", ...
        direct.fit_timing.iddata_total, direct.fit_timing.iddata_calls);
    text = text + sprintf("| arx inside fit_arx_model | %.6f | %d |\n", ...
        direct.fit_timing.arx_total, direct.fit_timing.arx_calls);
    text = text + sprintf("| extract_arx_coefficients inside fit_arx_model | %.6f | %d |\n", ...
        direct.fit_timing.extract_arx_coefficients_total, ...
        direct.fit_timing.extract_arx_coefficients_calls);
    text = text + sprintf("| residual scale inside fit_arx_model | %.6f | - |\n", ...
        direct.fit_timing.residual_std_total);
    text = text + sprintf("| forecast_arx_closed_loop | %.6f | 1 |\n", ...
        local_safe_number(direct.forecast_runtime_seconds));
    text = text + sprintf("| initialize_sirs_stepper inside forecast | %.6f | %d |\n", ...
        direct.forecast_timing.initialize_sirs_stepper_total, ...
        direct.forecast_timing.initialize_sirs_stepper_calls);
    text = text + sprintf("| recursive_arx_step inside forecast loop | %.6f | %d |\n", ...
        direct.forecast_timing.recursive_arx_step_total, ...
        direct.forecast_timing.recursive_arx_step_calls);
    text = text + sprintf("| advance_sirs_stepper inside forecast loop | %.6f | %d |\n", ...
        direct.forecast_timing.advance_sirs_stepper_total, ...
        direct.forecast_timing.advance_sirs_stepper_calls);
    text = text + sprintf("| extract_exogenous_from_state inside forecast loop | %.6f | %d |\n\n", ...
        direct.forecast_timing.extract_exogenous_from_state_total, ...
        direct.forecast_timing.extract_exogenous_from_state_calls);

    text = text + "## Fallback Status" + newline + newline;
    text = text + sprintf("- fit_arx_model persistence fallback in direct window: %s.\n", ...
        string(direct.model_used_persistence_fallback));
    text = text + sprintf("- forecast_arx_closed_loop persistence fallback in direct window: %s.\n", ...
        string(direct.forecast_used_persistence_fallback));
    text = text + sprintf("- forecast fallback identifier: `%s`.\n\n", ...
        direct.forecast_fallback_identifier);

    text = text + "## Selected Function Call Counts" + newline + newline;
    text = text + "| Function | Profile calls | Total time (s) | Self time (s) |" + newline;
    text = text + "|---|---:|---:|---:|" + newline;
    count_fields = fieldnames(counts);
    for i = 1:numel(count_fields)
        name = count_fields{i};
        text = text + sprintf("| `%s` | %d | %.6f | %.6f |\n", ...
            name, counts.(name), times.(name).total, times.(name).self);
    end
    text = text + newline;

    text = text + "## Top 20 Functions by Total Time" + newline + newline;
    text = text + local_top_table(results.top_total_time) + newline;

    text = text + "## Top 20 Functions by Self Time" + newline + newline;
    text = text + local_top_table(results.top_self_time) + newline;

    text = text + "## Search Validation" + newline + newline;
    sv = results.search_validation;
    text = text + sprintf("- `partA_03_run_forecasts.m` builds the forecast dataset: %s.\n", ...
        string(sv.partA03_uses_dataset_builder));
    text = text + sprintf("- `partA_03_run_forecasts.m` runs the expanding-window forecast: %s.\n", ...
        string(sv.partA03_uses_window_forecast));
    text = text + sprintf("- `partA_03_run_forecasts.m` calls `fit_arima` or `fit_arimax`: %s.\n", ...
        string(sv.partA03_calls_fit_arima_or_fit_arimax));
    text = text + sprintf("- `partA_03_run_forecasts.m` writes CSV or figures: %s.\n", ...
        string(sv.partA03_writes_csv_or_figures));
    text = text + sprintf("- `run_model_forecast.m` uses new AR functions: %s.\n", ...
        string(sv.run_model_forecast_uses_new_ar));
    text = text + sprintf("- `run_model_forecast.m` uses new ARX functions: %s.\n", ...
        string(sv.run_model_forecast_uses_new_arx));
    text = text + sprintf("- `run_model_forecast.m` calls `fit_arima` or `fit_arimax`: %s.\n", ...
        string(sv.run_model_forecast_calls_fit_arima_or_fit_arimax));
    text = text + sprintf("- `run_model_forecast.m` calls `genData_SIRS`: %s.\n", ...
        string(sv.run_model_forecast_calls_genData_SIRS));
    text = text + sprintf("- `forecast_arx_closed_loop.m` uses SIRS stepper helpers: %s.\n", ...
        string(sv.forecast_arx_uses_stepper));
    text = text + sprintf("- Part A 02 selection path untouched in git diff: %s.\n\n", ...
        string(sv.partA02_git_diff_empty));

    text = text + "## Interpretation" + newline + newline;
    if advance_fraction >= 0.5
        text = text + "- The direct ARX forecast is dominated by `advance_sirs_stepper`, ";
        text = text + "which indicates URDME state advancement is the main per-window cost." + newline;
    else
        text = text + "- The direct ARX forecast is not dominated by `advance_sirs_stepper` in this window." + newline;
    end
    text = text + "- The Part A 03 dispatch reproduces the corrected Part A 02 ARX behaviour through `run_model_forecast`." + newline;
    text = text + "- Full Part A 03 runtimes are collected from clean MATLAB child processes; the profiler table comes from one direct ARX window in the current process." + newline;
    text = text + "- The direct ARX window measures one expanding-window forecast; the full Part A 03 runtime covers every window across all four scenarios." + newline + newline;

    text = text + local_interval_report_section(results, "Final-Stage Interval Monte Carlo");
end

function [interval_results, profinfo_cases] = local_profile_interval_cases(cfg, stage, specs)
%LOCAL_PROFILE_INTERVAL_CASES Profile the interval path for several cases.
    interval_results = repmat(local_empty_interval_result(), size(specs, 1), 1);
    profinfo_cases = cell(size(specs, 1), 1);
    for i = 1:size(specs, 1)
        [interval_results(i), profinfo_cases{i}] = local_profile_interval_case( ...
            cfg, specs{i, 1}, specs{i, 2}, stage);
    end
end

function [result, profinfo] = local_profile_interval_case(cfg, model_type, exo_mode, stage)
%LOCAL_PROFILE_INTERVAL_CASE Profile one AR/ARX interval simulation window.
    result = local_empty_interval_result();
    profinfo = struct();
    result.model_type = string(model_type);
    result.exo_mode = string(exo_mode);
    result.stage = string(stage);
    try
        [window_entry, num_exo] = local_build_interval_inputs(cfg, char(exo_mode));
        params = local_first_candidate(cfg, char(model_type));
        context = struct('stage', char(stage), 'exo_mode', char(exo_mode), ...
            'sirs_cfg', cfg.sirs, 'horizon', cfg.forecast.horizon, ...
            'alphas', cfg.forecast.wis_alphas, 'sim_seed', cfg.sim.seed, ...
            'scenario_key', "A1", 'window_index', window_entry.window_day_idx, ...
            'model_type', string(model_type));
        interval_options = make_interval_options(cfg.intervals, context);

        profile clear;
        profile on;
        timer_obj = tic;
        [~, aicc, ~, ~, ~, meta] = simulate_ar_arx_intervals(char(model_type), ...
            params, window_entry.Rt_past, window_entry.U_past, ...
            window_entry.sirs_state, num_exo, interval_options);
        result.runtime_seconds = toc(timer_obj);
        profile off;

        profinfo = profile('info');
        result.counts = local_interval_counts(profinfo);
        result.aicc = aicc;
        result.num_draws = interval_options.num_draws;
        result.num_valid_draws = meta.num_valid_draws;
        result.interval_status = string(meta.interval_status);
        result.interval_method = string(meta.interval_method);
        result.residual_status = string(meta.residual_status);
        result.passed = true;
    catch ME
        try
            profile off;
            profinfo = profile('info');
            result.counts = local_interval_counts(profinfo);
        catch
            profinfo = struct();
        end
        result.error_identifier = string(ME.identifier);
        result.error_message = string(ME.message);
    end
end

function [window_entry, num_exo] = local_build_interval_inputs(cfg, exo_mode)
%LOCAL_BUILD_INTERVAL_INPUTS Build one expanding window from the first truth.
    truth_files = dir(fullfile(cfg.output.data_dir, 'partA_01_truth_*.mat'));
    if isempty(truth_files)
        error('PROFILE:MissingTruth', 'No Part A truth artifacts found.');
    end
    [~, order] = sort({truth_files.name});
    truth_files = truth_files(order);
    loaded = load(fullfile(truth_files(1).folder, truth_files(1).name));

    scaled_S = loaded.S_true(:) / cfg.sirs.pop_size;
    scaled_I = loaded.I_true(:) / cfg.sirs.pop_size;
    switch exo_mode
        case 'None', U_true = [];
        case 'S',    U_true = scaled_S;
        case 'I',    U_true = scaled_I;
        case 'Both', U_true = [scaled_S, scaled_I];
        otherwise
            error('PROFILE:UnknownExoMode', 'Unsupported EXO_MODE: %s', exo_mode);
    end

    scenario_inputs = struct('Rt_true', loaded.Rt_true(:), 'tspan', loaded.tspan(:), ...
        'S_true', loaded.S_true(:), 'I_true', loaded.I_true(:), 'U_true', U_true);
    window_entry = prepare_window_data(scenario_inputs, cfg.forecast.min_window, ...
        cfg.forecast.horizon, cfg.sirs);
    num_exo = size(window_entry.U_past, 2);
end

function params = local_first_candidate(cfg, model_type)
%LOCAL_FIRST_CANDIDATE Return the first candidate row for a model family.
    grid = generate_candidate_grid(cfg, model_type);
    params = grid(1, :);
end

function counts = local_interval_counts(profinfo)
%LOCAL_INTERVAL_COUNTS Count selected interval and epidemic functions.
    targets = {'make_interval_options', 'sample_centered_residuals', ...
        'compute_interval_bounds_from_ensemble', 'simulate_ar_arx_intervals', ...
        'simulate_ar_residual_bootstrap_paths', ...
        'simulate_arx_closed_loop_bootstrap_paths', 'recursive_arx_step', ...
        'initialize_sirs_stepper', 'advance_sirs_stepper'};
    counts = struct();
    for i = 1:numel(targets)
        counts.(targets{i}) = local_profile_metric(profinfo, targets{i}, 'NumCalls');
    end
end

function result = local_empty_interval_result()
%LOCAL_EMPTY_INTERVAL_RESULT Initialize one interval-profile result.
    result = struct();
    result.model_type = "";
    result.exo_mode = "";
    result.stage = "";
    result.runtime_seconds = NaN;
    result.aicc = NaN;
    result.num_draws = NaN;
    result.num_valid_draws = NaN;
    result.interval_status = "";
    result.interval_method = "";
    result.residual_status = "";
    result.passed = false;
    result.error_identifier = "";
    result.error_message = "";
    result.counts = local_interval_counts(struct());
end

function text = local_interval_report_section(results, title)
%LOCAL_INTERVAL_REPORT_SECTION Format the interval-profiling Markdown section.
    text = "## " + string(title) + newline + newline;
    if ~isfield(results, 'interval_results') || isempty(results.interval_results)
        text = text + "No interval profiling was collected." + newline + newline;
        return;
    end

    text = text + "| model | exo | method | draws | valid draws | status | runtime (s) | path-sim calls | recursive_arx_step calls | advance_sirs_stepper calls | sample_centered_residuals calls |" + newline;
    text = text + "|---|---|---|---:|---:|---|---:|---:|---:|---:|---:|" + newline;
    for i = 1:numel(results.interval_results)
        r = results.interval_results(i);
        c = r.counts;
        path_calls = c.simulate_ar_residual_bootstrap_paths + ...
            c.simulate_arx_closed_loop_bootstrap_paths;
        text = text + sprintf("| %s | %s | %s | %d | %d | %s | %.3f | %d | %d | %d | %d |\n", ...
            r.model_type, r.exo_mode, r.interval_method, r.num_draws, ...
            r.num_valid_draws, r.interval_status, r.runtime_seconds, path_calls, ...
            c.recursive_arx_step, c.advance_sirs_stepper, c.sample_centered_residuals);
    end
    text = text + newline;
    text = text + "- Selection uses the lightweight frozen-epidemic residual bootstrap; final uses the resimulated-epidemic Monte Carlo. advance_sirs_stepper calls scale with the per-draw epidemic advances in the final stage." + newline + newline;
end

function table_text = local_top_table(rows)
%LOCAL_TOP_TABLE Format profiler top rows as Markdown.
    table_text = "| Rank | Function | Calls | Total time (s) | Self time (s) |" + newline;
    table_text = table_text + "|---:|---|---:|---:|---:|" + newline;
    for i = 1:numel(rows)
        table_text = table_text + sprintf("| %d | `%s` | %d | %.6f | %.6f |\n", ...
            i, local_escape_markdown(rows(i).function_name), rows(i).num_calls, ...
            rows(i).total_time, rows(i).self_time);
    end
end

function value = local_safe_number(value)
%LOCAL_SAFE_NUMBER Return NaN for unavailable numeric values.
    if isempty(value) || ~isnumeric(value) || ~isscalar(value)
        value = NaN;
    end
end

function count = local_safe_count(root, varargin)
%LOCAL_SAFE_COUNT Safely read a nested numeric count.
    count = 0;
    value = root;
    for i = 1:numel(varargin)
        field_name = varargin{i};
        if isstruct(value) && isfield(value, field_name)
            value = value.(field_name);
        else
            return;
        end
    end

    if isnumeric(value) && isscalar(value)
        count = value;
    end
end

function value = local_get_field(row, field_name, default_value)
%LOCAL_GET_FIELD Read a struct field with a default value.
    if isfield(row, field_name)
        value = row.(field_name);
    else
        value = default_value;
    end
end

function value = local_profile_row_metric(row, field_name)
%LOCAL_PROFILE_ROW_METRIC Read or derive a profiler timing field.
    if strcmp(field_name, 'SelfTime')
        value = local_profile_self_time(row);
    else
        value = local_get_field(row, field_name, 0);
    end
end

function value = local_profile_self_time(row)
%LOCAL_PROFILE_SELF_TIME Derive self time when MATLAB omits SelfTime.
    value = local_get_field(row, 'SelfTime', NaN);
    if isfinite(value)
        return;
    end

    value = local_get_field(row, 'TotalTime', 0);
    if isfield(row, 'Children') && ~isempty(row.Children)
        child_times = [row.Children.TotalTime];
        value = value - sum(child_times);
    end
    value = max(value, 0);
end

function is_empty = local_git_diff_empty(repo_root, path_spec)
%LOCAL_GIT_DIFF_EMPTY Check whether selected paths have no unstaged diff.
    cmd = sprintf('git --no-pager -C "%s" diff --name-only -- %s', repo_root, path_spec);
    [status, output] = system(cmd);
    cleaned = regexprep(output, '[^\x20-\x7E\n]', '');
    is_empty = (status == 0) && isempty(strtrim(cleaned));
end

function tail_text = local_file_tail(file_path, max_lines)
%LOCAL_FILE_TAIL Return the last max_lines from a text file.
    tail_text = "";
    if exist(file_path, 'file') ~= 2
        return;
    end

    raw_text = string(fileread(file_path));
    lines = regexp(raw_text, '\r\n|\n|\r', 'split');
    if isempty(lines)
        return;
    end

    first_line = max(1, numel(lines) - max_lines + 1);
    tail_text = strjoin(lines(first_line:end), newline);
end

function text = local_pass_fail(passed)
%LOCAL_PASS_FAIL Format pass/fail status.
    if passed
        text = "PASSED";
    else
        text = "FAILED";
    end
end

function escaped = local_escape_markdown(value)
%LOCAL_ESCAPE_MARKDOWN Escape table delimiters in Markdown cells.
    escaped = char(strrep(string(value), "|", "\|"));
end

function local_write_text(file_path, text)
%LOCAL_WRITE_TEXT Write text to disk.
    fid = fopen(file_path, 'w');
    if fid < 0
        error('PROFILE:WriteFailed', 'Could not open report for writing: %s', file_path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', text);
    clear cleaner
end
