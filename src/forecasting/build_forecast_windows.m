function [window_data, num_exo] = build_forecast_windows(Rt_true, S_true, I_true, ...
    tspan, exo_mode, pop_size, min_window, step_size, horizon)

%BUILD_FORECAST_WINDOWS Expanding-window forecast entries for one scenario.
%
%   Syntax:
%       [window_data, num_exo] = build_forecast_windows(Rt_true, S_true, I_true,
%           tspan, exo_mode, pop_size, min_window, step_size, horizon)
%
%   Description:
%       Builds the expanding-window entries used for global model selection and
%       final forecasting. Each window stores the past Rt history, the matching
%       exogenous covariate history and forecast-origin SIRS state for
%       closed-loop modes, the horizon time axis, and the truth Rt window to be
%       scored. Window origins are the configured endpoints whose forecast
%       horizon stays inside the truth length.
%
%   Inputs:
%       Rt_true    - T-by-1 true effective-Rt trajectory.
%       S_true     - T-by-1 true susceptible counts.
%       I_true     - T-by-1 true infectious counts.
%       tspan      - 1-by-T time grid (days).
%       exo_mode   - "None", "S", "I", or "Both".
%       pop_size   - Total population size.
%       min_window - First forecast-origin day.
%       step_size  - Spacing between forecast origins (days).
%       horizon    - Forecast horizon (steps).
%
%   Outputs:
%       window_data - Struct array with fields window_day, window_day_idx,
%                     time_horizon, Rt_past, U_past, sirs_state, truth_Rt.
%                     U_past and sirs_state are empty when exo_mode is "None".
%       num_exo     - Number of exogenous covariate columns (0 for "None").
%
%   See also PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS, PARTA_03_RUN_FORECASTS,
%            PARTB_02_RUN_FORECASTS.
%
% A. M. Kaahin 2026-06-28
% Modified: 2026-08-23

%% 1. Exogenous Covariate Construction
U_true  = local_exo_matrix(S_true, I_true, exo_mode, pop_size);
num_exo = size(U_true, 2);
has_exo = num_exo > 0;

%% 2. Forecast Origin Initialization
win_endpoints = min_window : step_size : (numel(Rt_true) - horizon);

template = struct('window_day', [], 'window_day_idx', [], 'time_horizon', [], ...
    'Rt_past', [], 'U_past', [], 'sirs_state', [], 'truth_Rt', []);
built = repmat(template, numel(win_endpoints), 1);
keep  = false(numel(win_endpoints), 1);

%% 3. Window Construction
for k = 1:numel(win_endpoints)
    idx_T = find(tspan == win_endpoints(k), 1);
    if isempty(idx_T) || idx_T + horizon > numel(Rt_true)
        continue;
    end

    built(k).window_day     = win_endpoints(k);
    built(k).window_day_idx = idx_T;
    built(k).time_horizon   = tspan(idx_T + 1 : idx_T + horizon);
    built(k).Rt_past        = Rt_true(1:idx_T);

    if has_exo
        R_at_T = pop_size - S_true(idx_T) - I_true(idx_T);
        built(k).U_past     = U_true(1:idx_T, :);
        built(k).sirs_state = [S_true(idx_T); I_true(idx_T); R_at_T];
    end

    built(k).truth_Rt = Rt_true(idx_T + 1 : idx_T + horizon);
    keep(k) = true;
end

%% 4. Output Assembly
window_data = built(keep);
end

%% 5. Local Functions
function U_true = local_exo_matrix(S_true, I_true, exo_mode, pop_size)
%LOCAL_EXO_MATRIX Build the exogenous covariate matrix for one scenario.
switch exo_mode
    case "None"; U_true = [];
    case "S";    U_true = S_true / pop_size;
    case "I";    U_true = I_true / pop_size;
    case "Both"; U_true = [S_true / pop_size, I_true / pop_size];
    otherwise
        error('FORECAST:UnknownExoMode', 'Unsupported exo_mode: %s', exo_mode);
end
end
