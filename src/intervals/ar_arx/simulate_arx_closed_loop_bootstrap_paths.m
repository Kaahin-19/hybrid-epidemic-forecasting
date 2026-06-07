function ensemble_Rt = simulate_arx_closed_loop_bootstrap_paths( ...
    coefficients, log_history, U_history, sirs_state, innovations, interval_options)
%SIMULATE_ARX_CLOSED_LOOP_BOOTSTRAP_PATHS Closed-loop ARX bootstrap trajectories.
%
%   Syntax:
%       ensemble_Rt = simulate_arx_closed_loop_bootstrap_paths( ...
%           coefficients, log_history, U_history, sirs_state, innovations, ...
%           interval_options)
%
%   Description:
%       Generates an ensemble of closed-loop ARX forecast trajectories using
%       the recursive ARX coefficient machinery. Two epidemic-propagation
%       modes are supported:
%
%       "frozen" (selection / lightweight bootstrap):
%           The closed-loop exogenous future path is produced once from the
%           deterministic ARX recursion and the SIRS stepper, then reused for
%           every draw. Innovations propagate through the autoregressive
%           memory but the exogenous feedback is held at its deterministic
%           path, so only one set of epidemic advances is performed per
%           window. This is the cheaper approximation used in Part A 02.
%
%       "resimulate" (final / fuller Monte Carlo):
%           Each draw advances the SIRS state with its own sampled Rt values,
%           so innovation uncertainty propagates through the epidemic feedback.
%           When include_epidemic_seed_variation is true the per-draw epidemic
%           seed schedule is varied so stochastic epidemic simulation also
%           contributes to the predictive spread. This is the higher-fidelity
%           procedure used in Part A 03.
%
%       Closed-loop exogenous propagation uses initialize_sirs_stepper and
%       advance_sirs_stepper. genData_SIRS is never used.
%
%   Inputs:
%       coefficients     - ARX coefficient structure (extract_arx_coefficients).
%       log_history      - Column vector of historical log-Rt values.
%       U_history        - Historical exogenous covariate matrix.
%       sirs_state       - Current [S, I, R] state at the forecast origin.
%       innovations      - horizon-by-numDraws matrix of sampled innovations.
%       interval_options - Option set from make_interval_options.
%
%   Outputs:
%       ensemble_Rt - horizon-by-numDraws matrix of Rt draws. Columns from
%                     failed draws are returned as NaN for the caller to drop.
%
%   See also RECURSIVE_ARX_STEP, EXTRACT_EXOGENOUS_FROM_STATE, ...
%            INITIALIZE_SIRS_STEPPER, ADVANCE_SIRS_STEPPER.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-05

    %% 1. Input Preparation
    log_history = double(log_history(:));
    U_history = double(U_history);
    if isvector(U_history)
        U_history = U_history(:);
    end
    num_inputs = coefficients.num_inputs;
    if size(U_history, 2) ~= num_inputs
        error('INTERVALS:InvalidExogenousHistory', ...
            'U_history column count does not match ARX input count.');
    end

    [horizon, num_draws] = size(innovations);
    exo_mode = interval_options.exo_mode;
    sirs_cfg = interval_options.sirs_cfg;
    pop_size = sirs_cfg.pop_size;
    [log_lo, log_hi] = local_log_clip_range();

    %% 2. Stepper Setup
    sim_options = struct('solver', 'uds', 'compile', false, ...
        'seed', local_valid_seed(interval_options.epidemic_base_seed));
    stepper = initialize_sirs_stepper(sirs_cfg, sim_options);

    ensemble_Rt = nan(horizon, num_draws);

    if interval_options.epidemic_mode == "frozen"
        %% 3a. Frozen Exogenous Path (deterministic single epidemic pass)
        future_U = local_deterministic_future_exogenous( ...
            coefficients, log_history, U_history, sirs_state, ...
            stepper, exo_mode, pop_size, horizon, log_lo, log_hi);

        for d = 1:num_draws
            ensemble_Rt(:, d) = local_frozen_draw( ...
                coefficients, log_history, U_history, future_U, ...
                innovations(:, d), horizon, log_lo, log_hi);
        end
    else
        %% 3b. Resimulated Epidemic Path (per-draw closed loop)
        for d = 1:num_draws
            draw_seed = local_draw_epidemic_seed(interval_options, d, horizon);
            ensemble_Rt(:, d) = local_resimulate_draw( ...
                coefficients, log_history, U_history, sirs_state, ...
                innovations(:, d), stepper, draw_seed, exo_mode, pop_size, ...
                horizon, log_lo, log_hi);
        end
    end
end

function future_U = local_deterministic_future_exogenous( ...
    coefficients, log_history, U_history, sirs_state, stepper, exo_mode, ...
    pop_size, horizon, log_lo, log_hi)
