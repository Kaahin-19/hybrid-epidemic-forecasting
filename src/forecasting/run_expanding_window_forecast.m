function forecast_results = run_expanding_window_forecast(scenario_entry, ...
    model_type, selected_configuration, forecast_options)
%RUN_EXPANDING_WINDOW_FORECAST Run all window forecasts for one scenario.
%
%   Syntax:
%       forecast_results = run_expanding_window_forecast(scenario_entry, ...
%           model_type, selected_configuration, forecast_options)
%
%   Description:
%       Executes the expanding-window forecast loop for a single scenario
%       using the globally selected configuration. Each valid window is
%       forecast with the corrected Part A model dispatch and stored together
%       with the matching future truth and predictive intervals.
%
%   Inputs:
%       scenario_entry         - One scenario structure from
%                                build_forecasting_dataset.
%       model_type             - Model family identifier.
%       selected_configuration - Numeric row vector of selected parameters.
%       forecast_options       - Structure consumed by run_model_forecast,
%                                extended with num_exo per scenario.
%
%   Outputs:
%       forecast_results - Structure array, one entry per valid window, with
%                          forecast origin, future indexing, truth, median,
%                          predictive bounds, interval alphas, and status.
%
%   See also RUN_MODEL_FORECAST, BUILD_FORECASTING_DATASET, PREPARE_WINDOW_DATA.
%
% A. M. Kaahin 2026-06-01

    %% 1. Setup
    forecast_options.num_exo = scenario_entry.num_exo;
    forecast_options.scenario_id = scenario_entry.scenario_id;
    window_data = scenario_entry.window_data;
    num_windows = numel(window_data);

    forecast_results = repmat(local_empty_result(), num_windows, 1);
    count = 0;

    %% 2. Expanding-Window Loop
    for w = 1:num_windows
        window_entry = window_data(w);
        if ~window_entry.is_valid_window
            continue;
        end

        forecast = run_model_forecast(model_type, selected_configuration, ...
            window_entry, forecast_options);

        is_valid = is_valid_forecast(forecast.Rt_pred, ...
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
        forecast_results(count).interval_method     = forecast.interval_method;
        forecast_results(count).interval_num_draws  = forecast.interval_num_draws;
        forecast_results(count).interval_seed       = forecast.interval_seed;
        forecast_results(count).interval_status     = forecast.interval_status;
        forecast_results(count).is_valid         = is_valid;
        forecast_results(count).status           = local_status_label(is_valid);
    end

    forecast_results = forecast_results(1:count);
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

function label = local_status_label(is_valid)
%LOCAL_STATUS_LABEL Map a validity flag to a status string.
    if is_valid
        label = "ok";
    else
        label = "invalid";
    end
end
