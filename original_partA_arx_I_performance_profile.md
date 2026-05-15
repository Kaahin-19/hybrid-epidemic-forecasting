# Original Part A ARX-I Performance Profile

Profiling date/time: 2026-05-15 11:03:44-11:17:58 Europe/Stockholm

## Command Profiled

```bash
/usr/bin/time -p ./run_partA_pipeline.sh --models 2 --exo 2 --fresh
```

This is the original Part A pipeline, ARX model with exogenous mode `I`. The run used the current closed-loop exogenous generation in `fit_arimax.m`; SIRS advancement remained URDME/UDS-based through `genData_SIRS.m`.

## Environment Summary

- Repository: `/home/kaahin/degree_project/hybrid-epidemic-forecasting`
- Git commit: `1e7d26f`
- OS: Linux WSL2, kernel `6.6.114.1-microsoft-standard-WSL2`, x86_64
- CPU availability: `nproc = 24`
- Memory: 30 GiB total, 29 GiB available during inspection
- Disk: 1007 GiB filesystem, 907 GiB available
- MATLAB binary: `/home/kaahin/MATLAB/R2025b/bin/matlab`
- MATLAB version: `25.2.0.3177638 (R2025b) Update 5`
- MATLAB root: `/home/kaahin/MATLAB/R2025b`
- System Identification Toolbox: `25.2`
- Parallel Computing Toolbox: `25.2`

Relevant current configuration:

- `cfg.forecast.min_window = 49`
- `cfg.forecast.step_size = 7`
- `cfg.forecast.horizon = 14`
- `cfg.forecast.wis_alphas = [0.05, 0.10, 0.20, 0.50]`
- `cfg.forecast.max_ar_order = 2`
- `cfg.forecast.max_exo_order = 1`
- `cfg.forecast.max_exo_delay = 2`
- SIRS population `100000`, `gamma = 1/7`, `xi = 1/90`, seed `1234`

ARX tiny-grid confirmation:

- Candidate grid in `scripts/partA_02_select_global_hyperparameters.m` uses:
  - `na = 1:cfg.forecast.max_ar_order`
  - `nb = 1:cfg.forecast.max_exo_order`
  - `nk = 1:cfg.forecast.max_exo_delay`
- Current ARX-I grid has 4 candidates: `[1 1 1]`, `[2 1 1]`, `[1 1 2]`, `[2 1 2]`.
- ARX starts at `na = 1`; `na = 0` is not included in the original Part A tuning grid currently executed.
- `partA_02_select_global_hyperparameters.m` starts `parpool('Processes', 4)`, confirmed both in code and logs.

## Runtime Summary

Top-level `/usr/bin/time -p` result:

| Metric | Seconds |
|---|---:|
| real | 515.98 |
| user | 2055.74 |
| sys | 67.67 |

The user/wall ratio is about 3.98x, consistent with the 4-worker process pool during tuning.

Per-stage runtime from `results/logs/20260515_110344/manifest.tsv`:

| Stage | Runtime | Share of total wall |
|---|---:|---:|
| Scenario generation | 11 s | 2.1% |
| Synthetic ground truth | 46 s | 8.9% |
| ARX-I hyperparameter tuning | 288 s | 55.8% |
| ARX-I forecast execution | 159 s | 30.8% |
| WIS evaluation | 12 s | 2.3% |
| Total | 516 s | 100.0% |

Candidate evaluation timing:

- Tuning evaluated 4 candidates across 4 scenarios and 44 windows per scenario.
- Total candidate-window fits in tuning: `4 * 4 * 44 = 704`.
- Closed-loop horizon steps in tuning: `704 * 14 = 9856`.
- Candidate progress from `ARX_I_tuning.log`:
  - 1/4 complete at 256.8 s
  - 2/4 complete at 256.9 s
  - 3/4 complete at 262.5 s
  - 4/4 complete at 266.9 s
- Candidate evaluation consumed 266.9 s of the 288 s tuning stage.
- Non-candidate tuning overhead, including MATLAB startup, data preparation, pool startup/shutdown, and artifact writing, was about 21.1 s.

Forecast/evaluation timing:

