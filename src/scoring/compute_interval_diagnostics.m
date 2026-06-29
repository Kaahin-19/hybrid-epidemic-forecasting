function interval = compute_interval_diagnostics(truth, lower, upper, alphas)
%COMPUTE_INTERVAL_DIAGNOSTICS Raw prediction-interval diagnostics across H horizons and K levels.
%
%   Syntax:
%       interval = compute_interval_diagnostics(truth, lower, upper, alphas)
%
%   Description:
%       For an H-by-1 truth vector, H-by-K central prediction-interval bounds,
%       and a K-by-1 vector of miscoverage levels, computes the raw per-horizon
%       and per-interval diagnostics needed for interval scoring and
%       calibration analysis: empirical coverage, interval width, calibration
%       error, the interval score, the per-interval weighted-interval-score
%       components, and their per-horizon means across interval levels. Inputs
%       are assumed to already follow the internal orientation conventions; no
%       reshaping, conversion, validation, or repair is performed.
%
%   Inputs:
%       truth  - H-by-1 vector of observed values.
%       lower  - H-by-K matrix of lower interval bounds.
%       upper  - H-by-K matrix of upper interval bounds.
%       alphas - K-by-1 vector of miscoverage levels.
%
%   Outputs:
%       interval - Struct with fields:
%           nominal_coverage              - K-by-1 nominal coverage (1 - alphas).
%           coverage                      - H-by-K interval coverage indicators.
%           interval_width                - H-by-K interval widths.
%           coverage_error                - H-by-K coverage minus nominal.
%           absolute_coverage_error       - H-by-K |coverage_error|.
%           underprediction               - H-by-K lower-side exceedances.
%           overprediction                - H-by-K upper-side exceedances.
%           interval_score                - H-by-K interval scores.
%           wis_sharpness_component       - H-by-K WIS sharpness term.
%           wis_underprediction_component - H-by-K WIS underprediction term.
%           wis_overprediction_component  - H-by-K WIS overprediction term.
%           wis_interval_component        - H-by-K WIS per-interval total.
%           coverage_mean                 - H-by-1 mean coverage across levels.
%           calibration_bias_mean         - H-by-1 mean coverage error.
%           absolute_calibration_mean     - H-by-1 mean |coverage error|.
%           width_mean                    - H-by-1 mean interval width.
%
%   See also COMPUTE_WIS, COMPUTE_POINT_ERROR.
%
% A. M. Kaahin 2026-06-22

%% 1. Coverage and Width
nominal_coverage = 1 - alphas;
coverage         = truth >= lower & truth <= upper;
interval_width   = upper - lower;

coverage_error          = coverage - nominal_coverage.';
absolute_coverage_error = abs(coverage_error);

%% 2. Interval Score and WIS Components
underprediction = max(lower - truth, 0);
overprediction  = max(truth - upper, 0);

interval_score = interval_width + (2 ./ alphas.') .* underprediction + (2 ./ alphas.') .* overprediction;

wis_sharpness_component       = (alphas.' / 2) .* interval_width;
wis_underprediction_component = underprediction;
wis_overprediction_component  = overprediction;
wis_interval_component        = wis_sharpness_component + wis_underprediction_component + wis_overprediction_component;

%% 3. Per-Horizon Means Across Interval Levels
coverage_mean             = mean(coverage, 2);
calibration_bias_mean     = mean(coverage_error, 2);
absolute_calibration_mean = mean(absolute_coverage_error, 2);
width_mean                = mean(interval_width, 2);

%% 4. Output Assembly
interval = struct('nominal_coverage', nominal_coverage, 'coverage', coverage, 'interval_width', interval_width, 'coverage_error', coverage_error, 'absolute_coverage_error', absolute_coverage_error, 'underprediction', underprediction, 'overprediction', overprediction, 'interval_score', interval_score, 'wis_sharpness_component', wis_sharpness_component, 'wis_underprediction_component', wis_underprediction_component, 'wis_overprediction_component', wis_overprediction_component, 'wis_interval_component', wis_interval_component, 'coverage_mean', coverage_mean, 'calibration_bias_mean', calibration_bias_mean, 'absolute_calibration_mean', absolute_calibration_mean, 'width_mean', width_mean);
end
