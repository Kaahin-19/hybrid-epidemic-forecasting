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
* ``src/``: Core functional modules, separated into ``scenarios/`` (analytic $R_t$ signals), ``epidemic/`` (ground-truth simulation), ``models/`` (forecasting algorithms and legacy simulators), and ``plots/`` (visualization helpers).

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
* ``scripts/partA/partA_01_generate_synthetic_truth.m``: Simulates the SIRS epidemic model to generate and save one synthetic ground-truth ``.mat`` artifact for each Part A scenario.
* ``scripts/partA/partA_02_select_global_hyperparameters.m``: Selects one global hyperparameter configuration per model family and exogenous-input setting using cross-scenario WIS and the active ``cfg.run`` configuration.
* ``scripts/partA/partA_03_run_forecasts.m``: Acts as a unified switchboard to execute expanding-window probabilistic forecasts using the selected global hyperparameter configuration, causal effective-``R_t`` SIRS covariate projection, and the active ``cfg.run`` configuration.
* ``scripts/partA/partA_04_evaluate_models.m``: Aggregates the forecast results, calculates WIS metrics, and produces final statistical summaries.
* ``scripts/partB/partB_01_generate_truth.m``: Generates SEIR ground-truth trajectories for the same four analytic $R_t$ scenarios used in Part A.
* ``scripts/partB/partB_02_run_fixed_forecasts.m``: Runs fixed Part A-selected AR/ARX configurations against SEIR truth using SIRS-style future covariate projection.
* ``scripts/partB/partB_03_evaluate_models.m``: Computes Part B WIS summaries, SIRS-vs-SEIR state-projection errors, and Part B evaluation figures.
* ``scripts/partC/partC_01_prepare_real_data.m``: Reads the WHO daily COVID-19 case file, derives a smoothed case proxy and empirical ``Rt_est`` internally, and writes processed Part C real-data artifacts.
* ``scripts/partC/partC_02_run_forecasts.m``: Runs fixed expanding-window AR/None and ARX/I forecasts for the WHO-derived real-data $R_t$ signal, using ``I_scaled`` as the ARX/I exogenous input, and writes full plus capped diagnostic forecast figures.
* ``scripts/partC/partC_03_evaluate_models.m``: Computes the primary all-window Part C WIS summaries for ``Rt_est``, the fixed-comparison evaluation figure, and diagnostic explosive-window/stable-window artifacts.
* ``scripts/partC/partC_04_local_refinement.m``: Runs held-out local AR/ARX recalibration, all-window diagnostics, holdout WIS comparison, refined forecast figures, and projected infection-proxy diagnostics.

### Source Code (``src/``)
* ``src/models/fit_arima.m``: Fits an autoregressive model to a historical reproduction number time series through a standardized ARIMA wrapper.
* ``src/models/fit_arimax.m``: Fits an autoregressive model with exogenous inputs to historical data through a standardized ARIMAX wrapper.
* ``src/models/fit_n4sid.m``: Fits a discrete-time state-space model utilizing the Subspace State-Space System Identification (N4SID) algorithm.
* ``src/models/fit_ssest.m``: Fits an optimized discrete-time state-space model using iterative Prediction Error Minimization (PEM).
* ``src/models/genData_SIRS.m``: Simulates SIRS trajectories from desired effective-``R_t`` inputs, computing the state-consistent internal transmission rates required by URDME.
* ``src/models/genData_SEIR.m``: Simulates deterministic SEIR trajectories for Part B robustness testing.
* ``src/scenarios/generate_rt_signal.m``: Generates configured Part A analytic effective reproduction-number trajectories, with seasonal, sigmoid, and multi-wave formulas kept as local helpers.
* ``src/epidemic/simulate_ground_truth_epidemic.m``: Simulates effective-``R_t``-driven SIRS ground truth directly with URDME and assembles reusable truth structures.
* ``src/plots/plot_model_performance.m``: Visualizes the comparative WIS distributions across various model configurations and scenarios.
* ``src/plots/plot_rt_forecast_comparison.m``: Generates a unified visualization comparing the expanding-window forecast medians and predictive intervals against the ground truth.
* ``src/plots/plot_rt_scenarios.m``: Generates a tiled summary figure displaying the predefined synthetic reproduction number profiles.
