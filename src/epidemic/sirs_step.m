function [next_state, stepper] = sirs_step(stepper, current_state, Rt_next)
%SIRS_STEP Advance one reusable SIRS stepper by one day.
%
%   Description:
%       Advances the prepared URDME SIRS model by one effective-Rt-driven
%       one-day interval. The function updates the current state, Rt-derived
%       transmission rate, execution seed, and URDME solve flags before
%       returning the next SIRS state.
%
%   Inputs:
%       stepper       - Reusable SIRS stepper returned by sirs_init.
%       current_state - Current [S, I, R] state.
%       Rt_next       - Effective reproduction number for the next step.
%
%   Outputs:
%       next_state - Advanced [S, I, R] state.
%       stepper    - Updated stepper with incremented call count.
%
%   See also SIRS_INIT.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-28

%% 1. Prepare Inputs
params = stepper.model_params;

S_current = current_state(1);

%% 2. Rt-to-Beta Domain Guard
if S_current <= params.min_susceptible
    error('EPIDEMIC:SusceptibleBelowThreshold', 'Susceptible state %.6g is at or below the configured minimum susceptible threshold %.6g.', S_current, params.min_susceptible);
end

beta_value = Rt_next * params.gamma * params.pop_size / S_current;

if ~isfinite(beta_value) || beta_value <= 0
    error('EPIDEMIC:InvalidBeta', 'Computed internal transmission rate must be finite and positive.');
end

%% 3. Configure URDME Step
umod        = stepper.umod_template;
num_species = size(umod.N, 1);

umod.u0      = zeros(num_species, 1);
umod.u0(1:3) = current_state;
beta_driver  = repmat(beta_value, 1, numel(umod.tspan));
umod.ldata_time = reshape(beta_driver, [1, numel(umod.vol), numel(umod.tspan)]);

umod.solve   = 1;
umod.parse   = 0;
umod.compile = 0;
step_seed    = stepper.seed + stepper.call_count;
umod.seed    = step_seed;
umod.U       = [];

%% 4. Advance State
umod = urdme(umod);

next_state = umod.U(1:3, end);

if any(~isfinite(next_state))
    error('EPIDEMIC:InvalidState', 'URDME produced a non-finite SIRS state.');
end

%% 5. Update Stepper
stepper.call_count = stepper.call_count + 1;
end