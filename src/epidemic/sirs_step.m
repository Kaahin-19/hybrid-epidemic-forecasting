function [next_state, stepper] = sirs_step(stepper, current_state, Rt_next)
%SIRS_STEP Advance one day with a reusable URDME SIRS stepper.
%
%   Syntax:
%       [next_state, stepper] = sirs_step(stepper, current_state, Rt_next)
%
%   Description:
%       Advances one effective-Rt-driven SIRS interval using a stepper
%       prepared by sirs_init. The parsed URDME model is reused; this
%       function only updates the current state, time-dependent beta driver,
%       seed, and solve flags before calling URDME.
%
%   Inputs:
%       stepper       - Structure returned by sirs_init.
%       current_state - Current [S, I, R] state (row or column vector).
%       Rt_next       - Effective reproduction number for the step.
%
%   Outputs:
%       next_state - Advanced row-vector [S, I, R] state.
%       stepper    - Updated stepper with incremented call_count.
%
%   See also SIRS_INIT.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-16

params = stepper.model_params;

if numel(current_state) ~= 3
    error('EPIDEMIC:InvalidState', 'current_state must contain exactly [S, I, R].');
end

if current_state(1) <= 0
    error('EPIDEMIC:InvalidState', 'Susceptible state must be positive.');
end

beta_value = Rt_next * params.gamma * params.pop_size / current_state(1);

if ~isfinite(beta_value) || beta_value <= 0
    error('EPIDEMIC:InvalidBeta', ...
        'Computed internal transmission rate must be finite and positive.');
end

umod        = stepper.umod_template;
num_species = size(umod.N, 1);

umod.u0      = zeros(num_species, 1);
umod.u0(1:3) = reshape(current_state, 3, 1);
beta_driver  = repmat(beta_value, 1, numel(umod.tspan));
umod.ldata_time = reshape(beta_driver, [1, numel(umod.vol), numel(umod.tspan)]);

step_seed    = stepper.seed + stepper.call_count;
umod.solve   = 1;
umod.parse   = 0;
umod.compile = 0;
umod.seed    = step_seed;
umod.U       = [];

umod = urdme(umod);

next_state = reshape(umod.U(1:3, end), 1, []);

if any(~isfinite(next_state))
    error('EPIDEMIC:InvalidState', 'URDME produced a non-finite SIRS state.');
end

stepper.call_count = stepper.call_count + 1;
end
