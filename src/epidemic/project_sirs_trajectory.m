function projected_states = project_sirs_trajectory(stepper, initial_state, Rt_drivers)
%PROJECT_SIRS_TRAJECTORY Propagate a prepared SIRS stepper along an Rt trajectory.
%
%   Syntax:
%       projected_states = project_sirs_trajectory(stepper, initial_state, Rt_drivers)
%
%   Description:
%       Advances a prepared SIRS stepper from an initial compartment state
%       using one effective-reproduction-number driver per transition.
%
%   Inputs:
%       stepper       - Prepared reusable SIRS stepper from sirs_init.
%       initial_state - 3-by-1 initial [S; I; R] compartment state.
%       Rt_drivers    - H-by-1 effective-Rt transition drivers.
%
%   Outputs:
%       projected_states - H-by-3 propagated states with columns [S, I, R].
%
%   See also SIRS_INIT, SIRS_STEP.
%
% A. M. Kaahin 2026-08-13

projected_states = zeros(numel(Rt_drivers), 3);
state = initial_state;

for h = 1:numel(Rt_drivers)
    [state, stepper] = sirs_step(stepper, state, Rt_drivers(h));
    projected_states(h, :) = state.';
end
end
