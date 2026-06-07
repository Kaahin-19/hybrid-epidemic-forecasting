function forecast = run_model_forecast(model_type, selected_configuration, ...
    window_entry, forecast_options)
%RUN_MODEL_FORECAST Fit and forecast one selected configuration for one window.
%
%   Syntax:
%       forecast = run_model_forecast(model_type, selected_configuration, ...
%           window_entry, forecast_options)
%
%   Description:
%       Dispatches a single expanding-window forecast using the corrected
%       Part A model implementations. The forecast always runs the final
%       closed-loop Monte Carlo / residual-bootstrap interval mode: the
%       selected configuration is propagated through the closed-loop interval
%       simulator for its model family, producing the predictive median and
%       intervals together. AR and ARX use simulate_ar_arx_intervals; N4SID
%       and SSEST use simulate_statespace_intervals.
%
%   Inputs:
%       model_type             - Model family identifier: AR, ARX, N4SID, SSEST.
%       selected_configuration - Numeric row vector of selected model parameters.
%       window_entry           - Structure with Rt_past, U_past, sirs_state, and
%                                window_day_idx for the current window.
%       forecast_options       - Structure with horizon, wis_alphas, sirs_cfg,
%                                exo_mode, sim_seed, num_exo, intervals, and
%                                scenario_id.
%
%   Outputs:
%       forecast - Structure with Rt_pred, aicc, interval_alphas,
%                  lower_bounds, upper_bounds, and interval metadata
%                  (interval_method, interval_num_draws, interval_seed,
%                  interval_status).
%
%   See also SIMULATE_AR_ARX_INTERVALS, SIMULATE_STATESPACE_INTERVALS, ...
%            MAKE_INTERVAL_OPTIONS, RUN_EXPANDING_WINDOW_FORECAST.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-07

    %% 1. Input Preparation
    model_type = string(model_type);
    params = reshape(double(selected_configuration), 1, []);

    Rt_past    = window_entry.Rt_past;
    U_past     = window_entry.U_past;
    sirs_state = window_entry.sirs_state;

    horizon    = forecast_options.horizon;
    wis_alphas = forecast_options.wis_alphas;
    sirs_cfg   = forecast_options.sirs_cfg;
    exo_mode   = forecast_options.exo_mode;
    sim_seed   = forecast_options.sim_seed;
    num_exo    = forecast_options.num_exo;

    %% 2. Final Closed-Loop Interval Forecast
    context = struct( ...
        'stage', "final", ...
        'exo_mode', exo_mode, ...
        'sirs_cfg', sirs_cfg, ...
        'horizon', horizon, ...
        'alphas', wis_alphas, ...
        'sim_seed', sim_seed, ...
        'scenario_key', forecast_options.scenario_id, ...
        'window_index', window_entry.window_day_idx, ...
        'model_type', model_type);
    interval_options = make_interval_options(forecast_options.intervals, context);

    switch model_type
        case {"AR", "ARX"}
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper, meta] = ...
                simulate_ar_arx_intervals(model_type, params, Rt_past, ...
                U_past, sirs_state, num_exo, interval_options);
        case {"N4SID", "SSEST"}
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper, meta] = ...
                simulate_statespace_intervals(model_type, params, Rt_past, ...
                U_past, sirs_state, num_exo, interval_options);
        otherwise
            error('FORECAST:UnknownModel', ...
                'Unsupported MODEL_TYPE: %s', string(model_type));
    end

    %% 3. Output Assembly
    forecast = struct( ...
        'Rt_pred', Rt_pred(:), ...
        'aicc', aicc, ...
        'interval_alphas', reshape(double(out_alphas), 1, []), ...
        'lower_bounds', Rt_lower, ...
        'upper_bounds', Rt_upper, ...
        'interval_method', string(meta.interval_method), ...
        'interval_num_draws', double(meta.interval_num_draws), ...
        'interval_seed', double(meta.interval_seed), ...
        'interval_status', string(meta.interval_status));
end
