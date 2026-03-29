# Hybrid Epidemic Forecasting

This repository contains a MATLAB framework that combines mechanistic SIR models with statistical time-series models to infer and predict the time-varying reproduction number ($R_t$). The project evaluates whether this hybrid methodology outperforms pure data-driven or mechanistic approaches in short-term forecasting.

## Project Progress

The implementation is divided into three major phases as outlined in the project plan. 

| Phase | Scope / Description | Current Status | Last Revised | Supervisor Validated | Validation Date |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Part A** | Synthetic Validation | Completed | 2026-02-22 | [ ] Pending | - |
| **Part B** | Robustness Testing | Not Started | - | [ ] Pending | - |
| **Part C** | Real-world Application | Not Started | - | [ ] Pending | - |

## Directory Structure

* ``config/``: Stores the central configuration scripts that define simulation parameters and hyperparameter grids.
* ``data/``: Contains both the static empirical datasets (``R0a.mat``, ``F.mat``, etc.) and the generated ``synthetic/`` ground-truth trajectories.
* ``results/``: The primary output destination for the pipeline, categorized into ``forecasts/`` (raw prediction artifacts), ``scores/`` (aggregated CSV summaries), ``figures/`` (visualizations), ``tuning/`` (global hyperparameter selection artifacts), and ``logs/`` (per-run execution logs and manifests).
* ``scripts/``: High-level execution pipelines that run the scenario generation, truth simulation, global hyperparameter selection, model forecasting, and evaluation processes.
* ``src/``: Core functional modules, separated into ``models/`` (standardized fitting algorithms), ``plots/`` (visualization helpers), and ``signals/`` (data generators).

## Active Files Summary

### Root & Configuration
* ``startup.m``: Initializes the project environment by dynamically adding internal subdirectories to the active MATLAB path.
* ``run_partA_pipeline.sh``: Convenience entry point that runs the Part A pipeline in the correct order, supports numeric Model/Exogenous selections, can clear previous result artifacts with ``--fresh``, and stores each invocation under a timestamped ``results/logs/<run_id>/`` directory containing per-stage logs and a run manifest. The terminal shows stage progress and saved artifact paths, while detailed warnings are preserved in the raw per-stage logs.
* ``config/partA_config.m``: Serves as the central configuration hub, defining the simulation environment, active run settings, ground truth constraints, and forecasting hyperparameters for the synthetic validation phase. The active Model Type and Exogenous Mode can also be overridden externally via environment variables.

### Execution Scripts
* ``scripts/partA_00_make_scenarios.m``: Generates and visualizes the distinct transmission scenarios (seasonality, interventions, resurgences) to be used as ground truth.
* ``scripts/partA_01_generate_truth.m``: Simulates the SIRS epidemic model to generate and save the synthetic ground-truth datasets for each scenario.
* ``scripts/partA_02_select_global_hyperparameters.m``: Selects one global hyperparameter configuration per model family and exogenous-input setting using cross-scenario WIS and the active ``cfg.run`` configuration.
* ``scripts/partA_03_run_forecasts.m``: Acts as a unified switchboard to execute expanding-window probabilistic forecasts using the selected global hyperparameter configuration and the active ``cfg.run`` configuration.
* ``scripts/partA_04_evaluate_models.m``: Aggregates the forecast results, calculates WIS metrics, and produces final statistical summaries.

### Source Code (``src/``)
* ``src/models/fit_arima.m``: Fits an autoregressive model to a historical reproduction number time series through a standardized ARIMA wrapper.
* ``src/models/fit_arimax.m``: Fits an autoregressive model with exogenous inputs to historical data through a standardized ARIMAX wrapper.
* ``src/models/fit_n4sid.m``: Fits a discrete-time state-space model utilizing the Subspace State-Space System Identification (N4SID) algorithm.
* ``src/models/fit_ssest.m``: Fits an optimized discrete-time state-space model using iterative Prediction Error Minimization (PEM).
* ``src/models/genData.m``: A general utility for generating synthetic data from compartmental epidemic models using URDME.
* ``src/models/genData_SIRS.m``: A specialized wrapper for simulating stochastic or deterministic trajectories of the SIRS model with parameter-driven compilation and explicit seed handling.
* ``src/plots/plot_model_performance.m``: Visualizes the comparative WIS distributions across various model configurations and scenarios.
* ``src/plots/plot_rt_forecast_comparison.m``: Generates a unified visualization comparing the expanding-window forecast medians and predictive intervals against the ground truth.
* ``src/plots/plot_rt_scenarios.m``: Generates a tiled summary figure displaying the predefined synthetic reproduction number profiles.
* ``src/signals/rt_multi_wave.m``: Generates a four-peak Gaussian trajectory to model sustained, sequentially damping or amplifying epidemic resurgences.
* ``src/signals/rt_seasonal.m``: Generates a sinusoidal reproduction number trajectory to simulate recurrent epidemic waves.
* ``src/signals/rt_sigmoid.m``: Generates a smooth sigmoid transition to model the impact of a targeted policy intervention.
