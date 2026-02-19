function [Rt_curve, aicc] = fit_n4sid(Rt_hist, U_hist, U_future, n, d, horizon)
%FIT_N4SID Fit a State-Space model via N4SID to historical Rt data and forecast.
%
%   Syntax:
%       [Rt_curve, aicc] = fit_n4sid(Rt_hist, U_hist, U_future, n, d, horizon)
%
%   Description:
%       Fits a discrete-time state-space model using the Subspace State-Space 
%       System Identification (N4SID) algorithm. Incorporates optional exogenous 
%       inputs. Employs a threshold-clipped logarithmic transform for numerical 
%       stability. Model selection is penalized via the Corrected Akaike 
%       Information Criterion (AICc).
%
%   Inputs:
%       Rt_hist  - Numeric vector of historical Rt values.
%       U_hist   - Numeric matrix of historical exogenous variables.
%       U_future - Numeric matrix of future exogenous variables.
%       n        - Model order (number of internal states).
%       d        - Degree of differencing (0 or 1).
%       horizon  - Number of time steps to forecast.
%
%   Outputs:
%       Rt_curve - Numeric vector of forecasted Rt values.
%       aicc     - Corrected Akaike Information Criterion score.

% A. M. Kaahin 2026-02-19

    %% 1. Preprocessing
    % Threshold clip before log-transform to handle zero-values without biasing non-zero data
    y = log(max(Rt_hist(:), eps));
    
    if d == 1
        fit_y = diff(y);
        
        if isempty(U_hist)
            fit_u     = [];
            fit_u_fut = [];
        else
            fit_u = diff(U_hist, 1, 1); 
            
            % Difference future exogenous inputs connecting to the last historical row
            combined_fut = [U_hist(end, :); U_future];
            fit_u_fut    = diff(combined_fut, 1, 1);
        end
    else
        fit_y     = y;
        fit_u     = U_hist;
        fit_u_fut = U_future;
    end

    %% 2. Signal Integrity Check
    % If signal variance is negligible, model identification is ill-posed.
    % Return a persistence forecast with theoretically infinite information loss.
    if std(fit_y) < 1e-8
        Rt_curve = repmat(Rt_hist(end), horizon, 1);
        aicc     = inf; 
        return;
    end
    
    %% 3. Model Fitting
    data = iddata(fit_y, fit_u, 1);
    
    try
        % Fit subspace state-space model
        opt_est = n4sidOptions('Display', 'off');
        sys     = n4sid(data, n, opt_est);
        
        % Utilize native System Identification Toolbox AICc calculation
        aicc = sys.Report.Fit.AICc;
        
        %% 4. Forecasting
        fut_data = iddata([], fit_u_fut, 1);
        opt      = forecastOptions('InitialCondition', 'z');
        f_obj    = forecast(sys, data, horizon, fut_data, opt);
        pred_fit = f_obj.OutputData;
        
        %% 5. Postprocessing
        if d == 1
            pred_y = y(end) + cumsum(pred_fit);
        else
            pred_y = pred_fit;
        end
        
        % Reverse log-transform to physical scale
        Rt_curve = exp(pred_y);
        
    catch
        % Fallback to persistence forecast on numerical estimation failure
        Rt_curve = repmat(Rt_hist(end), horizon, 1);
        aicc     = inf;
    end
end