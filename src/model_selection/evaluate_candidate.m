function scenario_scores = evaluate_candidate(model_type, candidate_configuration, ...
    scenario_data, evaluation_options)
%EVALUATE_CANDIDATE Score one Part A model configuration across scenarios.
%
%   Syntax:
%       scenario_scores = evaluate_candidate(model_type, candidate_configuration, ...
%           scenario_data, evaluation_options)
%
%   Description:
%       Evaluates one candidate configuration over all prepared Part A scenario
%       windows using the expanding-window protocol. Each window is forecast
%       with closed-loop residual-bootstrap predictive intervals, and the mean
%       window WIS is returned per scenario. Invalid forecasts receive infinite
%       WIS so failed candidates are rejected by the global selection.
%
%   Inputs:
%       model_type              - Model family identifier.
%       candidate_configuration - Numeric row vector of model parameters.
%       scenario_data           - Prepared scenario-window inputs.
%       evaluation_options      - Structure with exo mode, SIRS settings, seed,
%                                 horizon, WIS alpha levels, and interval settings.
%
%   Outputs:
%       scenario_scores - Mean window WIS for each scenario.
%
%   See also AGGREGATE_CANDIDATE_SCORES, SELECT_BEST_CONFIGURATION,
%            SIMULATE_AR_ARX_INTERVALS, SIMULATE_STATESPACE_INTERVALS.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-05

    %% 1. Candidate Evaluation
    params = candidate_configuration;
    scenario_scores = inf(1, length(scenario_data));

    for s = 1:length(scenario_data)
        data = scenario_data(s);
        window_wis = inf(numel(data.window_data), 1);
        scenario_key = data.scenario_id;

        for w = 1:numel(data.window_data)
            window_entry = data.window_data(w);

            [Rt_pred, out_alphas, Rt_lower, Rt_upper] = local_window_forecast( ...
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

function [Rt_pred, out_alphas, Rt_lower, Rt_upper] = local_window_forecast( ...
    model_type, params, window_entry, evaluation_options, num_exo, scenario_key, w)
%LOCAL_WINDOW_FORECAST Forecast one window with closed-loop residual-bootstrap intervals.
    context = struct( ...
        'stage', "selection", ...
        'exo_mode', evaluation_options.exo_mode, ...
        'sirs_cfg', evaluation_options.sirs_cfg, ...
        'horizon', evaluation_options.horizon, ...
        'alphas', evaluation_options.wis_alphas, ...
        'sim_seed', evaluation_options.sim_seed, ...
        'scenario_key', scenario_key, ...
        'window_index', w, ...
        'model_type', model_type);
    interval_options = make_interval_options(evaluation_options.intervals, context);

    switch model_type
        case {'AR', 'ARX'}
            [Rt_pred, ~, out_alphas, Rt_lower, Rt_upper] = ...
                simulate_ar_arx_intervals(model_type, params, ...
                window_entry.Rt_past, window_entry.U_past, ...
                window_entry.sirs_state, num_exo, interval_options);
        case {'N4SID', 'SSEST'}
            [Rt_pred, ~, out_alphas, Rt_lower, Rt_upper] = ...
                simulate_statespace_intervals(model_type, params, ...
                window_entry.Rt_past, window_entry.U_past, ...
                window_entry.sirs_state, num_exo, interval_options);
        otherwise
            error('MODEL_SELECTION:UnknownModel', ...
                'Unsupported MODEL_TYPE: %s', model_type);
    end
end
