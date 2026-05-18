# Hybrid Epidemic Forecasting

This repository contains a MATLAB framework that combines mechanistic SIR models with statistical time-series models to infer and predict the time-varying reproduction number ($R_t$). The project evaluates whether this hybrid methodology outperforms pure data-driven or mechanistic approaches in short-term forecasting.

## Project Progress

The implementation is divided into three major phases as outlined in the project plan. 

| Phase | Scope / Description | Current Status | Last Revised | Supervisor Validated | Validation Date |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Part A** | SIRS Synthetic Validation | Completed | 2026-05-18 | [ ] Pending | - |
| **Part B** | SEIR Robustness Testing | Completed | 2026-05-18 | [ ] Pending | - |
| **Part C** | Real-world Application | Not Started | - | [ ] Pending | - |

## Directory Structure

* ``config/``: Stores central configuration scripts for Part A synthetic validation and Part B robustness testing.
* ``data/``: Contains generated SIRS truth under ``data/partA/``, and generated SEIR truth under ``data/partB/``.
* ``results/``: Stores generated outputs, with Part A artifacts under ``results/partA/`` and Part B artifacts under ``results/partB/``.
* ``scripts/``: Contains high-level execution scripts, with Part A scripts under ``scripts/partA/`` and Part B scripts under ``scripts/partB/``.
* ``src/``: Core functional modules, separated into ``models/`` (simulation and forecasting algorithms), ``plots/`` (visualization helpers), and ``signals/`` (analytic $R_t$ generators).

## Active Files Summary

### Root & Configuration
* ``startup.m``: Initializes the project environment by dynamically adding internal subdirectories to the active MATLAB path.
* ``run_partA_pipeline.sh``: Orchestrates the Part A SIRS synthetic-validation pipeline and writes artifacts under ``data/partA/`` and ``results/partA/``.
* ``run_partB_pipeline.sh``: Orchestrates the Part B SEIR robustness pipeline and writes artifacts under ``data/partB/`` and ``results/partB/``.
* ``config/partA_config.m``: Defines the Part A time grid, analytic $R_t$ scenarios, SIRS parameters, active model/exogenous-input settings, forecast settings, and output paths.
* ``config/partB_config.m``: Reuses the Part A scenarios and forecast settings while adding SEIR truth parameters, SIRS projection parameters, fixed Part A tuning references, and Part B output paths.

### Execution Scripts
* ``scripts/partA/partA_00_make_scenarios.m``: Generates and visualizes the distinct effective reproduction-number scenarios (seasonality, interventions, resurgences) to be used as ground truth.
* ``scripts/partA/partA_01_generate_truth.m``: Simulates the SIRS epidemic model to generate and save the synthetic ground-truth datasets for each scenario.
* ``scripts/partA/partA_02_select_global_hyperparameters.m``: Selects one global hyperparameter configuration per model family and exogenous-input setting using cross-scenario WIS and the active ``cfg.run`` configuration.
* ``scripts/partA/partA_03_run_forecasts.m``: Acts as a unified switchboard to execute expanding-window probabilistic forecasts using the selected global hyperparameter configuration, causal effective-``R_t`` SIRS covariate projection, and the active ``cfg.run`` configuration.
* ``scripts/partA/partA_04_evaluate_models.m``: Aggregates the forecast results, calculates WIS metrics, and produces final statistical summaries.
* ``scripts/partB/partB_01_generate_truth.m``: Generates SEIR ground-truth trajectories for the same four analytic $R_t$ scenarios used in Part A.
* ``scripts/partB/partB_02_run_fixed_forecasts.m``: Runs fixed Part A-selected AR/ARX configurations against SEIR truth using SIRS-style future covariate projection.
* ``scripts/partB/partB_03_evaluate_models.m``: Computes Part B WIS summaries, SIRS-vs-SEIR state-projection errors, and Part B evaluation figures.

### Source Code (``src/``)
* ``src/models/fit_arima.m``: Fits an autoregressive model to a historical reproduction number time series through a standardized ARIMA wrapper.
* ``src/models/fit_arimax.m``: Fits an autoregressive model with exogenous inputs to historical data through a standardized ARIMAX wrapper.
* ``src/models/fit_n4sid.m``: Fits a discrete-time state-space model utilizing the Subspace State-Space System Identification (N4SID) algorithm.
* ``src/models/fit_ssest.m``: Fits an optimized discrete-time state-space model using iterative Prediction Error Minimization (PEM).
* ``src/models/genData_SIRS.m``: Simulates SIRS trajectories from desired effective-``R_t`` inputs, computing the state-consistent internal transmission rates required by URDME.
* ``src/models/genData_SEIR.m``: Simulates deterministic SEIR trajectories for Part B robustness testing.
* ``src/plots/plot_model_performance.m``: Visualizes the comparative WIS distributions across various model configurations and scenarios.
* ``src/plots/plot_rt_forecast_comparison.m``: Generates a unified visualization comparing the expanding-window forecast medians and predictive intervals against the ground truth.
* ``src/plots/plot_rt_scenarios.m``: Generates a tiled summary figure displaying the predefined synthetic reproduction number profiles.
* ``src/signals/rt_multi_wave.m``: Generates a four-peak Gaussian trajectory to model sustained, sequentially damping or amplifying epidemic resurgences.
* ``src/signals/rt_seasonal.m``: Generates a sinusoidal reproduction number trajectory to simulate recurrent epidemic waves.
* ``src/signals/rt_sigmoid.m``: Generates a smooth sigmoid transition to model the impact of a targeted policy intervention.