%LOCAL_DETERMINISTIC_FUTURE_EXOGENOUS Build the frozen future exogenous path.
    rolling_log = log_history;
    rolling_U = U_history;
    state = local_sanitize_state(sirs_state, pop_size);
    future_U = zeros(horizon, size(U_history, 2));

    stepper.seed = local_valid_seed(stepper.seed);
    stepper.call_count = 0;

    for h = 1:horizon
        y_hat = recursive_arx_step(coefficients, rolling_log, rolling_U);
        y_hat = min(max(y_hat, log_lo), log_hi);
        Rt_next = exp(y_hat);
        [state, stepper] = advance_sirs_stepper(stepper, state, Rt_next);
        U_next = extract_exogenous_from_state(state, exo_mode, pop_size);

        future_U(h, :) = U_next;
        rolling_log = [rolling_log; y_hat]; %#ok<AGROW>
        rolling_U = [rolling_U; U_next]; %#ok<AGROW>
    end
end

function column = local_frozen_draw( ...
    coefficients, log_history, U_history, future_U, innovation_column, ...
    horizon, log_lo, log_hi)
%LOCAL_FROZEN_DRAW One bootstrap draw reusing the frozen exogenous path.
    column = nan(horizon, 1);
    rolling_log = log_history;
    full_U = [U_history; future_U];
    base_rows = size(U_history, 1);

    for h = 1:horizon
        u_rows = full_U(1:(base_rows + h - 1), :);
        y_hat = recursive_arx_step(coefficients, rolling_log, u_rows);
        y_next = min(max(y_hat + innovation_column(h), log_lo), log_hi);
        Rt_next = exp(y_next);
        if ~isfinite(Rt_next) || Rt_next <= 0
            return;
        end
        column(h) = Rt_next;
        rolling_log = [rolling_log; y_next]; %#ok<AGROW>
    end
end

function column = local_resimulate_draw( ...
    coefficients, log_history, U_history, sirs_state, innovation_column, ...
    stepper, draw_seed, exo_mode, pop_size, horizon, log_lo, log_hi)
%LOCAL_RESIMULATE_DRAW One Monte Carlo draw with per-draw epidemic advances.
    column = nan(horizon, 1);
    try
        rolling_log = log_history;
        rolling_U = U_history;
        state = local_sanitize_state(sirs_state, pop_size);
        stepper.seed = draw_seed;
        stepper.call_count = 0;

        for h = 1:horizon
            y_hat = recursive_arx_step(coefficients, rolling_log, rolling_U);
            y_next = min(max(y_hat + innovation_column(h), log_lo), log_hi);
            Rt_next = exp(y_next);
            if ~isfinite(Rt_next) || Rt_next <= 0
                column = nan(horizon, 1);
                return;
            end

            [state, stepper] = advance_sirs_stepper(stepper, state, Rt_next);
            U_next = extract_exogenous_from_state(state, exo_mode, pop_size);

            column(h) = Rt_next;
            rolling_log = [rolling_log; y_next]; %#ok<AGROW>
            rolling_U = [rolling_U; U_next]; %#ok<AGROW>
        end
    catch
        column = nan(horizon, 1);
    end
end

function seed = local_draw_epidemic_seed(interval_options, draw_index, horizon)
%LOCAL_DRAW_EPIDEMIC_SEED Resolve the epidemic seed schedule base for a draw.
    base = local_valid_seed(interval_options.epidemic_base_seed);
    if interval_options.include_epidemic_seed_variation
        seed = local_valid_seed(base + (draw_index - 1) * (horizon + 1));
    else
        seed = base;
    end
end

function state = local_sanitize_state(raw_state, pop_size)
%LOCAL_SANITIZE_STATE Normalize an [S, I, R] state to the population size.
    state = reshape(double(raw_state), 1, []);
    if numel(state) ~= 3 || any(~isfinite(state))
        error('INTERVALS:InvalidSirsState', ...
            'sirs_state must contain three finite compartment values.');
    end
    tolerance = max(1e-7 * pop_size, 1e-9);
    state(abs(state) < tolerance) = 0;
    state = max(state, 0);
    state(1) = max(state(1), max(1, 1e-6 * pop_size));
    total = sum(state);
    if total <= 0
        error('INTERVALS:InvalidSirsState', 'sirs_state must be positive.');
    end
    state = state * (pop_size / total);
end

function seed = local_valid_seed(seed)
%LOCAL_VALID_SEED Coerce a seed into a valid nonnegative integer.
    seed = double(seed);
    if ~isscalar(seed) || ~isfinite(seed) || seed < 0
        seed = 0;
    end
    seed = mod(floor(seed), 2^32);
end

function [log_lo, log_hi] = local_log_clip_range()
%LOCAL_LOG_CLIP_RANGE Plausibility guard range for log-Rt draws.
    log_lo = log(1e-2);
    log_hi = log(1e2);
end
