# Hybrid Epidemic Forecasting

This repository contains a MATLAB framework that combines mechanistic SIR models with statistical time-series methods to infer and forecast the effective reproduction number ($R_t$). The project evaluates whether this hybrid framework improves short-term forecasting performance relative to purely statistical or purely mechanistic approaches.

---

## Project Progress

The implementation is divided into three major phases as outlined in the project plan.

| Phase      | Scope / Description   | Current Status | Last Revised | Supervisor Validated | Validation Date |
| :--------- | :-------------------- | :------------- | :----------- | :------------------- | :-------------- |
| **Part A** | Synthetic Validation  | Completed      | 2026-08-23   | [ ] Pending          | -               |
| **Part B** | Robustness Testing    | Completed      | 2026-08-23   | [ ] Pending          | -               |
| **Part C** | Real-Data Application | Completed      | 2026-08-23   | [ ] Pending          | -               |

---

## Directory Structure

* **`config/`**: Stores central configuration functions for Part A synthetic validation, Part B robustness testing, and the Part C real-data adaptation.
* **`data/`**: Contains generated SIRS truth under `data/partA/`, generated robustness datasets under `data/partB/`, and WHO COVID-19 raw inputs under `data/partC/raw/` with prepared real-data artifacts under `data/partC/prepared/`.
* **`results/`**: Stores generated outputs, with Part A artifacts under `results/partA/` including `model_selection/`, `forecasts/`, `evaluation/`, `figures/`, `tables/`, and `logs/`; Part B artifacts include `forecasts/`, `evaluation/`, `figures/`, `tables/`, and `logs/`; Part C artifacts additionally include local model selections under `results/partC/model_selection/`.
* **`scripts/`**: Contains high-level execution scripts, with the five-stage Part A pipeline under `scripts/partA/`, the four-stage Part B pipeline under `scripts/partB/`, and the five-stage Part C pipeline under `scripts/partC/`.
* **`src/`**: Core functional modules, separated into `epidemic/` (SIRS/SEIRS stepping, renewal estimation, and state reconstruction), `forecasting/` (expanding-window construction and bootstrap forecasting), `scoring/` (forecast metrics and diagnostics), and `visualization/` (reusable plotting and styling helpers).

---

## Active Files Summary

### Root & Configuration

* **`startup.m`**: Initializes the project environment by dynamically adding internal subdirectories to the active MATLAB path.
* **`run_partA_pipeline.sh`**: Orchestrates the Part A SIRS synthetic-validation pipeline and writes artifacts under `data/partA/` and `results/partA/`.
* **`run_partB_pipeline.sh`**: Orchestrates the configuration-driven Part B robustness pipeline and writes artifacts under `data/partB/` and `results/partB/`.
* **`run_partC_pipeline.sh`**: Orchestrates the five-stage Part C Swedish COVID-19 real-data adaptation pipeline and writes artifacts under `data/partC/` and `results/partC/`.
* **`config/partA_config.m`**: Defines the Part A time grid, analytic $R_t$ scenarios, SIRS parameters, active model/exogenous-input settings, forecast settings, and output paths.
* **`config/partB_config.m`**: Extends the Part A configuration with noisy-$R_t$-input, process-noise, structural-mismatch, and combined-stress cases, SEIR/SEIRS truth parameters, and Part B output paths.
* **`config/partC_config.m`**: Defines the WHO COVID-19 source, Sweden study period, renewal estimation, reported-case SIRS state reconstruction, chronological validation, local selection, held-out forecasting, evaluation, visualization, and output paths.

### Execution Scripts

