# Hybrid Epidemic Forecasting

This repository contains a MATLAB framework that combines mechanistic SIR models with statistical time-series methods to infer and forecast the effective reproduction number ($R_t$). The project evaluates whether forecasting $R_t$ improves short-term epidemic predictions relative to holding the latest available $R_t$ estimate constant.

---

## Project Progress

The implementation is divided into three major phases as outlined in the project plan.

| Phase      | Scope / Description                 | Current Status | Last Revised | Supervisor Validated | Validation Date |
| :--------- | :---------------------------------- | :------------- | :----------- | :------------------- | :-------------- |
| **Part A** | Reproduction-Number Model Design    | Completed      | 2026-11-17   | [ ] Pending          | -               |
| **Part B** | Synthetic Epidemic Forecasting      | Completed      | 2026-11-18   | [ ] Pending          | -               |
| **Part C** | Real-Data Application               | Completed      | 2026-10-12   | [ ] Pending          | -               |

---

## Directory Structure

* **`config/`**: Stores central configuration functions for Part A synthetic model design, Part B infectious-population forecasting, and Part C real-data adaptation.
* **`data/`**: Contains the Part A synthetic SIRS datasets under `data/partA/development/`, `data/partA/refinement/`, and `data/partA/assessment/` with the dataset manifest `data/partA/partA_01_dataset_manifest.mat`, synthetic truth, incidence observations, and historical estimates under `data/partB/`, and WHO COVID-19 raw inputs under `data/partC/raw/` with prepared real-data artifacts under `data/partC/prepared/`.
* **`results/`**: Stores generated outputs, with Part A artifacts under `results/partA/` including `model_selection/`, `forecasts/`, `evaluation/`, `figures/`, `tables/`, and `logs/`; Part B artifacts include `forecasts/`, `evaluation/`, `figures/`, `tables/`, and `logs/`; Part C artifacts additionally include local model selections under `results/partC/model_selection/`.
* **`scripts/`**: Contains high-level execution scripts, with the five-stage Part A pipeline under `scripts/partA/`, the four-stage Part B pipeline under `scripts/partB/`, and the five-stage Part C pipeline under `scripts/partC/`.
* **`src/`**: Core functional modules, separated into `scenarios/` (prescribed $R_t$ signal generation), `epidemic/` (SIRS/SEIRS stepping, incidence-based inversion, renewal estimation, and state reconstruction), `forecasting/` (expanding-window construction and bootstrap forecasting), `scoring/` (forecast metrics and diagnostics), and `visualization/` (reusable plotting and styling helpers).

---

## Active Files Summary

### Root & Configuration

* **`startup.m`**: Initializes the project environment by dynamically adding internal subdirectories to the active MATLAB path.
* **`run_partA_pipeline.sh`**: Orchestrates the Part A SIRS synthetic-validation pipeline for the selected model/input combinations (dataset generation, hyperparameter selection for every selected combination, then independent assessment for every selected combination, evaluation, and figures) and writes artifacts under `data/partA/` and `results/partA/`. `--fresh` removes generated Part A data and results but keeps run logs; Part A artifacts from the single-stage design (commit `cc62c12`) are rejected by the evaluation stage, so the first run of the redesigned pipeline must use `--fresh`.
* **`run_partB_pipeline.sh`**: Orchestrates the Part B infectious-population forecasting pipeline using the Part A-selected AR/None and ARX/I configurations and writes artifacts under `data/partB/` and `results/partB/`.
* **`run_partC_pipeline.sh`**: Orchestrates the five-stage Part C Swedish COVID-19 real-data adaptation pipeline and writes artifacts under `data/partC/` and `results/partC/`.
* **`config/partA_config.m`**: Defines the Part A time grid, canonical analytic $R_t$ scenarios A1-A4, SIRS parameters, the development/refinement/assessment dataset design with its random-stream policy, the active and valid model/exogenous-input configurations, the forecasting protocol and candidate grids, recognised forecast-infeasibility identifiers, the one-SE selection rule, artifact snapshots, and output paths.
* **`config/partB_config.m`**: Extends the Part A configuration with five robustness conditions, SEIR/SEIRS truth parameters, SIRS inversion settings, persistence/oracle/AR/ARX forecast methods, the Part A AR/None and ARX/I selection references, the primary and extended matched evaluation sets, the paired method comparisons, and Part B output paths.
* **`config/partC_config.m`**: Defines the WHO COVID-19 source, Sweden study period, renewal estimation, reported-case SIRS state reconstruction, chronological validation, local selection, held-out forecasting, evaluation, visualization, and output paths.