- Final forecast stage evaluated the selected candidate for 4 scenarios and 44 windows per scenario: `176` forecast windows.
- Final forecast closed-loop horizon steps: `176 * 14 = 2464`.
- Forecast summaries confirm `Times_Selected = 44` for each scenario.
- Evaluation aggregated 176 forecast windows and 2464 pointwise WIS rows.
- In-process targeted timing measured WIS evaluation without plotting at 0.454 s; most of the 12 s production evaluation stage is MATLAB startup plus plot export.

## Generated Result Summaries

Tuning summary from `results/tuning/partA_02_global_hyperparameters_ARX_I_summary.csv`:

| Rank | na | nb | nk | A1 Mean WIS | A2 Mean WIS | A3 Mean WIS | A4 Mean WIS | Global Mean WIS |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2 | 1 | 2 | 0.008998 | 0.034906 | 0.057370 | 0.044419 | 0.036423 |
| 2 | 2 | 1 | 1 | 0.010234 | 0.039634 | 0.053622 | 0.046436 | 0.037481 |
| 3 | 1 | 1 | 1 | 0.046553 | 0.028030 | 0.143451 | 0.134289 | 0.088081 |
| 4 | 1 | 1 | 2 | 0.048191 | 0.027976 | 0.142030 | 0.134973 | 0.088292 |

The selected candidate was `[2 1 2]`. Candidate selection is not obviously suspicious: all candidates produced finite scores, and the selected candidate is best globally. The top two candidates are close, however: rank 1 beats rank 2 by about `0.00106` absolute global mean WIS, or roughly `2.9%` relative to the selected score. Rank 2 is better on A3, while rank 1 is better on A1, A2, and A4. If this result becomes a thesis-critical claim, repeat the run once to confirm stability under the same seed and environment.

WIS summary from `results/scores/partA_04_wis_performance_summary.csv`:

| Scenario | Model | Exo | Windows | Mean WIS | Median WIS | Std WIS | Min WIS | Max WIS | Acceptable |
|---|---|---|---:|---:|---:|---:|---:|---:|---|
| A1 | ARX | I | 44 | 0.007124 | 0.002622 | 0.026088 | 0.000106 | 0.175475 | true |
| A2 | ARX | I | 44 | 0.036664 | 0.014397 | 0.086082 | 0.000000 | 0.502846 | true |
| A3 | ARX | I | 44 | 0.045080 | 0.042068 | 0.031857 | 0.005231 | 0.148765 | true |
| A4 | ARX | I | 44 | 0.042132 | 0.037884 | 0.033388 | 0.001659 | 0.146263 | true |

## Profiling Evidence

Logs inspected:

- `results/logs/20260515_110344/pipeline.log`
- `results/logs/20260515_110344/manifest.tsv`
- `results/logs/20260515_110344/partA_00_make_scenarios.log`
- `results/logs/20260515_110344/partA_01_generate_truth.log`
- `results/logs/20260515_110344/ARX_I_tuning.log`
- `results/logs/20260515_110344/ARX_I_forecast.log`
- `results/logs/20260515_110344/partA_04_evaluate_models.log`

Artifacts inspected:

- `results/tuning/partA_02_global_hyperparameters_ARX_I_summary.csv`
- `results/tuning/partA_02_global_hyperparameters_ARX_I.mat`
- `results/forecasts/partA_03_forecast_A*_ARX_I_summary.csv`
- `results/forecasts/partA_03_forecast_A*_ARX_I.mat`
- `results/scores/partA_04_wis_performance_summary.csv`
- `results/scores/partA_04_wis_pointwise_details.csv`

Temporary profiling helper created:

- `scripts/profiling/profile_original_partA_arx_I_inner_loop.m`

Profiling outputs created:

- `results/profiling/original_partA_arx_I_fit_arimax_timing.csv`
- `results/profiling/original_partA_arx_I_component_timing.csv`
- `results/profiling/original_partA_arx_I_component_summary.csv`
- `results/profiling/original_partA_arx_I_matlab_profile_top.csv`
- `results/profiling/original_partA_arx_I_plot_eval_timing.csv`
- `results/profiling/figures/*.png`

The helper does not change normal Part A pipeline behavior. It calls the same `fit_arimax` and `genData_SIRS` paths and writes only under `results/profiling`.

Warnings/errors observed:

