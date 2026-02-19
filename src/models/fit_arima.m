function [Rt_curve, aicc] = fit_arima(Rt_hist, p, d, q, horizon)
%FIT_ARIMA Fit an ARIMA(p,d,q) model to historical Rt data and forecast.
%
%   Syntax:
%       [Rt_curve, aicc] = fit_arima(Rt_hist, p, d, q, horizon)
%
%   Description:
%       Fits an Autoregressive Integrated Moving Average model to a historical
%       Rt time series. Employs a threshold-clipped logarithmic transform for 
%       numerical stability and positivity. Model selection is driven by the 
%       Corrected Akaike Information Criterion (AICc).
%
%   Inputs:
%       Rt_hist - Numeric vector of historical Rt values.
%       p       - Autoregressive polynomial order.
%       d       - Degree of differencing (0 or 1).
%       q       - Moving average polynomial order.
%       horizon - Number of time steps to forecast.
%
%   Outputs:
%       Rt_curve - Numeric vector of forecasted Rt values.
%       aicc     - Corrected Akaike Information Criterion score.

% A. M. Kaahin 2026-02-19

    %% 1. Preprocessing
    % Threshold clip before log-transform to handle zero-values without biasing non-zero data
    y = log(max(Rt_hist(:), eps));
    
    if d == 1
        fit_data = diff(y);
    else
        fit_data = y;
    end

    %% 2. Signal Integrity Check
    % If signal variance is negligible, model identification is ill-posed.
    % Return a persistence forecast with theoretically infinite information loss.
    if std(fit_data) < 1e-8
        Rt_curve = repmat(Rt_hist(end), horizon, 1);
        aicc     = inf; 
        return;
    end
    
    %% 3. Model Order Validation
    n = length(fit_data);
    k = p + q; 
    
    if n <= k + 1
        Rt_curve = repmat(Rt_hist(end), horizon, 1); 
        aicc     = inf; 
        return;
    end
    
    %% 4. Model Fitting
    data = iddata(fit_data, [], 1);
    
    try
        if q == 0
            % Burg's method guarantees stability for purely autoregressive models on short data windows
            sys = ar(data, p, 'burg');
        else
            sys = armax(data, [p, q], 'Display', 'off');
        end
        
        % Utilize native System Identification Toolbox AICc calculation
        aicc = sys.Report.Fit.AICc;
        
        %% 5. Forecasting
        opt      = forecastOptions('InitialCondition', 'z');
        f_obj    = forecast(sys, data, horizon, opt);
        pred_fit = f_obj.OutputData;
        
        %% 6. Postprocessing
        if d == 1
            pred_y = y(end) + cumsum(pred_fit);
        else
            pred_y = pred_fit;
        end
        
        % Reverse log-transform and constrain to physical bounds
        Rt_curve = exp(pred_y);
        Rt_curve = max(0, min(10, Rt_curve));
        
    catch
        % Fallback to persistence forecast on numerical estimation failure
        Rt_curve = repmat(Rt_hist(end), horizon, 1);
        aicc     = inf;
    end
end