function Rt = rt_sigmoid(t, p)
%RT_SIGMOID Compatibility wrapper for the sigmoid Rt signal.
%
%   Syntax:
%       Rt = rt_sigmoid(t, p)
%
%   Description:
%       Delegates to generate_rt_signal. This wrapper is retained
%       temporarily for scenario configurations and older scripts that still
%       reference @rt_sigmoid.
%
%   Inputs:
%       t - Time vector [days].
%       p - Parameter structure containing:
%           .high - Initial effective reproduction-number level.
%           .low  - Final effective reproduction-number level.
%           .t0   - Inflection point of the curve [days].
%           .k    - Steepness of the transition.
%
%   Outputs:
%       Rt - Vector of effective reproduction-number values evaluated at t.
%
%   See also GENERATE_RT_SIGNAL, PARTA_CONFIG.

% A. M. Kaahin 2026-02-19
% Modified: 2026-05-31

    Rt = generate_rt_signal(t, "sigmoid", p);
end
