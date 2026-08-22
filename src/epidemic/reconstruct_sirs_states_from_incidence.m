function [S_proxy, I_proxy, R_proxy, incidence_scaled_proxy, diagnostics] = ...
    reconstruct_sirs_states_from_incidence(incidence_observed, model_params)
%RECONSTRUCT_SIRS_STATES_FROM_INCIDENCE Reconstruct causal SIRS state proxies.
%
%   Description:
%       Scales reported daily incidence to the configured effective SIRS
%       population and reconstructs deterministic susceptible, infectious, and
%       recovered state proxies using daily recovery and immunity-loss
%       transitions. Each output row is the end-of-day state after processing
%       the incidence reported for that row.
%
%   Inputs:
%       incidence_observed - T-by-1 finite, nonnegative daily incidence.
%       model_params       - State-reconstruction parameters containing:
%           .reference_population
%           .reporting_fraction
%           .effective_population
%           .gamma
%           .xi
%           .initial_susceptible
%           .initial_infectious
%           .initial_recovered
%           .min_susceptible
%           .conservation_tolerance
%
%   Outputs:
%       S_proxy                - End-of-day susceptible proxy.
%       I_proxy                - End-of-day infectious proxy.
%       R_proxy                - End-of-day recovered proxy.
%       incidence_scaled_proxy - Incidence on the effective-population scale.
%       diagnostics            - Reconstruction diagnostics.
%
%   See also PARTC_01_PREPARE_DATA, PARTC_CONFIG.
%
% A. M. Kaahin 2026-07-28
% Modified: 2026-08-22

%% 1. Input and Parameter Domains
if isempty(incidence_observed) || ~iscolumn(incidence_observed) || ...
        ~isreal(incidence_observed) || any(~isfinite(incidence_observed)) || ...
        any(incidence_observed < 0)
    error('EPIDEMIC:InvalidProxyIncidence', 'incidence_observed must be a nonempty, finite, nonnegative real column vector.');
end

parameter_values = [
    model_params.reference_population
    model_params.reporting_fraction
    model_params.effective_population
    model_params.gamma
    model_params.xi
    model_params.initial_susceptible
    model_params.initial_infectious
    model_params.initial_recovered
    model_params.min_susceptible
    model_params.conservation_tolerance
    ];

if ~isreal(parameter_values) || any(~isfinite(parameter_values))
    error('EPIDEMIC:InvalidProxyModelParameters', 'State-reconstruction parameters must be finite and real.');
end

if model_params.reference_population <= 0 || model_params.effective_population <= 0
    error('EPIDEMIC:InvalidProxyPopulation', 'Reference and effective populations must be positive.');
end

if model_params.reporting_fraction <= 0 || model_params.reporting_fraction > 1
    error('EPIDEMIC:InvalidProxyReportingFraction', 'reporting_fraction must lie in (0, 1].');
end

if model_params.gamma <= 0 || model_params.gamma > 1
    error('EPIDEMIC:InvalidProxyRecoveryRate', 'gamma must lie in (0, 1].');
end

if model_params.xi < 0 || model_params.xi > 1
    error('EPIDEMIC:InvalidProxyImmunityLossRate', 'xi must lie in [0, 1].');
end

if model_params.min_susceptible <= 0 || model_params.min_susceptible >= model_params.effective_population
    error('EPIDEMIC:InvalidProxySusceptibleThreshold', 'min_susceptible must be positive and smaller than effective_population.');
end

if model_params.conservation_tolerance <= 0
    error('EPIDEMIC:InvalidProxyConservationTolerance', 'conservation_tolerance must be positive.');
end

initial_state = [
    model_params.initial_susceptible
    model_params.initial_infectious
    model_params.initial_recovered
    ];

if any(initial_state < 0)
    error('EPIDEMIC:InvalidProxyInitialState', 'Initial SIRS proxy compartments must be nonnegative.');
end

initial_conservation_error = abs(sum(initial_state) - model_params.effective_population);

if initial_conservation_error > model_params.conservation_tolerance
    error('EPIDEMIC:InvalidProxyInitialState', 'Initial SIRS proxy compartments must conserve the effective population.');
end

if initial_state(1) <= model_params.min_susceptible
    error('EPIDEMIC:ProxySusceptibleBelowThreshold', 'Initial susceptible proxy is at or below min_susceptible.');
end

%% 2. Causal State Reconstruction
incidence_scaled_proxy = incidence_observed ./ ...
    (model_params.reference_population * model_params.reporting_fraction) .* ...
    model_params.effective_population;

if any(~isfinite(incidence_scaled_proxy))
    error('EPIDEMIC:InvalidScaledProxyIncidence', 'Scaled incidence must remain finite.');
end

observation_count = numel(incidence_observed);

S_proxy = zeros(observation_count, 1);
I_proxy = zeros(observation_count, 1);
R_proxy = zeros(observation_count, 1);

current_state = initial_state;
maximum_conservation_error = initial_conservation_error;

for time_index = 1:observation_count
    new_infections = incidence_scaled_proxy(time_index);
    recoveries = model_params.gamma * current_state(2);
    waning_immunity = model_params.xi * current_state(3);

    next_state = [
        current_state(1) - new_infections + waning_immunity
        current_state(2) + new_infections - recoveries
        current_state(3) + recoveries - waning_immunity
        ];

    if any(~isfinite(next_state))
        error('EPIDEMIC:InvalidProxyState', 'SIRS proxy recursion produced a nonfinite state at row %d.', time_index);
    end

    if any(next_state < 0)
        error('EPIDEMIC:NegativeProxyState', 'SIRS proxy recursion produced a negative compartment at row %d.', time_index);
    end

    if next_state(1) <= model_params.min_susceptible
        error('EPIDEMIC:ProxySusceptibleBelowThreshold', 'Susceptible proxy %.6g is at or below threshold %.6g at row %d.', next_state(1), model_params.min_susceptible, time_index);
    end

    conservation_error = abs(sum(next_state) - model_params.effective_population);

    if conservation_error > model_params.conservation_tolerance
        error('EPIDEMIC:ProxyConservationFailure', 'SIRS proxy population conservation failed at row %d.', time_index);
    end

    S_proxy(time_index) = next_state(1);
    I_proxy(time_index) = next_state(2);
    R_proxy(time_index) = next_state(3);

    current_state = next_state;
    maximum_conservation_error = max(maximum_conservation_error, conservation_error);
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