- No MATLAB errors or failed stages were found in the fresh run logs.
- `ARX_I_tuning.log` contains 44 warnings with message: `Will not overwrite existing file if not created by RPARSE.`
- The warning stack points through:
  - `third_party/urdme/urdme/msrc/utils/rparse.m`
  - `src/models/genData_SIRS.m`, line 155 (`rparse`)
  - `src/models/genData_SIRS.m`, line 88 (per-interval simulation)
  - `src/models/fit_arimax.m`, line 274 (`genData_SIRS([0, 1], ...)`)
  - `src/models/fit_arimax.m`, line 235 (closed-loop horizon advancement)
  - `scripts/partA_02_select_global_hyperparameters.m`, line 318
- The forecast log did not show the same warning messages.

Targeted component timing on 12 representative windows:

| Component | Total Seconds | Mean / Window | Mean / Horizon Step | Share of Accounted Component Time |
|---|---:|---:|---:|---:|
| `fit_arimax` end-to-end | 12.745 | 1.062 | n/a | n/a |
| Fit `iddata(...)` | 0.0086 | 0.0007 | n/a | 0.08% |
| `arx(...)` fit | 0.426 | 0.0355 | n/a | 3.97% |
| `forecastOptions(...)` | 0.0068 | 0.0006 | n/a | 0.06% |
| Prediction-loop `iddata(...)` | 0.102 | 0.0085 | 0.00061 | 0.95% |
| One-step `forecast(...)` | 6.004 | 0.500 | 0.0357 | 55.9% |
| One-day `genData_SIRS` / UDS | 4.197 | 0.350 | 0.0250 | 39.1% |
| Closed-loop total | 10.321 | 0.860 | 0.0614 | 96.1% |

Notes:

- One early A2 window returned through the persistence fallback in 0.0009 s, because the historical signal is nearly constant. That lowers the representative mean.
- Excluding that fallback window, the measured `fit_arimax` mean was about 1.159 s per profiled window.
- User-level `iddata(...)` construction is measurable but not a primary bottleneck. The expensive data/model conversion appears inside System Identification `forecast(...)`.

MATLAB profiler top functions for two profiled `fit_arimax` calls:

| Function | Calls | Total Seconds |
|---|---:|---:|
| `fit_arimax` | 2 | 3.253 |
| `fit_arimax>local_closed_loop_forecast` | 2 | 2.647 |
| `idmodel.forecast` | 28 | 1.764 |
| `idParametric.forecast_` | 28 | 1.412 |
| `polydata.forecast` | 28 | 1.220 |
| `ltidata.forecast` | 28 | 1.219 |
| `ltidata.data2state` | 28 | 0.914 |
| `fit_arimax>local_advance_sirs_one_day` | 28 | 0.848 |
| `genData_SIRS` | 28 | 0.846 |
| `genData_SIRS>local_simulate_beta_interval` | 28 | 0.832 |
| `arx` | 2 | 0.549 |

Plot/evaluation helper timing:

| Operation | Seconds |
|---|---:|
| 4 forecast plots total | 12.218 |
| Mean per forecast plot | 3.054 |
| In-memory WIS evaluation without plots | 0.454 |
| Performance boxplot | 2.664 |

Artifact sizes after the fresh run:

| Directory | Size |
|---|---:|
| `results/forecasts` | 224K |
| `results/figures` | 564K |
| `results/scores` | 184K |
| `results/tuning` | 12K |
| `results/logs/20260515_110344` | 176K |

These sizes are small; filesystem I/O is not the main bottleneck.

## Bottleneck Analysis

### CPU-Heavy Sections

The dominant work is inside `fit_arimax.m`, specifically the closed-loop forecast loop. Tuning calls it 704 times, and final forecast execution calls it 176 more times. Every non-fallback call performs a 14-step recursive closed-loop forecast.

Across tuning and final forecast execution, the original ARX-I run performs up to:

- 880 ARX model fits.
- 12320 one-step System Identification `forecast(...)` calls.
- 12320 one-day `genData_SIRS([0, 1], ...)` UDS advancements.

This repeated inner-loop structure explains why tuning and forecasting account for about 86.6% of total wall time.

### System Identification Toolbox Costs

