function report = partB_verify_implementation()

%PARTB_VERIFY_IMPLEMENTATION Lightweight verification of the Part B implementation.
%
%   Syntax:
%       report = partB_verify_implementation()
%
%   Description:
%       Runs the real Part B stage scripts on a small sandbox fixture and
%       checks the scientific and numerical contracts of the implementation.
%       The production configuration and outputs are not touched: a renamed
%       copy of config/partB_config.m is placed in a temporary sandbox and
%       called through a wrapper with fixture = (T_end = 80, scenarios A2 and
%       A4, 2 stochastic replicates), so all Part B outputs are written to
%       the sandbox (16 datasets, 3 forecast origins each). Part A
%       configuration and selection artifacts resolve from the repository.
%
%       Correctness checks use exact equality (isequal) only when the same
%       compiled stepper variant receives the same inputs; otherwise the
%       stated tolerance applies. Estimator accuracy is reported as
%       diagnostics, not as pass/fail criteria.
%
%   Inputs:
%       None.
%
%   Outputs:
%       report - Structure with fields checks (table of correctness checks)
%                and diagnostics (table of estimator diagnostics). The
%                function errors after printing the report if any
%                correctness check fails.
%
%   See also PARTB_CONFIG, PARTB_01_PREPARE_DATASETS, PARTB_02_RUN_FORECASTS,
%            PARTB_03_EVALUATE_FORECASTS, PARTB_04_GENERATE_FIGURES.
%
% A. M. Kaahin 2026-11-18

%% 1. Sandbox Configuration
repo_root   = fileparts(fileparts(fileparts(mfilename('fullpath'))));
sandbox     = tempname;
sandbox_cfg = fullfile(sandbox, 'config');
mkdir(sandbox_cfg);

production_text = fileread(fullfile(repo_root, 'config', 'partB_config.m'));
production_text = regexprep(production_text, '^function cfg = partB_config\(fixture\)', 'function cfg = partB_config_production(fixture)', 'once');
local_write_text(fullfile(sandbox_cfg, 'partB_config_production.m'), production_text);
local_write_text(fullfile(sandbox_cfg, 'partB_config.m'), sprintf([ ...
    'function cfg = partB_config()\n' ...
    'cfg = partB_config_production(struct(''T_end'', 80, ''scenario_ids'', ["A2", "A4"], ''num_replicates'', 2));\n' ...
    'cfg.partB.visualization.trajectory_origin_day = 56;\n' ...
    'end\n']));

addpath(sandbox_cfg, '-begin');
path_cleanup = onCleanup(@() rmpath(sandbox_cfg));

cfg = partB_config();
pb  = cfg.partB;
H   = cfg.forecast.horizon;
N   = cfg.sirs.pop_size;
fprintf('Verification sandbox: %s\n', sandbox);

checks = table('Size', [0, 4], 'VariableTypes', {'string', 'string', 'logical', 'string'}, 'VariableNames', {'Id', 'Check', 'Passed', 'Detail'});

%% 2. Run Real Stages on the Fixture
local_run_stage(repo_root, 'partB_01_prepare_datasets');
local_run_stage(repo_root, 'partB_02_run_forecasts');
local_run_stage(repo_root, 'partB_03_evaluate_forecasts');
local_run_stage(repo_root, 'partB_04_generate_figures');

generation = load(fullfile(pb.output.data_dir, 'partB_01_generation_status.mat'));
saved      = generation.generation_status([generation.generation_status.status] == "saved");
datasets   = cell(numel(saved), 1);
forecasts  = cell(numel(saved), 1);
for i = 1:numel(saved)
    datasets{i}  = load(fullfile(pb.output.data_dir, saved(i).output_filename));
    forecasts{i} = load(fullfile(pb.output.forecast_dir, "partB_02_forecast_" + saved(i).dataset_id + ".mat"));
