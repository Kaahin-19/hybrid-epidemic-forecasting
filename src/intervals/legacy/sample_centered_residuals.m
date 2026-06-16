function [innovations, residual_status] = sample_centered_residuals( ...
    residuals, num_draws, horizon, resample_seed, min_residual_std)
%SAMPLE_CENTERED_RESIDUALS Resample centered innovation draws for bootstrapping.
%
%   Syntax:
%       [innovations, residual_status] = sample_centered_residuals( ...
%           residuals, num_draws, horizon, resample_seed, min_residual_std)
%
%   Description:
%       Builds a horizon-by-draws matrix of innovation samples for closed-loop
%       interval simulation. Valid residuals are centered (mean removed) and
%       resampled with replacement so the empirical innovation distribution is
%       reused. When residual extraction fails or yields no usable values, the
%       function falls back to small Gaussian innovations scaled by
%       min_residual_std and reports the fallback through residual_status.
%
%   Inputs:
%       residuals        - Vector of one-step residual innovations (log scale).
%       num_draws        - Number of bootstrap/Monte Carlo draws.
%       horizon          - Forecast horizon (innovations per draw).
%       resample_seed    - Deterministic RNG seed for reproducible resampling.
%       min_residual_std - Minimum innovation scale for the Gaussian fallback.
%
%   Outputs:
%       innovations     - horizon-by-num_draws matrix of innovation samples.
%       residual_status - "ok" or "gaussian_innovations".
%
%   See also SIMULATE_AR_ARX_INTERVALS, SIMULATE_STATESPACE_INTERVALS.
%
% A. M. Kaahin 2026-06-01

    %% 1. Input Preparation
    num_draws = max(1, round(double(num_draws)));
    horizon = max(1, round(double(horizon)));
    min_residual_std = double(min_residual_std);
    if ~isscalar(min_residual_std) || ~isfinite(min_residual_std) || min_residual_std <= 0
        min_residual_std = 1e-6;
    end

    residuals = double(residuals(:));
    residuals = residuals(isfinite(residuals));

    %% 2. Reproducible RNG Scope
    caller_rng_state = rng;
    rng_cleanup = onCleanup(@() rng(caller_rng_state));
    rng(local_valid_seed(resample_seed), 'twister');

    %% 3. Residual Resampling or Gaussian Fallback
    if numel(residuals) >= 2 && std(residuals) > 0
        centered = residuals - mean(residuals);
        idx = randi(numel(centered), horizon, num_draws);
        innovations = centered(idx);
        innovations = reshape(innovations, horizon, num_draws);
        residual_status = "ok";
    else
        innovations = min_residual_std * randn(horizon, num_draws);
        residual_status = "gaussian_innovations";
    end

    clear rng_cleanup
end

function seed = local_valid_seed(seed)
%LOCAL_VALID_SEED Coerce a seed into a valid nonnegative integer.
    seed = double(seed);
    if ~isscalar(seed) || ~isfinite(seed) || seed < 0
        seed = 0;
    end
    seed = mod(floor(seed), 2^32);
end
