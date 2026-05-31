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
%   See also AGGREGATE_CANDIDATE_SCORES, SELECT_BEST_CONFIGURATION.
%
% A. M. Kaahin 2026-05-31

    %% 1. Candidate Evaluation
    params = reshape(double(candidate_configuration), 1, []);
    scenario_scores = inf(1, length(scenario_data));

    for s = 1:length(scenario_data)
        data = scenario_data(s);
        window_wis = inf(numel(data.window_data), 1);

        for w = 1:numel(data.window_data)
            window_entry = data.window_data(w);
            if isempty(window_entry.Rt_past) || isempty(window_entry.truth_Rt)
                continue;
            end

            [Rt_pred, ~, out_alphas, Rt_lower, Rt_upper] = local_fit_candidate( ...
                model_type, params, window_entry.Rt_past, window_entry.U_past, ...
                window_entry.sirs_state, evaluation_options, data.num_exo);

            if ~local_is_valid_forecast(Rt_pred, out_alphas, Rt_lower, Rt_upper, ...
                    window_entry.truth_Rt)
                window_wis(w) = inf;
                continue;
            end

            pointwise_wis = local_compute_wis(window_entry.truth_Rt, Rt_pred, ...
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

function [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = local_fit_candidate( ...
    model_type, params, Rt_past, U_past, sirs_state, evaluation_options, num_exo)
%LOCAL_FIT_CANDIDATE Fit and forecast one candidate model.
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
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                fit_arima(Rt_past, params(1), 0, 0, horizon, wis_alphas);

        case 'ARX'
            nb_vec = repmat(params(2), 1, num_exo);
            nk_vec = repmat(params(3), 1, num_exo);
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                fit_arimax(Rt_past, U_past, [], params(1), 0, 0, ...
                nb_vec, nk_vec, horizon, wis_alphas, ...
                sirs_state, sirs_cfg, exo_mode, sim_seed);

        case 'N4SID'
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                fit_n4sid(Rt_past, U_past, [], params(1), params(2), ...
                horizon, wis_alphas, sirs_state, sirs_cfg, exo_mode, sim_seed);

        case 'SSEST'
            [Rt_pred, aicc, out_alphas, Rt_lower, Rt_upper] = ...
                fit_ssest(Rt_past, U_past, [], params(1), params(2), ...
                horizon, wis_alphas, sirs_state, sirs_cfg, exo_mode, sim_seed);
    end
end

function is_valid = local_is_valid_forecast(Rt_pred, out_alphas, Rt_lower, Rt_upper, truth_Rt)
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
        all(isfinite(Rt_pred)) && ...
        all(isfinite(Rt_lower(:))) && ...
        all(isfinite(Rt_upper(:))) && ...
        all(Rt_lower(:) <= Rt_upper(:));
end

function wis = local_compute_wis(truth_Rt, median_Rt, lower_Rt, upper_Rt, alphas)
%LOCAL_COMPUTE_WIS Compute pointwise weighted interval score values.
    truth_Rt = double(truth_Rt(:));
    median_Rt = double(median_Rt(:));
    lower_Rt = double(lower_Rt);
    upper_Rt = double(upper_Rt);
    alphas = reshape(double(alphas), 1, []);

    num_intervals = numel(alphas);
    wis = 0.5 * abs(truth_Rt - median_Rt);

    for j = 1:num_intervals
        alpha = alphas(j);
        interval_score = (upper_Rt(:, j) - lower_Rt(:, j)) ...
            + (2 / alpha) * max(lower_Rt(:, j) - truth_Rt, 0) ...
            + (2 / alpha) * max(truth_Rt - upper_Rt(:, j), 0);
        wis = wis + (alpha / 2) * interval_score;
    end

    wis = wis / (num_intervals + 0.5);
end
