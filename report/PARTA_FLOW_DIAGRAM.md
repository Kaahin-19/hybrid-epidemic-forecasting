# Part A: Synthetic Validation Pipeline Flow Diagram

## Overview
Part A validates the hybrid epidemic forecasting framework using synthetic SIRS ground truth under controlled analytic effective reproduction number (R_t) scenarios. The pipeline progresses through five sequential stages: truth generation, model selection, forecasting, evaluation, and visualization.

---

## Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PART A SYNTHETIC VALIDATION                         │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌──────────────────────┐
                              │  partA_config.m      │
                              │  (Configuration)     │
                              │                      │
                              │  • Time grid (tspan) │
                              │  • R_t scenarios (4) │
                              │  • SIRS parameters   │
                              │  • Model settings    │
                              │  • Forecast horizon  │
                              └──────┬───────────────┘
                                     │
                    ┌────────────────┴────────────────┐
                    │                                 │
         ┌──────────▼──────────┐         ┌───────────▼────────────┐
         │   SCENARIO DATA     │         │   MODEL CONFIGURATION  │
         │                     │         │                        │
         │ • Seasonal R_t      │         │ • AR, ARX, N4SID, SSEST│
         │ • Sigmoid R_t       │         │ • Order grids (p, d, q)│
         │ • Multi-wave R_t    │         │ • Exogenous inputs (Y) │
         │ • Constant R_t      │         │ • Calibration settings │
         └──────────┬──────────┘         └───────────┬────────────┘
                    │                                 │
                    │                                 │
        ┌───────────▼─────────────────────────────────▼────────┐
        │           STAGE 1: SYNTHETIC TRUTH GENERATION         │
        │        (partA_01_generate_synthetic_truth.m)          │
        ├──────────────────────────────────────────────────────┤
        │  Input:   config, R_t scenarios, SIRS parameters      │
        │  Process: For each scenario:                          │
        │           1. Generate analytic R_t(t) trajectory      │
        │           2. Simulate SIRS ground truth (URDME)       │
        │           3. Extract state trajectory & metrics       │
        │  Output:  Truth artifacts (4 × .mat files)            │
        │           └─ data/partA/partA_01_truth_A*.mat         │
        └────────────────┬──────────────────────────────────────┘
                         │
                         │ [Truth data: S(t), I(t), R(t), R_t(t)]
                         │
        ┌────────────────▼──────────────────────────────────────┐
        │     STAGE 2: MODEL SELECTION & HYPERPARAMETER TUNING   │
        │    (partA_02_select_global_model_configurations.m)     │
        ├──────────────────────────────────────────────────────┤
        │  Input:   Truth artifacts, model candidate grid       │
        │  Process: For each candidate configuration:           │
        │           1. Cross-scenario expanding-window fitting  │
        │           2. Forecast on holdout test windows         │
        │           3. Compute Weighted Interval Score (WIS)    │
        │           4. Aggregate WIS across all scenarios       │
        │           5. Select best config per model family      │
        │  Output:  Selected configurations (4 × .mat)          │
        │           └─ results/partA/model_selection/           │
        │             partA_02_selected_config_*.mat            │
        └────────────────┬──────────────────────────────────────┘
                         │
                         │ [Best hyperparams: p, d, q, λ, calibration]
                         │
        ┌────────────────▼──────────────────────────────────────┐
        │        STAGE 3: EXPANDING-WINDOW FORECASTING          │
        │           (partA_03_run_forecasts.m)                  │
        ├──────────────────────────────────────────────────────┤
        │  Input:   Truth artifacts, selected configurations    │
        │  Process: For each scenario & model:                  │
        │           1. Build expanding-window forecast dataset  │
        │           2. For each window:                         │
        │              • Fit model on historical [0, t_w]       │
        │              • Project covariate (epidemic state)     │
        │              • Forecast R_t & compute prediction      │
        │              • Simulate ensemble (bootstrap/MC)       │
        │              • Compute intervals from ensemble        │
        │           3. Aggregate predictions & intervals        │
        │  Output:  Forecast artifacts (4×4 scenarios×models)   │
        │           └─ results/partA/forecasts/                 │
        │             partA_03_forecast_*.mat                   │
        └────────────────┬──────────────────────────────────────┘
                         │
                         │ [Forecast data: point, lower CI, upper CI]
                         │
        ┌────────────────▼──────────────────────────────────────┐
        │            STAGE 4: FORECAST EVALUATION               │
        │          (partA_04_evaluate_forecasts.m)              │
        ├──────────────────────────────────────────────────────┤
        │  Input:   Truth & forecast artifacts                  │
        │  Process: For all forecasts:                          │
        │           1. Compute WIS (Weighted Interval Score)    │
        │           2. Decompose WIS components:                │
        │              • Median error                           │
        │              • Dispersion (interval width)            │
        │              • Underprediction penalty                │
        │              • Overprediction penalty                 │
        │           3. Compute point-forecast metrics:          │
        │              • RMSE, MAE (on median)                  │
        │           4. Compute interval metrics:                │
        │              • Coverage (% predictions in bounds)     │
        │              • Interval width statistics              │
        │           5. Aggregate by scenario, horizon, model    │
        │           6. Generate summary tables (CSV)            │
        │  Output:  Evaluation artifact (.mat)                  │
        │           └─ results/partA/evaluation/                │
        │             partA_04_evaluation.mat                   │
        │           Summary tables (.csv)                       │
        │           └─ results/partA/tables/                    │
        │             wis_summary.csv, components.csv, etc.     │
        └────────────────┬──────────────────────────────────────┘
                         │
                         │ [Scores: WIS, RMSE, MAE, Coverage, Width]
                         │
        ┌────────────────▼──────────────────────────────────────┐
        │         STAGE 5: FIGURE GENERATION & REPORTING        │
        │           (partA_05_generate_figures.m)               │
        ├──────────────────────────────────────────────────────┤
        │  Input:   Truth, model-selection, forecast,           │
        │           evaluation artifacts, & table outputs        │
        │  Process: Generate comprehensive figures:             │
        │           1. Truth trajectories per scenario          │
        │           2. Model selection convergence curves       │
        │           3. Forecast vs. truth comparison plots      │
        │           4. Prediction interval visualizations       │
        │           5. WIS & component score comparisons        │
        │           6. Performance metrics heatmaps             │
        │           7. Coverage & interval-width distributions  │
        │  Output:  Publication-quality figures                 │
        │           └─ results/partA/figures/                   │
        │             *_scenario_*.pdf, *_model_*.pdf, etc.     │
        └──────────────────────────────────────────────────────┘
                         │
                         │ [Final analysis: visuals for thesis]
                         │
                    ┌────▼─────────────────────────────┐
                    │   PART A VALIDATION COMPLETE      │
                    │                                   │
                    │ • 4 scenarios validated          │
                    │ • 4 model families tested        │
                    │ • Cross-scenario tuning          │
                    │ • Interval performance assessed   │
                    └────────────────────────────────────┘