end
evaluation = load(fullfile(pb.output.evaluation_dir, 'partB_03_evaluation_results.mat'));
stepper    = sirs_init(cfg.sirs, struct('solver', 'uds', 'seed', cfg.run.seed), true);
clean      = datasets{find([saved.dataset_id] == "clean_baseline_A2_rep001", 1)};

%% 3. Exact-State Oracle
iT = find(clean.tspan == cfg.forecast.min_window);
X_true = [clean.S_true(iT); clean.I_true(iT); clean.R_removed_true(iT)];
projected = local_project(stepper, X_true, clean.Rt_true(iT:iT + H - 1));
shifted   = local_project(stepper, X_true, clean.Rt_true(iT + 1:iT + H));
shift_gap = max(abs(shifted(:, 2) - clean.I_true(iT + 1:iT + H)) ./ clean.I_true(iT + 1:iT + H));
checks = local_add(checks, "T1", "Exact-state oracle reproduces I_true; +1-shifted drivers do not", isequal(projected(:, 2), clean.I_true(iT + 1:iT + H)) && shift_gap > 1e-6, sprintf('exact match = %d, shifted max rel gap = %.3g', isequal(projected(:, 2), clean.I_true(iT + 1:iT + H)), shift_gap));

%% 4. Identical Estimated Initial State and Re-Projection
[same_state, same_projection, n_windows] = deal(true, true, 0);
for i = 1:numel(saved)
    ds = datasets{i};
    for w = 1:numel(forecasts{i}.windows)
        win = forecasts{i}.windows(w);
        if ~ds.state_valid_mask(win.window_day_idx)
            continue;
        end
        n_windows = n_windows + 1;
        same_state = same_state && isequal(win.X_hat_T, [ds.S_estimated(win.window_day_idx); ds.I_estimated(win.window_day_idx); ds.R_removed_estimated(win.window_day_idx)]);
        for m = find(win.status == "ok")'
            reprojected = local_project(stepper, win.X_hat_T, win.drivers(:, m));
            same_projection = same_projection && isequal(reprojected(:, 2), win.I_pred(:, m));
        end
    end
end
checks = local_add(checks, "T2", "All methods start from X_hat_T (= dataset estimate) and differ only by drivers", same_state && same_projection, sprintf('%d windows; state equal = %d; stored I_pred reproduced from X_hat_T and stored drivers = %d', n_windows, same_state, same_projection));

%% 5. ARX Closed-Loop State Consistency
[arx_consistent, n_arx] = deal(true, 0);
for i = 1:numel(saved)
    ds = datasets{i};
    for w = 1:numel(forecasts{i}.windows)
        win = forecasts{i}.windows(w);
        if win.status(3) ~= "ok"
            continue;
        end
        n_arx = n_arx + 1;
        k = win.window_day_idx - 1;
        replay = sirs_step(stepper, [ds.S_estimated(k); ds.I_estimated(k); ds.R_removed_estimated(k)], ds.Rt_estimated(k));
        arx_consistent = arx_consistent && isequal(replay, win.X_hat_T);
    end
end
checks = local_add(checks, "T3", "FORECAST_CLOSED replay of [T-1,T] equals X_hat_T exactly", arx_consistent && n_arx > 0, sprintf('%d ARX windows checked', n_arx));

%% 6. Causality of Historical Estimation
noisy = datasets{find([saved.case_id] == "combined_stress", 1)};
k_cut = 50;
causal = true;
for fixture = {clean, noisy}
    ds = fixture{1};
    truncated = estimate_sirs_history_from_incidence(ds.incidence_observed(1:k_cut), pb.estimation.initial_state, stepper, pb.estimation);
    causal = causal && isequal(truncated.I(1:k_cut), ds.I_estimated(1:k_cut)) && isequal(truncated.S(1:k_cut), ds.S_estimated(1:k_cut)) && isequaln(truncated.Rt(1:k_cut - 1), ds.Rt_estimated(1:k_cut - 1));
end
checks = local_add(checks, "T4", "Estimates through k depend only on observations through k", causal, sprintf('truncated at index %d (clean and combined-stress datasets)', k_cut));

