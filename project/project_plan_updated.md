# Project Plan (Updated)

**Title:** Hybrid Epidemic Forecasting: Mechanistic SIR & Time-Series Inference

**Supervisor:** Stefan Engblom

**Subject Reviewer:** ____________________

## Introduction & Objective

Epidemiological forecasting using mechanistic SIR models often struggles when the reproduction number ($R_t$) is unknown and the observed data are noisy. In this project, $R_t$ is treated as a hidden value that must be estimated from observed cases. We will use an existing MATLAB framework to test a hybrid approach combining mechanistic epidemic models with statistical time-series models (ARX/ARMA). The goal is to determine whether these models can forecast $R_t$ and whether using these forecasts improves epidemic predictions compared with holding the latest estimate of $R_t$ constant.

## Goals

### 1. Part A: Design and Calibration of an Rt Forecasting Model

Design and fit a suitable ARX model using a typical synthetic $R_t$ trajectory, for example, periodic oscillations between 0.5 and 2. We will use four different synthetic $R_t$ trajectories to test the robustness of the model and refine its design. The models will be trained on expanding windows of data, adding 7 days at a time, to evaluate their predictive accuracy and select a suitable ARX configuration for Part B.

### 2. Part B: Synthetic Evaluation of Epidemic Forecasting

Test how well the ARX model selected in Part A improves predictions of the infectious population $I(t)$. Starting from historical estimates of $I(t)$ and $R_t$ obtained from synthetic epidemic data, we will compare three approaches:

- Holding the latest estimated $R_t$ constant.
- Using the exact future synthetic $R_t$ values.
- Using the future $R_t$ values predicted by the ARX model.

Each approach will use the same mechanistic forecasting model and estimated initial state. The predicted infectious population will be compared with the known synthetic truth. We will also introduce observation noise, process noise and structural mismatch using more complex epidemic models, such as SEIR, to evaluate the robustness of the approach.

### 3. Part C: Real-world Application

Stress-test the framework using Swedish Covid-19 data to determine its reliability for actual short-term forecasting when the underlying truth is fully unknown.

## Timeline (20 Weeks, Starting Jan 19, 2026)

| Week | Moment |
|---|---|
| 1–5 | Literature review, Environment setup and implementation of Part A. |
| 6–11 | Implementation of Part B. |
| 12–15 | Implementation of Part C. |
| 16–20 | Finalizing thesis report, preparation for presentation, and opposition. |