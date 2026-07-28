function [S_proxy, I_proxy, R_proxy, incidence_scaled_proxy, diagnostics] = ...
    reconstruct_sirs_states_from_incidence(incidence_observed, model_params)
%RECONSTRUCT_SIRS_STATES_FROM_INCIDENCE Reconstruct causal SIRS state proxies.
%
%   Syntax:
%       [S_proxy, I_proxy, R_proxy, incidence_scaled_proxy, diagnostics] = ...
%           reconstruct_sirs_states_from_incidence(incidence_observed, ...
%           model_params)
%
%   Description:
%       Converts reported daily incidence to an infection-flow proxy on a
%       configured effective SIRS population scale, then applies deterministic
%       daily SIRS recovery and immunity-loss transitions. Each output row is
%       the end-of-day state after processing the incidence in the matching
%       input row. The outputs are model-derived reported-case proxies, not
%       observed or true biological compartments.
%
%   Inputs:
%       incidence_observed - T-by-1 real, finite, nonnegative reported daily
%                            incidence column vector.
%       model_params       - Scalar structure with fields:
%           .reference_population    - Positive reported-case denominator.
%           .reporting_fraction      - Constant value in (0, 1].
%           .effective_population    - Positive numerical SIRS population.
%           .gamma                   - Daily recovery rate in (0, 1].
%           .xi                      - Daily immunity-loss rate in [0, 1].
%           .initial_susceptible     - Susceptible state before the first row.
%           .initial_infectious      - Infectious state before the first row.
%           .initial_recovered       - Recovered state before the first row.
%           .min_susceptible         - Positive susceptible-domain threshold.
%           .conservation_tolerance  - Positive absolute population tolerance.
%
%   Outputs:
%       S_proxy                  - T-by-1 end-of-day susceptible proxy.
%       I_proxy                  - T-by-1 end-of-day infectious proxy.
%       R_proxy                  - T-by-1 end-of-day recovered proxy.
%       incidence_scaled_proxy   - T-by-1 reported-case infection-flow proxy
%                                  on the effective-population scale.
%       diagnostics              - Compact structure describing the method,
%                                  initial/final states, state extrema,
%                                  conservation error, and total scaled flow.
%
%   See also PARTC_01_PREPARE_DATA, PARTC_CONFIG, SIRS_INIT, SIRS_STEP.
%
% A. M. Kaahin 2026-07-28

    %% 1. Input Validation
    if ~isnumeric(incidence_observed) || ~isreal(incidence_observed) || ...
            ~iscolumn(incidence_observed) || isempty(incidence_observed)
        error('EPIDEMIC:InvalidProxyIncidence', ...
            'incidence_observed must be a nonempty real numeric column vector.');
    end

    if any(~isfinite(incidence_observed)) || any(incidence_observed < 0)
        error('EPIDEMIC:InvalidProxyIncidence', ...
            'incidence_observed must be finite and nonnegative.');
    end

    if ~isstruct(model_params) || ~isscalar(model_params)
        error('EPIDEMIC:InvalidProxyModelParameters', ...
            'model_params must be a scalar structure.');
    end

    required_fields = {
        'reference_population'
        'reporting_fraction'
        'effective_population'
        'gamma'
        'xi'
        'initial_susceptible'
        'initial_infectious'
        'initial_recovered'
        'min_susceptible'
        'conservation_tolerance'
        };

    actual_fields = fieldnames(model_params);
    missing_fields = required_fields(~isfield(model_params, required_fields));
    unexpected_fields = actual_fields(~ismember(actual_fields, required_fields));

    if ~isempty(missing_fields) || ~isempty(unexpected_fields)
        error('EPIDEMIC:InvalidProxyModelParameters', ...
            'model_params must contain exactly the documented state-reconstruction fields.');
    end

    scalar_fields = required_fields;
    for field_index = 1:numel(scalar_fields)
        field_name = scalar_fields{field_index};
        value = model_params.(field_name);

        if ~isnumeric(value) || ~isreal(value) || ...
                ~isscalar(value) || ~isfinite(value)
            error('EPIDEMIC:InvalidProxyModelParameters', ...
                'model_params.%s must be a real finite numeric scalar.', ...
                field_name);
        end
    end

    if model_params.reference_population <= 0
        error('EPIDEMIC:InvalidProxyReferencePopulation', ...
            'reference_population must be strictly positive.');
    end

    if model_params.reporting_fraction <= 0 || ...
            model_params.reporting_fraction > 1
        error('EPIDEMIC:InvalidProxyReportingFraction', ...
            'reporting_fraction must lie in (0, 1].');
    end

    if model_params.effective_population <= 0
        error('EPIDEMIC:InvalidProxyEffectivePopulation', ...
            'effective_population must be strictly positive.');
    end

    if model_params.gamma <= 0 || model_params.gamma > 1
        error('EPIDEMIC:InvalidProxyRecoveryRate', ...
            'gamma must lie in (0, 1].');
    end

    if model_params.xi < 0 || model_params.xi > 1
        error('EPIDEMIC:InvalidProxyImmunityLossRate', ...
            'xi must lie in [0, 1].');
    end

    initial_state = [
        model_params.initial_susceptible
        model_params.initial_infectious
        model_params.initial_recovered
        ];

    if any(initial_state < 0)
        error('EPIDEMIC:InvalidProxyInitialState', ...
            'Initial SIRS proxy compartments must be nonnegative.');
    end

    if model_params.min_susceptible <= 0 || ...
            model_params.min_susceptible >= model_params.effective_population
        error('EPIDEMIC:InvalidProxySusceptibleThreshold', ...
            'min_susceptible must be positive and smaller than effective_population.');
    end

    if model_params.conservation_tolerance <= 0
        error('EPIDEMIC:InvalidProxyConservationTolerance', ...
            'conservation_tolerance must be strictly positive.');
    end

    initial_conservation_error = abs( ...
        sum(initial_state) - model_params.effective_population);
    if initial_conservation_error > model_params.conservation_tolerance
        error('EPIDEMIC:InvalidProxyInitialState', ...
            'Initial SIRS proxy compartments do not conserve effective_population within tolerance.');
    end

    if initial_state(1) <= model_params.min_susceptible
        error('EPIDEMIC:ProxySusceptibleBelowThreshold', ...
            'Initial susceptible proxy is at or below min_susceptible.');
    end

    incidence_denominator = model_params.reference_population * ...
        model_params.reporting_fraction;
    if ~isfinite(incidence_denominator) || incidence_denominator <= 0
        error('EPIDEMIC:InvalidProxyIncidenceScale', ...
            'The reported-case incidence denominator must be finite and positive.');
    end

    %% 2. Causal State Reconstruction
    incidence_fraction_proxy = incidence_observed ./ incidence_denominator;
    incidence_scaled_proxy = incidence_fraction_proxy .* ...
        model_params.effective_population;

    observation_count = numel(incidence_observed);
    S_proxy = zeros(observation_count, 1);
    I_proxy = zeros(observation_count, 1);
    R_proxy = zeros(observation_count, 1);

    current_state = initial_state;
    maximum_conservation_error = initial_conservation_error;

    for time_index = 1:observation_count
        new_infections = incidence_scaled_proxy(time_index);

        if ~isfinite(new_infections) || new_infections < 0
            error('EPIDEMIC:InvalidScaledProxyIncidence', ...
                'Scaled incidence must be finite and nonnegative at row %d.', ...
                time_index);
        end

        recoveries = model_params.gamma * current_state(2);
        waning_immunity = model_params.xi * current_state(3);

        next_state = [
            current_state(1) - new_infections + waning_immunity
            current_state(2) + new_infections - recoveries
            current_state(3) + recoveries - waning_immunity
            ];

        if any(~isfinite(next_state))
            error('EPIDEMIC:InvalidProxyState', ...
                'SIRS proxy recursion produced a nonfinite state at row %d.', ...
                time_index);
        end

        if any(next_state < -model_params.conservation_tolerance)
            error('EPIDEMIC:NegativeProxyState', ...
                'SIRS proxy recursion produced a negative compartment beyond tolerance at row %d.', ...
                time_index);
        end

        if any(next_state < 0)
            error('EPIDEMIC:NegativeProxyState', ...
                'SIRS proxy recursion produced a negative stored compartment at row %d.', ...
                time_index);
        end

        if next_state(1) <= model_params.min_susceptible
            error('EPIDEMIC:ProxySusceptibleBelowThreshold', ...
                'Susceptible proxy %.6g is at or below threshold %.6g at row %d.', ...
                next_state(1), model_params.min_susceptible, time_index);
        end

        conservation_error = abs( ...
            sum(next_state) - model_params.effective_population);
        if conservation_error > model_params.conservation_tolerance
            error('EPIDEMIC:ProxyConservationFailure', ...
                'SIRS proxy population conservation failed at row %d.', ...
                time_index);
        end

        S_proxy(time_index) = next_state(1);
        I_proxy(time_index) = next_state(2);
        R_proxy(time_index) = next_state(3);
        current_state = next_state;
        maximum_conservation_error = max( ...
            maximum_conservation_error, conservation_error);
    end

    %% 3. Diagnostics
    diagnostics = struct();
    diagnostics.method = "reported_case_sirs_proxy";
    diagnostics.observation_count = observation_count;
    diagnostics.reference_population = model_params.reference_population;
    diagnostics.reporting_fraction = model_params.reporting_fraction;
    diagnostics.effective_population = model_params.effective_population;
    diagnostics.initial_state = initial_state;
    diagnostics.final_state = current_state;
    diagnostics.maximum_conservation_error = maximum_conservation_error;
    diagnostics.minimum_susceptible = min(S_proxy);
    diagnostics.maximum_infectious = max(I_proxy);
    diagnostics.total_scaled_incidence = sum(incidence_scaled_proxy);
end
