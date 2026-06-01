%PROFILE_PARTA03_N4SID_SSEST Profile Part A 03 N4SID/SSEST forecast paths.
%
%   Description:
%       Runs focused full-script timing and direct one-window profiling for
%       exactly four Part A 03 state-space cases: N4SID | None, N4SID | I,
%       SSEST | None, and SSEST | I. The None cases measure the statistical
%       forecast path, while the I cases measure the closed-loop SIRS
%       feedback path. Direct profiling exercises the Part A 03 dispatch
%       (run_model_forecast) on a single expanding window.
%
%   Workflow:
%       1. Initialize paths, configuration, and output locations.
%       2. Measure full Part A 03 runtime in child MATLAB processes.
%       3. Profile one direct expanding-window forecast for each case.
%       4. Write a Markdown report and save profiler data.
%
%   See also PARTA_03_RUN_FORECASTS, RUN_MODEL_FORECAST, PREPARE_WINDOW_DATA,
%            FIT_N4SID_MODEL, FIT_SSEST_MODEL.
%
% A. M. Kaahin 2026-06-01

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part A 03 N4SID/SSEST Profiling ===\n');

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

profile_path = fullfile(cfg.output.log_dir, 'profile_partA03_n4sid_ssest_profile.mat');
report_path = fullfile(cfg.output.log_dir, 'profile_partA03_n4sid_ssest_report.md');

cases = struct( ...
    'model_type', {"N4SID", "N4SID", "SSEST", "SSEST"}, ...
    'exo_mode', {"None", "I", "None", "I"});

results = struct();
results.generated_at = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
results.repo_root = string(repo_root);
results.profile_path = string(profile_path);
results.report_path = string(report_path);

%% 2. Full Part A 03 Runtime Measurements
full_results = repmat(local_empty_full_result(), numel(cases), 1);
for i = 1:numel(cases)
    fprintf('Stage: Measuring full Part A 03 runtime for %s | %s\n', ...
        cases(i).model_type, cases(i).exo_mode);
    full_results(i) = local_run_partA03_child( ...
        repo_root, cases(i).model_type, cases(i).exo_mode);
end
results.full_results = full_results;

%% 3. Direct One-Window Profiling
direct_results = repmat(local_empty_direct_result(), numel(cases), 1);
profinfo_cases = cell(numel(cases), 1);
for i = 1:numel(cases)
    fprintf('Stage: Direct profile for %s | %s\n', ...
        cases(i).model_type, cases(i).exo_mode);
    profile clear;
    profile on;
    try
        direct_results(i) = local_direct_profile_case( ...
            cfg, cases(i).model_type, cases(i).exo_mode);
    catch ME
        direct_results(i) = local_direct_exception_result( ...
            cases(i).model_type, cases(i).exo_mode, ME);
    end
    profile off;
    profinfo_cases{i} = profile('info');
    direct_results(i).counts = local_profile_counts( ...
        profinfo_cases{i}, cases(i).model_type);
end
results.direct_results = direct_results;

%% 4. Report Assembly
results.search_validation = local_search_validation(repo_root);
report_text = local_build_report(results);
local_write_text(report_path, report_text);
save(profile_path, 'profinfo_cases', 'results');

fprintf('\n%s\n', report_text);
fprintf('Profile MAT saved to: %s\n', profile_path);
fprintf('Markdown report saved to: %s\n', report_path);
fprintf('=== Part A 03 N4SID/SSEST Profiling Complete ===\n');

clear cleanup_obj

%% 5. Local Functions
function result = local_empty_full_result()
%LOCAL_EMPTY_FULL_RESULT Initialize full-script result fields.
    result = struct();
    result.model_type = "";
    result.exo_mode = "";
    result.command = "";
    result.status = NaN;
    result.runtime_seconds = NaN;
    result.passed = false;
    result.console_tail = "";
end

function result = local_empty_direct_result()
%LOCAL_EMPTY_DIRECT_RESULT Initialize direct profile result fields.
    result = struct();
    result.model_type = "";
    result.exo_mode = "";
    result.runtime_seconds = NaN;
    result.passed = false;
    result.aicc = NaN;
    result.truth_artifact = "";
    result.candidate = [];
    result.error_identifier = "";
    result.error_message = "";
    result.counts = local_empty_counts();
end

