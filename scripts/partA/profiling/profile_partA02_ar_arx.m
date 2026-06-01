%PROFILE_PARTA02_AR_ARX Profile Part A 02 AR and ARX model-selection paths.
%
%   Description:
%       Runs focused profiling and sanity validation for the AR | None and
%       ARX | I paths used by Part A global model-configuration selection.
%       The script measures full Part A 02 runtimes in clean MATLAB child
%       processes, then profiles one direct ARX expanding-window call in the
%       current MATLAB session.
%
%   Workflow:
%       1. Initialize paths and output locations.
%       2. Measure full Part A 02 runtime for AR | None and ARX | I.
%       3. Profile one direct ARX expanding-window fit and closed-loop
%          forecast.
%       4. Run static path checks and write a Markdown profiling report.
%
%   See also PARTA_02_SELECT_GLOBAL_MODEL_CONFIGURATIONS, FIT_ARX_MODEL,
%            FORECAST_ARX_CLOSED_LOOP.
%
% A. M. Kaahin 2026-06-01

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A 02 AR/ARX Profiling ===\n');

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

profile_path = fullfile(cfg.output.log_dir, 'profile_partA02_ar_arx_profile.mat');
report_path = fullfile(cfg.output.log_dir, 'profile_partA02_ar_arx_report.md');

results = struct();
results.generated_at = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
results.repo_root = string(repo_root);
results.profile_path = string(profile_path);
results.report_path = string(report_path);
results.previous_baseline = local_previous_baseline();

%% 2. Full Part A 02 Runtime Measurements
fprintf('Stage: Measuring full Part A 02 runtime for AR | None\n');
results.full_ar_none = local_run_partA02_child(repo_root, "AR", "None");

fprintf('Stage: Measuring full Part A 02 runtime for ARX | I\n');
results.full_arx_i = local_run_partA02_child(repo_root, "ARX", "I");

%% 3. Direct ARX Profiling and Smoke Test
fprintf('Stage: Profiling one direct ARX expanding-window call\n');
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

report_text = local_build_report(results);
local_write_text(report_path, report_text);
save(profile_path, 'profinfo', 'results');

fprintf('\n%s\n', report_text);
fprintf('Profile MAT saved to: %s\n', profile_path);
fprintf('Markdown report saved to: %s\n', report_path);
fprintf('=== Part A 02 AR/ARX Profiling Complete ===\n');

clear cleanup_obj

%% 5. Local Functions
function run_result = local_run_partA02_child(repo_root, model_type, exo_mode)
%LOCAL_RUN_PARTA02_CHILD Run Part A 02 in a clean MATLAB child process.
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
        'run(''scripts/partA/partA_02_select_global_model_configurations.m'')'], ...
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

function baseline = local_previous_baseline()
%LOCAL_PREVIOUS_BASELINE Store pre-stepper profiling results for comparison.
    baseline = struct();
    baseline.full_ar_none_seconds = 29.785;
    baseline.full_arx_i_seconds = 200.138;
    baseline.direct_arx_total_seconds = 1.641;
    baseline.fit_arx_model_seconds = 0.943833;
    baseline.forecast_arx_closed_loop_seconds = 0.697514;
    baseline.recursive_arx_step_total_seconds = 0.005769;
    baseline.advance_epidemic_state_total_seconds = 0.675073;
    baseline.rparse_calls = 14;
    baseline.urdme_calls = 28;
    baseline.genData_SIRS_calls = 0;
    baseline.forecast_calls = 0;
end

