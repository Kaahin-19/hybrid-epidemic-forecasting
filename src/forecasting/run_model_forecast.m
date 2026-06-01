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
%       Part A model implementations. When interval bootstrapping is enabled
%       the final selected forecasts use the fuller closed-loop Monte Carlo
%       interval procedure (the higher-fidelity counterpart of the lightweight
%       residual bootstrap used during Part A model selection). Both stages
%       target the same closed-loop predictive uncertainty definition. When
%       interval bootstrapping is disabled the legacy analytic forecast path is
%       used:
%           AR    uses fit_ar_model + forecast_ar_model.
%           ARX   uses fit_arx_model + forecast_arx_closed_loop.
%           N4SID uses the corrected fit_n4sid_model path.
%           SSEST uses the corrected fit_ssest_model path.
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

    use_intervals = isfield(forecast_options, 'intervals') && ...
        isstruct(forecast_options.intervals) && forecast_options.intervals.enabled;

    %% 2. Forecast Dispatch
    if use_intervals
        context = struct( ...
            'stage', "final", ...
            'exo_mode', exo_mode, ...
            'sirs_cfg', sirs_cfg, ...
            'horizon', horizon, ...
            'alphas', wis_alphas, ...
            'sim_seed', sim_seed, ...
            'scenario_key', local_scenario_key(forecast_options), ...
            'window_index', local_window_index(window_entry), ...
            'model_type', string(model_type));
        interval_options = make_interval_options(forecast_options.intervals, context);

        switch char(model_type)
            case {'AR', 'ARX'}
                [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper, meta] = ...
                    simulate_ar_arx_intervals(model_type, params, Rt_past, ...
                    U_past, sirs_state, num_exo, interval_options);
            case {'N4SID', 'SSEST'}
                [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper, meta] = ...
                    simulate_statespace_intervals(model_type, params, Rt_past, ...
                    U_past, sirs_state, num_exo, interval_options);
            otherwise
                error('FORECAST:UnknownModel', ...
                    'Unsupported MODEL_TYPE: %s', string(model_type));
        end
    else
        [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = local_legacy_forecast( ...
            model_type, params, Rt_past, U_past, sirs_state, sirs_cfg, ...
            exo_mode, sim_seed, num_exo, horizon, wis_alphas);
        meta = local_legacy_meta();
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

%% Local Functions
function key = local_scenario_key(forecast_options)
%LOCAL_SCENARIO_KEY Stable scenario identifier for interval seeding.
    if isfield(forecast_options, 'scenario_id') && ~isempty(forecast_options.scenario_id)
        key = string(forecast_options.scenario_id);
    else
        key = "scenario";
    end
end

function idx = local_window_index(window_entry)
%LOCAL_WINDOW_INDEX Stable window index for interval seeding.
    if isfield(window_entry, 'window_day_idx') && ~isempty(window_entry.window_day_idx)
        idx = double(window_entry.window_day_idx);
    elseif isfield(window_entry, 'window_day') && ~isempty(window_entry.window_day)
        idx = double(window_entry.window_day);
    else
        idx = 0;
    end
end

function meta = local_legacy_meta()
%LOCAL_LEGACY_META Metadata for the legacy analytic forecast path.
    meta = struct();
    meta.interval_method = "legacy_analytic";
    meta.interval_num_draws = 0;
    meta.interval_seed = 0;
    meta.interval_status = "legacy_analytic";
end

function [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = local_legacy_forecast( ...
    model_type, params, Rt_past, U_past, sirs_state, sirs_cfg, exo_mode, ...
    sim_seed, num_exo, horizon, wis_alphas)
%LOCAL_LEGACY_FORECAST Analytic forecast dispatch matching Part A model selection.
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
end
