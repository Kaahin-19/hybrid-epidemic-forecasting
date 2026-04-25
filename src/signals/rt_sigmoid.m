function Rt = rt_sigmoid(t, p)
%RT_SIGMOID Generate a sigmoid step transmission-potential signal.
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
%           .high - Initial transmission-potential level.
%           .low  - Final transmission-potential level.
%           .t0   - Inflection point of the curve [days].
%           .k    - Steepness of the transition.
%
%   Outputs:
%       Rt - Vector of transmission-potential values evaluated at t.
%
%   See also PARTA_CONFIG, RT_MULTI_WAVE, RT_SEASONAL.

% A. M. Kaahin 2026-02-19
% Modified: 2026-03-28

    Rt = p.high + (p.low - p.high) ./ (1 + exp(-p.k * (t - p.t0)));
end
