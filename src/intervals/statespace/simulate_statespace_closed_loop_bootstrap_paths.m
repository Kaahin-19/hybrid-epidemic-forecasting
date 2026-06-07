function ensemble_Rt = simulate_statespace_closed_loop_bootstrap_paths( ...
    ss, x_origin, U_history, sirs_state, innovations, interval_options)
%SIMULATE_STATESPACE_CLOSED_LOOP_BOOTSTRAP_PATHS Closed-loop SS bootstrap paths.
%
%   Syntax:
%       ensemble_Rt = simulate_statespace_closed_loop_bootstrap_paths( ...
%           ss, x_origin, U_history, sirs_state, innovations, interval_options)
%
%   Description:
%       Generates an ensemble of closed-loop state-space forecast trajectories
%       for the N4SID/SSEST families. The fitted innovations-form matrices are
%       shared across both families; only the estimation step differs. Each
%       step predicts log-Rt from the current state and exogenous input, adds a
%       sampled innovation, and propagates the latent state through the
%       innovations-form update x(t+1) = A x(t) + B u(t) + K e(t) so the
%       innovation perturbs both the current output and the latent recursion.
%
%       For exogenous models the same two epidemic-propagation modes as the
%       AR/ARX simulator are supported:
%         "frozen"     - reuse one deterministic exogenous future path
%                        (lightweight, Part A 02);
%         "resimulate" - advance the SIRS state per draw with sampled Rt
%                        (fuller Monte Carlo, Part A 03).
%       Closed-loop exogenous propagation uses initialize_sirs_stepper and
%       advance_sirs_stepper. genData_SIRS is never used. Output-only models
%       (exo mode None) use the pure latent recursion with no epidemic step.
%
%   Inputs:
%       ss               - Struct with innovations-form matrices A, B, C, D, K.
%       x_origin         - Predictor state at the forecast origin.
%       U_history        - Historical exogenous covariate matrix (may be empty).
%       sirs_state       - Current [S, I, R] state at the forecast origin.
%       innovations      - horizon-by-numDraws matrix of sampled innovations.
%       interval_options - Option set from make_interval_options.
%
%   Outputs:
%       ensemble_Rt - horizon-by-numDraws matrix of Rt draws. Columns from
%                     failed draws are returned as NaN for the caller to drop.
%
%   See also SIMULATE_STATESPACE_INTERVALS, INITIALIZE_SIRS_STEPPER, ...
%            ADVANCE_SIRS_STEPPER, EXTRACT_EXOGENOUS_FROM_STATE.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-05

    %% 1. Input Preparation
    A = double(ss.A); B = double(ss.B); C = double(ss.C);
    D = double(ss.D); K = double(ss.K);
    x_origin = double(x_origin(:));
    num_inputs = size(B, 2);

    [horizon, num_draws] = size(innovations);
    [log_lo, log_hi] = local_log_clip_range();
    ensemble_Rt = nan(horizon, num_draws);

    %% 2. Output-Only Recursion (no epidemic feedback)
    if num_inputs == 0
        for d = 1:num_draws
            ensemble_Rt(:, d) = local_output_only_draw( ...
                A, C, K, x_origin, innovations(:, d), horizon, log_lo, log_hi);
        end
        return;
    end

    %% 3. Closed-Loop Recursion (exogenous epidemic feedback)
    U_history = double(U_history);
    if isvector(U_history)
        U_history = U_history(:);
    end
    exo_mode = interval_options.exo_mode;
    sirs_cfg = interval_options.sirs_cfg;
    pop_size = sirs_cfg.pop_size;

    sim_options = struct('solver', 'uds', 'compile', false, ...
        'seed', local_valid_seed(interval_options.epidemic_base_seed));
    stepper = initialize_sirs_stepper(sirs_cfg, sim_options);

    if interval_options.epidemic_mode == "frozen"
        future_U = local_deterministic_future_exogenous( ...
            A, B, C, D, x_origin, U_history, sirs_state, stepper, ...
            exo_mode, pop_size, horizon, log_lo, log_hi);
        for d = 1:num_draws
            ensemble_Rt(:, d) = local_frozen_draw( ...
                A, B, C, D, K, x_origin, future_U, innovations(:, d), ...
                horizon, log_lo, log_hi);
        end
    else
        for d = 1:num_draws
            draw_seed = local_draw_epidemic_seed(interval_options, d, horizon);
            ensemble_Rt(:, d) = local_resimulate_draw( ...
                A, B, C, D, K, x_origin, U_history, sirs_state, ...
                innovations(:, d), stepper, draw_seed, exo_mode, pop_size, ...
                horizon, log_lo, log_hi);
        end
    end