### Execution Scripts

* **`scripts/partA/partA_01_generate_truth.m`**: Generates (or reuses) the role-separated synthetic datasets: periodic development trajectories, the canonical A1-A4 scenarios with random refinement variants, and unused random assessment variants, each simulated with the deterministic SIRS stepper, checked for feasibility, and listed in a dataset manifest.
* **`scripts/partA/partA_02_select_hyperparameters.m`**: Selects the hyperparameters of one model/input combination in three stages: preliminary identification on the development data, cross-scenario validation of the fixed preliminary configuration on A1-A4 (saved as the transfer forecast artifact), and final refinement on A1-A4. Selection uses trajectory-level WIS with stratified standard errors, the one-standard-error rule, and a coefficient-count complexity ranking, and writes the final configuration to the `partA_02_global_hyperparameters_<Model>_<ExoMode>.mat` handover read by Parts B and C.
* **`scripts/partA/partA_03_run_forecasts.m`**: Executes the independent assessment: expanding-window probabilistic $R_t$ forecasts of the final configuration on the unused assessment trajectories, with deterministic SIRS infectious-population projections driven by the median forecast and by $R_t$ persistence.
* **`scripts/partA/partA_04_evaluate_forecasts.m`**: Checks artifact compatibility and selection identities, scores the transfer and assessment forecasts and the deterministic $R_t$ persistence reference with WIS, RMSE, MAE, coverage, and interval width, aggregates them hierarchically (lead, origin, trajectory, scenario family, equal-family global mean), evaluates the infectious-population projections, and exports selection, candidate, trajectory, and feasibility diagnostics under `results/partA/evaluation/` and `results/partA/tables/`.
* **`scripts/partA/partA_05_generate_figures.m`**: Generates the Part A synthetic-validation thesis figures from saved dataset, forecast, and evaluation artifacts, including model-selection diagnostics, preliminary versus final performance on the refinement data, and forecast feasibility.
* **`scripts/partB/partB_01_prepare_datasets.m`**: Generates synthetic SIRS/SEIRS truth and incidence observations under clean baseline, observation noise, process noise, structural mismatch, and combined stress conditions, and reconstructs historical epidemic states and $R_t$ through causal SIRS inversion.
* **`scripts/partB/partB_02_run_forecasts.m`**: Generates infectious-population forecasts from a common estimated SIRS state using persistence, exact future $R_t$ (oracle), and the Part A-selected AR/None and ARX/I configurations refitted to historical estimates, and records forecast-execution outcomes.
* **`scripts/partB/partB_03_evaluate_forecasts.m`**: Scores infectious-population forecasts against synthetic $I(t)$ truth, computes MAE and RMSE on the primary (persistence, oracle, ARX/I) and extended (all four methods) matched-window sets, paired method comparisons, $R_t$-driver errors, degradation relative to the clean baseline, and execution support, and exports evaluation summaries.
* **`scripts/partB/partB_04_generate_figures.m`**: Generates Part B thesis figures summarizing infectious-population trajectories, horizon- and condition-level forecast errors, paired ARX improvement over persistence, extended paired comparisons involving AR/None, and execution support.
* **`scripts/partC/partC_01_prepare_data.m`**: Reads the configured WHO incidence series, estimates operational $R_t$, reconstructs causal reported-case SIRS state proxies, and saves the prepared artifact.
* **`scripts/partC/partC_02_select_local_orders.m`**: Evaluates limited AR/None and ARX/I order neighbourhoods on the calibration block and saves one local-selection artifact per configuration.
* **`scripts/partC/partC_03_run_forecasts.m`**: Generates held-out AR/None and ARX/I forecasts under global online, local online, and global fixed-fit transfer strategies.
* **`scripts/partC/partC_04_evaluate_forecasts.m`**: Scores the held-out forecasts, builds strategy and interval summaries, and exports the Part C evaluation artifact and tables.
* **`scripts/partC/partC_05_generate_figures.m`**: Generates eight Part C thesis figures from prepared-data, held-out forecast, and evaluation artifacts, including comprehensive and focused fixed-lead forecast comparisons.

