function [Rt_pred, aicc, out_alphas, lower_bounds, upper_bounds, meta] = ...
    simulate_statespace_intervals(model_type, params, Rt_past, U_past, ...
    sirs_state, num_exo, interval_options)
%SIMULATE_STATESPACE_INTERVALS Closed-loop bootstrap intervals for N4SID/SSEST.
%
%   Syntax:
%       [Rt_pred, aicc, out_alphas, lower_bounds, upper_bounds, meta] = ...
%           simulate_statespace_intervals(model_type, params, Rt_past, U_past, ...
%           sirs_state, num_exo, interval_options)
%
%   Description:
%       Family entry point that produces closed-loop predictive intervals for
%       the N4SID and SSEST state-space families. The only family-specific step
%       is the state-space estimator (n4sid vs ssest); everything else is
%       shared. The fitted innovations-form model provides matrices and a
%       predictor recursion used to estimate one-step residual innovations and
%       the forecast-origin state. Innovations are resampled and propagated
%       through the local closed-loop state-space path simulator. The
%       optimized d = 0 manual state-space path is preserved by working
%       directly from the estimated state-space matrices rather than a repeated
%       MATLAB forecast loop; the existing fit_n4sid_model / fit_ssest_model
%       analytic forecast is used only as a fallback.
%
%   Reuse note (future Part B/C; not implemented here):
%       Same fit/simulate seam as the AR/ARX family entry: the estimate +
%       predictor-residual step could be split from innovation resampling and
%       path simulation so a fit-once caller can reuse the bootstrap intervals.
%       See simulate_ar_arx_intervals for the full note. Deferred (would touch
%       Part B/C).
%
%   Inputs:
%       model_type       - "N4SID" or "SSEST".
%       params           - Candidate configuration row [n d].
%       Rt_past          - Historical effective Rt values.
%       U_past           - Historical exogenous covariate matrix (may be empty).
%       sirs_state       - Current [S, I, R] state at the forecast origin.
%       num_exo          - Number of exogenous inputs.
%       interval_options - Option set from make_interval_options.
%
%   Outputs:
%       Rt_pred      - Empirical predictive median (horizon-by-one).
%       aicc         - Corrected AIC from the fitted model when available.
%       out_alphas   - Interval miscoverage rates (row vector).
%       lower_bounds - horizon-by-numAlphas lower interval matrix.
%       upper_bounds - horizon-by-numAlphas upper interval matrix.
%       meta         - Interval metadata structure (method, draws, seed, status).
%
%   See also FIT_N4SID_MODEL, FIT_SSEST_MODEL, ...
%            INITIALIZE_SIRS_STEPPER, ADVANCE_SIRS_STEPPER.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-10

    %% 1. Setup
    model_type = string(model_type);
    params = reshape(double(params), 1, []);
    n = params(1);
    d = params(2);
    out_alphas = reshape(double(interval_options.alphas), 1, []);
    horizon = double(interval_options.horizon);
    num_draws = double(interval_options.num_draws);

    Rt_past = double(Rt_past(:));
    y = log(max(Rt_past, eps));
    fit_u = local_fit_inputs(U_past, num_exo);

    meta = local_base_meta(interval_options);

    %% 2. Estimation and Bootstrap (with deterministic fallback)
    use_bootstrap = (d == 0) && (std(y) >= 1e-8);
    if use_bootstrap
        try
            [ss, aicc, x_origin, residuals] = local_estimate_statespace( ...
                model_type, y, fit_u, n);

            [innovations, residual_status] = sample_centered_residuals( ...
                residuals, num_draws, horizon, interval_options.resample_seed, ...
                interval_options.min_residual_std);

            ensemble = local_closed_loop_bootstrap_paths( ...
                ss, x_origin, fit_u, sirs_state, innovations, interval_options);

            [valid_ensemble, num_valid] = local_valid_columns(ensemble);
            min_valid = max(2, ceil(0.2 * num_draws));

            if num_valid >= min_valid
                [Rt_pred, lower_bounds, upper_bounds] = ...
                    compute_interval_bounds_from_ensemble(valid_ensemble, out_alphas);
                meta.num_valid_draws = num_valid;
                meta.residual_status = residual_status;
                meta.interval_status = local_resolve_status( ...
                    residual_status, num_valid, num_draws);
                return;
            end
        catch
            % Fall through to the deterministic analytic fallback below.
        end
    end

    %% 3. Deterministic Analytic Fallback
    [Rt_pred, aicc, lower_bounds, upper_bounds] = local_deterministic_fallback( ...
        model_type, Rt_past, U_past, sirs_state, params, interval_options, ...
        out_alphas, horizon);
    meta.interval_status = "deterministic_fallback";
    meta.num_valid_draws = 0;