function direct = local_direct_arx_smoke(cfg)
%LOCAL_DIRECT_ARX_SMOKE Run and validate one ARX expanding-window call.
    truth_files = dir(fullfile(cfg.output.data_dir, 'partA_01_truth_*.mat'));
    if isempty(truth_files)
        error('PROFILE:MissingTruth', ...
            'No Part A truth artifacts found under %s.', cfg.output.data_dir);
    end

    truth_files = local_sort_dir_by_name(truth_files);
    truth_path = fullfile(truth_files(1).folder, truth_files(1).name);
    data = load(truth_path);

    idx_T = find(data.tspan(:) == cfg.forecast.min_window, 1);
    if isempty(idx_T)
        error('PROFILE:MissingWindow', ...
            'Could not locate min_window = %d in truth tspan.', cfg.forecast.min_window);
    end

    [candidate_grid, parameter_names] = generate_candidate_grid(cfg, 'ARX');
    candidate = candidate_grid(1, :);

    Rt_hist = data.Rt_true(1:idx_T);
    U_hist = data.I_true(1:idx_T)' / cfg.sirs.pop_size;
    current_S = data.S_true(idx_T);
    current_I = data.I_true(idx_T);
    if isfield(data, 'R_true')
        current_R = data.R_true(idx_T);
    else
        current_R = cfg.sirs.pop_size - current_S - current_I;
    end
    sirs_state = [current_S, current_I, current_R];

    fit_timer = tic;
    [arx_model, fit_timing] = fit_arx_model( ...
        Rt_hist, U_hist, candidate(1), candidate(2), candidate(3));
    fit_runtime = toc(fit_timer);

    forecast_options = struct('collect_timing', true);
    forecast_timer = tic;
    [Rt_curve, aicc, out_alphas, lower_bounds, upper_bounds, forecast_timing] = ...
        forecast_arx_closed_loop(arx_model, Rt_hist, U_hist, sirs_state, ...
        cfg.sirs, 'I', cfg.forecast.horizon, cfg.forecast.wis_alphas, ...
        cfg.sim.seed, forecast_options);
    forecast_runtime = toc(forecast_timer);

    smoke_checks = struct();
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

