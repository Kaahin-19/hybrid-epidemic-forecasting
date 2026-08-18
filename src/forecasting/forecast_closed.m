function [ensemble_paths, fit_info] = forecast_closed(model_type, params, Rt_past, U_past, sirs_state, num_exo, num_draws, horizon, exo_mode, base_stepper, resample_seed, epidemic_base_seed, vary_epidemic_seed)
%FORECAST_CLOSED Bootstrap forecast ensemble for models with exogenous inputs (num_exo > 0).
%
%   Syntax:
%       [ensemble_paths, fit_info] = forecast_closed(model_type, params,
%           Rt_past, U_past, sirs_state, num_exo, num_draws, horizon, exo_mode,
%           base_stepper, resample_seed, epidemic_base_seed, vary_epidemic_seed)
%
%   Description:
%       Fits an ARX or state-space model with exogenous inputs to log(Rt_past),
%       computes one-step prediction residuals using estimated initial
%       conditions, maps the observed history to the forecast-origin state,
%       resamples centred residuals as innovations under resample_seed, and
%       propagates closed-loop bootstrap paths on the Rt scale. The last observed
%       Rt drives the first SIRS step; each forecast Rt drives the following step,
%       whose output state determines the next exogenous covariate.
%       The susceptible-domain threshold is enforced both on entry to sirs_step
%       (before beta is computed) and after each advance to guard the returned
%       state. Fails fast if the series is constant, the history is too short,
%       any bootstrap draw produces a non-finite or non-positive Rt, or the
%       forecasted SIRS state crosses the susceptible-domain threshold.
%
%   Inputs:
%       model_type         - "ARX", "N4SID", or "SSEST".
%       params             - [na, nb, nk] for ARX; [n] for state-space.
%       Rt_past            - T×1 historical Rt values.
%       U_past             - T×num_exo historical exogenous covariate matrix.
%       sirs_state         - [S, I, R] epidemic state at the forecast origin.
%       num_exo            - Number of exogenous inputs (> 0).
%       num_draws          - Number of Monte Carlo draws.
%       horizon            - Forecast horizon in steps.
%       exo_mode           - "S", "I", or "Both" (controls covariate extraction).
%       base_stepper       - Prebuilt SIRS stepper from sirs_init, reused across all
%                            draws and windows (the caller builds it once, e.g. once
%                            per parallel worker). Its model_params supplies pop_size
%                            and min_susceptible; forecast_closed never calls sirs_init.
%       resample_seed      - Integer seed for the residual resample RNG.
%       epidemic_base_seed - Integer base seed for per-draw SIRS epidemic seeds.
%       vary_epidemic_seed - Logical; if true, each draw receives a distinct seed.
%
%   Outputs:
%       ensemble_paths - horizon×num_draws matrix of finite Rt bootstrap draws.
%       fit_info       - Struct with field AICc (corrected AIC of the fitted model);
%                        a diagnostic that never influences model selection.
%
%   See also PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS, PARTA_03_RUN_FORECASTS, FORECAST_OPEN, SIRS_STEP.
%
% A. M. Kaahin 2026-06-15
% Modified: 2026-08-15

y = log(Rt_past);
Rt_origin_driver = Rt_past(end);

switch model_type
    case "ARX"
        [ensemble_paths, aicc] = local_arx(y, U_past, params, num_exo, num_draws, horizon, exo_mode, base_stepper, sirs_state, Rt_origin_driver, resample_seed, epidemic_base_seed, vary_epidemic_seed);
    case {"N4SID", "SSEST"}
        [ensemble_paths, aicc] = local_ss_closed(model_type, y, U_past, params(1), num_exo, num_draws, horizon, exo_mode, base_stepper, sirs_state, Rt_origin_driver, resample_seed, epidemic_base_seed, vary_epidemic_seed);
    otherwise
        error('FORECAST_CLOSED:UnknownModel', 'Unsupported model type: %s', model_type);
end

fit_info = struct('AICc', aicc);
end

%% Local functions

function [ensemble, aicc] = local_arx(y, U_past, params, num_exo, num_draws, ...
    horizon, exo_mode, base_stepper, sirs_state, Rt_origin_driver, ...
    resample_seed, epidemic_base_seed, vary_epidemic_seed)
