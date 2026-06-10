function [Rt_curve, aicc, interval_alphas, lower_bounds, upper_bounds] = fit_n4sid_model( ...
    Rt_hist, U_hist, U_future, n, d, horizon, interval_alphas, ...
    sirs_state, sirs_params, exo_mode, sim_seed)
%FIT_N4SID_MODEL Fit a State-Space model via N4SID to historical Rt data and forecast.
%
%   Syntax:
%       [Rt_curve, aicc, interval_alphas, lower_bounds, upper_bounds] = ...
%           fit_n4sid_model(Rt_hist, U_hist, U_future, n, d, horizon, interval_alphas)
%
%   Description:
%       Fits a discrete-time state-space model using the Subspace State-Space
%       System Identification (N4SID) algorithm. Incorporates optional
%       exogenous inputs. Employs a threshold-clipped logarithmic transform
%       for numerical stability and computes analytic predictive intervals
%       from forecast uncertainty. When a current SIRS state is supplied,
%       future exogenous covariates are generated recursively from one-step
%       Rt forecasts and URDME/UDS SIRS advancement. The returned AICc is
%       reported for reference; global hyperparameter selection is performed
%       by the pipeline using WIS.
%
%   Inputs:
%       Rt_hist  - Numeric vector of historical Rt values.
%       U_hist   - Numeric matrix of historical exogenous variables.
%       U_future - Numeric matrix of future exogenous variables.
%       n        - Model order (number of internal states).
%       d        - Degree of differencing (0 or 1).
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
%   See also FIT_AR_MODEL, FIT_ARX_MODEL, FIT_SSEST_MODEL, PARTA_03_RUN_FORECASTS.
%
% A. M. Kaahin 2026-02-19
% Modified: 2026-06-11

    %% 1. Preprocessing
    if nargin < 7 || isempty(interval_alphas)
        interval_alphas = [0.05, 0.10, 0.20, 0.50];
    else
        interval_alphas = reshape(double(interval_alphas), 1, []);
    end

    if any(interval_alphas <= 0 | interval_alphas >= 1)
        error('FIT:InvalidAlpha', 'Interval alphas must satisfy 0 < alpha < 1.');
    end

    if nargin < 8, sirs_state = []; end
    if nargin < 9, sirs_params = []; end
    if nargin < 10, exo_mode = ''; end
    if nargin < 11, sim_seed = []; end

    use_closed_loop = local_use_closed_loop(U_hist, sirs_state, sirs_params, exo_mode);

    y = log(max(Rt_hist(:), eps));
    
    if d == 1
        fit_y = diff(y);
        
        if isempty(U_hist)
            fit_u     = [];
            fit_u_fut = [];
        else
            fit_u = diff(U_hist, 1, 1); 
            
            if use_closed_loop
                fit_u_fut = [];
            else
                combined_fut = [U_hist(end, :); U_future];
                fit_u_fut    = diff(combined_fut, 1, 1);
            end
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
    
    %% 3. Model Fitting
    data = iddata(fit_y, fit_u, 1);
    
    try
        opt_est = n4sidOptions('Display', 'off');
        sys     = n4sid(data, n, opt_est);
        
        aicc = sys.Report.Fit.AICc;
        
        %% 4. Forecasting
        opt = forecastOptions('InitialCondition', 'e');
        if use_closed_loop
            [pred_y, pred_sd] = local_closed_loop_forecast( ...
                sys, Rt_hist, U_hist, d, horizon, sirs_state, ...
                sirs_params, exo_mode, sim_seed, opt, data);
        elseif isempty(fit_u_fut)
            [yf, ~, ~, yf_sd] = forecast(sys, data, horizon, opt);
            pred_fit = local_extract_output(yf);
            pred_sd  = local_extract_output(yf_sd);
        else
            [yf, ~, ~, yf_sd] = forecast(sys, data, horizon, fit_u_fut, opt);
            pred_fit = local_extract_output(yf);
            pred_sd  = local_extract_output(yf_sd);
        end
        
        %% 5. Postprocessing
        if ~use_closed_loop
            if d == 1
                pred_y = y(end) + cumsum(pred_fit);
            else
                pred_y = pred_fit;
            end
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

