function [Rt_pred, aicc, out_alphas, lower_bounds, upper_bounds, meta] = ...
    simulate_ar_arx_intervals(model_type, params, Rt_past, U_past, ...
    sirs_state, num_exo, interval_options)
%SIMULATE_AR_ARX_INTERVALS Closed-loop bootstrap intervals for AR and ARX.
%
%   Syntax:
%       [Rt_pred, aicc, out_alphas, lower_bounds, upper_bounds, meta] = ...
%           simulate_ar_arx_intervals(model_type, params, Rt_past, U_past, ...
%           sirs_state, num_exo, interval_options)
%
%   Description:
%       Family entry point that produces closed-loop predictive intervals for
%       the AR and ARX model families. The model is fitted through the existing
%       fit_ar_model / fit_arx_model path; one-step residual innovations are
%       estimated from the fitted recursion and resampled; an ensemble of
%       horizon trajectories is generated; and the empirical quantiles form the
%       predictive median and interval bounds. AR uses the output-only
%       recursion (no epidemic state), while ARX uses the recursive ARX
%       coefficient machinery with closed-loop SIRS feedback. If too few
%       simulated paths remain plausible, the forecast is returned as an
%       explicit invalid failure rather than being replaced by an unconstrained
%       deterministic trajectory.
%
%   Inputs:
%       model_type       - "AR" or "ARX".
%       params           - Candidate configuration row (AR: [p]; ARX: [na nb nk]).
%       Rt_past          - Historical effective Rt values.
%       U_past           - Historical exogenous covariate matrix (ARX).
%       sirs_state       - Current [S, I, R] state at the forecast origin (ARX).
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
%   See also FIT_AR_MODEL, FIT_ARX_MODEL, RECURSIVE_ARX_STEP, ...
%            INITIALIZE_SIRS_STEPPER, ADVANCE_SIRS_STEPPER.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-12

    %% 1. Setup
    model_type = string(model_type);
    params = reshape(double(params), 1, []);
    out_alphas = reshape(double(interval_options.alphas), 1, []);
    horizon = double(interval_options.horizon);
    num_draws = double(interval_options.num_draws);
    Rt_past = double(Rt_past(:));
    log_past = log(Rt_past);

    meta = local_base_meta(interval_options);

    %% 2. Family Dispatch
    switch model_type
        case "AR"
            model = fit_ar_model(Rt_past, params(1));
            aicc = model.aicc;
            if local_is_persistence(model)
                [Rt_pred, lower_bounds, upper_bounds] = ...
                    local_persistence(Rt_past(end), horizon, out_alphas);
                meta.interval_status = "persistence_fallback";
                return;
            end

            residuals = local_ar_residuals(model.coefficients.a_values, model.log_history);
            [innovations, residual_status] = sample_centered_residuals( ...
                residuals, num_draws, horizon, interval_options.resample_seed, ...
                interval_options.min_residual_std);
            ensemble = local_ar_bootstrap_paths( ...
                model.coefficients.a_values, model.log_history, innovations);

        case "ARX"
            nb_vec = repmat(params(2), 1, num_exo);
            nk_vec = repmat(params(3), 1, num_exo);
            model = fit_arx_model(Rt_past, U_past, params(1), nb_vec, nk_vec);
            aicc = model.aicc;
            if local_is_persistence(model)
                [Rt_pred, lower_bounds, upper_bounds] = ...
                    local_persistence(Rt_past(end), horizon, out_alphas);
                meta.interval_status = "persistence_fallback";
                return;
            end

            residuals = local_arx_residuals(model.coefficients, log_past, U_past);
            [innovations, residual_status] = sample_centered_residuals( ...
                residuals, num_draws, horizon, interval_options.resample_seed, ...
                interval_options.min_residual_std);
            ensemble = local_arx_closed_loop_bootstrap_paths( ...
                model.coefficients, log_past, U_past, sirs_state, ...
                innovations, interval_options);

        otherwise
            error('INTERVALS:UnknownModel', ...
                'simulate_ar_arx_intervals supports AR and ARX only.');
    end

    %% 3. Ensemble Reduction with Validity Guard
    [valid_ensemble, num_valid] = local_valid_columns(ensemble);
    min_valid = max(2, ceil(0.2 * num_draws));

    if num_valid < min_valid
        [Rt_pred, lower_bounds, upper_bounds] = ...
            local_insufficient_draws_failure(horizon, out_alphas);
        meta.interval_status = "insufficient_valid_draws";
        meta.num_valid_draws = num_valid;
        meta.min_valid_draws = min_valid;
        meta.residual_status = residual_status;
        return;
    end

    [Rt_pred, lower_bounds, upper_bounds] = ...
        compute_interval_bounds_from_ensemble(valid_ensemble, out_alphas);

    meta.num_valid_draws = num_valid;
    meta.residual_status = residual_status;
    meta.interval_status = local_resolve_status(residual_status, num_valid, num_draws);
end

%% 4. Local Functions
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

function tf = local_is_persistence(model)
%LOCAL_IS_PERSISTENCE Detect a persistence-fallback fitted model.
    tf = ~isfield(model, 'is_persistence') || model.is_persistence;
end

function residuals = local_ar_residuals(a_values, log_history)
%LOCAL_AR_RESIDUALS One-step AR residual innovations on the log scale.
    a_values = reshape(double(a_values), [], 1);
    p = numel(a_values);
    log_history = double(log_history(:));
    residuals = nan(max(0, numel(log_history) - p), 1);

    for t = (p + 1):numel(log_history)
        y_pred = 0;
        for lag = 1:p
            y_pred = y_pred - a_values(lag) * log_history(t - lag);
        end
        residuals(t - p) = log_history(t) - y_pred;
    end
    residuals = residuals(isfinite(residuals));
