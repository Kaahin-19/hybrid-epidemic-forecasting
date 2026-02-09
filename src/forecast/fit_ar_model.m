function [Rt_forecast, sys] = fit_ar_model(Rt_history, horizon, order)
%FIT_AR_MODEL Train an autoregressive model and forecast future Rt.
%
%   Syntax:
%       [Rt_forecast, sys] = fit_ar_model(Rt_history, horizon)
%       [Rt_forecast, sys] = fit_ar_model(Rt_history, horizon, order)
%
%   Description:
%       Implements the "Statistical" component of the Hybrid framework.
%       It fits a linear Auto-Regressive (AR) model to the historical 
%       Rt trajectory and projects it forward into the forecast horizon.
%
%       Method: Least Squares ('ls') estimation is used for stability and
%       computational speed on synthetic data.
%
%   Inputs:
%       Rt_history - Vector of past Rt values (Training Data).
%       horizon    - Integer specifying the number of steps to predict.
%       order      - (Optional) Integer specifying the model order (lags).
%                    Default: 7 (captures weekly periodicity).
%
%   Outputs:
%       Rt_forecast - Vector of predicted Rt values (length = horizon).
%       sys         - The identified IDPOLY system model (for inspection).
%
%   See also PARTA_02_RUN_FORECASTS, AR, FORECAST.

    if nargin < 3, order = 7; end
    
    %% 1. Pre-processing
    % Ensure input is a column vector for the System Identification Toolbox
    Rt_history = Rt_history(:);
    
    %% 2. Model Training
    % Fit an AR(p) model using the Least Squares approach.
    % We use 'ls' because it is robust and efficient for univariate time series.
    sys = ar(Rt_history, order, 'ls'); 
    
    %% 3. Forecasting
    % Create a data object from history to seed the forecast
    data_obj = iddata(Rt_history, [], 1);
    
    % Predict future values (T+1 to T+Horizon)
    f_obj = forecast(sys, data_obj, horizon);
    
    % Extract the raw vector from the iddata result
    Rt_forecast = f_obj.OutputData;
    
end