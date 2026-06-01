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
%       coefficient machinery with closed-loop SIRS feedback.
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
%   See also SIMULATE_AR_RESIDUAL_BOOTSTRAP_PATHS, ...
%            SIMULATE_ARX_CLOSED_LOOP_BOOTSTRAP_PATHS, FIT_AR_MODEL, FIT_ARX_MODEL.
%
% A. M. Kaahin 2026-06-01

    %% 1. Setup
    model_type = char(model_type);
    params = reshape(double(params), 1, []);
    out_alphas = reshape(double(interval_options.alphas), 1, []);
    horizon = double(interval_options.horizon);
    num_draws = double(interval_options.num_draws);
    Rt_past = double(Rt_past(:));
    log_past = log(max(Rt_past, eps));

    meta = local_base_meta(interval_options);

    %% 2. Family Dispatch
    switch model_type
        case 'AR'
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
            ensemble = simulate_ar_residual_bootstrap_paths( ...
                model.coefficients.a_values, model.log_history, innovations);

        case 'ARX'
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
            ensemble = simulate_arx_closed_loop_bootstrap_paths( ...
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
        [Rt_pred, aicc, lower_bounds, upper_bounds] = local_deterministic_fallback( ...
            model_type, model, Rt_past, U_past, sirs_state, ...
            interval_options, out_alphas, horizon);
        meta.interval_status = "deterministic_fallback";
        meta.num_valid_draws = num_valid;
        meta.residual_status = residual_status;
        return;
    end

    [Rt_pred, lower_bounds, upper_bounds] = ...
        compute_interval_bounds_from_ensemble(valid_ensemble, out_alphas);

    meta.num_valid_draws = num_valid;
    meta.residual_status = residual_status;
    meta.interval_status = local_resolve_status(residual_status, num_valid, num_draws);
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
%   Draws that reached the divergence clamp (Rt at or beyond 1e-2 / 1e2) are
%   dropped so unstable trajectories cannot dominate the empirical quantiles.
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

function [Rt_pred, aicc, lower_bounds, upper_bounds] = local_deterministic_fallback( ...
    model_type, model, Rt_past, U_past, sirs_state, interval_options, alphas, horizon)
%LOCAL_DETERMINISTIC_FALLBACK Reuse analytic forecasts when draws are invalid.
    exo_mode = char(interval_options.exo_mode);
    sirs_cfg = interval_options.sirs_cfg;
    sim_seed = interval_options.sim_seed;

    switch model_type
        case 'AR'
            [Rt_pred, aicc, ~, lower_bounds, upper_bounds] = ...
                forecast_ar_model(model, horizon, alphas);
        case 'ARX'
            [Rt_pred, aicc, ~, lower_bounds, upper_bounds] = ...
                forecast_arx_closed_loop(model, Rt_past, U_past, sirs_state, ...
                sirs_cfg, exo_mode, horizon, alphas, sim_seed);
        otherwise
            error('INTERVALS:UnknownModel', 'Unsupported model for fallback.');
    end
    Rt_pred = double(Rt_pred(:));
end
