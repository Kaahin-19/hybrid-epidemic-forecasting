# Hybrid Epidemic Forecasting

This repository contains the codebase for evaluating statistical (ARIMA/ARIMAX) and State-Space (N4SID/SSEST) models on epidemic data. The project relies on an expanding-window forecasting pipeline to compare pure autoregressive approaches against hybrid architectures that incorporate exogenous biological covariates (Susceptible and Infected populations).

## Directory Structure

* `config/`: Stores the central configuration scripts that define simulation parameters and hyperparameter grids.
* `data/`: Contains both the static empirical datasets (`R0a.mat`, `F.mat`, etc.) and the generated `synthetic/` ground-truth trajectories.
* `results/`: The primary output destination for the pipeline, categorized into `forecasts/` (raw prediction artifacts), `scores/` (aggregated CSV summaries), and `figures/` (visualizations).
* `scripts/`: High-level execution pipelines that run the scenario generation, truth simulation, model forecasting, and evaluation processes.
* `src/`: Core functional modules, separated into `models/` (standardized fitting algorithms), `plot/` (visualization helpers), and `signals/` (deterministic data generators).

## Active Files Summary

### Root & Configuration
* `startup.m`: Initializes the project environment by dynamically adding internal subdirectories to the active MATLAB path.
* `config/partA_config.m`: Serves as the central configuration hub, defining the simulation environment, ground truth constraints, and forecasting hyperparameters for the synthetic validation phase.

### Execution Scripts
* `scripts/partA_00_make_scenarios.m`: Generates and visualizes the distinct transmission scenarios (seasonality, interventions, resurgences) to be used as ground truth.
* `scripts/partA_01_generate_truth.m`: Simulates the SIRS epidemic model to generate and save the synthetic ground-truth datasets for each scenario.
* `scripts/partA_02_run_forecasts.m`: Acts as a unified switchboard to execute expanding-window forecasts across all selected model types and exogenous modes.
* `scripts/partA_03_evaluate_models.m`: Aggregates the parallel forecast results, calculates RMSE/MAE metrics, and produces final statistical summaries.

### Source Code (`src/`)
* `src/models/fit_arima.m`: Fits an Autoregressive Integrated Moving Average (ARIMA) model to a historical reproduction number time series.
* `src/models/fit_arimax.m`: Fits an ARIMAX model to historical data by incorporating external covariate matrices.
* `src/models/fit_n4sid.m`: Fits a discrete-time state-space model utilizing the Subspace State-Space System Identification (N4SID) algorithm.
* `src/models/fit_ssest.m`: Fits an optimized discrete-time state-space model using iterative Prediction Error Minimization (PEM).
* `src/models/genData.m`: A general utility for generating synthetic data from compartmental epidemic models using URDME.
* `src/models/genData_SIRS.m`: A specialized wrapper for simulating stochastic or deterministic trajectories of the SIRS model.
* `src/plot/plot_rt_scenarios.m`: Generates a tiled summary figure displaying the predefined synthetic reproduction number profiles.
* `src/plot/plot_rt_forecast_comparison.m`: Generates a two-panel visualization comparing the expanding window forecasts against the ground truth and tracking AICc stability.
* `src/plot/plot_model_performance.m`: Visualizes the comparative RMSE distributions across various model configurations and scenarios.
* `src/signals/rt_multi_wave.m`: Generates a four-peak Gaussian trajectory to model sustained, sequentially damping or amplifying epidemic resurgences.
* `src/signals/rt_seasonal.m`: Generates a deterministic, sinusoidal reproduction number trajectory to simulate recurrent epidemic waves.
* `src/signals/rt_sigmoid.m`: Generates a smooth sigmoid transition to model the impact of a targeted policy intervention.
