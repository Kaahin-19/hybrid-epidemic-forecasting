function [Rt_curve, aicc] = fit_arimax(Rt_hist, U_hist, U_future, p, d, q, nb_vec, nk_vec, horizon)
%FIT_ARIMAX Fit an ARIMAX model to historical Rt and exogenous data, and forecast.
%
%   Syntax:
%       [Rt_curve, aicc] = fit_arimax(Rt_hist, U_hist, U_future, p, d, q, nb_vec, nk_vec, horizon)
%
%   Description:
%       Fits an Autoregressive Integrated Moving Average with Exogenous inputs
%       (ARIMAX) model to a historical Rt time series and associated exogenous
%       covariates. Employs a threshold-clipped logarithmic transform for 
%       numerical stability. Model selection is driven by the Corrected Akaike 
%       Information Criterion (AICc).
%
%   Inputs:
%       Rt_hist  - Numeric vector of historical Rt values.
%       U_hist   - Numeric matrix of historical exogenous variables.
%       U_future - Numeric matrix of future exogenous variables.
%       p        - Autoregressive polynomial order.
%       d        - Degree of differencing (0 or 1).
%       q        - Moving average polynomial order.
%       nb_vec   - Vector of exogenous memory orders per input.
%       nk_vec   - Vector of exogenous delays per input.
%       horizon  - Number of time steps to forecast.
%
%   Outputs:
%       Rt_curve - Numeric vector of forecasted Rt values.
%       aicc     - Corrected Akaike Information Criterion score.
%
%   See also FIT_ARIMA, FIT_N4SID, FIT_SSEST, PARTA_02_RUN_FORECASTS.

% A. M. Kaahin 2026-02-19

    %% 1. Preprocessing
    % Apply threshold clipping prior to log-transformation
    y = log(max(Rt_hist(:), eps));
    
    if d == 1
        fit_y = diff(y);
        fit_u = diff(U_hist, 1, 1); 
        
        % Difference future exogenous inputs relative to final historical value
        combined_fut = [U_hist(end, :); U_future];
        fit_u_fut    = diff(combined_fut, 1, 1);
    else
        fit_y     = y;
        fit_u     = U_hist;
        fit_u_fut = U_future;
    end

    %% 2. Signal Integrity Check
    % Return persistence forecast if signal variance is negligible
    if std(fit_y) < 1e-8
        Rt_curve = repmat(Rt_hist(end), horizon, 1);
        aicc     = inf; 
        return;
    end
    
    %% 3. Model Order Validation
    % Validate model order constraints including exogenous memory
    n = length(fit_y);
    k = p + q + sum(nb_vec); 
    
    if n <= k + 1
        Rt_curve = repmat(Rt_hist(end), horizon, 1); 
        aicc     = inf; 
        return;
    end
    
    %% 4. Model Fitting
    data = iddata(fit_y, fit_u, 1);
    
    try
        if q == 0
            sys = arx(data, [p, nb_vec, nk_vec]);
        else
            sys = armax(data, [p, nb_vec, q, nk_vec], 'Display', 'off');
        end
        
        % Extract AICc score
        aicc = sys.Report.Fit.AICc;
        
        %% 5. Forecasting
        fut_data = iddata([], fit_u_fut, 1);
        opt      = forecastOptions('InitialCondition', 'e');
        f_obj    = forecast(sys, data, horizon, fut_data, opt);
        pred_fit = f_obj.OutputData;
        
        %% 6. Postprocessing
        if d == 1
            pred_y = y(end) + cumsum(pred_fit);
        else
            pred_y = pred_fit;
        end
        
        % Reverse transformation and enforce physical bounds
        Rt_curve = exp(pred_y);
        Rt_curve = max(0, min(10, Rt_curve));
        
    catch
        % Fallback to persistence forecast on estimation failure
        Rt_curve = repmat(Rt_hist(end), horizon, 1);
        aicc     = inf;
    end
end