%% 6. Local Helpers
function values = local_extract_output(data)
%LOCAL_EXTRACT_OUTPUT Return numeric output data from iddata or arrays.
    if isa(data, 'iddata')
        values = double(data.OutputData(:));
    else
        values = double(data(:));
    end
end

function [lower_bounds, upper_bounds] = local_interval_bounds(pred_y, pred_sd, interval_alphas)
%LOCAL_INTERVAL_BOUNDS Convert log-scale forecast uncertainty to Rt bounds.
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
%LOCAL_USE_CLOSED_LOOP Decide whether recursive SIRS inputs are available.
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
    sys, Rt_hist, U_hist, d, horizon, sirs_state, sirs_params, exo_mode, sim_seed, opt, origin_data)
%LOCAL_CLOSED_LOOP_FORECAST Forecast recursively with SIRS-updated inputs.
    initial_Rt = double(Rt_hist(:));
    initial_U  = double(U_hist);
    num_history = numel(initial_Rt);

    if size(initial_U, 1) ~= num_history
        error('FIT:InvalidExogenousHistory', 'Rt and exogenous histories must have matching lengths.');
    end

    if d == 0
        [manual_ok, pred_y, pred_sd] = local_manual_closed_loop_forecast( ...
            sys, origin_data, initial_U, horizon, sirs_state, sirs_params, ...
            exo_mode, sim_seed, opt);
        if manual_ok
            return;
        end
    end

    rolling_Rt = zeros(num_history + horizon, 1);
    rolling_U  = zeros(size(initial_U, 1) + horizon, size(initial_U, 2));
    rolling_Rt(1:num_history) = initial_Rt;
    rolling_U(1:size(initial_U, 1), :) = initial_U;
    current_state = local_sanitize_sirs_state(sirs_state, sirs_params.pop_size);

    pred_y  = zeros(horizon, 1);
    pred_sd = zeros(horizon, 1);
    sim_options = struct( ...
        'solver', 'uds', ...
        'compile', false, ...
        'seed', local_resolve_sim_seed(sim_seed));
    stepper = initialize_sirs_stepper(sirs_params, sim_options);

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

        [current_state, stepper] = advance_sirs_stepper( ...
            stepper, current_state, Rt_next);
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

function [manual_ok, pred_y, pred_sd] = local_manual_closed_loop_forecast( ...
    sys, origin_data, initial_U, horizon, sirs_state, sirs_params, exo_mode, sim_seed, opt)
%LOCAL_MANUAL_CLOSED_LOOP_FORECAST Use forecast-model matrices for d = 0 recursion.
    manual_ok = false;
    pred_y = [];
    pred_sd = [];

    try
        current_state = local_sanitize_sirs_state(sirs_state, sirs_params.pop_size);
        current_u = initial_U(end, :);
        placeholder_u = repmat(current_u, horizon, 1);

        [yf_ref, x_current, sys_forecast, ~] = forecast( ...
            sys, origin_data, horizon, placeholder_u, opt);
        [A, B, C, D] = idssdata(sys_forecast);

        local_validate_state_space_matrices(A, B, C, D, current_u);

        sim_options = struct( ...
            'solver', 'uds', ...
            'compile', false, ...
            'seed', local_resolve_sim_seed(sim_seed));
        stepper = initialize_sirs_stepper(sirs_params, sim_options);

        pred_y = zeros(horizon, 1);
        future_U = zeros(horizon, size(initial_U, 2));
        % x_current is the forecast-model state before output h; update it after consuming u_h.
        x_current = double(x_current(:));

        for h = 1:horizon
            future_U(h, :) = current_u;
            u_column = double(current_u(:));
            step_y = C * x_current + D * u_column;
            if ~isscalar(step_y) || ~isfinite(step_y)
                error('FIT:InvalidManualStateSpace', 'Manual state-space prediction is invalid.');
            end

            x_current = A * x_current + B * u_column;
            Rt_next = exp(step_y);
            if ~isfinite(Rt_next) || Rt_next <= 0
                error('FIT:InvalidForecastOutput', 'Closed-loop Rt forecast is invalid.');
            end

            [current_state, stepper] = advance_sirs_stepper( ...
                stepper, current_state, Rt_next);
            U_next = local_state_to_exogenous(current_state, exo_mode, sirs_params.pop_size);

            if numel(U_next) ~= size(initial_U, 2)
                error('FIT:InvalidExogenousState', 'Closed-loop exogenous state has invalid dimension.');
            end

            pred_y(h) = step_y;
            current_u = U_next;
        end

        [yf_check, ~, ~, yf_sd] = forecast(sys, origin_data, horizon, future_U, opt);
        check_y = local_extract_output(yf_check);
        pred_sd = local_extract_output(yf_sd);

        if numel(check_y) ~= horizon || numel(pred_sd) ~= horizon
            error('FIT:InvalidManualStateSpace', 'Manual state-space validation output is invalid.');
        end

        mismatch = max(abs(pred_y(:) - check_y(:)));
        first_ref = local_extract_output(yf_ref);
        first_mismatch = abs(pred_y(1) - first_ref(1));
        tolerance = local_state_space_match_tolerance(check_y);
        if mismatch > tolerance || first_mismatch > tolerance
            manual_ok = false;
            pred_y = [];
            pred_sd = [];
            return;
        end

        pred_sd = max(double(pred_sd(:)), 0);
        manual_ok = true;
    catch
        manual_ok = false;
        pred_y = [];
        pred_sd = [];
    end