```

---

## Detailed Data Flow

### Stage 1: Truth Generation
```
partA_config.m
    ↓
generate_rt_signal.m (4 scenarios)
    ├─ R_t(t) = seasonal (A1)
    ├─ R_t(t) = sigmoid ramp (A2)
    ├─ R_t(t) = multi-wave (A3)
    └─ R_t(t) = constant (A4)
    ↓
simulate_ground_truth_epidemic.m (URDME SIRS)
    ├─ S(t), I(t), R(t) trajectories
    ├─ Effective transmission rates λ(t) = R_t(t) × γ
    └─ Deterministic simulations with configured SIRS parameters
    ↓
Save: data/partA/partA_01_truth_A1.mat
       data/partA/partA_01_truth_A2.mat
       data/partA/partA_01_truth_A3.mat
       data/partA/partA_01_truth_A4.mat
```

### Stage 2: Model Selection
```
Truth artifacts (4 × .mat)
    ↓
generate_candidate_grid.m
    ├─ AR(p) candidates (p ∈ [1, 10])
    ├─ ARX(p, d) candidates (p ∈ [1, 10], d ∈ [0, 1])
    ├─ N4SID orders (p ∈ [1, 5])
    └─ SSEST orders (p ∈ [1, 5])
    ↓
For each candidate:
    evaluate_candidate.m (cross-scenario expanding-window validation)
        ├─ Fit on scenario 1, 2, 3 (aggregated)
        ├─ Test on scenario 1, 2, 3 (holdout windows)
        ├─ Compute WIS per scenario
        └─ Store WIS metrics
    ↓
aggregate_candidate_scores.m
    └─ Compute mean WIS across all scenarios
    ↓
