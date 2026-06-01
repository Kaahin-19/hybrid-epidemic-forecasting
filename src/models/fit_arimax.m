function [Rt_curve, aicc, interval_alphas, lower_bounds, upper_bounds] = fit_arimax( ...
    Rt_hist, U_hist, U_future, p, d, q, nb_vec, nk_vec, horizon, interval_alphas, ...
    sirs_state, sirs_params, exo_mode, sim_seed)
%FIT_ARIMAX Fit an ARIMAX model to historical Rt and exogenous data, and forecast.
%
%   Syntax:
%       [Rt_curve, aicc, interval_alphas, lower_bounds, upper_bounds] = ...
%           fit_arimax(Rt_hist, U_hist, U_future, p, d, q, nb_vec, nk_vec, ...
%           horizon, interval_alphas)
%
%   Description:
%       Fits an Autoregressive Integrated Moving Average with Exogenous inputs
%       (ARIMAX) model to a historical Rt time series and associated exogenous
%       covariates. Employs a threshold-clipped logarithmic transform for
%       numerical stability and computes analytic predictive intervals from
%       forecast uncertainty. When a current SIRS state is supplied, future
%       exogenous covariates are generated recursively from one-step Rt
%       forecasts and URDME/UDS SIRS advancement. The returned AICc is reported
%       for reference; global hyperparameter selection is performed by the
%       pipeline using WIS.
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
%       interval_alphas - Vector of interval miscoverage rates.
%       sirs_state  - Optional current [S, I, R] state for closed-loop mode.
%       sirs_params - Optional SIRS parameter structure.
%       exo_mode    - Optional exogenous mode: S, I, or Both.
%       sim_seed    - Optional URDME/UDS simulation seed.
%
%   Outputs:
%       Rt_curve       - Numeric vector of forecast medians.
%       aicc           - Corrected Akaike Information Criterion value.
%       interval_alphas - Vector of interval miscoverage rates.
%       lower_bounds   - Matrix of lower predictive interval bounds.
%       upper_bounds   - Matrix of upper predictive interval bounds.
%
%   See also FIT_ARIMA, FIT_N4SID_MODEL, FIT_SSEST_MODEL, PARTA_03_RUN_FORECASTS.

% A. M. Kaahin 2026-02-19
% Modified: 2026-05-04

    %% 1. Preprocessing
    if nargin < 10 || isempty(interval_alphas)
        interval_alphas = [0.05, 0.10, 0.20, 0.50];
    else
        interval_alphas = reshape(double(interval_alphas), 1, []);
    end

    if any(interval_alphas <= 0 | interval_alphas >= 1)
        error('FIT:InvalidAlpha', 'Interval alphas must satisfy 0 < alpha < 1.');
    end

    if nargin < 11, sirs_state = []; end
    if nargin < 12, sirs_params = []; end
    if nargin < 13, exo_mode = ''; end
    if nargin < 14, sim_seed = []; end

    use_closed_loop = local_use_closed_loop(U_hist, sirs_state, sirs_params, exo_mode);

    y = log(max(Rt_hist(:), eps));
    
    if d == 1
        fit_y = diff(y);
        fit_u = diff(U_hist, 1, 1); 
        
        if use_closed_loop
            fit_u_fut = [];
        else
            combined_fut = [U_hist(end, :); U_future];
            fit_u_fut    = diff(combined_fut, 1, 1);
        end
    else
        fit_y     = y;
        fit_u     = U_hist;
        if use_closed_loop
            fit_u_fut = [];
        else
            fit_u_fut = U_future;
        end
    end

    %% 2. Signal Integrity Check
    if std(fit_y) < 1e-8
        [Rt_curve, lower_bounds, upper_bounds] = local_persistence_forecast(Rt_hist(end), horizon, interval_alphas);
        aicc = inf;
        return;
    end
    
    %% 3. Model Order Validation
    n = length(fit_y);
    k = p + q + sum(nb_vec); 
    
    if n <= k + 1
        [Rt_curve, lower_bounds, upper_bounds] = local_persistence_forecast(Rt_hist(end), horizon, interval_alphas);
        aicc = inf;
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
        
        aicc = sys.Report.Fit.AICc;
        
        %% 5. Forecasting
        opt = forecastOptions('InitialCondition', 'e');
        if use_closed_loop
            [pred_y, pred_sd] = local_closed_loop_forecast( ...
                sys, Rt_hist, U_hist, d, horizon, sirs_state, ...
                sirs_params, exo_mode, sim_seed, opt);
        else
            [yf, ~, ~, yf_sd] = forecast(sys, data, horizon, fit_u_fut, opt);
            pred_fit = local_extract_output(yf);
            pred_sd  = local_extract_output(yf_sd);

            if d == 1
                pred_y = y(end) + cumsum(pred_fit);
            else
                pred_y = pred_fit;
            end
        end

        %% 6. Postprocessing
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

function enabled = local_use_closed_loop(U_hist, sirs_state, sirs_params, exo_mode)
    if isempty(exo_mode)
        enabled = false;
        return;
    end

    mode = char(string(exo_mode));
    enabled = ~isempty(U_hist) && ~isempty(sirs_state) && ...
        isstruct(sirs_params) && isfield(sirs_params, 'pop_size') && ...
        any(strcmp(mode, {'S', 'I', 'Both'}));
