# Project Plan

**Title:** Hybrid Epidemic Forecasting: Mechanistic SIR & Time-Series Inference

**Supervisor:** Stefan Engblom

**Subject Reviewer:** \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_

## Introduction & Objective

Epidemiological forecasting using mechanistic SIR models often struggles to accurately predict the reproduction number ($R_t$) because the data is often noisy. In this project, $R_t$ is treated as a "hidden" value that we have to figure out from the number of observed cases. We will use an existing MATLAB framework to test a "hybrid" approach: combining these disease models with statistical time-series models (ARX/ARMA). The goal is to see if these time-series models can effectively learn how $R_t$ changes over time and if this hybrid method provides better forecasts than using just data or just mechanistic models alone.

## Goals

### 1. Part A: Synthetic Validation

Establish a "best-case" baseline to find the absolute limits of prediction. Instead of using existing models, we will "invent" 3–4 different $R_t$ trajectories using analytic functions. We will train the models on expanding windows of data (adding 7 days at a time, e.g., 14, 21, 28 days) to see how accuracy improves. These invented trajectories will follow realistic rules: $R_t$ stays between 0.5 and 2, eventually trends back toward 1, and includes "inertia" to represent natural delays in disease spread.

### 2. Part B: Robustness Testing

Introduce controllable errors to "break the model." We will test the method on more complex data, such as SIR models with different age groups (children, adults, elderly) or SEIR models, where an "Exposed" stage adds a delay. This helps us evaluate performance when the real-world data doesn't perfectly match our simple model assumptions.

### 3. Part C: Real-world Application

Stress-test the framework using Swedish Covid-19 data to determine its reliability for actual short-term forecasting when the underlying truth is fully unknown.

## Timeline (20 Weeks, Starting Jan 19, 2026)

| Week | Moment |
|---|---|
| 1–5 | Literature review, Environment setup and implementation of Part A. |
| 6–11 | Implementation of Part B. |
| 12–15 | Implementation of Part C. |
| 16–20 | Finalizing thesis report, preparation for presentation, and opposition. |