### Source Code (`src/`)

#### **Scenario functions (`src/scenarios/`)**

* **`generate_rt_signal.m`**: Evaluates the prescribed periodic, seasonal, sigmoid-intervention, and multi-wave effective $R_t$ signals used by Parts A and B.

#### **Epidemic functions (`src/epidemic/`)**

* **`estimate_rt_renewal.m`**: Estimates an operational effective reproduction-number series from incidence and renewal weights.
* **`estimate_sirs_history_from_incidence.m`**: Reconstructs historical SIRS states and effective $R_t$ from daily incidence through causal numerical inversion, recording estimation validity and failures.
* **`reconstruct_sirs_states_from_incidence.m`**: Reconstructs causal susceptible, infectious, and recovered state proxies from reported incidence.
* **`seirs_init.m`**: Prepares a reusable one-day URDME SEIRS stepper for Part B structural-mismatch truth, with optional incidence tracking.
* **`seirs_step.m`**: Advances the reusable effective $R_t$-driven SEIRS stepper by one day and returns entries into the infectious compartment when incidence tracking is enabled.
* **`serial_interval_weights.m`**: Constructs normalized discrete lognormal serial-interval weights from configured arithmetic moments with automatically determined finite numerical support.
* **`sirs_init.m`**: Prepares a reusable one-day URDME SIRS stepper for truth simulation, historical inversion, and forecasting, with optional incidence tracking.
* **`sirs_step.m`**: Advances the reusable effective $R_t$-driven SIRS stepper by one day and returns entries into the infectious compartment when incidence tracking is enabled.

#### **Forecasting functions (`src/forecasting/`)**

* **`build_forecast_windows.m`**: Builds expanding-window forecast entries with matching $R_t$, exogenous-history, SIRS-state, and truth data.
* **`forecast_closed.m`**: Fits exogenous-input ARX or state-space models and propagates closed-loop residual-bootstrap forecasts with SIRS feedback.
* **`forecast_open.m`**: Fits output-only AR or state-space models and propagates residual-bootstrap $R_t$ forecasts.

#### **Scoring functions (`src/scoring/`)**

* **`compute_interval_diagnostics.m`**: Computes per-horizon and per-interval coverage, width, calibration, and interval-score diagnostics.
* **`compute_point_error.m`**: Computes pointwise forecast errors together with RMSE and MAE.
* **`compute_stratified_mean.m`**: Computes the equal-stratum-weight mean of trajectory-level scores and its standard error, treating canonical trajectories as fixed design points.
* **`compute_wis.m`**: Computes per-horizon weighted interval scores and their optional components.

#### **Visualization functions (`src/visualization/`)**

* **`apply_panel_style.m`**: Applies shared thesis panel styling to caller-supplied axes.
* **`plot_distribution.m`**: Draws grouped boxchart distributions and applies shared panel styling.
* **`plot_series.m`**: Draws ordered line, interval-ribbon, and reference series and applies shared panel styling.