end

function [pred_y, pred_sd] = local_closed_loop_forecast( ...
    sys, Rt_hist, U_hist, d, horizon, sirs_state, sirs_params, exo_mode, sim_seed, opt)
    initial_Rt = double(Rt_hist(:));
    initial_U  = double(U_hist);
    num_history = numel(initial_Rt);

    if size(initial_U, 1) ~= num_history
        error('FIT:InvalidExogenousHistory', 'Rt and exogenous histories must have matching lengths.');
    end

    rolling_Rt = zeros(num_history + horizon, 1);
    rolling_U  = zeros(size(initial_U, 1) + horizon, size(initial_U, 2));
    rolling_Rt(1:num_history) = initial_Rt;
    rolling_U(1:size(initial_U, 1), :) = initial_U;
    current_state = local_sanitize_sirs_state(sirs_state, sirs_params.pop_size);

    pred_y  = zeros(horizon, 1);
    pred_sd = zeros(horizon, 1);

    for h = 1:horizon
        current_idx = num_history + h - 1;
        [data_step, fit_u_next] = local_build_forecast_data( ...
            rolling_Rt(1:current_idx), rolling_U(1:current_idx, :), d);
        [yf, ~, ~, yf_sd] = forecast(sys, data_step, 1, fit_u_next, opt);

        step_fit = local_extract_output(yf);
        step_sd  = local_extract_output(yf_sd);

        if isempty(step_fit) || isempty(step_sd)
            error('FIT:InvalidForecastOutput', 'Closed-loop forecast output is invalid.');
        end

        if d == 1
            step_y = log(max(rolling_Rt(current_idx), eps)) + step_fit(1);
        else
            step_y = step_fit(1);
        end

        Rt_next = exp(step_y);
        if ~isfinite(Rt_next) || Rt_next <= 0
            error('FIT:InvalidForecastOutput', 'Closed-loop Rt forecast is invalid.');
        end

        current_state = local_advance_sirs_one_day( ...
            Rt_next, current_state, sirs_params, sim_seed);
        U_next = local_state_to_exogenous(current_state, exo_mode, sirs_params.pop_size);

        if numel(U_next) ~= size(rolling_U, 2)
            error('FIT:InvalidExogenousState', 'Closed-loop exogenous state has invalid dimension.');
        end

        pred_y(h) = step_y;
        pred_sd(h) = step_sd(1);
        rolling_Rt(current_idx + 1, 1) = Rt_next;
        rolling_U(current_idx + 1, :) = U_next;
    end
end

function [data_step, fit_u_next] = local_build_forecast_data(rolling_Rt, rolling_U, d)
    y_step = log(max(rolling_Rt(:), eps));

    if d == 1
        fit_y_step = diff(y_step);
        fit_u_step = diff(rolling_U, 1, 1);
        fit_u_next = zeros(1, size(rolling_U, 2));
    else
        fit_y_step = y_step;
        fit_u_step = rolling_U;
        fit_u_next = rolling_U(end, :);
    end

    data_step = iddata(fit_y_step, fit_u_step, 1);
end

function next_state = local_advance_sirs_one_day(Rt_next, current_state, sirs_params, sim_seed)
    uds_params = sirs_params;
    uds_params.I0      = current_state(2);
    uds_params.R0_init = current_state(3);
    uds_params.solver  = 'uds';
    uds_params.compile = 0;
    uds_params.Rt      = [Rt_next, Rt_next];

    [uds_mod, ~] = genData_SIRS([0, 1], uds_params, sim_seed);
    next_state = local_sanitize_sirs_state(uds_mod.U(:, end), sirs_params.pop_size);
end

function U_next = local_state_to_exogenous(state, exo_mode, pop_size)
    switch char(string(exo_mode))
        case 'S'
            U_next = state(1) / pop_size;
        case 'I'
            U_next = state(2) / pop_size;
        case 'Both'
            U_next = [state(1), state(2)] / pop_size;
        otherwise
            U_next = [];
    end

    U_next = reshape(U_next, 1, []);
end

function state = local_sanitize_sirs_state(raw_state, pop_size)
    state = reshape(double(raw_state), [], 1);
    if numel(state) ~= 3 || any(~isfinite(state))
        error('FIT:InvalidSirsState', 'SIRS state must contain three finite compartment values.');
    end

    tolerance = max(1e-7 * pop_size, 1e-9);
    state(abs(state) < tolerance) = 0;
    state = max(state, 0);
    state(1) = max(state(1), max(1, 1e-6 * pop_size));

    total = sum(state);
    if total <= 0
        error('FIT:InvalidSirsState', 'SIRS state must have positive total population.');
    end

    state = state * (pop_size / total);
end

function [Rt_curve, lower_bounds, upper_bounds] = local_persistence_forecast(last_value, horizon, interval_alphas)
    Rt_curve = repmat(last_value, horizon, 1);
    lower_bounds = repmat(Rt_curve, 1, numel(interval_alphas));
    upper_bounds = repmat(Rt_curve, 1, numel(interval_alphas));
end
