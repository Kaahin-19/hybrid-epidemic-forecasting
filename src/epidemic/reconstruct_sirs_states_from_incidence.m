function [S_proxy, I_proxy, R_proxy, incidence_scaled_proxy] = reconstruct_sirs_states_from_incidence(incidence_observed, model_params)

%RECONSTRUCT_SIRS_STATES_FROM_INCIDENCE Reconstruct causal SIRS state proxies.
%
%   Syntax:
%       [S_proxy, I_proxy, R_proxy, incidence_scaled_proxy] = ...
%           reconstruct_sirs_states_from_incidence(incidence_observed, model_params)
%
%   Description:
%       Scales reported daily incidence to the configured effective SIRS
%       population and reconstructs deterministic susceptible, infectious, and
%       recovered state proxies using daily recovery and immunity-loss
%       transitions. Each output row is the end-of-day state after processing
%       the incidence reported for that row.
%
%   Inputs:
%       incidence_observed - T-by-1 nonnegative daily incidence.
%       model_params       - State-reconstruction parameters.
%
%   Outputs:
%       S_proxy                - End-of-day susceptible proxy.
%       I_proxy                - End-of-day infectious proxy.
%       R_proxy                - End-of-day recovered proxy.
%       incidence_scaled_proxy - Incidence on the effective-population scale.
%
%   See also PARTC_01_PREPARE_DATA.
%
% A. M. Kaahin 2026-07-28
% Modified: 2026-08-23

%% 1. Parameter Domains
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

initial_state = [model_params.initial_susceptible; model_params.initial_infectious; model_params.initial_recovered];

if any(initial_state < 0)
    error('EPIDEMIC:InvalidProxyInitialState', 'Initial SIRS proxy compartments must be nonnegative.');
end

if abs(sum(initial_state) - model_params.effective_population) > model_params.conservation_tolerance
    error('EPIDEMIC:InvalidProxyInitialState', 'Initial SIRS proxy compartments must conserve the effective population.');
end

if initial_state(1) <= model_params.min_susceptible
    error('EPIDEMIC:ProxySusceptibleBelowThreshold', 'Initial susceptible proxy is at or below min_susceptible.');
end

%% 2. Causal State Reconstruction
incidence_scaled_proxy = incidence_observed / (model_params.reference_population * model_params.reporting_fraction) * model_params.effective_population;

observation_count = numel(incidence_observed);

S_proxy = zeros(observation_count, 1);
I_proxy = zeros(observation_count, 1);
R_proxy = zeros(observation_count, 1);

current_state = initial_state;

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

    if abs(sum(next_state) - model_params.effective_population) > model_params.conservation_tolerance
        error('EPIDEMIC:ProxyConservationFailure', 'SIRS proxy population conservation failed at row %d.', time_index);
    end

    S_proxy(time_index) = next_state(1);
    I_proxy(time_index) = next_state(2);
    R_proxy(time_index) = next_state(3);

    current_state = next_state;
end

end