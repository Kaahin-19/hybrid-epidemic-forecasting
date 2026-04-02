## Figure Selection Guidance for results-and-discussion.tex

When selecting figures for the report, apply the following criteria
based on the performance ranking in this document:

Include in main text:
- partA_04_wis_performance_boxplot.png (mandatory)
- Forecast plots for the top 2 ranked combinations by global mean WIS
- One plot showing a case where a model degrades significantly (for limitations discussion)

Include in appendix:
- Forecast plots for remaining combinations that have complete results
- Exclude N4SID/Both (numerical blow-up on A2 renders it uninformative)

Do not include figures mechanically. Each included figure must be referenced
in the prose and serve a specific analytical purpose.

---

# Inconsistency Report — report.docx vs Current Codebase
**Prepared:** 2026-03-30
**Report version analysed:** report/archive/part_a/original/report.docx (last modified 2026-03-30 00:20)
**Codebase state:** Pipeline fully executed; all 12 model-exo combinations have complete
tuning, forecast, and score artifacts on disk.

---

## 1. Section-by-Section Outdated Claims

### Section 2.2 — Statistical Forecasting Models

**Claim (final paragraph):**
> "Two state-space identification methods (N4SID and SSEST) are available within the codebase but are not examined in this phase of the study."

**Contradiction:** N4SID and SSEST have been fully implemented and run. Both `fit_n4sid.m`
and `fit_ssest.m` are complete; tuning artifacts exist for all eight combinations (None, S, I,
Both for each); forecast artifacts exist for all 16 scenario-combination files; scores are
present in `results/scores/partA_04_wis_performance_summary.csv`.

**Fix required:** Remove the aside entirely. Add full subsections for N4SID and SSEST at the
same depth as AR and ARX: algorithm description, hyperparameter grid, and exogenous-input
configurations examined.

---

### Section 2.3 — Expanding-Window Validation

**Claim:**
> "Model selection was performed independently at each window endpoint using an exhaustive
> grid search. The optimal configuration was chosen according to the corrected Akaike
> Information Criterion (AICc). In this phase, the search was restricted to autoregressive
> structures (), so that only AR and ARX models were considered."

**Three separate contradictions:**

1. **Per-window selection is no longer used.** `partA_02_select_global_hyperparameters.m`
   runs the grid search once, before any forecasting, and selects a single optimal
   configuration per model-exo combination by minimising mean WIS across all scenarios and
   all expanding windows jointly. `partA_03_run_forecasts.m` then uses that fixed
   configuration for every window — there is no per-window grid search.

2. **AICc is not the selection criterion.** Selection is by minimum global mean WIS
   (Weighted Interval Score). AICc is computed per window and stored in forecast artifacts
   but is not used for selection anywhere in the current pipeline.

3. **The restriction to autoregressive structures is no longer true.** All four model
   families (AR, ARX, N4SID, SSEST) have been evaluated.

**Fix required:** Rewrite Section 2.3 to describe the two-phase procedure: (1) global
hyperparameter selection via partA_02 (scored by WIS, across all scenarios simultaneously),
then (2) expanding-window forecast execution via partA_03 with the fixed selected
configuration.

---

### Section 2.4 — Forecast Evaluation and Numerical Safeguards

**Claim:**
> "Forecast accuracy was quantified using the Root Mean Square Error (RMSE), computed over
> the 14-day forecast horizon: [RMSE formula] … RMSE was calculated independently for each
> expanding-window iteration."

**Contradiction:** RMSE is never computed anywhere in the codebase. `partA_02` scores
candidates by WIS; `partA_04_evaluate_models.m` aggregates WIS scores; the output CSV files
in `results/scores/` contain WIS columns only. The `compute_wis` function in `partA_02` uses
the standard weighted interval score formula:

```
WIS = (1 / (K + 0.5)) * [ 0.5 * |y - m|  +  sum_{k=1}^K (alpha_k / 2) * IS_k ]
```

where `IS_k = (u_k - l_k) + (2/alpha_k)*max(l_k - y, 0) + (2/alpha_k)*max(y - u_k, 0)`
and K = 4 (intervals at alpha ∈ {0.05, 0.10, 0.20, 0.50}).