function counts = local_empty_counts()
%LOCAL_EMPTY_COUNTS Initialize selected profiler count fields.
    counts = struct();
    counts.run_model_forecast = 0;
    counts.estimator = 0;
    counts.forecast = 0;
    counts.iddata = 0;
    counts.initialize_sirs_stepper = 0;
    counts.advance_sirs_stepper = 0;
    counts.rparse = 0;
    counts.urdme = 0;
    counts.genData_SIRS = 0;
end

function run_result = local_run_partA03_child(repo_root, model_type, exo_mode)
%LOCAL_RUN_PARTA03_CHILD Run Part A 03 in a clean MATLAB child process.
    model_type = string(model_type);
    exo_mode = string(exo_mode);

    run_result = local_empty_full_result();
    run_result.model_type = model_type;
    run_result.exo_mode = exo_mode;

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

function direct = local_direct_profile_case(cfg, model_type, exo_mode)
%LOCAL_DIRECT_PROFILE_CASE Run one direct Part A 03 single-window forecast.
    model_type = string(model_type);
    exo_mode = string(exo_mode);
    [truth_path, scenario_inputs] = local_load_scenario_inputs(cfg, exo_mode);
    window_entry = prepare_window_data(scenario_inputs, ...
        cfg.forecast.min_window, cfg.forecast.horizon, cfg.sirs);

    [candidate_grid, ~] = generate_candidate_grid(cfg, char(model_type));
    candidate = candidate_grid(1, :);

    forecast_options = struct( ...
        'horizon', cfg.forecast.horizon, ...
        'wis_alphas', cfg.forecast.wis_alphas, ...
        'sirs_cfg', cfg.sirs, ...
        'exo_mode', char(exo_mode), ...
        'sim_seed', cfg.sim.seed, ...
        'num_exo', size(window_entry.U_past, 2));

    timer_obj = tic;
    forecast = run_model_forecast(char(model_type), candidate, ...
        window_entry, forecast_options);
    runtime_seconds = toc(timer_obj);

    local_validate_forecast_output(forecast.Rt_pred, forecast.interval_alphas, ...
        forecast.lower_bounds, forecast.upper_bounds, cfg.forecast.horizon);

    direct = local_empty_direct_result();
    direct.model_type = model_type;
    direct.exo_mode = exo_mode;
    direct.runtime_seconds = runtime_seconds;
    direct.passed = true;
    direct.aicc = forecast.aicc;
    direct.truth_artifact = string(truth_path);
    direct.candidate = candidate;
end

function direct = local_direct_exception_result(model_type, exo_mode, ME)
%LOCAL_DIRECT_EXCEPTION_RESULT Store a direct-profile exception.
    direct = local_empty_direct_result();
    direct.model_type = string(model_type);
    direct.exo_mode = string(exo_mode);
    direct.passed = false;
    direct.error_identifier = string(ME.identifier);
    direct.error_message = string(ME.message);
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

function local_validate_forecast_output(Rt_curve, out_alphas, lower_bounds, upper_bounds, horizon)
%LOCAL_VALIDATE_FORECAST_OUTPUT Verify direct smoke output shape and values.
    Rt_curve = double(Rt_curve(:));
    lower_bounds = double(lower_bounds);
    upper_bounds = double(upper_bounds);
    out_alphas = reshape(double(out_alphas), 1, []);

    if numel(Rt_curve) ~= horizon || ...
            size(lower_bounds, 1) ~= horizon || ...
            size(upper_bounds, 1) ~= horizon || ...
            size(lower_bounds, 2) ~= numel(out_alphas) || ...
            size(upper_bounds, 2) ~= numel(out_alphas) || ...
            any(~isfinite(Rt_curve(:))) || any(Rt_curve(:) <= 0) || ...
            any(~isfinite(lower_bounds(:))) || any(lower_bounds(:) <= 0) || ...
            any(~isfinite(upper_bounds(:))) || any(upper_bounds(:) <= 0) || ...
            any(lower_bounds(:) > upper_bounds(:))
        error('PROFILE:InvalidDirectForecast', ...
            'Direct profile forecast output is invalid.');
    end
end

