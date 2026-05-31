function coefficients = extract_arx_coefficients(sys, nb_vec, nk_vec)
%EXTRACT_ARX_COEFFICIENTS Extract recursive ARX polynomial coefficients.
%
%   Syntax:
%       coefficients = extract_arx_coefficients(sys, nb_vec, nk_vec)
%
%   Description:
%       Extracts A and B polynomial coefficients from a fitted MATLAB ARX
%       idpoly model. The convention is:
%
%           A(q)y(t) = B(q)u(t) + e(t)
%
%       which expands to:
%
%           y(t) = -a1*y(t-1) - ... + b1*u(t-nk) + ...
%
%       The returned structure stores active B coefficients separately from
%       any delay zeros in the raw MATLAB polynomial.
%
%   Inputs:
%       sys    - Fitted MATLAB ARX/idpoly model.
%       nb_vec - Exogenous input orders.
%       nk_vec - Exogenous input delays.
%
%   Outputs:
%       coefficients - Structure usable by recursive_arx_step.
%
%   See also FIT_ARX_MODEL, RECURSIVE_ARX_STEP.
%
% A. M. Kaahin 2026-05-31

    %% 1. Input Validation
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

    %% 2. B Polynomial Extraction
    raw_B = local_raw_b_polynomials(sys.B, num_inputs);
    active_B = cell(1, num_inputs);
    for j = 1:num_inputs
        active_B{j} = local_active_b_values(raw_B{j}, nb_vec(j), nk_vec(j));
    end

    %% 3. Output Assembly
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