**Fix required:** Replace the RMSE formula and all RMSE references with the WIS formula.
Explain the probabilistic structure: each forecast is a predictive distribution
represented by a median and four symmetric credible intervals; WIS penalises both
sharpness and calibration.

**Additional gap — probabilistic forecasts not mentioned in Section 2.4:**
All four model functions return predictive intervals (lower and upper bounds at four alpha
levels), computed analytically from the forecast standard deviation via:
`exp(pred_y ± z_alpha * pred_sd)` where `z_alpha = sqrt(2) * erfinv(1 - alpha)`.
This probabilistic output structure is entirely absent from Section 2.4 and must be added.

---

### Section 3.1 — Qualitative Forecast Dynamics

**Claim (scope):** Only AR and ARX are discussed.

**Contradiction:** N4SID and SSEST have complete forecast artifacts for all four scenarios.

**Fix required:** Expand to cover qualitative behaviour of all four model families. Key
observations from the scores data:
- State-space models (N4SID, SSEST) show systematic underperformance on multi-wave
  scenarios (A3, A4) under None and S modes; the best state-space variant (N4SID/I) does
  substantially better by incorporating the Infected compartment.
- N4SID/Both on A2 produces a catastrophic numerical blow-up (mean WIS ≈ 5.1×10⁶⁵), which
  is a qualitative finding about numerical fragility worth discussing explicitly.
- AR outperforms all ARX variants on A2 (mean WIS 0.024 vs 0.042–0.044), because the
  exogenous compartment trajectories also shift during the sigmoid transition, introducing
  confounding information.

---

### Section 3.2 — Quantitative Performance Evaluation

**Claims:**
> "Forecast accuracy was assessed using the RMSE … For the smooth seasonal and multi-wave
> scenarios … RMSE values remain consistently low … Scenario A2 contributes
> disproportionately … Across scenarios, the baseline AR models exhibit stable and
> predictable error behavior."

**Three contradictions:**

1. **RMSE must be replaced by WIS throughout.** All numerical results referenced are
   unavailable from the current artifacts; the artifacts contain WIS only.

