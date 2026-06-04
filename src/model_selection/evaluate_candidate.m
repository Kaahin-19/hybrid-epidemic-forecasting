function scenario_scores = evaluate_candidate(model_type, candidate_configuration, ...
    scenario_data, evaluation_options)
%EVALUATE_CANDIDATE Score one Part A model configuration across scenarios.
%
%   Syntax:
%       scenario_scores = evaluate_candidate(model_type, candidate_configuration, ...
%           scenario_data, evaluation_options)
%
%   Description:
%       Evaluates one candidate configuration over all prepared Part A
%       scenario windows using the existing expanding-window protocol and WIS
%       failure policy.
%
%   Inputs:
%       model_type              - Model family identifier.
%       candidate_configuration - Numeric row vector of model parameters.
%       scenario_data           - Prepared scenario-window inputs.
%       evaluation_options      - Structure with exo mode, SIRS settings,
%                                 seed, horizon, and WIS alpha levels.
%
%   Outputs:
%       scenario_scores - Mean window WIS for each scenario.
%
%   See also AGGREGATE_CANDIDATE_SCORES, SELECT_BEST_CONFIGURATION,
%            SIMULATE_AR_ARX_INTERVALS, SIMULATE_STATESPACE_INTERVALS.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-01

    %% 1. Candidate Evaluation
    params = reshape(double(candidate_configuration), 1, []);
    scenario_scores = inf(1, length(scenario_data));

    for s = 1:length(scenario_data)
        data = scenario_data(s);
        window_wis = inf(numel(data.window_data), 1);
        scenario_key = local_scenario_key(data, s);

        for w = 1:numel(data.window_data)
            window_entry = data.window_data(w);
            if isempty(window_entry.Rt_past) || isempty(window_entry.truth_Rt)
                continue;
            end

            [Rt_pred, ~, out_alphas, Rt_lower, Rt_upper] = local_window_forecast( ...
                model_type, params, window_entry, evaluation_options, ...
                data.num_exo, scenario_key, w);

            if ~is_valid_forecast(Rt_pred, out_alphas, Rt_lower, Rt_upper, ...
                    window_entry.truth_Rt)
                window_wis(w) = inf;
                continue;
            end

            pointwise_wis = compute_wis(window_entry.truth_Rt, Rt_pred, ...
                Rt_lower, Rt_upper, out_alphas);
            if any(~isfinite(pointwise_wis))
                window_wis(w) = inf;
            else
                window_wis(w) = mean(pointwise_wis);
            end
        end

        scenario_scores(s) = mean(window_wis);
    end
end

function key = local_scenario_key(data, s)
%LOCAL_SCENARIO_KEY Stable scenario identifier for interval seeding.
    if isfield(data, 'scenario_id') && ~isempty(data.scenario_id)
        key = string(data.scenario_id);
    else
        key = string(s);
    end
end

function [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = local_window_forecast( ...
    model_type, params, window_entry, evaluation_options, num_exo, scenario_key, w)
%LOCAL_WINDOW_FORECAST Produce one window forecast and predictive intervals.
%   When interval bootstrapping is enabled this uses the lightweight
%   closed-loop residual-bootstrap intervals for model selection; otherwise it
%   falls back to the legacy analytic forecast path.
    if isfield(evaluation_options, 'intervals') && ...
            isstruct(evaluation_options.intervals) && ...
            evaluation_options.intervals.enabled
        context = struct( ...
            'stage', "selection", ...
            'exo_mode', evaluation_options.exo_mode, ...
            'sirs_cfg', evaluation_options.sirs_cfg, ...
            'horizon', evaluation_options.horizon, ...
            'alphas', evaluation_options.wis_alphas, ...
            'sim_seed', evaluation_options.sim_seed, ...
            'scenario_key', scenario_key, ...
            'window_index', w, ...
            'model_type', string(model_type));
        interval_options = make_interval_options(evaluation_options.intervals, context);

        switch char(model_type)
            case {'AR', 'ARX'}
                [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                    simulate_ar_arx_intervals(model_type, params, ...
                    window_entry.Rt_past, window_entry.U_past, ...
                    window_entry.sirs_state, num_exo, interval_options);
            case {'N4SID', 'SSEST'}
                [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                    simulate_statespace_intervals(model_type, params, ...
                    window_entry.Rt_past, window_entry.U_past, ...
                    window_entry.sirs_state, num_exo, interval_options);
            otherwise
                error('MODEL_SELECTION:UnknownModel', ...
                    'Unsupported MODEL_TYPE: %s', string(model_type));
        end
        return;
    end

    [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = local_fit_candidate( ...
        model_type, params, window_entry.Rt_past, window_entry.U_past, ...
        window_entry.sirs_state, evaluation_options, num_exo);
end

function [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = local_fit_candidate( ...
    model_type, params, Rt_past, U_past, sirs_state, evaluation_options, num_exo)
%LOCAL_FIT_CANDIDATE Fit and forecast one candidate model (legacy analytic path).
    Rt_pred = [];
    aicc = [];
    out_alphas = [];
    Rt_lower = [];
    Rt_upper = [];

    horizon = evaluation_options.horizon;
    wis_alphas = evaluation_options.wis_alphas;
    sirs_cfg = evaluation_options.sirs_cfg;
    exo_mode = evaluation_options.exo_mode;
    sim_seed = evaluation_options.sim_seed;

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
    end
end