select_best_configuration.m
    ├─ AR_best: minimize mean WIS
    ├─ ARX_best: minimize mean WIS
    ├─ N4SID_best: minimize mean WIS
    └─ SSEST_best: minimize mean WIS
    ↓
Save: results/partA/model_selection/
      partA_02_selected_config_ar.mat
      partA_02_selected_config_arx.mat
      partA_02_selected_config_n4sid.mat
      partA_02_selected_config_ssest.mat
```

### Stage 3: Expanding-Window Forecasting
```
Truth artifacts + Selected configurations
    ↓
For each scenario & model:
    build_forecasting_dataset.m
        └─ Expanding windows: [0, t1], [0, t2], ..., [0, t_final]
    ↓
    For each window w:
        prepare_window_data.m
            ├─ Historical R_t: [0, t_w]
            ├─ Causal covariates (S, I): [t_w, t_w + h]
            └─ Ground truth for validation
        ↓
        run_model_forecast.m
            ├─ Fit model on historical R_t
            ├─ Project covariates forward (epidemic state)
            ├─ Generate point forecast (median)
            ├─ Simulate ensemble (500 paths):
            │   ├─ AR: residual bootstrap
            │   ├─ ARX: closed-loop bootstrap with SIRS
            │   ├─ N4SID: state-space Gaussian sampling
            │   └─ SSEST: state-space Gaussian sampling
            └─ Extract intervals: [q_0.025, q_0.975]
        ↓
        Store forecast (point, lower, upper)
    ↓
Aggregate forecasts per (scenario, model) pair
    ↓
Save: results/partA/forecasts/
      partA_03_forecast_ar_A1.mat
      partA_03_forecast_ar_A2.mat
      ...
      partA_03_forecast_ssest_A4.mat
```

### Stage 4: Evaluation
```
Truth artifacts + Forecast artifacts
    ↓
For each forecast:
    compute_wis.m
        └─ WIS = α × |median - truth| 
               + (upper - lower)
               + penalties for bounds violation
    ↓
    compute_wis_components.m
        ├─ Median component: α × |median - truth|
        ├─ Dispersion: (upper - lower)
        ├─ Underprediction: penalty if truth > upper
        └─ Overprediction: penalty if truth < lower
    ↓
    compute_rmse.m → RMSE(median)
    compute_mae.m → MAE(median)
    compute_coverage.m → % in [lower, upper]
    compute_interval_width.m → width stats
    ↓
Aggregate by (scenario, horizon, model, exogenous-mode, calibration)
    ↓
summarize_forecast_scores.m
    ├─ WIS by scenario, horizon, model
    ├─ Components by scenario, model
    ├─ RMSE, MAE, coverage
    └─ Interval width summary
    ↓
Save: results/partA/evaluation/partA_04_evaluation.mat
      results/partA/tables/wis_summary.csv
      results/partA/tables/components_summary.csv
      results/partA/tables/rmse_mae_summary.csv
      results/partA/tables/coverage_summary.csv
      results/partA/tables/interval_width_summary.csv
```

### Stage 5: Visualization
```
All artifacts (truth, selection, forecasts, evaluation, tables)
    ↓
partA_05_generate_figures.m
    ├─ For each scenario:
    │   ├─ Subplot: truth trajectory with model predictions
    │   ├─ Subplots: forecast vs. truth for each model
    │   ├─ Subplots: prediction intervals from 4 models
    │   └─ Save: results/partA/figures/
    │
    ├─ Model selection convergence plots
    │   └─ WIS vs. candidate order for each model family
    │
    ├─ Performance metric heatmaps
    │   ├─ WIS by scenario & model
    │   ├─ Components decomposition
    │   ├─ Coverage by horizon & model
    │   └─ Interval width by horizon & model
    │
    └─ Comparative figures
        ├─ All models on single scenario
        ├─ Box plots: WIS/RMSE/MAE distributions
        └─ Sensitivity analysis by horizon
    ↓
