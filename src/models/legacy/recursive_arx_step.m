function next_log_Rt = recursive_arx_step(coefficients, rolling_log_Rt, rolling_U)
%RECURSIVE_ARX_STEP Compute one recursive ARX prediction from coefficients.
%
%   Syntax:
%       next_log_Rt = recursive_arx_step(coefficients, rolling_log_Rt, rolling_U)
%
%   Description:
%       Computes one ARX prediction directly from stored polynomial
%       coefficients and rolling histories. This function does not construct
%       iddata, does not call MATLAB forecast routines, and does not use any
%       System Identification object.
%
%   Inputs:
%       coefficients   - ARX coefficient structure produced by fit_arx_model.
%       rolling_log_Rt - Historical log-Rt values available up to now.
%       rolling_U      - Historical exogenous values available up to now.
%
%   Outputs:
%       next_log_Rt - One-step recursive ARX prediction on the log scale.
%
%   See also FIT_ARX_MODEL, FORECAST_ARX_CLOSED_LOOP.
%
% A. M. Kaahin 2026-05-31

    %% 1. Input Validation
    local_validate_coefficients(coefficients);
    rolling_log_Rt = double(rolling_log_Rt(:));
    rolling_U = double(rolling_U);
    if isvector(rolling_U)
        rolling_U = rolling_U(:);
    end

    num_history = numel(rolling_log_Rt);
    if size(rolling_U, 1) ~= num_history
        error('ARX:InvalidHistory', ...
            'rolling_log_Rt and rolling_U must have matching history lengths.');
    end

    if size(rolling_U, 2) ~= coefficients.num_inputs || ...
            any(~isfinite(rolling_log_Rt)) || any(~isfinite(rolling_U(:)))
        error('ARX:InvalidHistory', ...
            'Rolling histories must be finite and match the coefficient input count.');
    end

    required_log_history = coefficients.na;
    required_u_history = max(coefficients.nk_vec + coefficients.nb_vec - 1);
    if num_history < max(required_log_history, required_u_history)
        error('ARX:InsufficientHistory', ...
            'Not enough rolling history for the requested ARX recursion.');
    end

    %% 2. Recursive Prediction
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
            if history_idx < 1 || history_idx > size(rolling_U, 1)
                error('ARX:InsufficientHistory', ...
                    'Not enough exogenous history for ARX input %d.', input_idx);
            end

            next_log_Rt = next_log_Rt + ...
                b_values(coeff_idx) * rolling_U(history_idx, input_idx);
        end
    end

    if ~isscalar(next_log_Rt) || ~isfinite(next_log_Rt)
        error('ARX:InvalidPrediction', 'The recursive ARX prediction is invalid.');
    end
end

function local_validate_coefficients(coefficients)
%LOCAL_VALIDATE_COEFFICIENTS Verify coefficient structure consistency.
    required_fields = {'na', 'nb_vec', 'nk_vec', 'num_inputs', 'a_values', 'B'};
    for i = 1:numel(required_fields)
        if ~isfield(coefficients, required_fields{i})
            error('ARX:InvalidCoefficients', ...
                'Missing ARX coefficient field: %s.', required_fields{i});
        end
    end

    if numel(coefficients.a_values) ~= coefficients.na || ...
            numel(coefficients.nb_vec) ~= coefficients.num_inputs || ...
            numel(coefficients.nk_vec) ~= coefficients.num_inputs || ...
            numel(coefficients.B) ~= coefficients.num_inputs
        error('ARX:InvalidCoefficients', ...
            'ARX coefficient dimensions are inconsistent.');
    end

    for j = 1:coefficients.num_inputs
        if numel(coefficients.B{j}) ~= coefficients.nb_vec(j)
            error('ARX:InvalidCoefficients', ...
                'ARX B coefficient dimensions are inconsistent for input %d.', j);
        end
    end
end
