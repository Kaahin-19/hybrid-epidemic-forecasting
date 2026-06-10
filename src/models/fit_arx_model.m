function [model, timing] = fit_arx_model(Rt_hist, U_hist, na, nb_vec, nk_vec, options)
%FIT_ARX_MODEL Fit an ARX model once for Part A model selection.
%
%   Syntax:
%       model = fit_arx_model(Rt_hist, U_hist, na, nb_vec, nk_vec)
%       model = fit_arx_model(Rt_hist, U_hist, na, nb_vec, nk_vec, options)
%
%   Description:
%       Fits the current Part A ARX case on log-transformed effective Rt:
%       d = 0, q = 0, one or more exogenous inputs, and vector-valued
%       nb/nk input orders. The MATLAB arx(...) estimator is called once.
%       Forecasting is handled separately from stored polynomial
%       coefficients.
%
%   Inputs:
%       Rt_hist - Historical effective reproduction-number values.
%       U_hist  - Historical exogenous covariate matrix.
%       na      - Autoregressive output order.
%       nb_vec  - Exogenous input orders.
%       nk_vec  - Exogenous input delays.
%       options - Optional structure. Fields d and q must be zero if given.
%
%   Outputs:
%       model - Structure containing the fitted ARX model and coefficients.
%       timing - Optional diagnostic timing structure.
%
%   See also FORECAST_ARX_CLOSED_LOOP, RECURSIVE_ARX_STEP.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-11

    %% 1. Input Validation
    if nargin < 6 || isempty(options)
        options = struct();
    end
    timing = local_init_timing(nargout);
    if timing.collect_timing
        total_tic = tic;
    end

    na = local_validate_order(na, 'na');
    d = local_option_or_default(options, 'd', 0);
    q = local_option_or_default(options, 'q', 0);
    if d ~= 0 || q ~= 0
        error('ARX:UnsupportedOrder', ...
            'fit_arx_model currently supports the Part A ARX case d = 0 and q = 0.');
    end

    Rt_hist = local_validate_rt_history(Rt_hist);
    U_hist = local_validate_exogenous_history(U_hist, numel(Rt_hist));
    num_inputs = size(U_hist, 2);
    nb_vec = local_validate_order_vector(nb_vec, num_inputs, 'nb_vec');
    nk_vec = local_validate_order_vector(nk_vec, num_inputs, 'nk_vec');
    log_Rt = log(max(Rt_hist, eps));

    %% 2. Fallback Checks
    model = local_base_model(Rt_hist, na, nb_vec, nk_vec);
    num_parameters = na + sum(nb_vec);
    max_lag = max([na, nk_vec + nb_vec - 1]);
    if std(log_Rt) < 1e-8 || numel(log_Rt) <= num_parameters + 1 || ...
            numel(log_Rt) <= max_lag + 1
        model.is_persistence = true;
        timing.used_persistence_fallback = true;
        timing.fallback_identifier = "ARX:InsufficientOrConstantHistory";
        if timing.collect_timing
            timing.fit_arx_model_total = toc(total_tic);
        end
        return;
    end

    %% 3. Model Fitting
    try
        if timing.collect_timing
            iddata_tic = tic;
        end
        fit_data = iddata(log_Rt, U_hist, 1);
        if timing.collect_timing
            timing.iddata_total = timing.iddata_total + toc(iddata_tic);
            timing.iddata_calls = timing.iddata_calls + 1;
            arx_tic = tic;
        end

        sys = arx(fit_data, [na, nb_vec, nk_vec]);
        if timing.collect_timing
            timing.arx_total = timing.arx_total + toc(arx_tic);
            timing.arx_calls = timing.arx_calls + 1;
            extract_tic = tic;
        end

        coefficients = local_extract_arx_coefficients(sys, nb_vec, nk_vec);
        if timing.collect_timing
            timing.extract_arx_coefficients_total = ...
                timing.extract_arx_coefficients_total + toc(extract_tic);
            timing.extract_arx_coefficients_calls = ...
                timing.extract_arx_coefficients_calls + 1;
            residual_tic = tic;
        end

        model.sys = sys;
        model.coefficients = coefficients;
        model.aicc = local_extract_aicc(sys);
        model.residual_std = local_arx_residual_std(coefficients, log_Rt, U_hist);
        if timing.collect_timing
            timing.residual_std_total = timing.residual_std_total + toc(residual_tic);
            timing.fit_arx_model_total = toc(total_tic);
        end
    catch
        model.is_persistence = true;
        model.aicc = inf;
        timing.used_persistence_fallback = true;
        timing.fallback_identifier = "ARX:FitFailed";
        if timing.collect_timing
            timing.fit_arx_model_total = toc(total_tic);
        end
    end
