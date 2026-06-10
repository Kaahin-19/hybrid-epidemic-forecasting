function U_next = extract_exogenous_from_state(state, exo_mode, pop_size)
%EXTRACT_EXOGENOUS_FROM_STATE Convert epidemic state to ARX covariates.
%
%   Syntax:
%       U_next = extract_exogenous_from_state(state, exo_mode, pop_size)
%
%   Description:
%       Extracts the Part A ARX exogenous covariates from a current epidemic
%       state using the same normalized S/I convention as the existing
%       model-selection pipeline.
%
%   Inputs:
%       state    - Current [S, I, R] state.
%       exo_mode - Exogenous mode: S, I, or Both.
%       pop_size - Total population size.
%
%   Outputs:
%       U_next - Row vector of normalized exogenous covariates.
%
%   See also FORECAST_ARX_CLOSED_LOOP, ADVANCE_SIRS_STEPPER.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-11

    %% 1. Input Validation
    state = reshape(double(state), 1, []);
    pop_size = double(pop_size);
    if numel(state) ~= 3 || any(~isfinite(state)) || ...
            ~isscalar(pop_size) || ~isfinite(pop_size) || pop_size <= 0
        error('ARX:InvalidEpidemicState', ...
            'state must be finite [S, I, R] and pop_size must be positive.');
    end

    %% 2. Covariate Extraction
    exo_mode = string(exo_mode);
    switch exo_mode
        case "S"
            U_next = state(1) / pop_size;
        case "I"
            U_next = state(2) / pop_size;
        case "Both"
            U_next = state(1:2) / pop_size;
        otherwise
            error('ARX:InvalidExogenousMode', ...
                'exo_mode must be S, I, or Both for ARX closed-loop forecasts.');
    end

    U_next = reshape(double(U_next), 1, []);
end