`forecast(...)` is the largest measured inner-loop component. The helper measured 0.0357 s per one-step call, 55.9% of accounted component time. The MATLAB profiler shows repeated work under `idmodel.forecast`, `idParametric.forecast_`, `polydata.forecast`, `ltidata.forecast`, and `ltidata.data2state`.

The cost is not just the explicit `iddata(...)` call in `fit_arimax.m`. User-level `iddata(...)` construction was below 1.1% of accounted component time. The high-level `forecast(...)` machinery repeatedly converts the ARX polynomial model, estimates/reconstructs state from the full rolling history, and computes uncertainty for one horizon step.

`forecastOptions('InitialCondition','e')` is created once per `fit_arimax` call, not once per horizon step. It measured only 0.00056 s per profiled window, so caching it would be safe but low impact.

`arx(...)` fitting is visible but secondary. The helper measured 0.0355 s per representative window after warm-up, while the profiler saw 0.549 s over two cold-ish calls. ARX fit cost matters because it is repeated 880 times, but the closed-loop one-step forecasting dominates.

### URDME/UDS Costs

`fit_arimax>local_advance_sirs_one_day` calls `genData_SIRS([0, 1], ...)` once per forecast horizon step. The helper measured 0.0250 s per UDS one-day step, 39.1% of accounted component time. The profiler showed `genData_SIRS` and `genData_SIRS>local_simulate_beta_interval` immediately below System Identification forecast calls.

`genData_SIRS.m` calls `rparse(...)` every simulated interval, even when `compile = 0`. The RPARSE warnings in tuning confirm repeated parsing/setup activity. The current implementation avoids unnecessary compilation when generated UDS artifacts are available, but it still repeatedly parses and repackages the same SIRS reaction system.

The mechanistic SIRS advancement should remain URDME/UDS-based. The optimization target is therefore reuse of URDME/UDS model setup and parsed model state, not replacement with a hand-written deterministic SIRS solver.

### I/O and Plotting Costs

Filesystem output is small and not a major bottleneck. The larger cost is MATLAB figure creation and `exportgraphics`.

Measured plotting costs:

- 4 forecast plots: 12.2 s total.
- Evaluation boxplot: 2.7 s.
- Scenario generation stage took 11 s and includes figure generation plus MATLAB startup.

Plotting is not the main runtime driver, but making plot generation optional could save about 15-25 s in this ARX-I-only run, depending on MATLAB startup/session structure.

### Memory, Reallocation, and Data Conversion

No memory pressure was observed. Available memory was about 29 GiB, and result artifacts were under 1 MiB for the production ARX-I run outputs.

The largest data-conversion cost is internal to System Identification forecasting, not plain MATLAB array allocation. The profiler points to `ltidata.data2state`, `ltidata.convertToIDSS`, `polydata.ss`, and related functions. Rolling arrays in `fit_arimax.m` are preallocated, so simple reallocation is not the dominant issue.

### Parallel Overhead

The 4-worker `parfor` over candidates is useful for the current 4-candidate grid: all candidates started in one wave and completed around 257-267 s. However, the grid is so small that 4 workers is the natural ceiling. A 12-worker pool would not improve this candidate-level `parfor`, because only 4 candidate iterations exist; 8 workers would be idle while increasing startup and resource contention risk.

The 4-worker choice is appropriate compared with a 12-worker pool for this exact tiny grid. To use more than 4 workers effectively, the parallel decomposition would need to change, for example parallelizing candidate-scenario-window tasks or the final forecast windows.

## Stage 1 — Low-Impact Changes

### 1. Add an optional plotting switch

- Bottleneck: Forecast and evaluation plotting cost about 14.9 s measured; scenario plotting also contributes to the 11 s scenario stage.
- Why expensive: MATLAB figure creation and `exportgraphics(..., 'Resolution', 300)` are slow relative to WIS evaluation and file writes.
- Recommended change: Add a config flag such as `cfg.run.make_plots = true` and skip `plot_rt_forecast_comparison`, `plot_model_performance`, and scenario plot export when false. Preserve current behavior by default.
- Files/functions: `config/partA_config.m`, `scripts/partA_00_make_scenarios.m`, `scripts/partA_03_run_forecasts.m`, `scripts/partA_04_evaluate_models.m`, `src/plots/*`.
- Difficulty: Low.
- Estimated improvement: 3-5% for this ARX-I run, about 15-25 s. Larger if many model/exo combinations are run.
- Tradeoffs/risks: Plot artifacts may be missing for runs where the flag is disabled. This is safe if numeric artifacts remain unchanged and the default stays enabled.

