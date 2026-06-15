function [ensemble, aicc] = forecast_open(model_type, params, Rt_past, ...
    num_draws, horizon, resample_seed)
%FORECAST_OPEN Bootstrap forecast ensemble for output-only models (num_exo == 0).
%
%   Syntax:
%       [ensemble, aicc] = forecast_open(model_type, params, Rt_past,
%                                        num_draws, horizon, resample_seed)
%
%   Description:
%       Fits an AR or output-only state-space model to log(Rt_past), computes
%       one-step prediction residuals via the fitted recursion, resamples
%       centred residuals as innovations under resample_seed, and propagates
%       horizon-step bootstrap paths. Outputs are on the Rt scale
%       (exponentiated). A draw that produces a non-finite or non-positive Rt
%       at any step is left as NaN for that step and all later steps; it cannot
%       re-enter subsequent horizon steps. Range-based validity filtering is the
%       responsibility of interval_bounds. Returns nan(horizon, num_draws) and
%       aicc = inf when: the series is constant (std < 1e-8), the AR history is
%       too short (T <= p+1), fewer than two finite residuals remain after the
%       predictor pass, or the toolbox fit call fails.
%
%   Inputs:
%       model_type    - "AR", "N4SID", or "SSEST".
%       params        - [p] for AR; [n] for state-space.
%       Rt_past       - T×1 historical Rt values.
%       num_draws     - Number of Monte Carlo draws.
%       horizon       - Forecast horizon in steps.
%       resample_seed - Integer seed for the residual resample RNG.
%
%   Outputs:
%       ensemble - horizon×num_draws matrix of Rt bootstrap draws.
%       aicc     - Corrected AIC from the fitted model (inf on fit failure).
%
%   See also FORECAST_CLOSED, INTERVAL_BOUNDS, COMPUTE_WIS.
%
% A. M. Kaahin 2026-06-15

    y = log(Rt_past);

    switch model_type
        case "AR"
            [ensemble, aicc] = local_ar(y, params(1), num_draws, horizon, resample_seed);
        case {"N4SID", "SSEST"}
            [ensemble, aicc] = local_ss_open(model_type, y, params(1), ...
                num_draws, horizon, resample_seed);
        otherwise
            error('FORECAST_OPEN:UnknownModel', 'Unsupported model type: %s', model_type);
    end
end

%% Local functions

function [ensemble, aicc] = local_ar(y, p, num_draws, horizon, resample_seed)
%LOCAL_AR AR bootstrap ensemble on the log scale.
    if std(y) < 1e-8 || numel(y) <= p + 1
        ensemble = nan(horizon, num_draws);
        aicc     = inf;
        return;
    end

    try
        sys = ar(iddata(y, [], 1), p, 'burg');
    catch
        ensemble = nan(horizon, num_draws);
        aicc     = inf;
        return;
    end
    aicc   = sys.Report.Fit.AICc;
    a_vals = sys.A(2:end);                    % 1×p AR coefficients

    T         = numel(y);
    residuals = zeros(T - p, 1);
    for t = (p + 1):T
        y_hat            = -(a_vals * y(t - 1 : -1 : t - p));
        residuals(t - p) = y(t) - y_hat;
    end
    residuals = residuals(isfinite(residuals));

    if numel(residuals) < 2
        ensemble = nan(horizon, num_draws);
        return;
    end

    innovations = local_resample(residuals, horizon, num_draws, resample_seed);

    seed_vals = y(end - p + 1 : end);         % p×1, oldest→newest
    roll      = [repmat(seed_vals, 1, num_draws); zeros(horizon, num_draws)];
    ensemble  = nan(horizon, num_draws);
    active    = true(1, num_draws);
    for h = 1:horizon
        recent     = roll(h : h + p - 1, active);
        y_hat      = -(a_vals * flipud(recent));
        y_next     = y_hat + innovations(h, active);
        Rt_next    = exp(y_next);
        valid_now  = isfinite(y_next) & isfinite(Rt_next) & Rt_next > 0;
        active_idx = find(active);
        valid_idx  = active_idx(valid_now);
        ensemble(h, valid_idx) = Rt_next(valid_now);
        roll(p + h, valid_idx) = y_next(valid_now);
        active(active_idx(~valid_now)) = false;
    end
end

function [ensemble, aicc] = local_ss_open(model_type, y, n, num_draws, horizon, resample_seed)
%LOCAL_SS_OPEN Output-only state-space bootstrap ensemble on the log scale.
    if std(y) < 1e-8
        ensemble = nan(horizon, num_draws);
        aicc     = inf;
        return;
    end

    data = iddata(y, [], 1);
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

    [A, ~, C, ~, K_gain, X0] = idssdata(sys);

    x         = X0;
    T         = numel(y);
    residuals = zeros(T, 1);
    for t = 1:T
        y_hat        = C * x;
        e_t          = y(t) - y_hat;
        residuals(t) = e_t;
        x            = A * x + K_gain * e_t;
    end
    x_origin  = x;
    residuals = residuals(isfinite(residuals));

    if numel(residuals) < 2
        ensemble = nan(horizon, num_draws);
        return;
    end

    innovations = local_resample(residuals, horizon, num_draws, resample_seed);

    ensemble = nan(horizon, num_draws);
    for d = 1:num_draws
        x   = x_origin;
        col = nan(horizon, 1);
        for h = 1:horizon
            y_hat   = C * x;
            y_next  = y_hat + innovations(h, d);
            Rt_next = exp(y_next);
            if ~isfinite(Rt_next) || Rt_next <= 0
                break;
            end
            col(h) = Rt_next;
            x      = A * x + K_gain * innovations(h, d);
        end
        ensemble(:, d) = col;
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