end

function residuals = local_arx_residuals(coefficients, log_history, U_history)
%LOCAL_ARX_RESIDUALS One-step ARX residual innovations on the log scale.
    log_history = double(log_history(:));
    U_history = double(U_history);
    if isvector(U_history)
        U_history = U_history(:);
    end

    max_lag = max([coefficients.na, coefficients.nk_vec + coefficients.nb_vec - 1]);
    residuals = nan(max(0, numel(log_history) - max_lag), 1);

    for t = (max_lag + 1):numel(log_history)
        y_pred = recursive_arx_step(coefficients, ...
            log_history(1:(t - 1)), U_history(1:(t - 1), :));
        residuals(t - max_lag) = log_history(t) - y_pred;
    end
    residuals = residuals(isfinite(residuals));
end

function [valid_ensemble, num_valid] = local_valid_columns(ensemble)
%LOCAL_VALID_COLUMNS Keep finite draws strictly inside the plausibility band.
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

function [Rt_pred, lower_bounds, upper_bounds] = ...
    local_persistence(last_value, horizon, alphas)
%LOCAL_PERSISTENCE Deterministic persistence intervals (zero width).
    Rt_pred = repmat(double(last_value), horizon, 1);
    lower_bounds = repmat(Rt_pred, 1, numel(alphas));
    upper_bounds = repmat(Rt_pred, 1, numel(alphas));
end

function [Rt_pred, lower_bounds, upper_bounds] = ...
    local_insufficient_draws_failure(horizon, alphas)
%LOCAL_INSUFFICIENT_DRAWS_FAILURE Return a shaped invalid forecast failure.
    Rt_pred = nan(horizon, 1);
    lower_bounds = nan(horizon, numel(alphas));
    upper_bounds = nan(horizon, numel(alphas));
end

%% 5. Path Simulators
function ensemble_Rt = local_ar_bootstrap_paths(a_values, log_history, innovations)
%LOCAL_AR_BOOTSTRAP_PATHS Recursive output-only AR bootstrap Rt trajectories.
    a_values = reshape(double(a_values), [], 1);
    p = numel(a_values);
    log_history = double(log_history(:));
    if numel(log_history) < p
        error('INTERVALS:InsufficientHistory', ...
            'log_history is too short for the requested AR order.');
    end

    [horizon, num_draws] = size(innovations);
[log_lo, log_hi] = local_log_clip_range();
roll = zeros(p + horizon, num_draws);
roll(1:p, :) = repmat(log_history, 1, num_draws);
ensemble_Rt = zeros(horizon, num_draws);

for h = 1:horizon
    recent = roll(h:(h + p - 1), :);
    recent_newest_first = flipud(recent);
    y_hat = -(a_values.' * recent_newest_first);
    y_next = y_hat + innovations(h, :);
    y_next = min(max(y_next, log_lo), log_hi);
    ensemble_Rt(h, :) = exp(y_next);
    roll(p + h, :) = y_next;
end
end

function ensemble_Rt = local_arx_closed_loop_bootstrap_paths( ...
    coefficients, log_history, U_history, sirs_state, innovations, interval_options)
%LOCAL_ARX_CLOSED_LOOP_BOOTSTRAP_PATHS Closed-loop ARX bootstrap trajectories.
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

    sim_options = struct('solver', 'uds', 'compile', false, ...
        'seed', local_valid_seed(interval_options.epidemic_base_seed));
    stepper = initialize_sirs_stepper(sirs_cfg, sim_options);

    ensemble_Rt = nan(horizon, num_draws);
    for d = 1:num_draws
        draw_seed = local_draw_epidemic_seed(interval_options, d, horizon);
        ensemble_Rt(:, d) = local_resimulate_draw( ...
            coefficients, log_history, U_history, sirs_state, ...
            innovations(:, d), stepper, draw_seed, exo_mode, pop_size, ...
            horizon, log_lo, log_hi);
    end
end

function column = local_resimulate_draw( ...
    coefficients, log_history, U_history, sirs_state, innovation_column, ...
    stepper, draw_seed, exo_mode, pop_size, horizon, log_lo, log_hi)
%LOCAL_RESIMULATE_DRAW One Monte Carlo draw with per-draw epidemic advances.
    column = nan(horizon, 1);
try
    history_len = numel(log_history);
    rolling_log = zeros(history_len + horizon, 1);
    rolling_U = zeros(history_len + horizon, size(U_history, 2));
    rolling_log(1:history_len) = log_history;
    rolling_U(1:history_len, :) = U_history;
    state = local_sanitize_state(sirs_state, pop_size);
    stepper.seed = draw_seed;
    stepper.call_count = 0;

    for h = 1:horizon
        idx = history_len + h - 1;
        y_hat = recursive_arx_step(coefficients, rolling_log(1:idx), rolling_U(1:idx, :));
        y_next = min(max(y_hat + innovation_column(h), log_lo), log_hi);
        Rt_next = exp(y_next);
            if ~isfinite(Rt_next) || Rt_next <= 0
                column = nan(horizon, 1);
                return;
            end

        [state, stepper] = advance_sirs_stepper(stepper, state, Rt_next);
        U_next = extract_exogenous_from_state(state, exo_mode, pop_size);

        column(h) = Rt_next;
        rolling_log(idx + 1) = y_next;
        rolling_U(idx + 1, :) = U_next;
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