function counts = local_profile_counts(profinfo, model_type)
%LOCAL_PROFILE_COUNTS Count selected top-level profiler functions.
    counts = local_empty_counts();
    if strcmp(string(model_type), "N4SID")
        estimator_target = 'n4sid';
    else
        estimator_target = 'ssest';
    end

    counts.run_model_forecast = local_profile_metric(profinfo, 'run_model_forecast');
    counts.estimator = local_profile_metric(profinfo, estimator_target);
    counts.forecast = local_profile_metric(profinfo, 'forecast');
    counts.iddata = local_profile_metric(profinfo, 'iddata');
    counts.initialize_sirs_stepper = local_profile_metric(profinfo, 'initialize_sirs_stepper');
    counts.advance_sirs_stepper = local_profile_metric(profinfo, 'advance_sirs_stepper');
    counts.rparse = local_profile_metric(profinfo, 'rparse');
    counts.urdme = local_profile_metric(profinfo, 'urdme');
    counts.genData_SIRS = local_profile_metric(profinfo, 'genData_SIRS');
end

function value = local_profile_metric(profinfo, target)
%LOCAL_PROFILE_METRIC Count top-level profiler calls for one target.
    value = 0;
    if ~isfield(profinfo, 'FunctionTable') || isempty(profinfo.FunctionTable)
        return;
    end

    function_table = profinfo.FunctionTable;
    for i = 1:numel(function_table)
        if local_is_profile_target(function_table(i), target)
            value = value + function_table(i).NumCalls;
        end
    end
end

function is_match = local_is_profile_target(row, target)
%LOCAL_IS_PROFILE_TARGET Match one top-level profiler function entry.
    target = char(target);
    function_name = string(row.FunctionName);
    file_name = string(row.FileName);

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

function checks = local_search_validation(repo_root)
%LOCAL_SEARCH_VALIDATION Check files excluded by this profiling pass.
    checks = struct();
    checks.ar_arx_git_diff_empty = local_git_diff_empty(repo_root, ...
        'src/models/ar src/models/arx');
    checks.partA02_git_diff_empty = local_git_diff_empty(repo_root, ...
        'scripts/partA/partA_02_select_global_model_configurations.m src/model_selection');
end

function text = local_build_report(results)
%LOCAL_BUILD_REPORT Create the Markdown report text.
    text = "";
    text = text + "# Part A 03 N4SID/SSEST Profiling Report" + newline + newline;
    text = text + sprintf("Generated: %s\n\n", results.generated_at);
    text = text + "## Four-Case Comparison" + newline + newline;
    text = text + "| model | exogenous mode | full Part A 03 runtime | direct runtime | run_model_forecast calls | n4sid/ssest calls | forecast calls | iddata calls | initialize_sirs_stepper calls | advance_sirs_stepper calls | rparse calls | urdme calls | genData_SIRS calls | passed |" + newline;
    text = text + "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|" + newline;

    for i = 1:numel(results.full_results)
        full_result = results.full_results(i);
        direct = results.direct_results(i);
        counts = direct.counts;
        passed = full_result.passed && direct.passed;
        text = text + sprintf('| %s | %s | %.3f | %.3f | %d | %d | %d | %d | %d | %d | %d | %d | %d | %s |\n', ...
            full_result.model_type, full_result.exo_mode, ...
            full_result.runtime_seconds, direct.runtime_seconds, ...
            counts.run_model_forecast, counts.estimator, counts.forecast, ...
            counts.iddata, counts.initialize_sirs_stepper, counts.advance_sirs_stepper, ...
            counts.rparse, counts.urdme, counts.genData_SIRS, ...
            string(passed));
    end

    text = text + newline + "## Expected Direct Profile Pattern" + newline + newline;
    text = text + "- The Part A 03 dispatch runs each window through `run_model_forecast`." + newline;
    text = text + "- None cases should have zero SIRS stepper, `rparse`, `urdme`, and `genData_SIRS` calls." + newline;
    text = text + "- I cases should initialize the SIRS stepper once, advance it once per horizon step, and keep `genData_SIRS` at zero." + newline;
    text = text + "- I cases should not call `forecast(...)` or construct `iddata` inside the closed-loop horizon loop when the d = 0 manual state-space path validates." + newline;
    text = text + "- `forecast(...)` may still appear for the initial state/uncertainty calculation and for None cases." + newline + newline;

    text = text + "## Static Checks" + newline + newline;
    text = text + sprintf("- AR/ARX files unchanged in git diff: %s.\n", ...
        string(results.search_validation.ar_arx_git_diff_empty));
    text = text + sprintf("- Part A 02 selection path unchanged in git diff: %s.\n", ...
        string(results.search_validation.partA02_git_diff_empty));
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