function result = local_exception_result(ME)
%LOCAL_EXCEPTION_RESULT Store an exception without aborting report creation.
    result = struct();
    result.passed = false;
    result.horizon = 0;
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
    targets = ["fit_arx_model", "extract_arx_coefficients", ...
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
    targets = ["fit_arx_model", "extract_arx_coefficients", ...
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
%LOCAL_SEARCH_VALIDATION Run static source checks for the requested paths.
    evaluate_candidate = fileread(fullfile(repo_root, 'src', ...
        'model_selection', 'evaluate_candidate.m'));
    forecast_arx = fileread(fullfile(repo_root, 'src', 'models', ...
        'arx', 'forecast_arx_closed_loop.m'));
    recursive_arx = fileread(fullfile(repo_root, 'src', 'models', ...
        'arx', 'recursive_arx_step.m'));

    arx_path_text = local_concat_files({ ...
        fullfile(repo_root, 'src', 'models', 'arx'), ...
        fullfile(repo_root, 'src', 'epidemic', 'advance_epidemic_state.m')});

    checks = struct();
    checks.evaluate_candidate_uses_new_ar = ...
        contains(evaluate_candidate, 'fit_ar_model') && ...
        contains(evaluate_candidate, 'forecast_ar_model');
    checks.evaluate_candidate_uses_new_arx = ...
        contains(evaluate_candidate, 'fit_arx_model') && ...
        contains(evaluate_candidate, 'forecast_arx_closed_loop');
    checks.evaluate_candidate_calls_fit_arima_or_fit_arimax = ...
        contains(evaluate_candidate, 'fit_arima') || ...
        contains(evaluate_candidate, 'fit_arimax');
    checks.new_arx_path_calls_genData_SIRS = contains(arx_path_text, 'genData_SIRS');
    checks.forecast_arx_uses_stepper = ...
        contains(forecast_arx, 'initialize_sirs_stepper') && ...
        contains(forecast_arx, 'advance_sirs_stepper');
    checks.forecast_arx_calls_advance_epidemic_state = ...
        ~isempty(regexp(forecast_arx, '\<advance_epidemic_state\s*\(', 'once'));
    checks.forecast_arx_calls_forecast = ...
        ~isempty(regexp(forecast_arx, '\<forecast\s*\(', 'once'));
    checks.recursive_arx_calls_system_id = ...
        ~isempty(regexp(recursive_arx, ...
        '\<(iddata|arx|armax|forecast|forecastOptions|n4sid|ssest)\s*\(', 'once'));
    checks.partA03_git_diff_empty = local_git_diff_empty(repo_root, ...
        'scripts/partA/partA_03_run_forecasts.m');
    checks.n4sid_ssest_git_diff_empty = local_git_diff_empty(repo_root, ...
        'src/models/fit_n4sid_model.m src/models/fit_ssest_model.m src/models/n4sid src/models/ssest');
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
    text = text + "# Part A 02 AR/ARX Profiling Report" + newline + newline;
    text = text + sprintf("Generated: %s\n\n", results.generated_at);

    text = text + "## Summary" + newline + newline;
    text = text + sprintf("- AR | None Part A 02: %s in %.3f s.\n", ...
        local_pass_fail(results.full_ar_none.passed), results.full_ar_none.runtime_seconds);
    text = text + sprintf("- ARX | I Part A 02: %s in %.3f s.\n", ...
        local_pass_fail(results.full_arx_i.passed), results.full_arx_i.runtime_seconds);
    if isfield(direct, 'passed')
        text = text + sprintf("- Direct ARX single-window smoke test: %s in %.3f s.\n", ...
            local_pass_fail(direct.passed), local_safe_number(direct.total_runtime_seconds));
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

    text = text + "## Before/After Comparison" + newline + newline;
    baseline = results.previous_baseline;
    text = text + "| Metric | Before | After | Change |" + newline;
    text = text + "|---|---:|---:|---:|" + newline;
    text = text + local_comparison_row("AR | None Part A 02 runtime (s)", ...
        baseline.full_ar_none_seconds, results.full_ar_none.runtime_seconds, "%.3f");
    text = text + local_comparison_row("ARX | I Part A 02 runtime (s)", ...
        baseline.full_arx_i_seconds, results.full_arx_i.runtime_seconds, "%.3f");
    text = text + local_comparison_row("Direct ARX total runtime (s)", ...
        baseline.direct_arx_total_seconds, direct.total_runtime_seconds, "%.3f");
    text = text + local_comparison_row("Direct fit_arx_model runtime (s)", ...
        baseline.fit_arx_model_seconds, direct.fit_runtime_seconds, "%.3f");
    text = text + local_comparison_row("Direct forecast_arx_closed_loop runtime (s)", ...
        baseline.forecast_arx_closed_loop_seconds, ...
        direct.forecast_timing.forecast_arx_closed_loop_total, "%.3f");
    text = text + local_comparison_row("recursive_arx_step total (s)", ...
        baseline.recursive_arx_step_total_seconds, ...
        direct.forecast_timing.recursive_arx_step_total, "%.6f");
    text = text + local_comparison_row("epidemic advancement total (s)", ...
        baseline.advance_epidemic_state_total_seconds, ...
        direct.forecast_timing.advance_sirs_stepper_total, "%.3f");
    text = text + local_comparison_row("rparse calls in direct ARX profile", ...
        baseline.rparse_calls, counts.rparse, "%.0f");
    text = text + local_comparison_row("urdme calls in direct ARX profile", ...
        baseline.urdme_calls, counts.urdme, "%.0f");
    text = text + local_comparison_row("genData_SIRS calls in direct ARX profile", ...
        baseline.genData_SIRS_calls, counts.genData_SIRS, "%.0f");
    text = text + local_comparison_row("forecast calls in direct ARX profile", ...
        baseline.forecast_calls, counts.forecast, "%.0f");
    text = text + newline;

    text = text + "## Direct ARX Timing Split" + newline + newline;
    text = text + "| Component | Runtime (s) | Calls |" + newline;
    text = text + "|---|---:|---:|" + newline;
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
    text = text + sprintf("- `evaluate_candidate.m` uses new AR functions: %s.\n", ...
        string(sv.evaluate_candidate_uses_new_ar));
    text = text + sprintf("- `evaluate_candidate.m` uses new ARX functions: %s.\n", ...
        string(sv.evaluate_candidate_uses_new_arx));
    text = text + sprintf("- Part A 02 AR/ARX path calls `fit_arima` or `fit_arimax`: %s.\n", ...
        string(sv.evaluate_candidate_calls_fit_arima_or_fit_arimax));
    text = text + sprintf("- New ARX path calls `genData_SIRS`: %s.\n", ...
        string(sv.new_arx_path_calls_genData_SIRS));
    text = text + sprintf("- `forecast_arx_closed_loop.m` uses SIRS stepper helpers: %s.\n", ...
        string(sv.forecast_arx_uses_stepper));
    text = text + sprintf("- `forecast_arx_closed_loop.m` calls `advance_epidemic_state`: %s.\n", ...
        string(sv.forecast_arx_calls_advance_epidemic_state));
    text = text + sprintf("- `forecast_arx_closed_loop.m` calls `forecast(...)`: %s.\n", ...
        string(sv.forecast_arx_calls_forecast));
    text = text + sprintf("- `recursive_arx_step.m` calls System Identification functions: %s.\n", ...
        string(sv.recursive_arx_calls_system_id));
    text = text + sprintf("- `partA_03_run_forecasts.m` untouched in git diff: %s.\n", ...
        string(sv.partA03_git_diff_empty));
    text = text + sprintf("- N4SID/SSEST files untouched in git diff: %s.\n\n", ...
        string(sv.n4sid_ssest_git_diff_empty));

    text = text + "## Interpretation" + newline + newline;
    if advance_fraction >= 0.5
        text = text + "- The direct ARX forecast is dominated by `advance_sirs_stepper`, ";
        text = text + "which indicates URDME state advancement is the next optimization target." + newline;
    else
        text = text + "- The direct ARX forecast is not dominated by `advance_sirs_stepper` in this window." + newline;
    end
    text = text + "- The coefficient-recursive ARX horizon path is used when the closed-loop call count equals the forecast horizon." + newline;
    text = text + "- The full Part A 02 runtime measurements are collected from clean MATLAB child processes; the MATLAB profiler table comes from the direct ARX window in the current process." + newline;
    text = text + "- Recommended next optimization step: consider reusing more solve-time URDME data inside `advance_sirs_stepper` only if further profiling shows solve setup still dominates." + newline;
end

function row = local_comparison_row(label, before_value, after_value, number_format)
%LOCAL_COMPARISON_ROW Format one before/after Markdown table row.
    change_value = after_value - before_value;
    row = sprintf("| %s | %s | %s | %s |\n", label, ...
        sprintf(number_format, before_value), ...
        sprintf(number_format, after_value), ...
        sprintf(number_format, change_value));
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

function text = local_concat_files(paths)
%LOCAL_CONCAT_FILES Concatenate text from files or directories.
    text = "";
    for i = 1:numel(paths)
        path_item = paths{i};
        if isfolder(path_item)
            files = dir(fullfile(path_item, '*.m'));
            for j = 1:numel(files)
                text = text + newline + string(fileread(fullfile(files(j).folder, files(j).name)));
            end
        elseif isfile(path_item)
            text = text + newline + string(fileread(path_item));
        end
    end
end

function is_empty = local_git_diff_empty(repo_root, path_spec)
%LOCAL_GIT_DIFF_EMPTY Check whether selected paths have no unstaged diff.
    cmd = sprintf('git -C "%s" diff --name-only -- %s', repo_root, path_spec);
    [status, output] = system(cmd);
    is_empty = (status == 0) && isempty(strtrim(output));
end

function files = local_sort_dir_by_name(files)
%LOCAL_SORT_DIR_BY_NAME Sort a dir struct by name.
    [~, order] = sort({files.name});
    files = files(order);
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