end

%% Local Functions
function meta = local_base_meta(interval_options)
%LOCAL_BASE_META Initialize interval metadata fields.
    meta = struct();
    meta.interval_method = string(interval_options.method);
    meta.interval_num_draws = double(interval_options.num_draws);
    meta.interval_seed = double(interval_options.interval_seed);
    meta.interval_status = "ok";
    meta.num_valid_draws = double(interval_options.num_draws);
    meta.residual_status = "ok";
end

function fit_u = local_fit_inputs(U_past, num_exo)
%LOCAL_FIT_INPUTS Normalize exogenous inputs for state-space fitting.
    if num_exo == 0 || isempty(U_past)
        fit_u = [];
        return;
    end
    fit_u = double(U_past);
    if isvector(fit_u)
        fit_u = fit_u(:);
    end
end

function [ss, aicc, x_origin, residuals] = local_estimate_statespace( ...
    model_type, y, fit_u, n)
%LOCAL_ESTIMATE_STATESPACE Estimate the SS model (family-specific) and residuals.
    data = iddata(y, fit_u, 1);

    switch model_type
        case "N4SID"
            opt = n4sidOptions('Display', 'off');
            sys = n4sid(data, n, opt);
        case "SSEST"
            opt = ssestOptions('Display', 'off');
            sys = ssest(data, n, opt);
        otherwise
            error('INTERVALS:UnknownModel', ...
                'simulate_statespace_intervals supports N4SID and SSEST only.');
    end

    aicc = local_extract_aicc(sys);

    [A, B, C, D, K, X0] = idssdata(sys);
    ss = struct('A', double(A), 'B', double(B), 'C', double(C), ...
        'D', double(D), 'K', local_resolve_gain(K, size(A, 1)));

    [x_origin, residuals] = local_predictor_pass(ss, y, fit_u, double(X0(:)));
end

function K = local_resolve_gain(K, num_states)
%LOCAL_RESOLVE_GAIN Default the Kalman gain to zeros when unavailable.
    K = double(K);
    if isempty(K) || ~isequal(size(K), [num_states, 1])
        K = zeros(num_states, 1);
    end
end

