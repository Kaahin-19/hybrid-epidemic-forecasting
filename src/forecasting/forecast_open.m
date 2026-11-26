function [ensemble_paths, fit_info] = forecast_open(model_type, params, Rt_past, num_draws, horizon, resample_seed)

%FORECAST_OPEN Bootstrap forecast ensemble for output-only models (num_exo == 0).
%
%   Syntax:
%       [ensemble_paths, fit_info] = forecast_open(model_type, params,
%           Rt_past, num_draws, horizon, resample_seed)
%
%   Description:
%       Fits an AR or output-only state-space model to log(Rt_past), computes
%       one-step prediction residuals using estimated initial conditions,
%       maps the observed history to the forecast-origin state, resamples
%       centred residuals as innovations under resample_seed, and propagates
%       horizon-step bootstrap paths on the Rt scale. Fails fast if the series
%       is constant, the history is too short, or any bootstrap draw produces a
%       non-finite or non-positive Rt. Fit diagnostics are returned without
%       affecting the forecast.
%
%   Inputs:
%       model_type    - "AR", "N4SID", or "SSEST".
%       params        - [p] for AR; [n] for state-space.
%       Rt_past       - T×1 historical Rt values.
%       num_draws     - Number of Monte Carlo draws.
%       horizon       - Forecast horizon in steps.
%       resample_seed - Integer seed for the residual resample RNG.
%
%   Outputs:
%       ensemble_paths - horizon×num_draws matrix of finite Rt bootstrap draws.
%       fit_info       - Struct with fields:
%           AICc                    - Corrected AIC of the fitted model.
%           spectral_radius         - Largest pole modulus of the fitted model
%                                     (>= 1 means an unstable model).
%           termination             - SSEST stopping reason; "non-iterative"
%                                     for AR and N4SID.
%           iteration_limit_reached - True when SSEST stopped at its
%                                     iteration limit.
%
%   See also PARTA_02_SELECT_HYPERPARAMETERS, PARTA_03_RUN_FORECASTS,
%            PARTB_02_RUN_FORECASTS, PARTC_02_SELECT_LOCAL_ORDERS,
%            PARTC_03_RUN_FORECASTS, FORECAST_CLOSED.
%
% A. M. Kaahin 2026-06-15
% Modified: 2026-11-26

%% 1. Forecast Setup
y = log(Rt_past);

%% 2. Model-Specific Forecast
switch model_type
    case "AR"
        [ensemble_paths, fit_info] = local_ar(y, params(1), num_draws, horizon, resample_seed);
    case {"N4SID", "SSEST"}
        [ensemble_paths, fit_info] = local_ss_open(model_type, y, params(1), num_draws, horizon, resample_seed);
    otherwise
        error('FORECAST_OPEN:UnknownModel', 'Unsupported model type: %s', model_type);
end
end

%% 3. Local Functions

function [ensemble, fit_info] = local_ar(y, p, num_draws, horizon, resample_seed)
%LOCAL_AR AR bootstrap ensemble on the log scale.
if std(y) < 1e-8
    error('FORECAST_OPEN:ConstantSeries', 'log(Rt_past) is effectively constant (std < 1e-8); cannot fit AR model.');
end
if numel(y) <= p + 1
    error('FORECAST_OPEN:InsufficientHistory', 'AR history too short: numel(y) = %d <= p + 1 = %d.', numel(y), p + 1);
end

sys      = ar(iddata(y, [], 1), p, 'burg');
fit_info = struct('AICc', sys.Report.Fit.AICc, 'spectral_radius', max(abs(roots(sys.A))), 'termination', "non-iterative", 'iteration_limit_reached', false);
a_vals   = sys.A(2:end);

T         = numel(y);
residuals = zeros(T - p, 1);
for t = (p + 1):T
    y_hat            = -(a_vals * y(t - 1 : -1 : t - p));
    residuals(t - p) = y(t) - y_hat;
end
residuals = residuals(isfinite(residuals));

if numel(residuals) < 2
    error('FORECAST_OPEN:InsufficientResiduals', 'Fewer than two finite AR residuals available.');
end

innovations = local_resample(residuals, horizon, num_draws, resample_seed);

seed_vals = y(end - p + 1 : end);
roll      = [repmat(seed_vals, 1, num_draws); zeros(horizon, num_draws)];
ensemble  = zeros(horizon, num_draws);
for h = 1:horizon
    recent  = roll(h : h + p - 1, :);
    y_hat   = -(a_vals * flipud(recent));
    y_next  = y_hat + innovations(h, :);
    Rt_next = exp(y_next);
    invalid_draw = find(~(isfinite(Rt_next) & Rt_next > 0), 1);
    if ~isempty(invalid_draw)
        error('FORECAST_OPEN:InvalidForecastDraw', 'Bootstrap draw %d produced a non-finite or non-positive Rt at lead %d.', invalid_draw, h);
    end
    ensemble(h, :) = Rt_next;
    roll(p + h, :) = y_next;
end
end

function [ensemble, fit_info] = local_ss_open(model_type, y, n, num_draws, horizon, resample_seed)
%LOCAL_SS_OPEN Output-only state-space bootstrap ensemble on the log scale.
if std(y) < 1e-8
    error('FORECAST_OPEN:ConstantSeries', 'log(Rt_past) is effectively constant (std < 1e-8); cannot fit state-space model.');
end

data = iddata(y, [], 1);
switch model_type
    case "N4SID"
        sys = n4sid(data, n, n4sidOptions('Display', 'off'));
    case "SSEST"
        sys = ssest(data, n, 'Ts', data.Ts, ssestOptions('Display', 'off'));
end
[A, ~, C, ~, K_gain] = idssdata(sys);
fit_info = local_ss_fit_info(model_type, sys, A);

prediction_options = peOptions('InitialCondition', 'e');
prediction_errors  = pe(sys, data, 1, prediction_options);
residuals           = prediction_errors.OutputData;
x_origin            = data2state(sys, data);
residuals           = residuals(isfinite(residuals));

if numel(residuals) < 2
    error('FORECAST_OPEN:InsufficientResiduals', 'Fewer than two finite state-space residuals available.');
end

innovations = local_resample(residuals, horizon, num_draws, resample_seed);

ensemble = zeros(horizon, num_draws);
for d = 1:num_draws
    x = x_origin;
    for h = 1:horizon
        y_hat   = C * x;
        y_next  = y_hat + innovations(h, d);
        Rt_next = exp(y_next);
        if ~isfinite(Rt_next) || Rt_next <= 0
            error('FORECAST_OPEN:InvalidForecastDraw', 'Bootstrap draw %d produced a non-finite or non-positive Rt at lead %d.', d, h);
        end
        ensemble(h, d) = Rt_next;
        x              = A * x + K_gain * innovations(h, d);
    end
end
end

function fit_info = local_ss_fit_info(model_type, sys, A)
%LOCAL_SS_FIT_INFO AICc, stability, and search-termination diagnostics of a state-space fit.
if model_type == "SSEST"
    termination             = string(sys.Report.Termination.WhyStop);
    iteration_limit_reached = sys.Report.Termination.Iterations >= sys.Report.OptionsUsed.SearchOptions.MaxIterations;
else
    termination             = "non-iterative";
    iteration_limit_reached = false;
end
fit_info = struct('AICc', sys.Report.Fit.AICc, 'spectral_radius', max(abs(eig(A))), 'termination', termination, 'iteration_limit_reached', iteration_limit_reached);
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