Output: results/partA/figures/*.pdf
```

---

## Key Parameters & Configurations

| Parameter | Source | Purpose |
|-----------|--------|---------|
| Time span (tspan) | `partA_config.m` | Shared time grid for all scenarios |
| R_t scenarios | `generate_rt_signal.m` | 4 analytic trajectories (A1–A4) |
| SIRS parameters | `partA_config.m` | μ, ν, N (γ = recovery rate, ξ = waning rate) |
| Model orders | `generate_candidate_grid.m` | AR/ARX: p ∈ [1,10], d ∈ [0,1]; SS: p ∈ [1,5] |
| Window settings | `build_forecasting_dataset.m` | Expanding windows, training horizon |
| Forecast horizon | `partA_config.m` | h = 14 days (default) |
| Calibration method | `make_interval_options.m` | Residual bootstrap (AR/ARX), Gaussian (N4SID/SSEST) |
| Interval level | `partA_config.m` | [0.025, 0.975] (95% credible intervals) |
| WIS weight (α) | `compute_wis.m` | 1.0 (standard scoring rule) |

---

## Output Artifact Organization

```
results/partA/
├── model_selection/
│   ├── partA_02_selected_config_ar.mat
│   ├── partA_02_selected_config_arx.mat
│   ├── partA_02_selected_config_n4sid.mat
│   └── partA_02_selected_config_ssest.mat
│
├── forecasts/
│   ├── partA_03_forecast_ar_A1.mat
│   ├── partA_03_forecast_ar_A2.mat
│   ├── partA_03_forecast_ar_A3.mat
│   ├── partA_03_forecast_ar_A4.mat
│   ├── partA_03_forecast_arx_A1.mat
│   ├── ... (16 total: 4 scenarios × 4 models)
│   └── partA_03_forecast_ssest_A4.mat
│
├── evaluation/
│   └── partA_04_evaluation.mat
│
├── tables/
│   ├── wis_summary.csv
│   ├── components_summary.csv
│   ├── rmse_mae_summary.csv
│   ├── coverage_summary.csv
│   └── interval_width_summary.csv
│
└── figures/
    ├── part_a_scenario_A1_truth_and_predictions.pdf
    ├── part_a_scenario_A1_detailed_forecasts.pdf
    ├── ... (scenario-specific figures)
    ├── part_a_model_selection_convergence.pdf
    ├── part_a_wis_heatmap.pdf
    ├── part_a_components_heatmap.pdf
    ├── part_a_coverage_by_horizon.pdf
    ├── part_a_interval_width_by_horizon.pdf
    └── ... (summary & comparison figures)

data/partA/
├── partA_01_truth_A1.mat
├── partA_01_truth_A2.mat
├── partA_01_truth_A3.mat
└── partA_01_truth_A4.mat
```

---

## Execution Command

```bash
# Run all 5 stages in sequence
bash run_partA_pipeline.sh
```

Or run individual stages:

```bash
# Stage 1: Generate synthetic truth
matlab -r "partA_01_generate_synthetic_truth; exit;"

# Stage 2: Select global model configurations
matlab -r "partA_02_select_global_model_configurations; exit;"

# Stage 3: Run expanding-window forecasts
matlab -r "partA_03_run_forecasts; exit;"

# Stage 4: Evaluate forecasts
matlab -r "partA_04_evaluate_forecasts; exit;"

# Stage 5: Generate figures
matlab -r "partA_05_generate_figures; exit;"
```

---

## Validation Checkpoints

After each stage, verify:

| Stage | Artifact | Check |
|-------|----------|-------|
| 1 | `data/partA/partA_01_truth_A*.mat` | 4 files present; S, I, R, R_t fields exist |
| 2 | `results/partA/model_selection/*.mat` | 4 config files; scores computed and minimized |
| 3 | `results/partA/forecasts/partA_03_*.mat` | 16 files (4 models × 4 scenarios); forecasts are finite |
| 4 | `results/partA/evaluation/partA_04_*.mat` | Single eval file; metrics are finite; CSVs readable |
| 5 | `results/partA/figures/*.pdf` | Figures render; titles, labels, legends present |

---

## Notes

- **SIRS Model**: Ground truth uses URDME with effective R_t trajectories; no external forcing beyond R_t.
- **SIR Special Case**: Set `cfg.sirs.xi = 0` (waning immunity rate) to collapse SIRS to SIR.
- **Exogenous Input**: ARX uses causal epidemic-state covariates (S, I, derived infection proxy).
- **Closed-Loop Feedback**: ARX covariate projection uses URDME stepping to maintain consistency with truth.
- **Residual Bootstrap**: AR/ARX use one-step residual resampling; SSM use Gaussian ensemble.
- **Calibration**: Window-specific calibration applied post-simulation to match empirical coverage targets.
- **No Overlap**: Stages 1–3 produce artifacts only; Stage 4 performs evaluation; Stage 5 produces figures.
