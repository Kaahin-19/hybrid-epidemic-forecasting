function Rt = rt_sigmoid(t, p)
%RT_SIGMOID Generate a sigmoid step reproduction number signal.
%
%   Syntax:
%       Rt = rt_sigmoid(t, p)
%
%   Description:
%       Generates a smooth sigmoid transition from a high transmission 
%       baseline to a lower level, typically used to model the impact 
%       of a policy intervention (e.g., lockdown).
%
%   Inputs:
%       t - Time vector [days].
%       p - Parameter structure containing:
%           .high - Initial Rt level.
%           .low  - Final Rt level.
%           .t0   - Inflection point of the curve (day).
%           .k    - Steepness of the transition.
%
%   Outputs:
%       Rt - Vector of Rt values evaluated at t.

% A. M. Kaahin 2026-02-19

    Rt = p.high + (p.low - p.high) ./ (1 + exp(-p.k * (t - p.t0)));
end