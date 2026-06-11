# Hybrid Epidemic Forecasting

This repository contains a MATLAB framework that combines mechanistic SIR models with statistical time-series methods to infer and forecast the effective reproduction number ($R_t$). The project evaluates whether this hybrid framework improves short-term forecasting performance relative to purely statistical or purely mechanistic approaches.

## Project Progress

The implementation is divided into three major phases as outlined in the project plan. 

| Phase | Scope / Description | Current Status | Last Revised | Supervisor Validated | Validation Date |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Part A** | Synthetic Validation | Completed | 2026-05-18 | [ ] Pending | - |
| **Part B** | Robustness Testing | Completed | 2026-05-18 | [ ] Pending | - |
| **Part C** | Real-Data Application | Completed | 2026-05-19 | [ ] Pending | - |

## Directory Structure

* ``config/``: Stores central configuration scripts for Part A synthetic validation, Part B robustness testing, and the Part C real-data proof of concept.
* ``data/``: Contains generated SIRS truth under ``data/partA/``, generated SEIR truth under ``data/partB/``, and WHO COVID-19 raw inputs under ``data/partC/raw/`` with processed real-data artifacts under ``data/partC/processed/``.
* ``results/``: Stores generated outputs, with Part A artifacts under ``results/partA/`` including ``model_selection/``, ``forecasts/``, ``evaluation/``, ``figures/``, ``tables/``, and ``logs/``; Part B and Part C artifacts include forecasts, scores, figures, logs, and local-refinement outputs under ``results/partC/refinement/``.
* ``scripts/``: Contains high-level execution scripts, with Part A scripts under ``scripts/partA/``, Part B scripts under ``scripts/partB/``, and Part C frozen real-data plus local-refinement scripts under ``scripts/partC/``.
* ``src/``: Core functional modules, separated into ``epidemiology/scenarios/`` (analytic $R_t$ signals), ``epidemiology/dynamics/`` (ground-truth simulation and reusable SIRS stepping), ``forecasting/`` (expanding-window orchestration and dataset assembly), ``model_selection/`` (Part A candidate generation, scoring, and selection), ``evaluation/`` (Part A forecast metrics and summaries), ``visualization/`` (reusable figure helpers), ``models/`` (forecasting algorithms grouped into ``ar/``, ``arx/``, ``n4sid/``, and ``ssest/`` subfolders alongside the ARIMA/ARIMAX wrappers and the ``genData`` simulators), and ``intervals/`` (closed-loop residual-bootstrap and Monte Carlo predictive intervals, split into shared helpers, ``ar_arx/``, and ``statespace/``).

## Active Files Summary

### Root & Configuration
* ``startup.m``: Initializes the project environment by dynamically adding internal subdirectories to the active MATLAB path.
* ``run_partA_pipeline.sh``: Orchestrates the Part A SIRS synthetic-validation pipeline and writes artifacts under ``data/partA/`` and ``results/partA/``.
* ``run_partB_pipeline.sh``: Orchestrates the Part B SEIR robustness pipeline and writes artifacts under ``data/partB/`` and ``results/partB/``.
* ``run_partC_pipeline.sh``: Orchestrates the Part C WHO COVID-19 proof-of-concept pipeline in frozen or refined mode, supports ``--models`` for refined AR/ARX runs, and writes artifacts under ``data/partC/`` and ``results/partC/``.
* ``config/partA_config.m``: Defines the Part A time grid, analytic $R_t$ scenarios, SIRS parameters, active model/exogenous-input settings, forecast settings, and output paths.
* ``config/partB_config.m``: Reuses the Part A scenarios and forecast settings while adding SEIR truth parameters, SIRS projection parameters, fixed Part A tuning references, and Part B output paths.
* ``config/partC_config.m``: Reuses the Part A forecast settings while defining WHO COVID-19 input paths, the Sweden default date window, case preprocessing settings, Part C output paths, fixed AR/None versus ARX/I configurations, and local-refinement grids.