%% 7. Future-Information Leakage
cut_idx = 61;
original_forecasts = forecasts;
for i = 1:numel(saved)
    perturbed = datasets{i};
    perturbed.Rt_true(cut_idx:end)        = 1.3 * perturbed.Rt_true(cut_idx:end);
    perturbed.I_true(cut_idx:end)         = 0.5 * perturbed.I_true(cut_idx:end);
    perturbed.S_true(cut_idx:end)         = perturbed.S_true(cut_idx:end) + 1000;
    perturbed.R_removed_true(cut_idx:end) = perturbed.R_removed_true(cut_idx:end) + 1000;
    save(fullfile(pb.output.data_dir, saved(i).output_filename), '-struct', 'perturbed');
end
local_run_stage(repo_root, 'partB_02_run_forecasts');

[no_leak, oracle_reacts] = deal(true, true);
for i = 1:numel(saved)
    after = load(fullfile(pb.output.forecast_dir, "partB_02_forecast_" + saved(i).dataset_id + ".mat"));
    for w = 1:numel(after.windows)
        a = after.windows(w);
        b = original_forecasts{i}.windows(w);
        no_leak = no_leak && isequaln(a.drivers(:, [1, 3]), b.drivers(:, [1, 3])) && isequaln(a.I_pred(:, [1, 3]), b.I_pred(:, [1, 3])) && isequal(a.status([1, 3]), b.status([1, 3]));
        touches_cut = a.window_day_idx + H - 1 >= cut_idx;
        if b.status(2) == "ok" && touches_cut
            oracle_reacts = oracle_reacts && ~isequal(a.drivers(:, 2), b.drivers(:, 2));
        end
    end
end
checks = local_add(checks, "T5", "Changing future truth leaves persistence and ARX unchanged; oracle reacts", no_leak && oracle_reacts, sprintf('future truth perturbed from index %d in all %d datasets', cut_idx, numel(saved)));

for i = 1:numel(saved)
    restored = datasets{i};
    save(fullfile(pb.output.data_dir, saved(i).output_filename), '-struct', 'restored');
end

%% 8. Reproducibility
local_run_stage(repo_root, 'partB_02_run_forecasts');
reproducible = true;
for i = 1:numel(saved)
    rerun = load(fullfile(pb.output.forecast_dir, "partB_02_forecast_" + saved(i).dataset_id + ".mat"));
    reproducible = reproducible && isequaln(rerun.windows, original_forecasts{i}.windows);
end
checks = local_add(checks, "T13", "Rerunning Stage 2 with identical inputs and seeds reproduces all forecasts", reproducible, sprintf('%d forecast artifacts compared with isequaln', numel(saved)));

%% 9. Persistence and Oracle Drivers
[persistence_ok, oracle_ok, oracle_uses_estimate] = deal(true, true, false);
for i = 1:numel(saved)
    ds = datasets{i};
    for w = 1:numel(forecasts{i}.windows)
        win = forecasts{i}.windows(w);
        iT = win.window_day_idx;
        if win.status(1) == "ok"
            expected_idx = find(ds.estimation_valid_mask(1:iT - 1), 1, 'last');
            persistence_ok = persistence_ok && win.persistence_source_idx == expected_idx && all(win.drivers(:, 1) == ds.Rt_estimated(expected_idx));
        end
        if win.status(2) == "ok"
            oracle_ok = oracle_ok && isequal(win.drivers(:, 2), ds.Rt_true(iT:iT + H - 1)) && isequal(win.truth_I, ds.I_true(iT + 1:iT + H));
            oracle_uses_estimate = oracle_uses_estimate || ~isequal(win.X_hat_T, [ds.S_true(iT); ds.I_true(iT); ds.R_removed_true(iT)]);
        end
    end
