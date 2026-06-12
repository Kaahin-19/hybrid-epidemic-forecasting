# Milestone A1: `partA_01_generate_truth.m`

Date: 2026-06-12

## Reviewed

- `scripts/partA/partA_01_generate_truth.m`
- `config/partA_config.m`
- `src/scenarios/generate_rt_signal.m`
- `src/epidemic/simulate_ground_truth_epidemic.m`

Direct dependency chain for this milestone:

- `partA_01_generate_truth.m` loads `partA_config`.
- `partA_01_generate_truth.m` calls `generate_rt_signal`.
- `partA_01_generate_truth.m` calls `simulate_ground_truth_epidemic`.

## Files Changed

- `scripts/partA/partA_01_generate_truth.m`
- `src/scenarios/generate_rt_signal.m`
- `src/epidemic/simulate_ground_truth_epidemic.m`

## Changes Made

### `scripts/partA/partA_01_generate_truth.m`

- Added the project-level Rt bounds check immediately after `generate_rt_signal`.
- The check uses `cfg.Rt.bounds`, so the project constraint is enforced at the script/config boundary.
- Updated the script workflow header and `Modified:` date.

### `src/scenarios/generate_rt_signal.m`

- Simplified the function so it only evaluates the configured Rt formula.
- Removed input reshaping.
- Removed output reshaping.
- Removed the generic helper-level positivity/sanity check.
- Kept only the unsupported `signal_type` error required by the `switch`.
- Reduced section comments to the remaining useful formula section.
- Updated the `Modified:` date.

### `src/epidemic/simulate_ground_truth_epidemic.m`

- Removed top-level `tspan` and `Rt_true` reshaping.
- Renamed the first section to match the current code.
- Removed the redundant `double(susceptible)` conversion.
- Removed extra inline/internal comments so local helpers keep the repository style: compact one-line local function headers only.
- Kept SIRS and SEIR support.
- Kept URDME output clipping with `max(..., 0)` as existing solver-output sanitation.
- Updated the `Modified:` date.

## Files Reviewed But Left Unchanged

- `config/partA_config.m`

## Validation

- No expensive MATLAB run was performed for this milestone.
- Checked the A1 files with `git diff`, `sed`, and targeted `rg` inspection.

## Status

A1 complete and stopped pending approval before A2.