end

function timing = local_init_timing(requested_outputs)
%LOCAL_INIT_TIMING Initialize optional fit diagnostics.
    timing = struct();
    timing.collect_timing = requested_outputs >= 2;
    timing.fit_arx_model_total = 0;
    timing.iddata_total = 0;
    timing.arx_total = 0;
    timing.extract_arx_coefficients_total = 0;
    timing.residual_std_total = 0;
    timing.iddata_calls = 0;
    timing.arx_calls = 0;
    timing.extract_arx_coefficients_calls = 0;
    timing.used_persistence_fallback = false;
    timing.fallback_identifier = "";
end

function model = local_base_model(Rt_hist, na, nb_vec, nk_vec)
%LOCAL_BASE_MODEL Create the common ARX model structure.
    model = struct();
    model.type = "ARX";
    model.na = na;
    model.nb_vec = reshape(double(nb_vec), 1, []);
    model.nk_vec = reshape(double(nk_vec), 1, []);
    model.d = 0;
    model.q = 0;
    model.transform = "log";
    model.sys = [];
    model.coefficients = struct();
    model.aicc = inf;
    model.residual_std = 0;
    model.last_Rt = Rt_hist(end);
    model.is_persistence = false;
end

function value = local_validate_order(value, label)
%LOCAL_VALIDATE_ORDER Validate a positive integer model order.
    value = double(value);
    if ~isscalar(value) || ~isfinite(value) || value < 1 || value ~= floor(value)
        error('ARX:InvalidOrder', '%s must be a positive integer scalar.', label);
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
        error('ARX:InvalidHistory', 'Rt_hist must be a numeric vector.');
    end

    Rt_hist = double(Rt_hist(:));
    if isempty(Rt_hist) || any(~isfinite(Rt_hist)) || any(Rt_hist <= 0)
        error('ARX:InvalidHistory', ...
            'Rt_hist must contain finite positive values.');
    end
end

function U_hist = local_validate_exogenous_history(U_hist, expected_rows)
%LOCAL_VALIDATE_EXOGENOUS_HISTORY Validate historical exogenous inputs.
    if ~isnumeric(U_hist) || isempty(U_hist)
        error('ARX:InvalidExogenousHistory', ...
            'U_hist must be a nonempty numeric matrix.');
    end

    U_hist = double(U_hist);
    if isvector(U_hist)
        U_hist = U_hist(:);
    end

    if size(U_hist, 1) ~= expected_rows || any(~isfinite(U_hist(:)))
        error('ARX:InvalidExogenousHistory', ...
            'U_hist must have one finite row per Rt_hist sample.');
    end
end

function orders = local_validate_order_vector(orders, num_inputs, label)
%LOCAL_VALIDATE_ORDER_VECTOR Validate nb/nk vectors.
    orders = reshape(double(orders), 1, []);
    if isscalar(orders) && num_inputs > 1
        orders = repmat(orders, 1, num_inputs);
    end

    if numel(orders) ~= num_inputs || any(~isfinite(orders)) || ...
            any(orders < 1) || any(orders ~= floor(orders))
        error('ARX:InvalidOrderVector', ...
            '%s must contain one positive integer per exogenous input.', label);
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

function residual_std = local_arx_residual_std(coefficients, log_Rt, U_hist)
%LOCAL_ARX_RESIDUAL_STD Estimate one-step residual scale on the log scale.
    max_lag = max([coefficients.na, coefficients.nk_vec + coefficients.nb_vec - 1]);
    residuals = nan(max(0, numel(log_Rt) - max_lag), 1);

    for t = (max_lag + 1):numel(log_Rt)
        y_pred = local_arx_one_step(coefficients, log_Rt(1:(t - 1)), U_hist(1:(t - 1), :));
        residuals(t - max_lag) = log_Rt(t) - y_pred;
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