end
checks = local_add(checks, "T6", "Persistence holds the last valid estimate at or before iT-1", persistence_ok, "source index and constant drivers verified for every valid window");
checks = local_add(checks, "T7", "Oracle uses Rt_true(iT:iT+H-1) from the estimated (not true) state", oracle_ok && oracle_uses_estimate, sprintf('driver match = %d; estimated state differs from truth in at least one window = %d', oracle_ok, oracle_uses_estimate));

%% 10. Indexing and Minimum History
first = forecasts{find([saved.dataset_id] == "clean_baseline_A2_rep001", 1)}.windows(1);
available = first.window_day_idx - 1;
fit_length = first.arx_fit_range(2) - first.arx_fit_range(1) + 1;
k_range = (2:numel(clean.Rt_true) - 2)';
aligned = max(abs(clean.Rt_estimated(k_range) - clean.Rt_true(k_range)));
lagged  = min(max(abs(clean.Rt_estimated(k_range) - clean.Rt_true(k_range - 1))), max(abs(clean.Rt_estimated(k_range) - clean.Rt_true(k_range + 1))));
checks = local_add(checks, "T8", "First origin has 49 available estimates, so min_history = 49 is met (ARX attempted, any failure recorded); Rt_hat(k) aligns with Rt_true(k)", ...
    available == 49 && fit_length == 49 && first.status(3) ~= "insufficient_history" && first.status(3) ~= "estimation_unavailable" && aligned < lagged, sprintf('available = %d, ARX fit length = %d, ARX status = %s; max|Rt_hat(k)-Rt(k)| = %.3g vs min shifted error = %.3g', available, fit_length, first.status(3), aligned, lagged));

%% 11. Zero-Incidence Reconstruction Convention
y_zero = clean.incidence_observed;
zero_days = (31:35)';
y_zero(zero_days) = 0;
zero_est = estimate_sirs_history_from_incidence(y_zero, pb.estimation.initial_state, stepper, pb.estimation);
closed_form_error = 0;
for k = (zero_days - 1)'
    I_expected = zero_est.I(k) * exp(-cfg.sirs.gamma);
    R_expected = zero_est.R_removed(k) * exp(-cfg.sirs.xi) + cfg.sirs.gamma * zero_est.I(k) * (exp(-cfg.sirs.xi) - exp(-cfg.sirs.gamma)) / (cfg.sirs.gamma - cfg.sirs.xi);
    closed_form_error = max([closed_form_error, abs(zero_est.I(k + 1) - I_expected) / I_expected, abs(zero_est.R_removed(k + 1) - R_expected) / R_expected]);
end
zero_ok = all(zero_est.reason(zero_days - 1) == "unidentifiable_zero_incidence") && all(isnan(zero_est.Rt(zero_days - 1))) && closed_form_error <= 1e-12 ...
    && all(zero_est.state_valid_mask) && isnan(zero_est.failure_idx) && zero_est.reason(zero_days(end)) == "estimated" && isequal(zero_est.I(1:zero_days(1) - 1), clean.I_estimated(1:zero_days(1) - 1));
checks = local_add(checks, "T9", "Zero incidence: Rt unidentifiable (NaN), state continues by the zero-flux closed form", zero_ok, sprintf('max closed-form relative error = %.3g; estimation resumes after zeros = %d', closed_form_error, zero_est.reason(zero_days(end)) == "estimated"));

%% 12. Inversion Acceptance, Fallback, and Recorded Failure
residual_ok = true;
for i = 1:numel(saved)
    ds = datasets{i};
    accepted = ds.estimation_reason == "estimated";
    idx = find(accepted);
    tolerance = max(pb.estimation.rel_tol * ds.incidence_observed(idx + 1), pb.estimation.abs_tol);
    residual_ok = residual_ok && all(abs(ds.estimation_diagnostics.residual(idx)) <= tolerance);
end

fallback_settings = pb.estimation;
fallback_settings.max_fixed_point_iterations = 1;
fallback_est = estimate_sirs_history_from_incidence(clean.incidence_observed, pb.estimation.initial_state, stepper, fallback_settings);
fallback_ok = any(fallback_est.inversion_method == "bracketed_fzero") && isnan(fallback_est.failure_idx) && all(fallback_est.rt_valid_mask(1:end - 1));

