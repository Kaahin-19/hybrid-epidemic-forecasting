function [forecast_results, fit_metadata] = run_partC_fixed_parameter_forecast( ...
    scenario_entry, model_type, selected_order, forecast_options, calibration_end_idx)
%RUN_PARTC_FIXED_PARAMETER_FORECAST Run fixed-parameter Part C forecasts.
%
%   Syntax:
%       [forecast_results, fit_metadata] = run_partC_fixed_parameter_forecast( ...
%           scenario_entry, model_type, selected_order, forecast_options, calibration_end_idx)
%
%   Description:
%       Fits the requested AR/None or ARX/I model once on the initial Part C
%       real-data calibration segment, then reuses those fitted parameters
%       for all later forecast origins. The forecast windows themselves use
%       the canonical Part A/B result fields, but model parameters are not
%       re-estimated during the evaluation loop.
%
%   Inputs:
%       scenario_entry      - Part C forecast-entry structure.
%       model_type          - Model family identifier, "AR" or "ARX".
%       selected_order      - Fixed Part A-selected/fallback order.
%       forecast_options    - Forecast options structure.
%       calibration_end_idx - Last data index used for the one-time fit.
%
%   Outputs:
%       forecast_results - Canonical forecast-result structure array.
%       fit_metadata     - Metadata describing the one-time real-data fit.
%
%   See also FIT_AR_MODEL, FIT_ARX_MODEL, FORECAST_ARX_CLOSED_LOOP.
%
% A. M. Kaahin 2026-06-03

    %% 1. One-Time Calibration Fit
    model_type = char(string(model_type));
    selected_order = reshape(double(selected_order), 1, []);
    calibration_end_idx = round(double(calibration_end_idx));
    calibration_Rt = scenario_entry.Rt_model_input(1:calibration_end_idx);

    switch model_type
        case 'AR'
            fitted_model = fit_ar_model(calibration_Rt, selected_order(1));
        case 'ARX'
            calibration_U = scenario_entry.U_true(1:calibration_end_idx, :);
            nb_vec = repmat(selected_order(2), 1, scenario_entry.num_exo);
            nk_vec = repmat(selected_order(3), 1, scenario_entry.num_exo);
            fitted_model = fit_arx_model(calibration_Rt, calibration_U, ...
                selected_order(1), nb_vec, nk_vec);
        otherwise
            error('PARTC:UnsupportedFixedParameterModel', ...
                'Fixed-parameter Part C forecasts support only AR and ARX.');
    end

    fit_metadata = local_fit_metadata(fitted_model, model_type, ...
        selected_order, calibration_end_idx, numel(calibration_Rt));

    %% 2. Evaluation Forecast Loop
    window_data = scenario_entry.window_data;
    forecast_results = repmat(local_empty_result(), numel(window_data), 1);
    count = 0;

    for w = 1:numel(window_data)
        window_entry = window_data(w);
        if ~window_entry.is_valid_window || ...
                window_entry.window_day_idx < calibration_end_idx
            continue;
        end

        forecast = local_forecast_fixed_window(fitted_model, model_type, ...
            window_entry, forecast_options);
        is_valid = local_is_valid_forecast(forecast.Rt_pred, ...
            forecast.interval_alphas, forecast.lower_bounds, ...
            forecast.upper_bounds, window_entry.truth_Rt);

        count = count + 1;
        forecast_results(count).forecast_origin  = window_entry.window_day;
        forecast_results(count).window_day_idx   = window_entry.window_day_idx;
        forecast_results(count).horizon_indices  = window_entry.horizon_indices;
        forecast_results(count).t_future         = window_entry.t_future;
        forecast_results(count).Rt_true_future   = window_entry.truth_Rt;
        forecast_results(count).Rt_pred          = forecast.Rt_pred;
        forecast_results(count).lower_bounds     = forecast.lower_bounds;
        forecast_results(count).upper_bounds     = forecast.upper_bounds;
        forecast_results(count).interval_alphas  = forecast.interval_alphas;
        forecast_results(count).aicc             = forecast.aicc;
        forecast_results(count).interval_method  = forecast.interval_method;
        forecast_results(count).interval_num_draws = forecast.interval_num_draws;
        forecast_results(count).interval_seed    = forecast.interval_seed;
        forecast_results(count).interval_status  = forecast.interval_status;
        forecast_results(count).is_valid         = is_valid;
        forecast_results(count).status           = local_status_label(is_valid);
    end

    forecast_results = forecast_results(1:count);
    fit_metadata.evaluation_windows = count;
end

function forecast = local_forecast_fixed_window(fitted_model, model_type, ...
    window_entry, forecast_options)
%LOCAL_FORECAST_FIXED_WINDOW Forecast one window without refitting.
    switch model_type
        case 'AR'
            [Rt_pred, aicc, out_alphas, lower_bounds, upper_bounds, status] = ...
                local_forecast_fixed_ar(fitted_model, window_entry.Rt_past, ...
                forecast_options.horizon, forecast_options.wis_alphas);
            interval_method = "fixed_parameter_log_normal";

        case 'ARX'
            [Rt_pred, aicc, out_alphas, lower_bounds, upper_bounds] = ...
                forecast_arx_closed_loop(fitted_model, window_entry.Rt_past, ...
                window_entry.U_past, window_entry.sirs_state, ...
                forecast_options.sirs_cfg, forecast_options.exo_mode, ...
                forecast_options.horizon, forecast_options.wis_alphas, ...
                forecast_options.sim_seed);
            status = "fixed_parameter_log_normal";
            interval_method = "fixed_parameter_closed_loop_log_normal";

        otherwise
            error('PARTC:UnsupportedFixedParameterModel', ...
                'Fixed-parameter Part C forecasts support only AR and ARX.');
    end

    forecast = struct( ...
        'Rt_pred', Rt_pred(:), ...
        'aicc', aicc, ...
        'interval_alphas', reshape(double(out_alphas), 1, []), ...
        'lower_bounds', lower_bounds, ...
        'upper_bounds', upper_bounds, ...
        'interval_method', interval_method, ...
        'interval_num_draws', 0, ...
        'interval_seed', double(forecast_options.sim_seed), ...
        'interval_status', string(status));