### 2. Reuse or persist `forecastOptions`

- Bottleneck: `forecastOptions('InitialCondition','e')` is repeated once per `fit_arimax` call.
- Why expensive: It creates an options object 880 times in this run, but measured cost is tiny.
- Recommended change: Use a small persistent helper or pass a prebuilt option object into `fit_arimax` if the API remains clean.
- Files/functions: `src/models/fit_arimax.m`; possibly `fit_n4sid.m` and `fit_ssest.m` for consistency.
- Difficulty: Low.
- Estimated improvement: Less than 1%.
- Tradeoffs/risks: Minimal, but the measured benefit is too small to prioritize unless touching this code anyway.

### 3. Suppress or resolve repeated RPARSE warnings

- Bottleneck: 44 RPARSE warnings were emitted in tuning, with full stack traces in the log.
- Why expensive: Warning I/O is not the main cost, but it adds log noise and can mask real warnings.
- Recommended change: Identify the exact warning identifier in `rparse.m` and suppress it narrowly for known-safe generated-file reuse, or fix the build directory state so RPARSE recognizes its own generated files.
- Files/functions: `src/models/genData_SIRS.m`, `third_party/urdme/.../rparse.m` usage, `build/urdme`.
- Difficulty: Low to medium.
- Estimated improvement: Less than 1% wall time, but improves diagnostics.
- Tradeoffs/risks: Do not blanket-suppress all URDME warnings in production; only suppress a known benign warning after confirming generated executables are valid.

### 4. Preserve and expand focused profiling helpers

- Bottleneck: Current logs give stage timing but not inner-loop timing.
- Why expensive: Without lightweight profiling, optimization work can target low-impact code such as explicit `iddata(...)` construction while missing high-level `forecast(...)` and UDS setup costs.
- Recommended change: Keep `scripts/profiling/profile_original_partA_arx_I_inner_loop.m` or a cleaned variant as a non-production diagnostic. Add command-line documentation and keep outputs under `results/profiling`.
- Files/functions: `scripts/profiling/profile_original_partA_arx_I_inner_loop.m`.
- Difficulty: Low.
- Estimated improvement: No direct runtime improvement; reduces risk of wasted optimization effort.
- Tradeoffs/risks: Must remain separate from production scripts and should not become a hidden dependency.

## Stage 2 — Medium-Impact Changes

### 1. Reuse URDME/UDS model setup for one-day SIRS advancement

- Bottleneck: `genData_SIRS([0, 1], ...)` is called once per closed-loop horizon step and repeatedly calls `rparse(...)`.
- Why expensive: The SIRS reaction network, species, rates, solver choice, and generated UDS entry points are unchanged across steps; only initial state and beta/Rt driver change.
- Recommended change: Add a URDME/UDS stepper helper that initializes/parses the SIRS model once per MATLAB process or worker, then updates `u0`, `gdata`, `ldata_time`, `data_time`, and seed for each one-day advancement before calling `urdme`. Keep the numerical advancement in URDME/UDS.
- Files/functions: `src/models/genData_SIRS.m`, new helper such as `src/models/create_sirs_uds_stepper.m`, `src/models/fit_arimax.m`, and equivalent closed-loop paths in `fit_n4sid.m`/`fit_ssest.m`.
- Difficulty: Medium.
- Estimated improvement: SIRS is about 39% of accounted inner-loop time. A 2x SIRS-step speedup could reduce total pipeline wall time by roughly 10-20%; a stronger setup-reuse speedup could approach 20-30%.
- Tradeoffs/risks: Must validate bitwise or tolerance-level equivalence for S/I/R trajectories, beta metadata, seeding behavior, and warning behavior. Care is needed with parallel workers because each process needs its own reusable model state.

### 2. Avoid repeated full-history state reconstruction in one-step `forecast(...)`

