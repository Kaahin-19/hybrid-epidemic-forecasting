function [scenario_scores, scenario_aicc] = evaluate_candidate(model_type, ...
    candidate_configuration, scenario_data, evaluation_options)
%EVALUATE_CANDIDATE Score one Part A model configuration across scenarios.
%
%   Syntax:
%       [scenario_scores, scenario_aicc] = evaluate_candidate(model_type, ...
%           candidate_configuration, scenario_data, evaluation_options)
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
%       scenario_scores - Mean window WIS for each scenario (selection metric).
%       scenario_aicc   - Mean fitted-model AICc over finite windows for each
%                         scenario. Diagnostic only; never used for selection.
%
%   See also AGGREGATE_CANDIDATE_SCORES, PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS,
%            SIMULATE_AR_ARX_INTERVALS, SIMULATE_STATESPACE_INTERVALS.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-11

    %% 1. Candidate Evaluation
    params = candidate_configuration;
    num_scenarios = length(scenario_data);
    scenario_scores = inf(1, num_scenarios);
    scenario_aicc = nan(1, num_scenarios);   % diagnostic only; not a selector

    for s = 1:num_scenarios
        data = scenario_data(s);
        window_wis = inf(numel(data.window_data), 1);
        window_aicc = nan(numel(data.window_data), 1);
        scenario_key = data.scenario_id;

        for w = 1:numel(data.window_data)
            window_entry = data.window_data(w);

            % Capture fit AICc separately from WIS validity.
            [Rt_pred, out_alphas, Rt_lower, Rt_upper, window_aicc(w)] = ...
                local_window_forecast(model_type, params, window_entry, ...
                evaluation_options, data.num_exo, scenario_key, w);

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
        scenario_aicc(s) = local_mean_finite(window_aicc);
    end
end

function [Rt_pred, out_alphas, Rt_lower, Rt_upper, aicc] = local_window_forecast( ...
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
        case {"AR", "ARX"}
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                simulate_ar_arx_intervals(model_type, params, ...
                window_entry.Rt_past, window_entry.U_past, ...
                window_entry.sirs_state, num_exo, interval_options);
        case {"N4SID", "SSEST"}
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                simulate_statespace_intervals(model_type, params, ...
                window_entry.Rt_past, window_entry.U_past, ...
                window_entry.sirs_state, num_exo, interval_options);
        otherwise
            error('MODEL_SELECTION:UnknownModel', ...
                'Unsupported MODEL_TYPE: %s', model_type);
    end
end

function value = local_mean_finite(values)
%LOCAL_MEAN_FINITE Mean over finite values only (diagnostic AICc aggregation).
    values = double(values(:));
    values = values(isfinite(values));
    if isempty(values)
        value = nan;
    else
        value = mean(values);
    end
end