%LOCAL_ARX Closed-loop ARX bootstrap ensemble on the log scale.
na = params(1);
nb = params(2);
nk = params(3);
T  = numel(y);

if std(y) < 1e-8
    error('FORECAST_CLOSED:ConstantSeries', 'log(Rt_past) is effectively constant (std < 1e-8); cannot fit ARX model.');
end

max_lag = max(na, nk + nb - 1);
if T - max_lag < 2
    error('FORECAST_CLOSED:InsufficientHistory', 'ARX history too short: T - max_lag = %d < 2.', T - max_lag);
end

nb_vec = repmat(nb, 1, num_exo);
nk_vec = repmat(nk, 1, num_exo);
sys    = arx(iddata(y, U_past, 1), [na, nb_vec, nk_vec]);
aicc   = sys.Report.Fit.AICc;
a_vals = sys.A(2:end);
b_vals = local_extract_b(sys.B, nb, nk, num_exo);

residuals = zeros(T - max_lag, 1);
for t = (max_lag + 1):T
    y_hat                  = local_arx_step(a_vals, b_vals, na, nb, nk, ...
        y(1:t-1), U_past(1:t-1, :));
    residuals(t - max_lag) = y(t) - y_hat;
end
residuals = residuals(isfinite(residuals));

if numel(residuals) < 2
    error('FORECAST_CLOSED:InsufficientResiduals', 'Fewer than two finite ARX residuals available.');
end

innovations     = local_resample(residuals, horizon, num_draws, resample_seed);
pop_size        = base_stepper.model_params.pop_size;
min_susceptible = base_stepper.model_params.min_susceptible;

rolling_y = [y;      zeros(horizon, 1)];
rolling_U = [U_past; zeros(horizon, num_exo)];

ensemble = zeros(horizon, num_draws);
for d = 1:num_draws
    draw_seed          = local_draw_seed(epidemic_base_seed, d, horizon, vary_epidemic_seed);
    stepper            = base_stepper;
    stepper.seed       = draw_seed;
    stepper.call_count = 0;
    state              = sirs_state;
    Rt_driver          = Rt_origin_driver;
    roll_y             = rolling_y;
    roll_U             = rolling_U;
    for h = 1:horizon
        y_hat   = local_arx_step(a_vals, b_vals, na, nb, nk, ...
            roll_y(1:T+h-1), roll_U(1:T+h-1, :));
        y_next  = y_hat + innovations(h, d);
        Rt_next = exp(y_next);
        if ~isfinite(Rt_next) || Rt_next <= 0
            error('FORECAST_CLOSED:InvalidForecastDraw', 'Bootstrap draw produced a non-finite or non-positive Rt.');
        end
        [state, stepper] = sirs_step(stepper, state, Rt_driver);
        if state(1) <= min_susceptible
            error('EPIDEMIC:SusceptibleBelowThreshold', 'Forecasted SIRS state crossed the susceptible-domain threshold.');
        end
        ensemble(h, d)   = Rt_next;
        roll_y(T + h)    = y_next;
        roll_U(T + h, :) = local_exo_row(state, exo_mode, pop_size);
        Rt_driver        = Rt_next;
    end
end
end

function [ensemble, aicc] = local_ss_closed(model_type, y, U_past, n, ~, ...
    num_draws, horizon, exo_mode, base_stepper, sirs_state, Rt_origin_driver, ...
    resample_seed, epidemic_base_seed, vary_epidemic_seed)
%LOCAL_SS_CLOSED Closed-loop state-space bootstrap ensemble on the log scale.
if std(y) < 1e-8
    error('FORECAST_CLOSED:ConstantSeries', 'log(Rt_past) is effectively constant (std < 1e-8); cannot fit state-space model.');
end

data = iddata(y, U_past, 1);
switch model_type
    case "N4SID"
        sys = n4sid(data, n, n4sidOptions('Display', 'off'));
    case "SSEST"
        sys = ssest(data, n, 'Ts', data.Ts, ssestOptions('Display', 'off'));
end
aicc = sys.Report.Fit.AICc;

[A, B, C, D, K_gain] = idssdata(sys);

prediction_options = peOptions('InitialCondition', 'e');
prediction_errors  = pe(sys, data, 1, prediction_options);
residuals           = prediction_errors.OutputData;
x_origin            = data2state(sys, data);
residuals           = residuals(isfinite(residuals));