function next_log_Rt = local_arx_one_step(coefficients, rolling_log_Rt, rolling_U)
%LOCAL_ARX_ONE_STEP Compute one ARX prediction for residual diagnostics.
    rolling_log_Rt = double(rolling_log_Rt(:));
    rolling_U = double(rolling_U);
    if isvector(rolling_U)
        rolling_U = rolling_U(:);
    end

    num_history = numel(rolling_log_Rt);
    next_log_Rt = 0;
    for lag = 1:coefficients.na
        next_log_Rt = next_log_Rt - ...
            coefficients.a_values(lag) * rolling_log_Rt(num_history + 1 - lag);
    end

    for input_idx = 1:coefficients.num_inputs
        b_values = coefficients.B{input_idx};
        for coeff_idx = 1:coefficients.nb_vec(input_idx)
            input_lag = coefficients.nk_vec(input_idx) + coeff_idx - 1;
            history_idx = num_history + 1 - input_lag;
            next_log_Rt = next_log_Rt + ...
                b_values(coeff_idx) * rolling_U(history_idx, input_idx);
        end
    end
end

function coefficients = local_extract_arx_coefficients(sys, nb_vec, nk_vec)
%LOCAL_EXTRACT_ARX_COEFFICIENTS Extract recursive ARX polynomial coefficients.
%   Extracts A and B polynomials from a fitted MATLAB ARX idpoly model under the
%   convention A(q)y(t) = B(q)u(t) + e(t), storing active B coefficients
%   separately from delay zeros. The returned structure is consumed by
%   recursive_arx_step.
    nb_vec = reshape(double(nb_vec), 1, []);
    nk_vec = reshape(double(nk_vec), 1, []);
    if numel(nb_vec) ~= numel(nk_vec) || isempty(nb_vec)
        error('ARX:InvalidOrderVector', ...
            'nb_vec and nk_vec must have the same nonzero length.');
    end

    num_inputs = numel(nb_vec);
    raw_A = local_numeric_row(sys.A);
    na = numel(raw_A) - 1;
    if na < 1
        error('ARX:InvalidPolynomial', 'The fitted ARX A polynomial is invalid.');
    end

    raw_B = local_raw_b_polynomials(sys.B, num_inputs);
    active_B = cell(1, num_inputs);
    for j = 1:num_inputs
        active_B{j} = local_active_b_values(raw_B{j}, nb_vec(j), nk_vec(j));
    end

    coefficients = struct();
    coefficients.convention = "A(q)y(t) = B(q)u(t) + e(t)";
    coefficients.na = na;
    coefficients.nb_vec = nb_vec;
    coefficients.nk_vec = nk_vec;
    coefficients.num_inputs = num_inputs;
    coefficients.A = raw_A;
    coefficients.a_values = raw_A(2:end);
    coefficients.B_raw = raw_B;
    coefficients.B = active_B;
end

function values = local_numeric_row(values)
%LOCAL_NUMERIC_ROW Convert polynomial values to a numeric row.
    if iscell(values)
        values = values{1};
    end
    values = double(values(:)).';
end

function raw_B = local_raw_b_polynomials(B_property, num_inputs)
%LOCAL_RAW_B_POLYNOMIALS Normalize MATLAB B polynomials to a cell array.
    raw_B = cell(1, num_inputs);

    if iscell(B_property)
        if numel(B_property) < num_inputs
            error('ARX:InvalidPolynomial', ...
                'The fitted ARX B polynomial count is smaller than the input count.');
        end

        for j = 1:num_inputs
            raw_B{j} = double(B_property{j}(:)).';
        end
        return;
    end

    B_property = double(B_property);
    if num_inputs == 1
        raw_B{1} = B_property(:).';
    elseif size(B_property, 1) == num_inputs
        for j = 1:num_inputs
            raw_B{j} = B_property(j, :);
        end
    elseif size(B_property, 2) == num_inputs
        for j = 1:num_inputs
            raw_B{j} = B_property(:, j).';
        end
    else
        error('ARX:InvalidPolynomial', ...
            'The fitted ARX B polynomial dimensions do not match the input count.');
    end
end

function active_values = local_active_b_values(raw_values, nb, nk)
%LOCAL_ACTIVE_B_VALUES Extract active B coefficients for nb and nk.
    raw_values = reshape(double(raw_values), 1, []);
    nb = double(nb);
    nk = double(nk);

    if numel(raw_values) >= nk + nb
        active_values = raw_values((nk + 1):(nk + nb));
    elseif numel(raw_values) == nb
        active_values = raw_values;
    elseif numel(raw_values) > nb
        active_values = raw_values((end - nb + 1):end);
    else
        error('ARX:InvalidPolynomial', ...
            'The fitted ARX B polynomial is too short for nb/nk.');
    end

    if numel(active_values) ~= nb || any(~isfinite(active_values))
        error('ARX:InvalidPolynomial', ...
            'The active ARX B coefficients are invalid.');
    end
end