impossible_settings = fallback_settings;
impossible_settings.max_bracket_expansions = 3;
reference_est = estimate_sirs_history_from_incidence(clean.incidence_observed, pb.estimation.initial_state, stepper, impossible_settings);
y_bad = clean.incidence_observed;
y_bad(41) = 1000 * y_bad(41);
failure_est = estimate_sirs_history_from_incidence(y_bad, pb.estimation.initial_state, stepper, impossible_settings);
failure_ok = failure_est.failure_idx == 40 && failure_est.reason(40) == "inversion_failure" && all(isnan(failure_est.I(41:end))) && all(isnan(failure_est.Rt(40:end))) && isequal(failure_est.I(1:40), reference_est.I(1:40)) && isequaln(failure_est.Rt(1:39), reference_est.Rt(1:39));
checks = local_add(checks, "T10", "Accepted days meet the residual criterion; FZERO fallback works; failures are recorded with earlier estimates kept", residual_ok && fallback_ok && failure_ok, sprintf('residual criterion = %d; fallback days = %d; failure index = %g (%s)', residual_ok, sum(fallback_est.inversion_method == "bracketed_fzero"), failure_est.failure_idx, failure_est.failure_id));

%% 13. Scoring
hand = compute_point_error([1; 2; 3], [2; 2; 5]);
hand_ok = hand.mae == 1 && abs(hand.rmse - sqrt(5 / 3)) <= 1e-15 && isequal(hand.error, [1; 0; 2]);

ws = evaluation.window_scores;
recomputed_ok = true;
for i = 1:numel(saved)
    for w = 1:numel(forecasts{i}.windows)
        win = forecasts{i}.windows(w);
        for m = find(win.status == "ok")'
            row = ws(ws.Case == saved(i).case_id & ws.Scenario == saved(i).scenario_id & ws.Replicate == saved(i).replicate_id & ws.WindowDay == win.window_day & ws.Method == pb.method_ids(m), :);
            e = win.I_pred(:, m) - win.truth_I;
            recomputed_ok = recomputed_ok && height(row) == 1 && abs(row.MAE - mean(abs(e))) <= 1e-9 * max(1, row.MAE) && abs(row.RMSE - sqrt(mean(e.^2))) <= 1e-9 * max(1, row.RMSE);
        end
    end
end

matched = ws(ws.Matched, :);
condition_ok = true;
for c = 1:numel(pb.robustness_cases)
    case_id = pb.robustness_cases(c).case_id;
    scen_mae = NaN(numel(cfg.scenarios), 3);
    for s = 1:numel(cfg.scenarios)
        for m = 1:3
            rows = matched(matched.Case == case_id & matched.Scenario == cfg.scenarios(s).id & matched.Method == pb.method_ids(m), :);
            reps = unique(rows.Replicate);
            rep_mae = arrayfun(@(r) mean(rows.MAE(rows.Replicate == r)), reps);
            scen_mae(s, m) = mean(rep_mae);
        end
    end
    for m = 1:3
        row = evaluation.summaries.condition_summary(evaluation.summaries.condition_summary.Case == case_id & evaluation.summaries.condition_summary.Method == pb.method_ids(m), :);
        expected = mean(scen_mae(:, m));
        condition_ok = condition_ok && ((~row.Complete && isnan(row.MAE)) || abs(row.MAE - expected) <= 1e-9 * max(1, expected));
    end
    paired = evaluation.summaries.paired_condition_summary(evaluation.summaries.paired_condition_summary.Case == case_id, :);
    if paired.Complete
        condition_ok = condition_ok && abs(paired.DeltaMAE - mean(scen_mae(:, 1) - scen_mae(:, 3))) <= 1e-9 * max(1, abs(paired.DeltaMAE));
    end