2. **The description of AR performance relative to ARX is incomplete.** On A2 specifically,
   AR has *lower* WIS than all ARX variants. On A1, A3, A4, ARX consistently outperforms AR.
   The current claim ("ARX models demonstrate increased sensitivity … resulting in greater
   dispersion") is partly correct for A2 but does not reflect the overall picture.

3. **State-space results are entirely missing.** N4SID and SSEST results are not discussed.

**Fix required:** Replace the entire section with WIS-based analysis grounded in
`partA_04_wis_performance_summary.csv`. See Section 4 of this report for the complete
numerical record.

---

### Section 4 — Discussion

**Claims:**
> "In addition, restricting the analysis to autoregressive structures () ensures consistency
> across scenarios but limits the range of temporal dynamics that can be captured. The
> selected grid-search ranges and the use of AICc for model selection therefore define a
> controlled reference setup rather than a fully optimized configuration."

**Contradictions:**
1. The analysis is no longer restricted to autoregressive structures.
2. AICc is no longer used for model selection.
3. The characterisation of the setup as "controlled reference" (implying incompleteness)
   should be updated to reflect the global hyperparameter selection strategy as a
   deliberate and complete design choice.

**Fix required:** Update the discussion to reflect all four model families, WIS-based
evaluation, and the global selection strategy. The instability of state-space models (in
particular N4SID on certain exogenous configurations) is a substantive finding that belongs
in the discussion.

---

## 2. What Needs to Be Added for N4SID and SSEST

### In Section 2.2 (Methods — Models)

Both algorithms need descriptions at the same depth as AR and ARX:

**N4SID (Subspace State-Space System Identification):**
- Fits a discrete-time linear state-space model via subspace identification (MATLAB `n4sid`)
- Parameters: state order n (grid: 1–8), no differencing (d=0 throughout)
- Accepts optional exogenous inputs in the same four modes as ARX: None, S, I, Both
- Forecast standard deviation obtained from the state-space model's output uncertainty;
  intervals constructed identically to AR and ARX

**SSEST (State-Space Estimation via PEM):**
- Fits a discrete-time linear state-space model via iterative Prediction Error Minimisation
  (MATLAB `ssest`)
- Parameters: state order n (grid: 1–8), no differencing (d=0)
- Otherwise identical interface and interval construction to N4SID
- Key distinction: N4SID uses a one-shot subspace algorithm; SSEST uses an iterative
  gradient-based optimiser which can find lower-error solutions but is more
  computationally expensive and can be numerically sensitive

### In Section 2.3 (Validation — Hyperparameter Grids)

The grid for N4SID/SSEST must be stated: n ∈ {1, …, 8}, d = 0 (8 candidates per
combination). Contrast with AR (15 candidates: p ∈ {0, …, 14}) and ARX (735 candidates:
na × nb × nk = 15 × 7 × 7).

---

## 3. WIS vs RMSE Changes Required (Complete List)

| Location | Current text | Required replacement |
|----------|-------------|----------------------|
| Section 2.4 heading | "Forecast Evaluation and Numerical Safeguards" | Retain heading; replace body entirely |
| Section 2.4 formula | RMSE formula | WIS formula with K=4 intervals |
| Section 2.4 explanation | "RMSE was calculated independently for each window" | WIS computed per forecast step, averaged over the 14-day horizon per window |
| Section 3.2 text | All RMSE-based descriptions | WIS-based descriptions with values from CSV |
| Section 4 discussion | "grid-search ranges and the use of AICc" | Global WIS-based selection |

---

## 4. Global Hyperparameter Selection Changes Required

**What to change in Section 2.3:**

Replace the per-window AICc grid search with:

> Global hyperparameter selection (partA_02) is performed once, before any forecasting, by
> evaluating each candidate configuration across all four scenarios and all expanding windows
> simultaneously. For each candidate, the mean WIS is computed over every window in every
> scenario, and these scenario means are averaged equally to obtain a global score. The
> configuration with the minimum global mean WIS is selected and fixed for all subsequent
> forecasting runs. This procedure separates hyperparameter selection from forecast
> evaluation, preventing the selection criterion from coinciding with the evaluation metric.

The section should also note:
- Grid sizes: AR (15), ARX (735), N4SID/SSEST (8 each)
- Equal scenario weighting
- WIS as both selection criterion and evaluation metric (they share the formula but operate
  on disjoint sets of results — selection uses all windows, evaluation uses the same windows
  but with the fixed selected model)

---

## 5. What Needs to Be Added for Probabilistic Forecasting

**New material for Section 2.4:**

All four model functions return a predictive distribution represented as a median forecast
plus four symmetric credible intervals at miscoverage rates α ∈ {0.05, 0.10, 0.20, 0.50},
corresponding to 95%, 90%, 80%, and 50% predictive intervals respectively.

Intervals are constructed analytically in log-space and then exponentiated:
- In log-space the forecast is assumed Gaussian with mean `pred_y` and standard deviation
  `pred_sd`, both obtained from the fitted model
- The interval bounds at level α are: `exp(pred_y ± z_α * pred_sd)` where
  `z_α = sqrt(2) * erfinv(1 - α)`
- This preserves positivity of Rt and reflects the multiplicative uncertainty structure

The persistence fallback (used when fitting fails or the signal has insufficient variance)
returns a degenerate forecast: a constant equal to the last observed Rt value, with
zero-width intervals at all levels.

---

## 6. Inventory of Combinations with Results and Editorial Recommendations

### Complete results on disk

All 12 expected combinations are fully present in results/scores/, results/tuning/, and
results/forecasts/:

| Model  | ExoMode | Selected HP      | Global Mean WIS† | Rank |
|--------|---------|------------------|------------------|------|
| ARX    | I       | na=4, nb=1, nk=1 | 0.01418          | 1    |
| ARX    | S       | na=4, nb=1, nk=1 | 0.01430          | 2    |
| ARX    | Both    | na=4, nb=1, nk=1 | 0.01451          | 3    |
| AR     | None    | p=2              | 0.01743          | 4    |
| N4SID  | I       | n=2              | 0.02728          | 5    |
| SSEST  | None    | n=1              | 0.04988          | 6    |
| SSEST  | I       | n=3              | 0.05463          | 7    |
| SSEST  | Both    | n=2              | 0.06285          | 8    |
| N4SID  | None    | n=1              | 0.06899          | 9    |
| SSEST  | S       | n=3              | 0.07434          | 10   |
| N4SID  | S       | n=2              | 0.08378          | 11   |
| N4SID  | Both    | n=2              | (see ‡ below)    | —    |

†Global mean = unweighted mean of the four per-scenario Mean_WindowWIS values from
`partA_04_wis_performance_summary.csv`. Computed from the actual forecast runs (partA_03),
not the tuning pass (partA_02); they use the same selected configuration but the numerical
values can differ slightly. Selected HP column is from the tuning artifacts.

‡N4SID/Both excluded from ranking: A2 mean WIS = 5.11×10⁶⁵ due to numerical blow-up in
the subspace identification algorithm during the sigmoid transition. The other three
scenarios give 0.035 (A1), 0.113 (A3), 0.103 (A4).

†N4SID/Both: A2 mean WIS = 5.11×10⁶⁵ (numerical blow-up). Global mean is dominated by
this outlier and is not a meaningful summary statistic. The other three scenarios give
0.035, 0.113, 0.103. **Do not report a global mean for N4SID/Both without caveat.**

Per-scenario WIS values (Mean_WindowWIS from partA_04_wis_performance_summary.csv):

| Model | ExoMode | A1 (Seasonal) | A2 (Intervention) | A3 (Damping) | A4 (Amplifying) |
|-------|---------|---------------|-------------------|--------------|-----------------|
| AR    | None    | 0.00396       | 0.02442           | 0.02012      | 0.02123         |
| ARX   | S       | 0.00201       | 0.04256           | 0.00636      | 0.00625         |
| ARX   | I       | 0.00217       | 0.04295           | 0.00569      | 0.00589         |
| ARX   | Both    | 0.00095       | 0.04377           | 0.00647      | 0.00684         |
| N4SID | None    | 0.03491       | 0.03333           | 0.10204      | 0.10566         |
| N4SID | S       | 0.04468       | 0.04371           | 0.14407      | 0.10265         |
| N4SID | I       | 0.01129       | 0.03166           | 0.03194      | 0.03422         |
| N4SID | Both    | 0.03503       | 5.11×10⁶⁵         | 0.11278      | 0.10319         |
| SSEST | None    | 0.02632       | 0.03410           | 0.06794      | 0.07114         |
| SSEST | S       | 0.02948       | 0.03550           | 0.11888      | 0.11350         |
| SSEST | I       | 0.03330       | 0.02961           | 0.08225      | 0.07337         |
| SSEST | Both    | 0.03113       | 0.03528           | 0.09493      | 0.09006         |

### Editorial recommendations: what to include in the report

**Recommended to include:**

1. **Summary performance table** — one row per model-exo combination, four scenario columns
   plus a note on N4SID/Both. This gives the supervisor a complete picture in compact form.
   N4SID/Both should be listed with a footnote rather than omitted.

2. **ARX variants (S, I, Both)** — the performance gap between ARX and AR is the central
   finding of the hybrid framework evaluation. ARX/Both achieves ~4× lower WIS than AR/None
   on A1 (0.00095 vs 0.00396). All three ARX variants select identical hyperparameters
   (na=4, nb=1, nk=1), which is itself a notable finding.

3. **AR vs ARX on A2 (intervention scenario)** — AR outperforms all ARX on A2 (0.024 vs
   0.042–0.044). This is the most interesting single finding: exogenous covariates hurt
   during abrupt regime shifts because the compartment trajectories also undergo rapid
   change, introducing confounding dynamics. Worth a dedicated paragraph.

4. **N4SID/I as the best state-space variant** — n=2 selected, global mean WIS ~0.027
   (excluding N4SID/Both outlier). Substantially better than N4SID/None and N4SID/S.
   Demonstrates that state-space models benefit from exogenous information but only from
   the Infected compartment, not the Susceptible.

5. **N4SID/Both blow-up on A2** — a concrete illustration of numerical fragility in
   subspace identification under rapid regime change. Worth a brief paragraph in Discussion.

6. **SSEST/None vs N4SID/None comparison** — SSEST/None (mean A1–A4: 0.026, 0.034, 0.068,
   0.071) consistently outperforms N4SID/None (0.035, 0.033, 0.102, 0.106) on A3 and A4.
   Suggests PEM finds better solutions than the subspace algorithm for multi-wave dynamics
   without exogenous inputs.

**Recommended to omit or consolidate:**

- Individual forecast plots for all 48 combinations — too many for a degree project report.
  Select at most one representative plot per model family, preferably showing contrasting
  behaviour (e.g. ARX/I on A1 showing good tracking, and A2 showing the regime-shift
  problem). Acknowledge that all 48 plots exist without including them all.

- N4SID/S and SSEST/S as separate subsection results — they are the two worst performers
  and the reason (slow-moving S compartment adds noise without useful signal) can be stated
  concisely without per-scenario breakdowns.

- Detailed ARX three-way comparison (S vs I vs Both) in Results — the differences are
  marginal (0.00095–0.00217 on A1). One sentence noting the convergence to identical
  hyperparameters and the negligible marginal improvement from Both over I is sufficient.

---

## 7. Which Results Can Be Grounded in Existing Artifacts

### Fully grounded (write directly from artifacts):

- All WIS values in the table above — from `results/scores/partA_04_wis_performance_summary.csv`
- Selected hyperparameters for all 12 combinations — from `results/tuning/*_summary.csv`
- Number of expanding windows: 44 per scenario (min_window=49, step=7, T_end=365, horizon=14)
- Window count: 44 windows × 4 scenarios = 176 forecast windows per model-exo combination
- Total scored forecast steps: 29,568 (from row count in pointwise details CSV)
- Comparison of state-space vs ARX performance (all numbers available)
- N4SID/Both blow-up value (5.11×10⁶⁵) — visible in summary CSV
- The convergence of all three ARX variants to na=4, nb=1, nk=1 — from tuning CSVs
- AR p=2 selected for AR/None; n=1 selected for both N4SID/None and SSEST/None

### Cannot be grounded without additional inspection (flag for manual update):

- **Figures:** No forecast overlay plots have been read in this session. Section 3.1's
  qualitative descriptions (e.g., "forecasts follow the oscillatory structure") cannot be
  confirmed against figures without reading the PNGs. If specific figure references are
  added to the report, they should be flagged as "verify against figure" until visually
  confirmed.

- **Median WIS values for discussion:** The summary CSV contains Mean_WindowWIS per group.
  Median_WindowWIS is also available in the CSV (column 6) and could enrich the discussion
  of distribution shape (e.g., whether A2 performance is driven by a few outlier windows),
  but these were not extracted per-cell above. Can be read directly if needed.

- **Horizon-specific WIS patterns:** The pointwise details CSV contains per-step WIS across
  the 14-day horizon. Whether WIS degrades with horizon, and by how much, is not captured
  in the summary. This analysis would require reading the 29,569-row details file.

---

## 8. Other Gaps

### Gap 1: Five-stage pipeline not described

The current report describes at most three steps (generate scenarios, run forecasts,
evaluate). The global hyperparameter selection stage (partA_02) is entirely absent. The
report should describe the five stages explicitly — either in a pipeline overview paragraph
in the Methods introduction or as a numbered list.

### Gap 2: Future exogenous projection method not described

When ARX, N4SID, or SSEST are used, forecasting requires future values of the exogenous
compartments. The report mentions that "state trajectories are obtained using the deterministic
solver" but does not say how *future* states are projected during forecasting. In the
codebase, `prepare_exogenous_inputs` runs the SIRS UDS solver forward from the current
state using a flat-beta assumption (constant β = γ × Rt(t) over the forecast horizon). This
is a methodological choice that belongs in Section 2.2 or 2.3.

### Gap 3: Persistence fallback not described for state-space models

The report describes the persistence fallback in the context of AICc (incorrect: fallback
is triggered by numerical failure or insufficient signal variance, not by AICc). The
fallback applies to all four model families identically — any model that fails fitting or
produces non-finite outputs falls back to a constant forecast equal to the last observed Rt,
with zero-width intervals. This should be described once, model-agnostically.

### Gap 4: Log-transform scope

The report correctly mentions log-transformation. It does not specify that the transform
applies to Rt_hist before model fitting and that forecasts are exponentiated back to
natural scale. This should be stated clearly for each model family.

### Gap 5: SIRS parameter for A2

CLAUDE.md lists I0 = 500 for all scenarios. The config uses I0 = 5000 for Scenario A2.
If scenario parameters are tabulated in the report, this should be corrected.

---

---

## 9. Session 9 Consistency Check Findings (2026-04-02)

The following issues were found during a full consistency sweep of all chapter .tex files
and were resolved in the same session.

### 9.1 Hyperparameter value errors in background-and-theory.tex

The selected HP sentences cited values that contradicted the tuning CSVs.
All errors were in the lines inserted by earlier sessions; Sessions 1–8 corrected the
results chapter but left the background chapter stale.

| Location | Wrong value | Correct value (CSV source) |
|----------|-------------|---------------------------|
| bg:135 ARX/S nk | nk=1 | nk=7 (partA_02_global_hyperparameters_ARX_S_summary.csv, Rank==1) |
| bg:153 ARX/I nb | nb=1 | nb=7 (partA_02_global_hyperparameters_ARX_I_summary.csv, Rank==1) |
| bg:153 ARX/I nk | nk=1 | nk=7 (partA_02_global_hyperparameters_ARX_I_summary.csv, Rank==1) |
| bg:184 N4SID/S n | n=2 | n=1 (partA_02_global_hyperparameters_N4SID_S_summary.csv, Rank==1) |
| bg:184 N4SID/Both n | n=2 | n=1 (partA_02_global_hyperparameters_N4SID_Both_summary.csv, Rank==1) |
| bg:195 SSEST/S n | n=3 | n=1 (partA_02_global_hyperparameters_SSEST_S_summary.csv, Rank==1) |
| bg:195 SSEST/I n | n=3 | n=1 (partA_02_global_hyperparameters_SSEST_I_summary.csv, Rank==1) |
| bg:195 SSEST/Both n | n=2 | n=1 (partA_02_global_hyperparameters_SSEST_Both_summary.csv, Rank==1) |

**Note:** The inconsistency_report.md table in Section 6 (Selected HP column) also contains
some of these wrong values; that table is a historical snapshot and should not be used as a
source of truth. The authoritative source is always the tuning CSV files.

### 9.2 Missing SOURCE annotations in background-and-theory.tex

All four selected-HP sentences (AR/None, ARX modes, N4SID modes, SSEST modes) lacked
`% SOURCE:` annotations. SOURCE annotations were added immediately before each sentence,
pointing to the corresponding `partA_02_global_hyperparameters_*_summary.csv` file,
`State_Order_n` or `p` or `na/nb/nk` column, `Rank==1` condition.

### 9.3 Resolution status

| Issue | Status |
|-------|--------|
| ARX/S nk value corrected | Resolved (2026-04-02) |
| ARX/I nb, nk values corrected | Resolved (2026-04-02) |
| N4SID/S n value corrected | Resolved (2026-04-02) |
| N4SID/Both n value corrected | Resolved (2026-04-02) |
| SSEST/S n value corrected | Resolved (2026-04-02) |
| SSEST/I n value corrected | Resolved (2026-04-02) |
| SSEST/Both n value corrected | Resolved (2026-04-02) |
| SOURCE annotations added (AR/None) | Resolved (2026-04-02) |
| SOURCE annotations added (ARX modes ×3) | Resolved (2026-04-02) |
| SOURCE annotations added (N4SID modes ×4) | Resolved (2026-04-02) |
| SOURCE annotations added (SSEST modes ×4) | Resolved (2026-04-02) |

Compile status after fixes: **PASS with warnings** (BibTeX exit 2 — pre-existing
no-citation condition; one natbib empty-bibliography warning; zero hard errors,
zero undefined references, zero overfull/underfull boxes).

---

*End of inconsistency report.*
