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
%       Part A model implementations. The model dispatch is identical to the
%       behaviour established during Part A model-configuration selection so
%       that final forecasts reproduce the selected-configuration behaviour:
%           AR    uses fit_ar_model + forecast_ar_model.
%           ARX   uses fit_arx_model + forecast_arx_closed_loop.
%           N4SID uses the corrected fit_n4sid_model path.
%           SSEST uses the corrected fit_ssest_model path.
%
%   Inputs:
%       model_type             - Model family identifier: AR, ARX, N4SID, SSEST.
%       selected_configuration - Numeric row vector of selected model parameters.
%       window_entry           - Structure with Rt_past, U_past, and sirs_state
%                                for the current window.
%       forecast_options       - Structure with horizon, wis_alphas, sirs_cfg,
%                                exo_mode, sim_seed, and num_exo.
%
%   Outputs:
%       forecast - Structure with Rt_pred, aicc, interval_alphas,
%                  lower_bounds, and upper_bounds.
%
%   See also FIT_AR_MODEL, FORECAST_AR_MODEL, FIT_ARX_MODEL, ...
%            FORECAST_ARX_CLOSED_LOOP, FIT_N4SID_MODEL, FIT_SSEST_MODEL.
%
% A. M. Kaahin 2026-06-01

    %% 1. Input Preparation
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

    %% 2. Model Dispatch
    switch char(model_type)
        case 'AR'
            ar_model = fit_ar_model(Rt_past, params(1));
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                forecast_ar_model(ar_model, horizon, wis_alphas);

        case 'ARX'
            nb_vec = repmat(params(2), 1, num_exo);
            nk_vec = repmat(params(3), 1, num_exo);
            arx_model = fit_arx_model(Rt_past, U_past, params(1), nb_vec, nk_vec);
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                forecast_arx_closed_loop(arx_model, Rt_past, U_past, ...
                sirs_state, sirs_cfg, exo_mode, horizon, wis_alphas, sim_seed);

        case 'N4SID'
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                fit_n4sid_model(Rt_past, U_past, [], params(1), params(2), ...
                horizon, wis_alphas, sirs_state, sirs_cfg, exo_mode, sim_seed);

        case 'SSEST'
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                fit_ssest_model(Rt_past, U_past, [], params(1), params(2), ...
                horizon, wis_alphas, sirs_state, sirs_cfg, exo_mode, sim_seed);

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
        'upper_bounds', Rt_upper);
end
