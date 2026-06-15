function [ensemble, aicc] = forecast_closed(model_type, params, Rt_past, U_past, ...
    sirs_state, num_exo, num_draws, horizon, exo_mode, sirs_cfg, ...
    resample_seed, epidemic_base_seed, vary_epidemic_seed)
%FORECAST_CLOSED Bootstrap forecast ensemble for models with exogenous inputs (num_exo > 0).
%
%   Syntax:
%       [ensemble, aicc] = forecast_closed(model_type, params, Rt_past, U_past,
%           sirs_state, num_exo, num_draws, horizon, exo_mode, sirs_cfg,
%           resample_seed, epidemic_base_seed, vary_epidemic_seed)
%
%   Description:
%       Fits an ARX or state-space model with exogenous inputs to log(Rt_past),
%       computes one-step prediction residuals, resamples centred residuals as
%       innovations under resample_seed, and propagates closed-loop bootstrap
%       paths. At each horizon step the forecast Rt drives a SIRS epidemic step
%       whose output state determines the next exogenous covariate. Outputs are
%       on the Rt scale. A draw that produces a non-finite or non-positive Rt
%       at any step is left as NaN for that step and all later steps. Range-based
%       validity filtering is the responsibility of interval_bounds. Returns
%       nan(horizon, num_draws) and aicc = inf when the series is constant
%       (std < 1e-8), there are too few observations relative to the model
%       order, fewer than two finite residuals remain after the predictor pass,
%       or the toolbox fit call fails.
%
%   Inputs:
%       model_type         - "ARX", "N4SID", or "SSEST".
%       params             - [na, nb, nk] for ARX; [n] for state-space.
%       Rt_past            - T×1 historical Rt values.
%       U_past             - T×num_exo historical exogenous covariate matrix.
%       sirs_state         - [S, I, R] epidemic state at the forecast origin.
%       num_exo            - Number of exogenous inputs (> 0).
%       num_draws          - Number of Monte Carlo draws.
%       horizon            - Forecast horizon in steps.
%       exo_mode           - "S", "I", or "Both" (controls covariate extraction).
%       sirs_cfg           - SIRS model configuration struct (passed to sirs_init).
%       resample_seed      - Integer seed for the residual resample RNG.
%       epidemic_base_seed - Integer base seed for per-draw SIRS epidemic seeds.
%       vary_epidemic_seed - Logical; if true, each draw receives a distinct seed.
%
%   Outputs:
%       ensemble - horizon×num_draws matrix of Rt bootstrap draws.
%       aicc     - Corrected AIC from the fitted model (inf on fit failure or
%                  insufficient residuals).
%
%   See also FORECAST_OPEN, INTERVAL_BOUNDS, COMPUTE_WIS, SIRS_INIT, SIRS_STEP.
%
% A. M. Kaahin 2026-06-15

    y = log(Rt_past);

    switch model_type
        case "ARX"
            [ensemble, aicc] = local_arx(y, U_past, params, num_exo, num_draws, ...
                horizon, exo_mode, sirs_cfg, sirs_state, ...
                resample_seed, epidemic_base_seed, vary_epidemic_seed);
        case {"N4SID", "SSEST"}
            [ensemble, aicc] = local_ss_closed(model_type, y, U_past, params(1), ...
                num_exo, num_draws, horizon, exo_mode, sirs_cfg, sirs_state, ...
                resample_seed, epidemic_base_seed, vary_epidemic_seed);
        otherwise
            error('FORECAST_CLOSED:UnknownModel', 'Unsupported model type: %s', model_type);
    end
end

%% Local functions

function [ensemble, aicc] = local_arx(y, U_past, params, num_exo, num_draws, ...
    horizon, exo_mode, sirs_cfg, sirs_state, ...
    resample_seed, epidemic_base_seed, vary_epidemic_seed)
