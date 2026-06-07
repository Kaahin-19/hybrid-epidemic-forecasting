function [next_state, stepper] = advance_sirs_stepper(stepper, current_state, Rt_next)
%ADVANCE_SIRS_STEPPER Advance one day with a reusable URDME SIRS stepper.
%
%   Syntax:
%       [next_state, stepper] = advance_sirs_stepper(stepper, current_state, Rt_next)
%
%   Description:
%       Advances one effective-Rt-driven SIRS interval using a stepper
%       prepared by initialize_sirs_stepper. The parsed URDME model is
%       reused; this function only updates the current state, time-dependent
%       beta driver, seed, and solve flags before calling URDME.
%
%   Inputs:
%       stepper       - Structure returned by initialize_sirs_stepper.
%       current_state - Current [S, I, R] state.
%       Rt_next       - Effective reproduction number for the step.
%
%   Outputs:
%       next_state - Advanced row-vector [S, I, R] state.
%       stepper    - Updated stepper with incremented call_count.
%
%   See also INITIALIZE_SIRS_STEPPER, FORECAST_ARX_CLOSED_LOOP.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-05

%% 1. Prepare Inputs
params = stepper.params;
state0 = local_prepare_current_state(current_state, params.pop_size);

%% 2. State-Dependent Driver Update
beta_value = local_beta_from_effective_rt(Rt_next, state0(1), params);
umod = stepper.umod_template;
num_species = size(umod.N, 1);

umod.u0 = zeros(num_species, 1);
umod.u0(1:3) = reshape(state0, 3, 1);
umod.ldata_time = reshape( ...
    repmat(beta_value, 1, numel(umod.tspan)), ...
    [1, numel(umod.vol), numel(umod.tspan)]);

step_seed = stepper.seed + stepper.call_count;
umod.solve = 1;
umod.parse = 0;
umod.compile = 0;
umod.seed = step_seed;
umod.U = [];

%% 3. One-Day URDME Solve
caller_rng_state = rng;
rng_cleanup = onCleanup(@() rng(caller_rng_state));
rng(step_seed);

umod = urdme(umod);
next_state = local_prepare_output_state(umod.U(:, end), params.pop_size);
next_state = reshape(next_state, 1, []);

stepper.call_count = stepper.call_count + 1;
stepper.last_beta = beta_value;
stepper.last_seed = step_seed;
stepper.last_state = next_state;

clear rng_cleanup
end

function state = local_prepare_current_state(current_state, pop_size)
%LOCAL_PREPARE_CURRENT_STATE Prepare a current [S, I, R] state.
state = reshape(double(current_state), 1, []);
tolerance = max(1e-6 * pop_size, 1e-6);

if numel(state) ~= 3 || any(~isfinite(state))
    error('EPIDEMIC:InvalidState', 'current_state must be finite [S, I, R].');
end

state(abs(state) < tolerance) = 0;

if any(state < 0)
    error('EPIDEMIC:InvalidState', 'current_state must be nonnegative.');
end

total = sum(state);
if abs(total - pop_size) > tolerance
    error('EPIDEMIC:InvalidState', ...
        'sum(current_state) must be approximately model_params.pop_size.');
end

if state(1) <= 0
    error('EPIDEMIC:InvalidState', ...
        'current susceptible state must be positive.');
end

state = state * (pop_size / total);
end

function beta = local_beta_from_effective_rt(Rt_value, susceptible, params)
%LOCAL_BETA_FROM_EFFECTIVE_RT Compute beta from effective Rt and current S.
beta = Rt_value * params.gamma * params.pop_size / susceptible;
if ~isfinite(beta) || beta <= 0
    error('EPIDEMIC:InvalidBeta', ...
        'Computed internal transmission rate must be finite and positive.');
end
end

function state = local_prepare_output_state(raw_state, pop_size)
%LOCAL_PREPARE_OUTPUT_STATE Prepare the simulated [S, I, R] output state.
state = reshape(double(raw_state), [], 1);
if numel(state) ~= 3 || any(~isfinite(state))
    error('EPIDEMIC:InvalidState', ...
        'SIRS state must contain three finite compartment values.');
end

tolerance = max(1e-7 * pop_size, 1e-9);
state(abs(state) < tolerance) = 0;
state = max(state, 0);
state(1) = max(state(1), max(1, 1e-6 * pop_size));

total = sum(state);
if total <= 0
    error('EPIDEMIC:InvalidState', ...
        'SIRS simulation produced an empty population state.');
end

state = state * (pop_size / total);
end