- Bottleneck: Each horizon step rebuilds an `iddata` object over the full rolling history and calls high-level `forecast(sys, data_step, 1, ...)`.
- Why expensive: The profiler shows repeated `ltidata.data2state`, model conversion, and forecast machinery for every horizon day.
- Recommended change: Investigate a System Identification API path that can update or reuse estimated initial conditions across the closed-loop horizon. If available, carry forward the forecast state instead of recalculating from full history each step.
- Files/functions: `src/models/fit_arimax.m`, especially `local_closed_loop_forecast` and `local_build_forecast_data`.
- Difficulty: Medium to high, depending on System Identification API support.
- Estimated improvement: One-step `forecast(...)` is about 56% of accounted inner-loop time. A 2x reduction in this component could reduce total pipeline wall time by roughly 15-30%.
- Tradeoffs/risks: Predictive intervals and initial-condition handling must match the current `forecastOptions('InitialCondition','e')` behavior. This needs equivalence tests over all scenarios and several windows.

### 3. Parallelize final forecast execution

- Bottleneck: `partA_03_run_forecasts.m` runs scenarios and windows serially; it took 159 s.
- Why expensive: The selected candidate is refit independently for every scenario/window. These windows are independent after loading truth and selected hyperparameters.
- Recommended change: Use a controlled `parfor` over scenarios or over flattened scenario-window tasks, collect results in memory, then write each scenario artifact and plot serially.
- Files/functions: `scripts/partA_03_run_forecasts.m`.
- Difficulty: Medium.
- Estimated improvement: With 4 workers, forecast stage could plausibly fall from 159 s to 45-80 s, a total pipeline improvement of about 15-22%.
- Tradeoffs/risks: Parallel UDS calls may contend for build artifacts if parsing is not fixed first. Artifact ordering and deterministic seed handling must be validated.

### 4. Keep MATLAB alive across stages

- Bottleneck: The shell wrapper launches a fresh MATLAB process for each stage.
- Why expensive: MATLAB startup is visible in short stages. In-process WIS evaluation without plots took 0.454 s, while the production evaluation stage took 12 s.
- Recommended change: Add an optional single-session runner that executes scenarios, truth, tuning, forecasting, and evaluation inside one MATLAB process, while preserving the current multi-process wrapper as the default until validated.
- Files/functions: `run_partA_pipeline.sh`, possible new MATLAB orchestrator script.
- Difficulty: Medium.
- Estimated improvement: About 20-40 s for this ARX-I run, or 4-8% total, plus possible warm-cache benefits.
- Tradeoffs/risks: Current stage isolation is useful for cleanup and reproducibility. A single session must carefully reset RNG, paths, figures, warnings, and parallel pools between stages.

### 5. Improve parallel granularity for larger worker counts

- Bottleneck: Candidate-level `parfor` has only 4 iterations in the current grid.
- Why expensive: More than 4 workers cannot help. A 12-worker pool is structurally capped by 4 candidates.
- Recommended change: For larger machines or tiny grids, parallelize over a flattened set of candidate-scenario-window tasks and reduce WIS afterward, or use nested batching where each worker receives balanced chunks.
- Files/functions: `scripts/partA_02_select_global_hyperparameters.m`.
- Difficulty: Medium.
- Estimated improvement: For 4 workers, current candidate-level `parfor` is already appropriate. For 12 workers, a better decomposition could improve tuning by up to about 2-3x compared with the current 4-worker wall time if URDME/setup contention is controlled.
- Tradeoffs/risks: More tasks mean more scheduling overhead and more data transfer. Aggregation must preserve the exact equal-scenario mean WIS policy.

## Stage 3 — High-Impact / Major Changes

### 1. Replace high-level one-step `forecast(...)` calls with an equivalent direct ARX recursion

- Bottleneck: System Identification one-step `forecast(...)` is the largest measured inner-loop component.
- Why expensive: The current closed loop calls high-level toolbox forecasting 12320 times in this run, repeatedly converting models and reconstructing state from rolling histories.
- Recommended change: Implement a direct recursive evaluator for the fitted MATLAB ARX/idpoly model coefficients and predictive variance, but only after proving equivalence to `forecast(sys, data, 1, U_next, forecastOptions('InitialCondition','e'))` for the current model class.
- Files/functions: New ARX helper under `src/models` or a separate validated implementation path; `src/models/fit_arimax.m`.
- Difficulty: High.
- Estimated improvement: Potentially 30-50% total wall-time reduction for ARX-I if it removes most high-level `forecast(...)` overhead.
- Tradeoffs/risks: This is a scientific integrity risk unless equivalence is demonstrated across candidates, windows, scenarios, and interval outputs. This is conceptually similar to a sidecar/direct ARX optimization and should be treated as a major optional redesign, not a silent production substitution.