* **`scripts/partA/partA_01_generate_truth.m`**: Simulates the SIRS epidemic model to generate and save one synthetic ground-truth `.mat` artifact for each Part A scenario.
* **`scripts/partA/partA_02_select_global_hyperparameters.m`**: Selects one global model configuration per model family and exogenous-input setting using cross-scenario WIS and the active `cfg.run` configuration.
* **`scripts/partA/partA_03_run_forecasts.m`**: Acts as a unified switchboard to execute expanding-window probabilistic forecasts using the selected global hyperparameter configuration, causal effective-`R_t` SIRS covariate projection, and the active `cfg.run` configuration.
* **`scripts/partA/partA_04_evaluate_forecasts.m`**: Aggregates all forecast artifacts, computes WIS, WIS components, RMSE, MAE, coverage, calibration, interval-width, and deterministic infected-state projection metrics, saves the evaluation `.mat` artifact under `results/partA/evaluation/`, and writes table outputs under `results/partA/tables/`.
* **`scripts/partA/partA_05_generate_figures.m`**: Generates the Part A synthetic-validation thesis figures from saved truth, forecast, and evaluation artifacts.
* **`scripts/partB/partB_01_generate_robustness_datasets.m`**: Generates synthetic robustness datasets for noisy $R_t$ input, process noise, structural mismatch, and combined stress.
* **`scripts/partB/partB_02_run_forecasts.m`**: Runs frozen Part A-selected model configurations on successful robustness datasets and records forecast-execution outcomes.
* **`scripts/partB/partB_03_evaluate_forecasts.m`**: Scores robustness forecasts against latent $R_t$ truth and matched Part A baselines, then exports robustness and execution summaries.
* **`scripts/partB/partB_04_generate_figures.m`**: Generates Part B thesis figures for robustness performance, degradation, interval calibration, and forecast-execution outcomes.
* **`scripts/partC/partC_01_prepare_data.m`**: Reads the configured WHO incidence series, estimates operational $R_t$, reconstructs causal reported-case SIRS state proxies, and saves the prepared artifact.
* **`scripts/partC/partC_02_select_local_orders.m`**: Evaluates limited AR/None and ARX/I order neighbourhoods on the calibration block and saves one local-selection artifact per configuration.
* **`scripts/partC/partC_03_run_forecasts.m`**: Generates held-out AR/None and ARX/I forecasts under global online, local online, and global fixed-fit transfer strategies.
* **`scripts/partC/partC_04_evaluate_forecasts.m`**: Scores the held-out forecasts, builds strategy and interval summaries, and exports the Part C evaluation artifact and tables.
* **`scripts/partC/partC_05_generate_figures.m`**: Generates seven Part C thesis figures from the prepared-data, held-out forecast, and evaluation artifacts.

### Source Code (`src/`)

#### **Epidemic functions (`src/epidemic/`)**

* **`estimate_rt_renewal.m`**: Estimates an operational effective reproduction-number series from incidence and renewal weights.
* **`reconstruct_sirs_states_from_incidence.m`**: Reconstructs causal susceptible, infectious, and recovered state proxies from reported incidence.
* **`seirs_init.m`**: Prepares a reusable one-day URDME SEIRS stepper for Part B structural-mismatch truth.
* **`seirs_step.m`**: Advances the reusable effective-$R_t$-driven SEIRS stepper by one day.
* **`serial_interval_weights.m`**: Constructs normalized discrete gamma serial-interval weights.
* **`sirs_init.m`**: Prepares a reusable one-day URDME SIRS stepper for truth simulation and closed-loop forecasting.
* **`sirs_step.m`**: Advances the reusable effective-$R_t$-driven SIRS stepper by one day.

#### **Forecasting functions (`src/forecasting/`)**

* **`build_forecast_windows.m`**: Builds expanding-window forecast entries with matching $R_t$, exogenous-history, SIRS-state, and truth data.
* **`forecast_closed.m`**: Fits exogenous-input ARX or state-space models and propagates closed-loop residual-bootstrap forecasts with SIRS feedback.
* **`forecast_open.m`**: Fits output-only AR or state-space models and propagates residual-bootstrap $R_t$ forecasts.

#### **Scoring functions (`src/scoring/`)**

* **`compute_interval_diagnostics.m`**: Computes per-horizon and per-interval coverage, width, calibration, and interval-score diagnostics.
* **`compute_point_error.m`**: Computes pointwise forecast errors together with RMSE and MAE.
* **`compute_wis.m`**: Computes per-horizon weighted interval scores and their optional components.

#### **Visualization functions (`src/visualization/`)**

* **`apply_panel_style.m`**: Applies shared thesis panel styling to caller-supplied axes.
* **`plot_distribution.m`**: Draws grouped boxchart distributions and applies shared panel styling.
* **`plot_series.m`**: Draws ordered line, interval-ribbon, and reference series and applies shared panel styling.