end
checks = local_add(checks, "T11", "MAE/RMSE, hierarchy aggregation, and paired DeltaMAE match independent recomputation", hand_ok && recomputed_ok && condition_ok, sprintf('hand example = %d; window metrics = %d; condition MAE and DeltaMAE = %d', hand_ok, recomputed_ok, condition_ok));

%% 14. Artifact Compatibility
compat = true;
details = strings(0, 1);
status_path = fullfile(pb.output.forecast_dir, 'partB_02_forecast_status.mat');
status_original = load(status_path);

dataset_path = fullfile(pb.output.data_dir, saved(1).output_filename);
tampered = datasets{1};
tampered.snapshot.truth_seed = -1;
save(dataset_path, '-struct', 'tampered');
[ok, id] = local_expect_error(repo_root, 'partB_02_run_forecasts', 'PARTB_02:IncompatibleArtifact');
compat = compat && ok; details(end + 1) = "dataset snapshot -> " + id;
restored = datasets{1};
save(dataset_path, '-struct', 'restored');
save(status_path, '-struct', 'status_original');

status_tampered = status_original;
status_tampered.snapshot.estimation.rel_tol = 1;
save(status_path, '-struct', 'status_tampered');
[ok, id] = local_expect_error(repo_root, 'partB_03_evaluate_forecasts', 'PARTB_03:IncompatibleArtifact');
compat = compat && ok; details(end + 1) = "forecast-status snapshot -> " + id;
save(status_path, '-struct', 'status_original');

evaluation_path = fullfile(pb.output.evaluation_dir, 'partB_03_evaluation_results.mat');
evaluation_tampered = evaluation;
evaluation_tampered.snapshot.method_ids = "tampered";
save(evaluation_path, '-struct', 'evaluation_tampered');
[ok, id] = local_expect_error(repo_root, 'partB_04_generate_figures', 'PARTB_04:IncompatibleArtifact');
compat = compat && ok; details(end + 1) = "evaluation snapshot -> " + id;
save(evaluation_path, '-struct', 'evaluation');

checks = local_add(checks, "T12", "Artifacts from a different configuration snapshot are rejected by every consuming stage", compat, strjoin(details, '; '));

%% 15. Part A and Part C Integrity
protected = 'config/partA_config.m scripts/partA data/partA results/partA config/partC_config.m scripts/partC data/partC results/partC';
[diff_status, ~] = system(sprintf('git -C "%s" diff --quiet HEAD -- %s', repo_root, protected));
[~, untracked] = system(sprintf('git -C "%s" status --porcelain -- %s', repo_root, protected));

max_default_gap = 0;
max_counter_gap = 0;
default_stepper = sirs_init(cfg.sirs, struct('solver', 'uds', 'seed', 1234));
for scenario_id = ["A1", "A2", "A3", "A4"]
    truth = load(fullfile(repo_root, 'data', 'partA', "partA_01_truth_" + scenario_id + ".mat"));
    U = [truth.S_true(1); truth.I_true(1); N - truth.S_true(1) - truth.I_true(1)];
    V = U;
    for k = 1:(numel(truth.Rt_true) - 1)
        U = sirs_step(default_stepper, U, truth.Rt_true(k));
        V = sirs_step(stepper, V, truth.Rt_true(k));
        max_default_gap = max(max_default_gap, max(abs(U(1:2) - [truth.S_true(k + 1); truth.I_true(k + 1)]) ./ [truth.S_true(k + 1); truth.I_true(k + 1)]));
        max_counter_gap = max(max_counter_gap, max(abs(V(1:2) - [truth.S_true(k + 1); truth.I_true(k + 1)]) ./ [truth.S_true(k + 1); truth.I_true(k + 1)]));
    end
