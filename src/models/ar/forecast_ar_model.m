function [Rt_curve, aicc, interval_alphas, lower_bounds, upper_bounds] = ...
    forecast_ar_model(model, horizon, interval_alphas)
%FORECAST_AR_MODEL Forecast future effective Rt from a fitted AR model.
%
%   Syntax:
%       [Rt_curve, aicc, interval_alphas, lower_bounds, upper_bounds] = ...
%           forecast_ar_model(model, horizon, interval_alphas)
%
%   Description:
%       Forecasts the output-only Part A AR model on the log-Rt scale and
%       transforms medians and predictive intervals back to effective Rt.
%
%   Inputs:
%       model           - Structure returned by fit_ar_model.
%       horizon         - Positive integer forecast horizon.
%       interval_alphas - Vector of interval miscoverage rates.
%
%   Outputs:
%       Rt_curve        - Horizon-by-one forecast median vector.
%       aicc            - Corrected AIC from the fitted model when available.
%       interval_alphas - Row vector of interval miscoverage rates.
%       lower_bounds    - Horizon-by-numAlphas lower interval matrix.
%       upper_bounds    - Horizon-by-numAlphas upper interval matrix.
%
%   See also FIT_AR_MODEL, EVALUATE_CANDIDATE.
%
% A. M. Kaahin 2026-05-31

    %% 1. Input Validation
    horizon = local_validate_horizon(horizon);
    interval_alphas = local_validate_alphas(interval_alphas);
    aicc = model.aicc;

    %% 2. Forecasting
    if ~isfield(model, 'is_persistence') || model.is_persistence || isempty(model.sys)
        [Rt_curve, lower_bounds, upper_bounds] = ...
            local_persistence_forecast(model.last_Rt, horizon, interval_alphas);
        return;
    end

    try
        opt = forecastOptions('InitialCondition', 'e');
        [yf, ~, ~, yf_sd] = forecast(model.sys, model.fit_data, horizon, opt);
        pred_log_Rt = local_extract_output(yf);
        pred_sd = local_extract_output(yf_sd);

        if numel(pred_log_Rt) ~= horizon || numel(pred_sd) ~= horizon
            error('AR:InvalidForecastShape', 'AR forecast returned an invalid shape.');
        end

        pred_log_Rt = pred_log_Rt(:);
        pred_sd = max(pred_sd(:), 0);
        if any(~isfinite(pred_log_Rt)) || any(~isfinite(pred_sd)) || any(pred_sd < 0)
            error('AR:InvalidForecastOutput', 'AR forecast output is invalid.');
        end

        [Rt_curve, lower_bounds, upper_bounds] = ...
            local_log_normal_output(pred_log_Rt, pred_sd, interval_alphas);
        local_validate_forecast_output(Rt_curve, lower_bounds, upper_bounds);
    catch
        [Rt_curve, lower_bounds, upper_bounds] = ...
            local_persistence_forecast(model.last_Rt, horizon, interval_alphas);
        aicc = inf;
    end

    local_validate_forecast_output(Rt_curve, lower_bounds, upper_bounds);
end

function horizon = local_validate_horizon(horizon)
%LOCAL_VALIDATE_HORIZON Validate forecast horizon.
    horizon = double(horizon);
    if ~isscalar(horizon) || ~isfinite(horizon) || horizon < 1 || horizon ~= floor(horizon)
        error('AR:InvalidHorizon', 'horizon must be a positive integer scalar.');
    end
end

function interval_alphas = local_validate_alphas(interval_alphas)
%LOCAL_VALIDATE_ALPHAS Validate interval alpha values.
    if nargin < 1 || isempty(interval_alphas)
        interval_alphas = [0.05, 0.10, 0.20, 0.50];
    end

    interval_alphas = reshape(double(interval_alphas), 1, []);
    if isempty(interval_alphas) || any(~isfinite(interval_alphas)) || ...
            any(interval_alphas <= 0 | interval_alphas >= 1)
        error('AR:InvalidAlpha', 'Interval alphas must satisfy 0 < alpha < 1.');
    end
end

function values = local_extract_output(data)
%LOCAL_EXTRACT_OUTPUT Extract numeric values from iddata or numeric arrays.
    if isa(data, 'iddata')
        values = double(data.OutputData(:));
    else
        values = double(data(:));
    end
end

function [Rt_curve, lower_bounds, upper_bounds] = ...
    local_log_normal_output(pred_log_Rt, pred_sd, interval_alphas)
%LOCAL_LOG_NORMAL_OUTPUT Convert log-scale medians and SDs to Rt intervals.
    z_scores = sqrt(2) * erfinv(1 - interval_alphas);
    horizon = numel(pred_log_Rt);
    num_alphas = numel(interval_alphas);

    Rt_curve = exp(pred_log_Rt(:));
    lower_bounds = zeros(horizon, num_alphas);
    upper_bounds = zeros(horizon, num_alphas);
    for j = 1:num_alphas
        lower_bounds(:, j) = exp(pred_log_Rt - z_scores(j) * pred_sd);
        upper_bounds(:, j) = exp(pred_log_Rt + z_scores(j) * pred_sd);
    end
end

function [Rt_curve, lower_bounds, upper_bounds] = ...
    local_persistence_forecast(last_value, horizon, interval_alphas)
%LOCAL_PERSISTENCE_FORECAST Return a deterministic persistence forecast.
    Rt_curve = repmat(double(last_value), horizon, 1);
    lower_bounds = repmat(Rt_curve, 1, numel(interval_alphas));
    upper_bounds = repmat(Rt_curve, 1, numel(interval_alphas));
end

function local_validate_forecast_output(Rt_curve, lower_bounds, upper_bounds)
%LOCAL_VALIDATE_FORECAST_OUTPUT Ensure forecasts and intervals are valid.
    if any(~isfinite(Rt_curve(:))) || any(Rt_curve(:) <= 0) || ...
            any(~isfinite(lower_bounds(:))) || any(lower_bounds(:) <= 0) || ...
            any(~isfinite(upper_bounds(:))) || any(upper_bounds(:) <= 0) || ...
            any(lower_bounds(:) > upper_bounds(:))
        error('AR:InvalidForecastOutput', ...
            'AR forecast values and bounds must be finite, positive, and ordered.');
    end
end