end

function local_validate_state_space_matrices(A, B, C, D, u_next)
%LOCAL_VALIDATE_STATE_SPACE_MATRICES Validate forecast-model matrix dimensions.
    if isempty(A) || isempty(C) || any(~isfinite(A(:))) || any(~isfinite(C(:)))
        error('FIT:InvalidManualStateSpace', 'Forecast state-space matrices are invalid.');
    end

    num_states = size(A, 1);
    num_inputs = numel(u_next);
    valid_dimensions = size(A, 2) == num_states && ...
        size(B, 1) == num_states && size(B, 2) == num_inputs && ...
        size(C, 2) == num_states && size(C, 1) == 1 && ...
        size(D, 1) == 1 && size(D, 2) == num_inputs;

    if ~valid_dimensions || any(~isfinite(B(:))) || any(~isfinite(D(:)))
        error('FIT:InvalidManualStateSpace', 'Forecast state-space dimensions are inconsistent.');
    end
end

function tolerance = local_state_space_match_tolerance(reference)
%LOCAL_STATE_SPACE_MATCH_TOLERANCE Tolerance for MATLAB forecast agreement.
    reference = double(reference(:));
    tolerance = 1e-8 + 1e-6 * max(1, max(abs(reference)));
end

function [data_step, fit_u_next] = local_build_forecast_data(rolling_Rt, rolling_U, d)
%LOCAL_BUILD_FORECAST_DATA Build one-step state-space forecast data.
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

function U_next = local_state_to_exogenous(state, exo_mode, pop_size)
%LOCAL_STATE_TO_EXOGENOUS Convert a SIRS state to model inputs.
    U_next = extract_exogenous_from_state(state, exo_mode, pop_size);
end

function state = local_sanitize_sirs_state(raw_state, pop_size)
%LOCAL_SANITIZE_SIRS_STATE Normalize a SIRS state before advancement.
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
%LOCAL_PERSISTENCE_FORECAST Return deterministic persistence intervals.
    Rt_curve = repmat(last_value, horizon, 1);
    lower_bounds = repmat(Rt_curve, 1, numel(interval_alphas));
    upper_bounds = repmat(Rt_curve, 1, numel(interval_alphas));
end

function seed = local_resolve_sim_seed(sim_seed)
%LOCAL_RESOLVE_SIM_SEED Validate or generate a URDME seed.
    if isempty(sim_seed)
        rng('shuffle');
        seed = randi(intmax('uint32'));
    else
        seed = double(sim_seed);
    end

    if ~isscalar(seed) || ~isfinite(seed) || seed < 0 || seed ~= floor(seed)
        error('FIT:InvalidSeed', 'sim_seed must be a finite nonnegative integer scalar.');
    end
end
