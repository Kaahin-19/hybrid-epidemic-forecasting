function Rt = rt_double_wave(t, p)
%RT_DOUBLE_WAVE Generate a double-peak Gaussian reproduction number signal.
%
%   Syntax:
%       Rt = rt_double_wave(t, p)
%
%   Description:
%       Generates a trajectory featuring two distinct Gaussian peaks over a 
%       constant baseline, used to model an initial wave and a single resurgence.
%
%   Inputs:
%       t - Time vector [days].
%       p - Parameter structure containing:
%           .baseline - Constant baseline Rt level.
%           .mu1, .mu2 - Center time points for each peak.
%           .A1, .A2   - Amplitudes (heights) of each peak.
%           .denom     - Variance parameter controlling wave duration.
%
%   Outputs:
%       Rt - Vector of Rt values evaluated at t.

% A. M. Kaahin 2026-02-19

    peak1 = p.A1 * exp(-((t - p.mu1).^2) / p.denom);
    peak2 = p.A2 * exp(-((t - p.mu2).^2) / p.denom);
    Rt = p.baseline + peak1 + peak2;
end