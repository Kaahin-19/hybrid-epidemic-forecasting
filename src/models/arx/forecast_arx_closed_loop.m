function [Rt_curve, aicc, interval_alphas, lower_bounds, upper_bounds] = ...
    forecast_arx_closed_loop(model, Rt_hist, U_hist, sirs_state, sirs_params, ...
    exo_mode, horizon, interval_alphas, sim_seed)
%FORECAST_ARX_CLOSED_LOOP Forecast ARX recursively with epidemic feedback.
%
%   Syntax:
%       [Rt_curve, aicc, interval_alphas, lower_bounds, upper_bounds] = ...
%           forecast_arx_closed_loop(model, Rt_hist, U_hist, sirs_state, ...
%           sirs_params, exo_mode, horizon, interval_alphas, sim_seed)
%
%   Description:
%       Forecasts a fitted ARX model over the requested horizon by applying
%       stored ARX coefficients recursively. Each predicted effective Rt
%       advances the SIRS state directly through URDME, and the next
%       exogenous input is extracted from the advanced state.
%
%   Inputs:
%       model           - Structure returned by fit_arx_model.
%       Rt_hist         - Historical effective Rt values.
%       U_hist          - Historical exogenous covariate matrix.
%       sirs_state      - Current [S, I, R] state.
%       sirs_params     - SIRS parameter structure.
%       exo_mode        - Exogenous mode: S, I, or Both.
%       horizon         - Positive integer forecast horizon.
%       interval_alphas - Vector of interval miscoverage rates.
%       sim_seed        - URDME simulation seed.
%
%   Outputs:
%       Rt_curve        - Horizon-by-one forecast median vector.
%       aicc            - Corrected AIC from the fitted model when available.
%       interval_alphas - Row vector of interval miscoverage rates.
%       lower_bounds    - Horizon-by-numAlphas lower interval matrix.
%       upper_bounds    - Horizon-by-numAlphas upper interval matrix.
%
%   See also FIT_ARX_MODEL, RECURSIVE_ARX_STEP, ADVANCE_EPIDEMIC_STATE.
%
% A. M. Kaahin 2026-05-31

    %% 1. Input Validation
    horizon = local_validate_horizon(horizon);
    interval_alphas = local_validate_alphas(interval_alphas);
    Rt_hist = local_validate_rt_history(Rt_hist);
    U_hist = local_validate_exogenous_history(U_hist, numel(Rt_hist));
    aicc = model.aicc;

    if ~isfield(model, 'is_persistence') || model.is_persistence
        [Rt_curve, lower_bounds, upper_bounds] = ...
            local_persistence_forecast(Rt_hist(end), horizon, interval_alphas);
        return;
    end

    if size(U_hist, 2) ~= model.coefficients.num_inputs
        error('ARX:InvalidExogenousHistory', ...
            'U_hist column count does not match fitted ARX input count.');
    end

    %% 2. Closed-Loop Forecast
    try
        rolling_log_Rt = log(max(Rt_hist, eps));
        rolling_U = U_hist;
        current_state = reshape(double(sirs_state), 1, []);
        Rt_curve = zeros(horizon, 1);
        pred_log_Rt = zeros(horizon, 1);

        sim_options = struct('solver', 'uds', 'compile', false, 'seed', sim_seed);

        for h = 1:horizon
            next_log_Rt = recursive_arx_step(model.coefficients, rolling_log_Rt, rolling_U);
            Rt_next = exp(next_log_Rt);
            if ~isfinite(Rt_next) || Rt_next <= 0
                error('ARX:InvalidForecastOutput', ...
                    'Closed-loop ARX Rt forecast is invalid.');
            end

            current_state = advance_epidemic_state( ...
                "SIRS", current_state, Rt_next, sirs_params, sim_options);
            U_next = extract_exogenous_from_state( ...
                current_state, exo_mode, sirs_params.pop_size);

            if numel(U_next) ~= size(rolling_U, 2)
                error('ARX:InvalidExogenousState', ...
                    'Closed-loop exogenous state has invalid dimension.');
            end

            pred_log_Rt(h) = next_log_Rt;
            Rt_curve(h) = Rt_next;
            rolling_log_Rt = [rolling_log_Rt; next_log_Rt]; %#ok<AGROW>
            rolling_U = [rolling_U; U_next]; %#ok<AGROW>
        end

        %% 3. Interval Construction
        pred_sd = repmat(local_forecast_scale(model), horizon, 1);
        [Rt_curve, lower_bounds, upper_bounds] = ...
            local_log_normal_output(pred_log_Rt, pred_sd, interval_alphas);
        local_validate_forecast_output(Rt_curve, lower_bounds, upper_bounds);
    catch ME
        if local_is_structural_arx_error(ME)
            rethrow(ME);
        end

        [Rt_curve, lower_bounds, upper_bounds] = ...
            local_persistence_forecast(Rt_hist(end), horizon, interval_alphas);
        aicc = inf;
    end
end

function horizon = local_validate_horizon(horizon)
%LOCAL_VALIDATE_HORIZON Validate forecast horizon.
    horizon = double(horizon);
    if ~isscalar(horizon) || ~isfinite(horizon) || horizon < 1 || horizon ~= floor(horizon)
        error('ARX:InvalidHorizon', 'horizon must be a positive integer scalar.');
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
        error('ARX:InvalidAlpha', 'Interval alphas must satisfy 0 < alpha < 1.');
    end
end

function Rt_hist = local_validate_rt_history(Rt_hist)
%LOCAL_VALIDATE_RT_HISTORY Validate positive historical Rt values.
    if ~isnumeric(Rt_hist) || ~isvector(Rt_hist)
        error('ARX:InvalidHistory', 'Rt_hist must be a numeric vector.');
    end

    Rt_hist = double(Rt_hist(:));
    if isempty(Rt_hist) || any(~isfinite(Rt_hist)) || any(Rt_hist <= 0)
        error('ARX:InvalidHistory', ...
            'Rt_hist must contain finite positive values.');
    end
end

function U_hist = local_validate_exogenous_history(U_hist, expected_rows)
%LOCAL_VALIDATE_EXOGENOUS_HISTORY Validate historical exogenous inputs.
    if ~isnumeric(U_hist) || isempty(U_hist)
        error('ARX:InvalidExogenousHistory', ...
            'U_hist must be a nonempty numeric matrix.');
    end

    U_hist = double(U_hist);
    if isvector(U_hist)
        U_hist = U_hist(:);
    end

    if size(U_hist, 1) ~= expected_rows || any(~isfinite(U_hist(:)))
        error('ARX:InvalidExogenousHistory', ...
            'U_hist must have one finite row per Rt_hist sample.');
    end
end

function scale = local_forecast_scale(model)
%LOCAL_FORECAST_SCALE Return a finite nonnegative log-scale interval SD.
    scale = double(model.residual_std);
    if isempty(scale) || ~isscalar(scale) || ~isfinite(scale) || scale < 0
        scale = 0;
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
        error('ARX:InvalidForecastOutput', ...
            'ARX forecast values and bounds must be finite, positive, and ordered.');
    end
end

function is_structural = local_is_structural_arx_error(ME)
%LOCAL_IS_STRUCTURAL_ARX_ERROR Keep coefficient/history errors explicit.
    structural_ids = { ...
        'ARX:InvalidCoefficients', ...
        'ARX:InvalidHistory', ...
        'ARX:InvalidExogenousHistory', ...
        'ARX:InvalidExogenousState', ...
        'ARX:InsufficientHistory'};
    is_structural = any(strcmp(ME.identifier, structural_ids));
end