end

function column = local_output_only_draw(A, C, K, x_origin, innovation_column, ...
    horizon, log_lo, log_hi)
%LOCAL_OUTPUT_ONLY_DRAW One draw for an output-only state-space model.
    column = nan(horizon, 1);
    x = x_origin;
    for h = 1:horizon
        y_hat = C * x;
        y_next = min(max(y_hat + innovation_column(h), log_lo), log_hi);
        Rt_next = exp(y_next);
        if ~isfinite(Rt_next) || Rt_next <= 0
            return;
        end
        column(h) = Rt_next;
        x = A * x + K * innovation_column(h);
    end
end

function future_U = local_deterministic_future_exogenous( ...
    A, B, C, D, x_origin, U_history, sirs_state, stepper, exo_mode, ...
    pop_size, horizon, log_lo, log_hi)
%LOCAL_DETERMINISTIC_FUTURE_EXOGENOUS Frozen future exogenous path (e = 0).
    x = x_origin;
    u_current = U_history(end, :);
    state = local_sanitize_state(sirs_state, pop_size);
    future_U = zeros(horizon, size(U_history, 2));

    stepper.seed = local_valid_seed(stepper.seed);
    stepper.call_count = 0;

    for h = 1:horizon
        future_U(h, :) = u_current;
        u_col = double(u_current(:));
        y_hat = min(max(C * x + D * u_col, log_lo), log_hi);
        Rt_next = exp(y_hat);
        [state, stepper] = advance_sirs_stepper(stepper, state, Rt_next);
        u_next = extract_exogenous_from_state(state, exo_mode, pop_size);
        x = A * x + B * u_col;
        u_current = u_next;
    end
end

function column = local_frozen_draw( ...
    A, B, C, D, K, x_origin, future_U, innovation_column, horizon, log_lo, log_hi)
%LOCAL_FROZEN_DRAW One bootstrap draw reusing the frozen exogenous path.
    column = nan(horizon, 1);
    x = x_origin;
    for h = 1:horizon
        u_col = double(future_U(h, :).');
        y_hat = C * x + D * u_col;
        e_h = innovation_column(h);
        y_next = min(max(y_hat + e_h, log_lo), log_hi);
        Rt_next = exp(y_next);
        if ~isfinite(Rt_next) || Rt_next <= 0
            return;
        end
        column(h) = Rt_next;
        x = A * x + B * u_col + K * e_h;
    end
end

function column = local_resimulate_draw( ...
    A, B, C, D, K, x_origin, U_history, sirs_state, innovation_column, ...
    stepper, draw_seed, exo_mode, pop_size, horizon, log_lo, log_hi)
%LOCAL_RESIMULATE_DRAW One Monte Carlo draw with per-draw epidemic advances.
    column = nan(horizon, 1);
    try
        x = x_origin;
        u_current = U_history(end, :);
        state = local_sanitize_state(sirs_state, pop_size);
        stepper.seed = draw_seed;
        stepper.call_count = 0;

        for h = 1:horizon
            u_col = double(u_current(:));
            y_hat = C * x + D * u_col;
            e_h = innovation_column(h);
            y_next = min(max(y_hat + e_h, log_lo), log_hi);
            Rt_next = exp(y_next);
            if ~isfinite(Rt_next) || Rt_next <= 0
                column = nan(horizon, 1);
                return;
            end

            [state, stepper] = advance_sirs_stepper(stepper, state, Rt_next);
            u_next = extract_exogenous_from_state(state, exo_mode, pop_size);
            x = A * x + B * u_col + K * e_h;
            column(h) = Rt_next;
            u_current = u_next;
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