end
integrity_ok = diff_status == 0 && strlength(strtrim(string(untracked))) == 0 && max_default_gap <= 1e-9 && max_counter_gap <= 1e-4;
checks = local_add(checks, "T14", "Part A/C paths unchanged; default stepper regenerates Part A truth; counter variant agrees within RelTol", integrity_ok, sprintf('git diff clean = %d, untracked/modified = "%s", default max rel gap = %.3g (tol 1e-9), counter max rel gap = %.3g (tol 1e-4)', diff_status == 0, strtrim(string(untracked)), max_default_gap, max_counter_gap));

%% 16. Estimator Diagnostics
diagnostics = table('Size', [numel(saved), 9], 'VariableTypes', {'string', 'string', 'string', 'double', 'double', 'double', 'double', 'double', 'double'}, ...
    'VariableNames', {'Case', 'Scenario', 'Replicate', 'MaxRelErrorI', 'MeanRelErrorI', 'MaxAbsErrorRt', 'ZeroIncidenceDays', 'FzeroDays', 'FailureIdx'});
for i = 1:numel(saved)
    ds = datasets{i};
    valid = ds.state_valid_mask;
    rel_I = abs(ds.I_estimated(valid) - ds.I_true(valid)) ./ ds.I_true(valid);
    rt_valid = ds.estimation_valid_mask;
    diagnostics(i, :) = {saved(i).case_id, saved(i).scenario_id, saved(i).replicate_id, max(rel_I), mean(rel_I), max(abs(ds.Rt_estimated(rt_valid) - ds.Rt_true(rt_valid))), sum(ds.estimation_reason == "unidentifiable_zero_incidence"), sum(ds.estimation_diagnostics.method == "bracketed_fzero"), ds.estimation_failure_idx};
end

%% 17. Report
report = struct('checks', checks, 'diagnostics', diagnostics, 'support', evaluation.summaries.support_condition, 'sandbox', string(sandbox));

fprintf('\n=== Part B Verification: Correctness Checks ===\n');
for i = 1:height(checks)
    verdict = "PASS";
    if ~checks.Passed(i)
        verdict = "FAIL";
    end
    fprintf('[%s] %-4s %s\n        %s\n', verdict, checks.Id(i), checks.Check(i), checks.Detail(i));
end

fprintf('\n=== Part B Verification: Estimator Diagnostics (not pass/fail) ===\n');
disp(diagnostics);
fprintf('=== Part B Verification: Window Support by Condition and Method ===\n');
disp(evaluation.summaries.support_condition);

if ~all(checks.Passed)
    error('PARTB_VERIFY:Failed', '%d of %d correctness checks failed.', sum(~checks.Passed), height(checks));
end

clear path_cleanup;
rmdir(sandbox, 's');
fprintf('All %d correctness checks passed. Sandbox removed.\n', height(checks));
end

%% 18. Local Functions
function local_run_stage(repo_root, script_name)
%LOCAL_RUN_STAGE Run one real Part B stage script in an isolated workspace.
run(fullfile(repo_root, 'scripts', 'partB', [script_name '.m']));
end

function [ok, error_id] = local_expect_error(repo_root, script_name, expected_id)
%LOCAL_EXPECT_ERROR Run a stage and require that it fails with the expected identifier.
try
    local_run_stage(repo_root, script_name);
    ok = false;
    error_id = "no error";
catch ME
    error_id = string(ME.identifier);
    ok = error_id == expected_id;
end
end

function projected = local_project(stepper, initial_state, drivers)
%LOCAL_PROJECT Propagate a SIRS state along an H-by-1 driver sequence.
projected = zeros(numel(drivers), 3);
state = initial_state;
for h = 1:numel(drivers)
    state = sirs_step(stepper, state, drivers(h));
    projected(h, :) = state.';
end
end

function checks = local_add(checks, id, description, passed, detail)
%LOCAL_ADD Append one correctness check.
checks = [checks; {string(id), string(description), logical(passed), string(detail)}];
end

function local_write_text(path, text)
%LOCAL_WRITE_TEXT Write text to a file.
fid = fopen(path, 'w');
fprintf(fid, '%s', text);
fclose(fid);
end