%LOCAL_ARX Closed-loop ARX bootstrap ensemble on the log scale.
    na = params(1);
    nb = params(2);
    nk = params(3);
    T  = numel(y);

    if std(y) < 1e-8
        ensemble = nan(horizon, num_draws);
        aicc     = inf;
        return;
    end

    max_lag = max(na, nk + nb - 1);
    if T - max_lag < 2
        ensemble = nan(horizon, num_draws);
        aicc     = inf;
        return;
    end

    nb_vec = repmat(nb, 1, num_exo);
    nk_vec = repmat(nk, 1, num_exo);
    try
        sys = arx(iddata(y, U_past, 1), [na, nb_vec, nk_vec]);
    catch
        ensemble = nan(horizon, num_draws);
        aicc     = inf;
        return;
    end
    aicc   = sys.Report.Fit.AICc;
    a_vals = sys.A(2:end);                   % 1×na
    b_vals = local_extract_b(sys.B, nb, nk, num_exo);

    residuals = zeros(T - max_lag, 1);
    for t = (max_lag + 1):T
        y_hat              = local_arx_step(a_vals, b_vals, na, nb, nk, ...
                                 y(1:t-1), U_past(1:t-1, :));
        residuals(t - max_lag) = y(t) - y_hat;
    end
    residuals = residuals(isfinite(residuals));

    if numel(residuals) < 2
        ensemble = nan(horizon, num_draws);
        aicc     = inf;
        return;
    end

    innovations  = local_resample(residuals, horizon, num_draws, resample_seed);
    pop_size     = sirs_cfg.pop_size;
    base_stepper = sirs_init(sirs_cfg, ...
        struct('solver', 'uds', 'compile', false, 'seed', epidemic_base_seed));

    rolling_y = [y;      zeros(horizon, 1)];
    rolling_U = [U_past; zeros(horizon, num_exo)];

    ensemble = nan(horizon, num_draws);
    for d = 1:num_draws
        draw_seed          = local_draw_seed(epidemic_base_seed, d, horizon, vary_epidemic_seed);
        stepper            = base_stepper;
        stepper.seed       = draw_seed;
        stepper.call_count = 0;
        state              = sirs_state;
        roll_y             = rolling_y;
        roll_U             = rolling_U;
        col                = nan(horizon, 1);
        for h = 1:horizon
            y_hat   = local_arx_step(a_vals, b_vals, na, nb, nk, ...
                          roll_y(1:T+h-1), roll_U(1:T+h-1, :));
            y_next  = y_hat + innovations(h, d);
            Rt_next = exp(y_next);
            if ~isfinite(Rt_next) || Rt_next <= 0
                break;
            end
            [state, stepper]  = sirs_step(stepper, state, Rt_next);
            col(h)            = Rt_next;
            roll_y(T + h)     = y_next;
            roll_U(T + h, :)  = local_exo_row(state, exo_mode, pop_size);
        end
        ensemble(:, d) = col;
    end
end

function [ensemble, aicc] = local_ss_closed(model_type, y, U_past, n, ~, ...
    num_draws, horizon, exo_mode, sirs_cfg, sirs_state, ...
    resample_seed, epidemic_base_seed, vary_epidemic_seed)