if numel(residuals) < 2
    error('FORECAST_CLOSED:InsufficientResiduals', 'Fewer than two finite state-space residuals available.');
end

innovations     = local_resample(residuals, horizon, num_draws, resample_seed);
pop_size        = base_stepper.model_params.pop_size;
min_susceptible = base_stepper.model_params.min_susceptible;

ensemble = zeros(horizon, num_draws);
for d = 1:num_draws
    draw_seed          = local_draw_seed(epidemic_base_seed, d, horizon, vary_epidemic_seed);
    stepper            = base_stepper;
    stepper.seed       = draw_seed;
    stepper.call_count = 0;
    x                  = x_origin;
    state              = sirs_state;
    Rt_driver          = Rt_origin_driver;
    u_current          = U_past(end, :).';
    for h = 1:horizon
        y_hat   = C * x + D * u_current;
        y_next  = y_hat + innovations(h, d);
        Rt_next = exp(y_next);
        if ~isfinite(Rt_next) || Rt_next <= 0
            error('FORECAST_CLOSED:InvalidForecastDraw', 'Bootstrap draw produced a non-finite or non-positive Rt.');
        end
        [state, stepper] = sirs_step(stepper, state, Rt_driver);
        if state(1) <= min_susceptible
            error('EPIDEMIC:SusceptibleBelowThreshold', 'Forecasted SIRS state crossed the susceptible-domain threshold.');
        end
        u_next         = local_exo_col(state, exo_mode, pop_size);
        x              = A * x + B * u_current + K_gain * innovations(h, d);
        ensemble(h, d) = Rt_next;
        u_current      = u_next;
        Rt_driver      = Rt_next;
    end
end
end

function b_vals = local_extract_b(B_property, nb, nk, num_exo)
%LOCAL_EXTRACT_B Extract active B coefficients from the ARX system polynomial.
b_vals = cell(1, num_exo);
if iscell(B_property)
    for j = 1:num_exo
        b_vals{j} = B_property{j}(nk + 1 : nk + nb);
    end
elseif num_exo == 1
    b_vals{1} = B_property(nk + 1 : nk + nb);
else
    for j = 1:num_exo
        b_vals{j} = B_property(j, nk + 1 : nk + nb);
    end
end
end

function y_hat = local_arx_step(a_vals, b_vals, na, nb, nk, log_hist, U_hist)
%LOCAL_ARX_STEP One-step ARX prediction from rolling log and exogenous history.
T     = numel(log_hist);
y_hat = 0;
for lag = 1:na
    y_hat = y_hat - a_vals(lag) * log_hist(T + 1 - lag);
end
for j = 1:numel(b_vals)
    for k = 1:nb
        input_lag = nk + k - 1;
        y_hat = y_hat + b_vals{j}(k) * U_hist(T + 1 - input_lag, j);
    end
end
end

function u = local_exo_row(state, exo_mode, pop_size)
%LOCAL_EXO_ROW Row-vector exogenous covariate from epidemic state.
switch exo_mode
    case "S";    u = state(1) / pop_size;
    case "I";    u = state(2) / pop_size;
    case "Both"; u = [state(1), state(2)] / pop_size;
end
end

function u = local_exo_col(state, exo_mode, pop_size)
%LOCAL_EXO_COL Column-vector exogenous covariate from epidemic state.
switch exo_mode
    case "S";    u = state(1) / pop_size;
    case "I";    u = state(2) / pop_size;
    case "Both"; u = [state(1); state(2)] / pop_size;
end
end

function seed = local_draw_seed(base, draw_index, horizon, vary)
%LOCAL_DRAW_SEED Per-draw epidemic seed derived from the base seed.
seed = base;
if vary
    seed = base + (draw_index - 1) * (horizon + 1);
end
end

function innovations = local_resample(residuals, horizon, num_draws, resample_seed)
%LOCAL_RESAMPLE Centred residual resample with isolated RNG state.
centered     = residuals - mean(residuals);
caller_state = rng;
cleanup      = onCleanup(@() rng(caller_state));
rng(resample_seed, 'twister');
idx         = randi(numel(centered), horizon, num_draws);
innovations = centered(idx);
clear cleanup;
end