end

function result = local_empty_result()
%LOCAL_EMPTY_RESULT Preallocate a single forecast-result entry.
    result = struct( ...
        'forecast_origin', [], ...
        'window_day_idx', [], ...
        'horizon_indices', [], ...
        't_future', [], ...
        'Rt_true_future', [], ...
        'Rt_pred', [], ...
        'lower_bounds', [], ...
        'upper_bounds', [], ...
        'interval_alphas', [], ...
        'aicc', [], ...
        'interval_method', "", ...
        'interval_num_draws', 0, ...
        'interval_seed', 0, ...
        'interval_status', "", ...
        'is_valid', false, ...
        'status', "");
end

function [Rt_pred, aicc, interval_alphas, lower_bounds, upper_bounds, status] = ...
    local_forecast_fixed_ar(model, Rt_hist, horizon, interval_alphas)
%LOCAL_FORECAST_FIXED_AR Recursive AR forecast using fixed coefficients.
    horizon = round(double(horizon));
    interval_alphas = reshape(double(interval_alphas), 1, []);
    Rt_hist = double(Rt_hist(:));
    aicc = model.aicc;

    if ~isfield(model, 'is_persistence') || model.is_persistence || ...
            ~isfield(model, 'coefficients') || ...
            isempty(model.coefficients.a_values)
        [Rt_pred, lower_bounds, upper_bounds] = ...
            local_persistence_forecast(Rt_hist(end), horizon, interval_alphas);
        status = "persistence_fallback";
        return;
    end

    try
        a_values = reshape(double(model.coefficients.a_values), [], 1);
        rolling_log_Rt = log(max(Rt_hist, eps));
        pred_log_Rt = zeros(horizon, 1);

        for h = 1:horizon
            next_log_Rt = 0;
            for lag = 1:numel(a_values)
                next_log_Rt = next_log_Rt - ...
                    a_values(lag) * rolling_log_Rt(end + 1 - lag);
            end
            pred_log_Rt(h) = next_log_Rt;
            rolling_log_Rt = [rolling_log_Rt; next_log_Rt]; %#ok<AGROW>
        end

        residual_std = local_residual_std(model);
        pred_sd = sqrt((1:horizon)') * residual_std;
        [Rt_pred, lower_bounds, upper_bounds] = local_log_normal_output( ...
            pred_log_Rt, pred_sd, interval_alphas);
        local_validate_forecast_output(Rt_pred, lower_bounds, upper_bounds);
        status = "fixed_parameter_log_normal";
    catch
        [Rt_pred, lower_bounds, upper_bounds] = ...
            local_persistence_forecast(Rt_hist(end), horizon, interval_alphas);
        aicc = inf;
        status = "persistence_fallback";
    end
end

function scale = local_residual_std(model)
%LOCAL_RESIDUAL_STD Return fixed log-scale innovation scale.
    scale = 0;
    if isfield(model, 'residual_std') && ~isempty(model.residual_std)
        scale = double(model.residual_std);
    end
    if ~isscalar(scale) || ~isfinite(scale) || scale < 0
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
        error('PARTC:InvalidFixedParameterForecast', ...
            'Fixed-parameter forecast values and bounds must be finite, positive, and ordered.');
    end
end

function is_valid = local_is_valid_forecast(Rt_pred, out_alphas, ...
    Rt_lower, Rt_upper, truth_Rt)
%LOCAL_IS_VALID_FORECAST Verify forecast output dimensions and finiteness.
    out_alphas = reshape(double(out_alphas), 1, []);
    Rt_pred = double(Rt_pred(:));
    Rt_lower = double(Rt_lower);
    Rt_upper = double(Rt_upper);
    truth_Rt = double(truth_Rt(:));

    is_valid = ...
        ~isempty(out_alphas) && ...
        numel(Rt_pred) == numel(truth_Rt) && ...
        size(Rt_lower, 1) == numel(truth_Rt) && ...
        size(Rt_upper, 1) == numel(truth_Rt) && ...
        size(Rt_lower, 2) == numel(out_alphas) && ...
        size(Rt_upper, 2) == numel(out_alphas) && ...
        all(isfinite(Rt_pred)) && all(isfinite(Rt_lower(:))) && ...
        all(isfinite(Rt_upper(:))) && all(Rt_lower(:) <= Rt_upper(:));
end

function label = local_status_label(is_valid)
%LOCAL_STATUS_LABEL Map a validity flag to a status string.
    if is_valid
        label = "ok";
    else
        label = "invalid";
    end
end

function metadata = local_fit_metadata(model, model_type, selected_order, ...
    calibration_end_idx, calibration_observations)
%LOCAL_FIT_METADATA Summarize the one-time fixed-parameter fit.
    metadata = struct();
    metadata.model_type = string(model_type);
    metadata.selected_order = selected_order;
    metadata.calibration_end_idx = calibration_end_idx;
    metadata.calibration_observations = calibration_observations;
    metadata.aicc = model.aicc;
    metadata.residual_std = local_residual_std(model);
    metadata.is_persistence = false;
    if isfield(model, 'is_persistence')
        metadata.is_persistence = logical(model.is_persistence);
    end
    metadata.parameter_treatment = "fit_once_on_initial_real_data_calibration_segment";
end
