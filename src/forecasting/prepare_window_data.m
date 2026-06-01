function window_entry = prepare_window_data(scenario_inputs, window_endpoint, ...
    horizon, sirs_cfg)
%PREPARE_WINDOW_DATA Build a single expanding-window forecast input entry.
%
%   Syntax:
%       window_entry = prepare_window_data(scenario_inputs, window_endpoint, ...
%           horizon, sirs_cfg)
%
%   Description:
%       Assembles the historical and future quantities for one expanding-window
%       forecast origin. The window construction reproduces the Part A
%       model-selection protocol: history is taken up to the window endpoint,
%       the future truth spans the forecast horizon, and exogenous covariates
%       plus the current SIRS state are derived for closed-loop forecasting.
%
%   Inputs:
%       scenario_inputs - Structure with Rt_true, tspan, S_true, I_true, and
%                         U_true column data for one scenario.
%       window_endpoint - Forecast-origin time value on the scenario time grid.
%       horizon         - Positive integer forecast horizon.
%       sirs_cfg        - SIRS parameter structure (uses pop_size).
%
%   Outputs:
%       window_entry - Structure describing the window, including Rt_past,
%                      truth_Rt, U_past, sirs_state, and future indexing.
%
%   See also BUILD_FORECASTING_DATASET, RUN_EXPANDING_WINDOW_FORECAST.
%
% A. M. Kaahin 2026-06-01

    %% 1. Window Resolution
    window_entry = struct( ...
        'window_day', window_endpoint, ...
        'window_day_idx', [], ...
        'horizon_indices', [], ...
        't_future', [], ...
        'Rt_past', [], ...
        'truth_Rt', [], ...
        'U_past', [], ...
        'sirs_state', [], ...
        'is_valid_window', false);

    idx_T = find(scenario_inputs.tspan == window_endpoint, 1);
    if isempty(idx_T)
        return;
    end

    idx_end = idx_T + horizon;

    %% 2. Historical and Future Slices
    window_entry.window_day_idx  = idx_T;
    window_entry.horizon_indices = (idx_T + 1 : idx_end)';
    window_entry.t_future        = scenario_inputs.tspan(idx_T + 1 : idx_end);
    window_entry.Rt_past         = scenario_inputs.Rt_true(1:idx_T);
    window_entry.truth_Rt        = scenario_inputs.Rt_true(idx_T + 1 : idx_end);

    %% 3. Exogenous Inputs and Current State
    [window_entry.U_past, window_entry.sirs_state] = ...
        local_prepare_exogenous_inputs(scenario_inputs, idx_T, sirs_cfg);

    window_entry.is_valid_window = ...
        ~isempty(window_entry.Rt_past) && ~isempty(window_entry.truth_Rt);
end

function [U_past, sirs_state] = local_prepare_exogenous_inputs(data, idx_T, sirs_cfg)
%LOCAL_PREPARE_EXOGENOUS_INPUTS Build historical covariates and current state.
    if isempty(data.U_true)
        U_past = [];
        sirs_state = [];
        return;
    end

    U_past = data.U_true(1:idx_T, :);

    current_I = data.I_true(idx_T);
    current_S = data.S_true(idx_T);
    current_R = sirs_cfg.pop_size - current_S - current_I;
    sirs_state = [current_S, current_I, current_R];
end