function [x_origin, residuals] = local_predictor_pass(ss, y, fit_u, X0)
%LOCAL_PREDICTOR_PASS One-step predictor residuals and forecast-origin state.
    y = double(y(:));
    num_obs = numel(y);
    has_inputs = ~isempty(fit_u);
    if has_inputs && size(fit_u, 1) ~= num_obs
        error('INTERVALS:InvalidExogenousHistory', ...
            'fit_u must have one row per observation.');
    end

    x = X0(:);
    if numel(x) ~= size(ss.A, 1)
        x = zeros(size(ss.A, 1), 1);
    end

    residuals = zeros(num_obs, 1);
    for t = 1:num_obs
        if has_inputs
            u_col = double(fit_u(t, :).');
        else
            u_col = zeros(0, 1);
        end
        y_hat = ss.C * x + ss.D * u_col;
        e_t = y(t) - y_hat;
        residuals(t) = e_t;
        x = ss.A * x + ss.B * u_col + ss.K * e_t;
    end

    x_origin = x;
    residuals = residuals(isfinite(residuals));
end

function aicc = local_extract_aicc(sys)
%LOCAL_EXTRACT_AICC Extract AICc when available.
    aicc = inf;
    try
        aicc = double(sys.Report.Fit.AICc);
    catch
    end
end

function [valid_ensemble, num_valid] = local_valid_columns(ensemble)
%LOCAL_VALID_COLUMNS Keep finite draws strictly inside the plausibility band.
%   Draws that reached the divergence clamp (Rt at or beyond 1e-2 / 1e2) are
%   dropped so unstable identified state-space trajectories cannot dominate the
%   empirical quantiles; too few valid draws trigger the analytic fallback.
    Rt_lo = 1e-2;
    Rt_hi = 1e2;
    is_valid = all(isfinite(ensemble), 1) & ...
        all(ensemble > Rt_lo, 1) & all(ensemble < Rt_hi, 1);
    valid_ensemble = ensemble(:, is_valid);
    num_valid = size(valid_ensemble, 2);
end

function status = local_resolve_status(residual_status, num_valid, num_draws)
%LOCAL_RESOLVE_STATUS Map residual status and draw counts to a status label.
    if strcmp(string(residual_status), "gaussian_innovations")
        status = "gaussian_innovations";
    elseif num_valid < num_draws
        status = "ok_partial_draws";
    else
        status = "ok";
    end
end

function [Rt_pred, aicc, lower_bounds, upper_bounds] = local_deterministic_fallback( ...
    model_type, Rt_past, U_past, sirs_state, params, interval_options, alphas, horizon)
%LOCAL_DETERMINISTIC_FALLBACK Reuse the analytic SS forecast when needed.
    exo_mode = interval_options.exo_mode;
    sirs_cfg = interval_options.sirs_cfg;
    sim_seed = interval_options.sim_seed;

    switch model_type
        case "N4SID"
            [Rt_pred, aicc, ~, lower_bounds, upper_bounds] = fit_n4sid_model( ...
                Rt_past, U_past, [], params(1), params(2), horizon, alphas, ...
                sirs_state, sirs_cfg, exo_mode, sim_seed);
        case "SSEST"
            [Rt_pred, aicc, ~, lower_bounds, upper_bounds] = fit_ssest_model( ...
                Rt_past, U_past, [], params(1), params(2), horizon, alphas, ...
                sirs_state, sirs_cfg, exo_mode, sim_seed);
        otherwise
            error('INTERVALS:UnknownModel', 'Unsupported model for fallback.');
    end
    Rt_pred = double(Rt_pred(:));
end

function ensemble_Rt = local_closed_loop_bootstrap_paths( ...
    ss, x_origin, U_history, sirs_state, innovations, interval_options)
%LOCAL_CLOSED_LOOP_BOOTSTRAP_PATHS Closed-loop N4SID/SSEST bootstrap trajectories.
%   Each draw predicts log-Rt from the current state and exogenous input, adds a
%   sampled innovation, and propagates the latent state through the
%   innovations-form update x(t+1) = A x + B u + K e. Exogenous models advance
%   the SIRS state per draw with sampled Rt; output-only models use the pure
%   latent recursion with no epidemic step. Failed draws return NaN columns.
    A = double(ss.A); B = double(ss.B); C = double(ss.C);
    D = double(ss.D); K = double(ss.K);
    x_origin = double(x_origin(:));
    num_inputs = size(B, 2);

    [horizon, num_draws] = size(innovations);
    [log_lo, log_hi] = local_log_clip_range();
    ensemble_Rt = nan(horizon, num_draws);

    % Output-only recursion (no epidemic feedback).
    if num_inputs == 0
        for d = 1:num_draws
            ensemble_Rt(:, d) = local_output_only_draw( ...
                A, C, K, x_origin, innovations(:, d), horizon, log_lo, log_hi);
        end
        return;
    end

    % Closed-loop recursion (exogenous epidemic feedback).
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

    for d = 1:num_draws
        draw_seed = local_draw_epidemic_seed(interval_options, d, horizon);
        ensemble_Rt(:, d) = local_resimulate_draw( ...
            A, B, C, D, K, x_origin, U_history, sirs_state, ...
            innovations(:, d), stepper, draw_seed, exo_mode, pop_size, ...
            horizon, log_lo, log_hi);
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
