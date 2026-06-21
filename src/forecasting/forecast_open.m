function [point_path, ensemble_paths, fit_info] = forecast_open(model_type, params, ...
    Rt_past, num_draws, horizon, resample_seed)
%FORECAST_OPEN Bootstrap forecast ensemble for output-only models (num_exo == 0).
%
%   Syntax:
%       [point_path, ensemble_paths, fit_info] = forecast_open(model_type, params,
%           Rt_past, num_draws, horizon, resample_seed)
%
%   Description:
%       Fits an AR or output-only state-space model to log(Rt_past), computes
%       one-step prediction residuals via the fitted recursion, resamples
%       centred residuals as innovations under resample_seed, and propagates
%       horizon-step bootstrap paths on the Rt scale (exponentiated). Every draw
%       must complete the full horizon with finite, positive Rt; a draw that
%       produces a non-finite or non-positive Rt raises
%       FORECAST_OPEN:InvalidForecastDraw. Degenerate fits raise
%       FORECAST_OPEN:ConstantSeries, :InsufficientHistory, or
%       :InsufficientResiduals, and toolbox fit errors propagate unchanged. The
%       function never returns an all-NaN fallback and never computes WIS.
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
%       point_path     - horizon×1 Rt point forecast (median across draws).
%       ensemble_paths - horizon×num_draws matrix of finite Rt bootstrap draws.
%       fit_info       - Struct with field AICc (corrected AIC of the fitted model).
%
%   See also FORECAST_CLOSED, INTERVAL_BOUNDS, COMPUTE_WIS.
%
% A. M. Kaahin 2026-06-15
% Modified: 2026-06-21

    y = log(Rt_past);

    switch model_type
        case "AR"
            [ensemble_paths, aicc] = local_ar(y, params(1), num_draws, horizon, resample_seed);
        case {"N4SID", "SSEST"}
            [ensemble_paths, aicc] = local_ss_open(model_type, y, params(1), ...
                num_draws, horizon, resample_seed);
        otherwise
            error('FORECAST_OPEN:UnknownModel', 'Unsupported model type: %s', model_type);
    end

    point_path = median(ensemble_paths, 2);
    fit_info   = struct('AICc', aicc);
end

%% Local functions

function [ensemble, aicc] = local_ar(y, p, num_draws, horizon, resample_seed)
%LOCAL_AR AR bootstrap ensemble on the log scale.
    if std(y) < 1e-8
        error('FORECAST_OPEN:ConstantSeries', ...
            'log(Rt_past) is effectively constant (std < 1e-8); cannot fit AR model.');
    end
    if numel(y) <= p + 1
        error('FORECAST_OPEN:InsufficientHistory', ...
            'AR history too short: numel(y) = %d <= p + 1 = %d.', numel(y), p + 1);
    end

    sys    = ar(iddata(y, [], 1), p, 'burg');
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
        error('FORECAST_OPEN:InsufficientResiduals', ...
            'Fewer than two finite AR residuals available.');
    end

    innovations = local_resample(residuals, horizon, num_draws, resample_seed);

    seed_vals = y(end - p + 1 : end);         % p×1, oldest→newest
    roll      = [repmat(seed_vals, 1, num_draws); zeros(horizon, num_draws)];
    ensemble  = zeros(horizon, num_draws);
    for h = 1:horizon
        recent  = roll(h : h + p - 1, :);
        y_hat   = -(a_vals * flipud(recent));
        y_next  = y_hat + innovations(h, :);
        Rt_next = exp(y_next);
        if ~all(isfinite(Rt_next) & Rt_next > 0)
            error('FORECAST_OPEN:InvalidForecastDraw', ...
                'Bootstrap draw produced a non-finite or non-positive Rt.');
        end
        ensemble(h, :) = Rt_next;
        roll(p + h, :) = y_next;
    end
end

function [ensemble, aicc] = local_ss_open(model_type, y, n, num_draws, horizon, resample_seed)
%LOCAL_SS_OPEN Output-only state-space bootstrap ensemble on the log scale.
    if std(y) < 1e-8
        error('FORECAST_OPEN:ConstantSeries', ...
            'log(Rt_past) is effectively constant (std < 1e-8); cannot fit state-space model.');
    end

    data = iddata(y, [], 1);
    switch model_type
        case "N4SID"
            sys = n4sid(data, n, n4sidOptions('Display', 'off'));
        case "SSEST"
            sys = ssest(data, n, ssestOptions('Display', 'off'));
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
        error('FORECAST_OPEN:InsufficientResiduals', ...
            'Fewer than two finite state-space residuals available.');
    end

    innovations = local_resample(residuals, horizon, num_draws, resample_seed);

    ensemble = zeros(horizon, num_draws);
    for d = 1:num_draws
        x = x_origin;
        for h = 1:horizon
            y_hat   = C * x;
            y_next  = y_hat + innovations(h, d);
            Rt_next = exp(y_next);
            if ~isfinite(Rt_next) || Rt_next <= 0
                error('FORECAST_OPEN:InvalidForecastDraw', ...
                    'Bootstrap draw produced a non-finite or non-positive Rt.');
            end
            ensemble(h, d) = Rt_next;
            x              = A * x + K_gain * innovations(h, d);
        end
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