### 2. Redesign closed-loop exogenous generation around reusable simulation state

- Bottleneck: Every horizon step re-enters `genData_SIRS` from scratch with a two-point tspan.
- Why expensive: Repeated setup dominates a substantial fraction of SIRS-step cost even with compilation disabled.
- Recommended change: Build a reusable closed-loop simulator object that owns the URDME/UDS model, SIRS state, beta/Rt packaging, and deterministic seed behavior, and advances one day at a time.
- Files/functions: `src/models/genData_SIRS.m`, `src/models/fit_arimax.m`, `fit_n4sid.m`, `fit_ssest.m`, new simulator/stepper helper.
- Difficulty: High.
- Estimated improvement: If combined with forecast-call optimization, this could support an overall 2x or better ARX-I speedup.
- Tradeoffs/risks: Must preserve URDME/UDS advancement and metadata semantics. Requires careful validation against current `genData_SIRS([0, 1], ...)` output.

### 3. Redesign tuning to decouple fitting, prediction, and scoring caches

- Bottleneck: Tuning repeatedly fits and forecasts every candidate/window/scenario combination, with little reuse across candidates.
- Why expensive: The workflow does 704 complete `fit_arimax` calls for the tiny grid, and scales linearly with candidate count.
- Recommended change: Build a tuning engine that precomputes immutable window data once, supports cached SIRS/forecast stepper state where valid, records per-window diagnostics, and can distribute candidate-window tasks across workers.
- Files/functions: `scripts/partA_02_select_global_hyperparameters.m`, `src/models/fit_arimax.m`, possible new tuning utility functions.
- Difficulty: High.
- Estimated improvement: Moderate for this 4-candidate run unless combined with forecast/SIRS optimization; high for larger grids.
- Tradeoffs/risks: More complex orchestration and caching can hide reproducibility bugs. The saved tuning artifact format and ranking semantics must remain compatible.

## Final Ranked Recommendations

Best performance gain for lowest implementation effort:

1. Add optional plot skipping while preserving plots by default. Expected ARX-I run improvement: 3-5%.
2. Keep the 4-worker pool for the 4-candidate grid; do not use 12 workers unless tuning parallelism is redesigned. This avoids waste and possible contention.
3. Suppress or resolve the known benign RPARSE warning narrowly, primarily for cleaner diagnostics.

Highest overall performance improvement:

1. Reduce or replace repeated one-step System Identification `forecast(...)` calls after equivalence validation. This targets the largest measured inner-loop cost.
2. Reuse URDME/UDS model setup for one-day closed-loop SIRS advancement. This targets the second-largest measured inner-loop cost while preserving URDME/UDS.
3. Parallelize final forecast windows after addressing UDS setup/build contention.

Safest optimizations for preserving current Part A behavior and reproducibility:

1. Optional plotting flag with default enabled.
2. Single-session runner as an opt-in mode, with strict RNG/path/pool cleanup checks.
3. URDME/UDS setup reuse with regression tests comparing S/I/R trajectories, Rt forecasts, interval bounds, WIS summaries, and saved artifacts against the current pipeline.

## Limitations

- The exact fresh pipeline command was run once. Candidate stability was assessed from one deterministic-seed run and the generated tuning summary; a repeat run was not performed because the task focus was profiling.
- The targeted helper profiled 12 representative windows and two MATLAB-profiler `fit_arimax` calls, not all 880 production `fit_arimax` calls.
- No 12-worker run was executed. The 4-vs-12 conclusion is based on the current 4-candidate `parfor` structure and the observed one-wave 4-worker completion behavior.
- The helper suppresses no production behavior and does not alter normal pipeline files, but its timings are representative measurements, not a replacement for full end-to-end benchmarking after changes.
