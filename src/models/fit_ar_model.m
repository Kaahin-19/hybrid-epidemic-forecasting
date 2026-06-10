function model = fit_ar_model(Rt_hist, p, options)
%FIT_AR_MODEL Fit an output-only AR model to historical effective Rt.
%
%   Syntax:
%       model = fit_ar_model(Rt_hist, p)
%       model = fit_ar_model(Rt_hist, p, options)
%
%   Description:
%       Fits the Part A output-only AR case on log-transformed effective Rt.
%       The current Part A model-selection path uses p >= 1, d = 0, and
%       q = 0. The fitted System Identification model is constructed once
%       and stored in a lightweight structure for forecasting.
%
%   Inputs:
%       Rt_hist - Historical effective reproduction-number values.
%       p       - Autoregressive order.
%       options - Optional structure. Fields d and q must be zero if given.
%
%   Outputs:
%       model - Structure containing the fitted AR model and forecast scale.
%
%   See also FORECAST_AR_MODEL, EVALUATE_CANDIDATE.
%
% A. M. Kaahin 2026-05-31

    %% 1. Input Validation
    if nargin < 3 || isempty(options)
        options = struct();
    end

    p = local_validate_order(p, 'p');
    d = local_option_or_default(options, 'd', 0);
    q = local_option_or_default(options, 'q', 0);
    if d ~= 0 || q ~= 0
        error('AR:UnsupportedOrder', ...
            'fit_ar_model currently supports the Part A AR case d = 0 and q = 0.');
    end

    Rt_hist = local_validate_rt_history(Rt_hist);
    log_Rt = log(max(Rt_hist, eps));

    %% 2. Fallback Checks
    model = local_base_model(Rt_hist, p);
    if std(log_Rt) < 1e-8 || numel(log_Rt) <= p + 1
        model.is_persistence = true;
        return;
    end

    %% 3. Model Fitting
    try
        fit_data = iddata(log_Rt, [], 1);
        sys = ar(fit_data, p, 'burg');

        model.sys = sys;
        model.fit_data = fit_data;
        model.aicc = local_extract_aicc(sys);
        model.residual_std = local_ar_residual_std(sys, log_Rt, p);
        model.coefficients = local_extract_ar_coefficients(sys, p);
    catch
        model.is_persistence = true;
        model.aicc = inf;
    end
end

function model = local_base_model(Rt_hist, p)
%LOCAL_BASE_MODEL Create the common AR model structure.
    model = struct();
    model.type = "AR";
    model.p = p;
    model.d = 0;
    model.q = 0;
    model.transform = "log";
    model.sys = [];
    model.fit_data = [];
    model.coefficients = struct('A', [], 'a_values', []);
    model.aicc = inf;
    model.residual_std = 0;
    model.last_Rt = Rt_hist(end);
    model.log_history = log(max(Rt_hist, eps));
    model.is_persistence = false;
end

function value = local_validate_order(value, label)
%LOCAL_VALIDATE_ORDER Validate a positive integer model order.
    value = double(value);
    if ~isscalar(value) || ~isfinite(value) || value < 1 || value ~= floor(value)
        error('AR:InvalidOrder', '%s must be a positive integer scalar.', label);
    end
end

function value = local_option_or_default(options, field_name, default_value)
%LOCAL_OPTION_OR_DEFAULT Read an optional scalar option.
    if isfield(options, field_name)
        value = double(options.(field_name));
    else
        value = default_value;
    end
end

function Rt_hist = local_validate_rt_history(Rt_hist)
%LOCAL_VALIDATE_RT_HISTORY Validate positive historical Rt values.
    if ~isnumeric(Rt_hist) || ~isvector(Rt_hist)
        error('AR:InvalidHistory', 'Rt_hist must be a numeric vector.');
    end

    Rt_hist = double(Rt_hist(:));
    if isempty(Rt_hist) || any(~isfinite(Rt_hist)) || any(Rt_hist <= 0)
        error('AR:InvalidHistory', ...
            'Rt_hist must contain finite positive values.');
    end
end

function aicc = local_extract_aicc(sys)
%LOCAL_EXTRACT_AICC Extract AICc when available.
    aicc = inf;
    try
        aicc = double(sys.Report.Fit.AICc);
    catch
    end
end

function coefficients = local_extract_ar_coefficients(sys, p)
%LOCAL_EXTRACT_AR_COEFFICIENTS Extract A(q) coefficients from an AR model.
    A = double(sys.A(:)).';
    if numel(A) < p + 1
        error('AR:InvalidPolynomial', 'The fitted AR A polynomial is too short.');
    end

    coefficients = struct();
    coefficients.A = A;
    coefficients.a_values = A(2:(p + 1));
end

function residual_std = local_ar_residual_std(sys, log_Rt, p)
%LOCAL_AR_RESIDUAL_STD Estimate one-step residual scale on the log scale.
    coefficients = local_extract_ar_coefficients(sys, p);
    residuals = nan(max(0, numel(log_Rt) - p), 1);

    for t = (p + 1):numel(log_Rt)
        y_pred = 0;
        for lag = 1:p
            y_pred = y_pred - coefficients.a_values(lag) * log_Rt(t - lag);
        end
        residuals(t - p) = log_Rt(t) - y_pred;
    end

    residuals = residuals(isfinite(residuals));
    if isempty(residuals)
        residual_std = 0;
    else
        residual_std = std(residuals);
    end

    if isempty(residual_std) || ~isfinite(residual_std) || residual_std < 0
        residual_std = 0;
    end
end