### Execution Scripts
* ``scripts/partA/partA_01_generate_truth.m``: Simulates the SIRS epidemic model to generate and save one synthetic ground-truth ``.mat`` artifact for each Part A scenario.
* ``scripts/partA/partA_02_select_global_hyperparameters.m``: Selects one global model configuration per model family and exogenous-input setting using cross-scenario WIS and the active ``cfg.run`` configuration.
* ``scripts/partA/partA_03_run_forecasts.m``: Acts as a unified switchboard to execute expanding-window probabilistic forecasts using the selected global hyperparameter configuration, causal effective-``R_t`` SIRS covariate projection, and the active ``cfg.run`` configuration.
* ``scripts/partA/partA_04_evaluate_forecasts.m``: Aggregates all forecast artifacts, computes WIS, WIS components, RMSE, MAE, coverage, calibration, and interval-width metrics, saves the evaluation ``.mat`` artifact under ``results/partA/evaluation/``, and writes table outputs under ``results/partA/tables/``.
* ``scripts/partA/partA_05_generate_figures.m``: Loads saved truth, model-selection, forecast, evaluation, and table artifacts, then writes final Part A figures under ``results/partA/figures/``.
* ``scripts/partB/partB_01_generate_truth.m``: Generates SEIR ground-truth trajectories for the same four analytic $R_t$ scenarios used in Part A.
* ``scripts/partB/partB_02_run_fixed_forecasts.m``: Runs fixed Part A-selected AR/ARX configurations against SEIR truth using SIRS-style future covariate projection.
* ``scripts/partB/partB_03_evaluate_models.m``: Computes Part B WIS summaries, SIRS-vs-SEIR state-projection errors, and Part B evaluation figures.
* ``scripts/partC/partC_01_prepare_real_data.m``: Reads the WHO daily COVID-19 case file, derives a smoothed case proxy and empirical ``Rt_est`` internally, and writes processed Part C real-data artifacts.
* ``scripts/partC/partC_02_run_forecasts.m``: Runs fixed expanding-window AR/None and ARX/I forecasts for the WHO-derived real-data $R_t$ signal, using ``I_scaled`` as the ARX/I exogenous input, and writes full plus capped diagnostic forecast figures.
* ``scripts/partC/partC_03_evaluate_models.m``: Computes the primary all-window Part C WIS summaries for ``Rt_est``, the fixed-comparison evaluation figure, and diagnostic explosive-window/stable-window artifacts.
* ``scripts/partC/partC_04_local_refinement.m``: Runs held-out local AR/ARX recalibration, all-window diagnostics, holdout WIS comparison, refined forecast figures, and projected infection-proxy diagnostics.

### Source Code (``src/``)

**Epidemiology scenarios (``src/epidemiology/scenarios/``)**
* ``generate_rt_signal.m``: Generates configured Part A analytic effective reproduction-number trajectories, with seasonal, sigmoid, and multi-wave formulas kept as local helpers.

**Epidemiology dynamics (``src/epidemiology/dynamics/``)**
* ``simulate_ground_truth_epidemic.m``: Simulates effective-``R_t``-driven SIRS ground truth directly with URDME and assembles reusable truth structures.
* ``initialize_sirs_stepper.m``: Prepares a reusable one-day URDME SIRS stepper.
* ``advance_sirs_stepper.m``: Advances the SIRS state one day using the reusable URDME stepper.
* ``advance_epidemic_state.m``: Advances one effective-``R_t``-driven epidemic state for closed-loop covariate projection.

**Forecasting orchestration (``src/forecasting/``)**
* ``build_forecast_entries.m``: Builds Part A/B/C expanding-window forecast entries.
* ``run_expanding_window_forecast.m``: Runs all window forecasts for one scenario.
* ``run_model_forecast.m``: Fits and forecasts one selected configuration for a single window.

**Model selection (``src/model_selection/``)**
* ``generate_candidate_grid.m``: Constructs the Part A model-configuration candidates.
* ``evaluate_candidate.m``: Scores one Part A model configuration across scenarios.
* ``aggregate_candidate_scores.m``: Evaluates and aggregates the Part A candidate scores.
* ``select_best_configuration.m``: Selects the candidate with the lowest global mean WIS.

