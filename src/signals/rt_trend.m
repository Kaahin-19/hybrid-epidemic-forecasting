function Rt = rt_trend(t, p)
%RT_TREND Generate a linear trend reproduction number signal.
%
%   Syntax:
%       Rt = rt_trend(t, p)
%
%   Description:
%       Generates a monotonic, linear drift in the reproduction number (Rt).
%       This signal represents slow, directional changes in transmission
%       potential, such as "pandemic fatigue" (gradual increase) or the
%       slow adoption of control measures (gradual decrease).
%
%       Formula: Linear interpolation from p.start to p.stop.
%
%   Inputs:
%       t - Time vector [days]. Used to determine the length of the output.
%       p - Parameter structure containing:
%           .start - Initial Rt value (at t(1)).
%           .stop  - Final Rt value (at t(end)).
%
%   Outputs:
%       Rt - Vector of linearly interpolated Rt values matching the length of t.
%
%   See also RT_SEASONAL, RT_TRANSIENT, PARTA_CONFIG.

    Rt = linspace(p.start, p.stop, numel(t));
    
end