%LOCAL_SS_CLOSED Closed-loop state-space bootstrap ensemble on the log scale.
    if std(y) < 1e-8
        ensemble = nan(horizon, num_draws);
        aicc     = inf;
        return;
    end

    data = iddata(y, U_past, 1);
    try
        switch model_type
            case "N4SID"
                sys = n4sid(data, n, n4sidOptions('Display', 'off'));
            case "SSEST"
                sys = ssest(data, n, ssestOptions('Display', 'off'));
        end
    catch
        ensemble = nan(horizon, num_draws);
        aicc     = inf;
        return;
    end
    aicc = sys.Report.Fit.AICc;

    [A, B, C, D, K_gain, X0] = idssdata(sys);

    x         = X0;
    T         = numel(y);
    residuals = zeros(T, 1);
    for t = 1:T
        u_col        = U_past(t, :).';         % column for D*u, B*u
        y_hat        = C * x + D * u_col;
        e_t          = y(t) - y_hat;
        residuals(t) = e_t;
        x            = A * x + B * u_col + K_gain * e_t;
    end
    x_origin  = x;
    residuals = residuals(isfinite(residuals));

    if numel(residuals) < 2
        ensemble = nan(horizon, num_draws);
        aicc     = inf;
        return;
    end

    innovations  = local_resample(residuals, horizon, num_draws, resample_seed);
    pop_size     = sirs_cfg.pop_size;
    base_stepper = sirs_init(sirs_cfg, ...
        struct('solver', 'uds', 'compile', false, 'seed', epidemic_base_seed));

    ensemble = nan(horizon, num_draws);
    for d = 1:num_draws
        draw_seed          = local_draw_seed(epidemic_base_seed, d, horizon, vary_epidemic_seed);
        stepper            = base_stepper;
        stepper.seed       = draw_seed;
        stepper.call_count = 0;
        x                  = x_origin;
        state              = sirs_state;
        u_current          = U_past(end, :).';  % last observed covariate, column for D*u
        col                = nan(horizon, 1);
        for h = 1:horizon
            y_hat   = C * x + D * u_current;
            y_next  = y_hat + innovations(h, d);
            Rt_next = exp(y_next);
            if ~isfinite(Rt_next) || Rt_next <= 0
                break;
            end
            [state, stepper] = sirs_step(stepper, state, Rt_next);
            u_next           = local_exo_col(state, exo_mode, pop_size);
            x                = A * x + B * u_current + K_gain * innovations(h, d);
            col(h)           = Rt_next;
            u_current        = u_next;
        end
        ensemble(:, d) = col;
    end
end

function b_vals = local_extract_b(B_property, nb, nk, num_exo)
%LOCAL_EXTRACT_B Extract active B coefficients from the ARX system polynomial.
    b_vals = cell(1, num_exo);
    if iscell(B_property)
        for j = 1:num_exo
            b_vals{j} = B_property{j}(nk + 1 : nk + nb);
        end
    elseif num_exo == 1
        b_vals{1} = B_property(nk + 1 : nk + nb);
    else
        for j = 1:num_exo
            b_vals{j} = B_property(j, nk + 1 : nk + nb);
        end
    end
end

function y_hat = local_arx_step(a_vals, b_vals, na, nb, nk, log_hist, U_hist)
%LOCAL_ARX_STEP One-step ARX prediction from rolling log and exogenous history.
    T     = numel(log_hist);
    y_hat = 0;
    for lag = 1:na
        y_hat = y_hat - a_vals(lag) * log_hist(T + 1 - lag);
    end
    for j = 1:numel(b_vals)
        for k = 1:nb
            input_lag = nk + k - 1;
            y_hat = y_hat + b_vals{j}(k) * U_hist(T + 1 - input_lag, j);
        end
    end
end

function u = local_exo_row(state, exo_mode, pop_size)
%LOCAL_EXO_ROW Row-vector exogenous covariate from epidemic state (for history update).
    switch exo_mode
        case "S";    u = state(1) / pop_size;
        case "I";    u = state(2) / pop_size;
        case "Both"; u = [state(1), state(2)] / pop_size;
    end
end

function u = local_exo_col(state, exo_mode, pop_size)
%LOCAL_EXO_COL Column-vector exogenous covariate from epidemic state (for matrix multiply).
    switch exo_mode
        case "S";    u = state(1) / pop_size;
        case "I";    u = state(2) / pop_size;
        case "Both"; u = [state(1); state(2)] / pop_size;
    end
end

function seed = local_draw_seed(base, draw_index, horizon, vary)
%LOCAL_DRAW_SEED Per-draw epidemic seed derived from the base seed.
    seed = base;
    if vary
        seed = base + (draw_index - 1) * (horizon + 1);
    end
end

function innovations = local_resample(residuals, horizon, num_draws, resample_seed)
%LOCAL_RESAMPLE Centred residual resample with isolated RNG state.
    centered     = residuals - mean(residuals);
    caller_state = rng;
    cleanup      = onCleanup(@() rng(caller_state));
    rng(resample_seed, 'twister');
    idx         = randi(numel(centered), horizon, num_draws);
    innovations = centered(idx);
    clear cleanup;
end