**Evaluation (``src/evaluation/``)**
* ``compute_wis.m``: Computes raw-scale pointwise weighted interval scores.
* ``compute_wis_components.m``: Decomposes WIS into median, dispersion, underprediction, and overprediction components.
* ``compute_rmse.m``: Computes median point-forecast RMSE.
* ``compute_mae.m``: Computes median point-forecast MAE.
* ``compute_coverage.m``: Computes empirical predictive-interval coverage.
* ``compute_interval_width.m``: Computes predictive-interval widths.
* ``summarize_forecast_scores.m``: Builds scenario, horizon, model, exogenous-mode, calibration, and WIS-component summary tables.

**Forecasting models (``src/models/``)**
* ``fit_arima.m``: Fits an ARIMA(p,d,q) model to historical ``R_t`` data and forecasts through a standardized wrapper.
* ``fit_arimax.m``: Fits an ARIMAX model to historical ``R_t`` and exogenous data and forecasts through a standardized wrapper.
* ``genData_SIRS.m``: Simulates SIRS trajectories from desired effective-``R_t`` inputs, computing the state-consistent internal transmission rates required by URDME.
* ``genData_SEIR.m``: Simulates deterministic SEIR trajectories for Part B robustness testing.
* ``ar/fit_ar_model.m``: Fits an output-only AR model to historical effective ``R_t``.
* ``ar/forecast_ar_model.m``: Forecasts future effective ``R_t`` from a fitted AR model.
* ``arx/fit_arx_model.m``: Fits an ARX model once for Part A model selection.
* ``arx/forecast_arx_closed_loop.m``: Forecasts ARX recursively with epidemic feedback.
* ``arx/recursive_arx_step.m``: Computes one recursive ARX prediction from coefficients.
* ``arx/extract_arx_coefficients.m``: Extracts the recursive ARX polynomial coefficients.
* ``arx/extract_exogenous_from_state.m``: Converts an epidemic state to ARX covariates.
* ``n4sid/fit_n4sid_model.m``: Fits a discrete-time state-space model via the Subspace State-Space System Identification (N4SID) algorithm and forecasts.
* ``ssest/fit_ssest_model.m``: Fits an optimized discrete-time state-space model using iterative Prediction Error Minimization (PEM) and forecasts.

**Predictive intervals (``src/intervals/``)**
* ``make_interval_options.m``: Builds the per-window interval-simulation options (lightweight residual bootstrap for selection, fuller Monte Carlo for final forecasts) with deterministic seeding.
* ``sample_centered_residuals.m``: Centers and resamples one-step residual innovations, with a Gaussian fallback.
* ``compute_interval_bounds_from_ensemble.m``: Reduces an ensemble of ``R_t`` trajectories to the empirical predictive median and central interval bounds.
* ``ar_arx/simulate_ar_residual_bootstrap_paths.m``: Generates recursive AR bootstrap ``R_t`` trajectories.
* ``ar_arx/simulate_arx_closed_loop_bootstrap_paths.m``: Generates closed-loop ARX bootstrap ``R_t`` trajectories with frozen or resimulated epidemic feedback.
* ``ar_arx/simulate_ar_arx_intervals.m``: AR/ARX family entry that fits, bootstraps innovations, and assembles interval outputs.
* ``statespace/simulate_statespace_closed_loop_bootstrap_paths.m``: Shared innovations-form closed-loop simulator for N4SID/SSEST trajectories.
* ``statespace/simulate_statespace_intervals.m``: N4SID/SSEST family entry where the state-space estimator is the only family-specific step.

**Visualization (``src/visualization/``)**
* ``build_plot_spec.m``: Builds reusable plot specification structures.
* ``export_figure.m``: Centralizes figure export behavior.
* ``plot_single_panel.m``: Draws one generic panel from caller-supplied series, labels, limits, legend entries, and styles.
* ``plot_multi_panel_figure.m``: Arranges generic panel definitions in a tiled figure and delegates each tile to ``plot_single_panel.m``.
* ``plot_model_performance.m``: Draws model-level WIS distributions for Part B/C score registries.
* ``plot_rt_forecast_comparison.m``: Draws fixed-lead ``R_t`` forecast comparisons for Part B/C scripts; Part A figures use ``plot_single_panel.m`` directly.
