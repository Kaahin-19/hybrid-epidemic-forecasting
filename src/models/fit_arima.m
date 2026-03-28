function [Rt_curve, aicc, interval_alphas, lower_bounds, upper_bounds] = fit_arima(Rt_hist, p, d, q, horizon, interval_alphas)
%FIT_ARIMA Fit an ARIMA(p,d,q) model to historical Rt data and forecast.
%
%   Syntax:
%       [Rt_curve, aicc, interval_alphas, lower_bounds, upper_bounds] = ...
%           fit_arima(Rt_hist, p, d, q, horizon, interval_alphas)
%
%   Description:
%       Fits an Autoregressive Integrated Moving Average model to a historical
%       Rt time series. Employs a threshold-clipped logarithmic transform for
%       numerical stability and computes analytic predictive intervals from
%       forecast uncertainty. Model selection is driven by the Corrected
%       Akaike Information Criterion (AICc).
%
%   Inputs:
%       Rt_hist  - Numeric vector of historical Rt values.
%       p        - Autoregressive polynomial order.
%       d        - Degree of differencing (0 or 1).
%       q        - Moving average polynomial order.
%       horizon  - Number of time steps to forecast.
%       interval_alphas - Vector of interval miscoverage rates.
%
%   Outputs:
%       Rt_curve       - Numeric vector of forecast medians.
%       aicc           - Corrected Akaike Information Criterion score.
%       interval_alphas - Vector of interval miscoverage rates.
%       lower_bounds   - Matrix of lower predictive interval bounds.
%       upper_bounds   - Matrix of upper predictive interval bounds.
%
%   See also FIT_ARIMAX, FIT_N4SID, FIT_SSEST, PARTA_03_RUN_FORECASTS.

% A. M. Kaahin 2026-02-19
% Modified: 2026-03-28

    %% 1. Preprocessing
    if nargin < 6 || isempty(interval_alphas)
        interval_alphas = [0.05, 0.10, 0.20, 0.50];
    else
        interval_alphas = reshape(double(interval_alphas), 1, []);
    end

    if any(interval_alphas <= 0 | interval_alphas >= 1)
        error('FIT:InvalidAlpha', 'Interval alphas must satisfy 0 < alpha < 1.');
    end

    y = log(max(Rt_hist(:), eps));
    
    if d == 1
        fit_data = diff(y);
    else
        fit_data = y;
    end

    %% 2. Signal Integrity Check
    if std(fit_data) < 1e-8
        [Rt_curve, lower_bounds, upper_bounds] = local_persistence_forecast(Rt_hist(end), horizon, interval_alphas);
        aicc = inf;
        return;
    end
    
    %% 3. Model Order Validation
    n = length(fit_data);
    k = p + q; 
    
    if n <= k + 1
        [Rt_curve, lower_bounds, upper_bounds] = local_persistence_forecast(Rt_hist(end), horizon, interval_alphas);
        aicc = inf;
        return;
    end
    
    %% 4. Model Fitting
    data = iddata(fit_data, [], 1);
    
    try
        if q == 0
            sys = ar(data, p, 'burg');
        else
            sys = armax(data, [p, q], 'Display', 'off');
        end
        
        aicc = sys.Report.Fit.AICc;
        
        %% 5. Forecasting
        opt = forecastOptions('InitialCondition', 'e');
        [yf, ~, ~, yf_sd] = forecast(sys, data, horizon, opt);
        pred_fit = local_extract_output(yf);
        pred_sd  = local_extract_output(yf_sd);

        %% 6. Postprocessing
        if d == 1
            pred_y = y(end) + cumsum(pred_fit);
        else
            pred_y = pred_fit;
        end

        if numel(pred_sd) ~= horizon || any(~isfinite(pred_sd(:))) || any(pred_sd(:) < 0)
            error('FIT:InvalidForecastVariance', 'Forecast uncertainty is invalid.');
        end

        pred_sd = max(pred_sd(:), 0);

        Rt_curve = exp(pred_y);
        [lower_bounds, upper_bounds] = local_interval_bounds(pred_y, pred_sd, interval_alphas);

        if any(~isfinite(Rt_curve(:))) || any(~isfinite(lower_bounds(:))) || any(~isfinite(upper_bounds(:)))
            error('FIT:InvalidForecastOutput', 'Forecast output is invalid.');
        end
        
    catch
        [Rt_curve, lower_bounds, upper_bounds] = local_persistence_forecast(Rt_hist(end), horizon, interval_alphas);
        aicc = inf;
    end
end

%% 7. Local Helpers
function values = local_extract_output(data)
    if isa(data, 'iddata')
        values = double(data.OutputData(:));
    else
        values = double(data(:));
    end
end

function [lower_bounds, upper_bounds] = local_interval_bounds(pred_y, pred_sd, interval_alphas)
    horizon = numel(pred_y);
    num_alphas = numel(interval_alphas);

    lower_bounds = zeros(horizon, num_alphas);
    upper_bounds = zeros(horizon, num_alphas);
    z_scores = sqrt(2) * erfinv(1 - interval_alphas);

    for k = 1:num_alphas
        lower_bounds(:, k) = exp(pred_y - z_scores(k) * pred_sd);
        upper_bounds(:, k) = exp(pred_y + z_scores(k) * pred_sd);
    end
end

function [Rt_curve, lower_bounds, upper_bounds] = local_persistence_forecast(last_value, horizon, interval_alphas)
    Rt_curve = repmat(last_value, horizon, 1);
    lower_bounds = repmat(Rt_curve, 1, numel(interval_alphas));
    upper_bounds = repmat(Rt_curve, 1, numel(interval_alphas));
end
