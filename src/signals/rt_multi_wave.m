function Rt = rt_multi_wave(t, p)
%RT_MULTI_WAVE Generate a four-peak Gaussian effective reproduction-number signal.
%
%   Syntax:
%       Rt = rt_multi_wave(t, p)
%
%   Description:
%       Generates a trajectory featuring four distinct Gaussian peaks over a 
%       constant baseline. Used to model sustained, sequentially damping or 
%       amplifying epidemic resurgences.
%
%   Inputs:
%       t - Time vector [days].
%       p - Parameter structure containing:
%           .baseline              - Constant effective reproduction-number level.
%           .mu1, .mu2, .mu3, .mu4 - Center time points for each peak.
%           .A1, .A2, .A3, .A4     - Amplitudes of each peak.
%           .denom                 - Variance parameter controlling wave duration.
%
%   Outputs:
%       Rt - Vector of effective reproduction-number values evaluated at t.
%
%   See also PARTA_CONFIG, RT_SEASONAL, RT_SIGMOID.

% A. M. Kaahin 2026-02-19
% Modified: 2026-03-28

    peak1 = p.A1 * exp(-((t - p.mu1).^2) / p.denom);
    peak2 = p.A2 * exp(-((t - p.mu2).^2) / p.denom);
    peak3 = p.A3 * exp(-((t - p.mu3).^2) / p.denom);
    peak4 = p.A4 * exp(-((t - p.mu4).^2) / p.denom);
    
    Rt = p.baseline + peak1 + peak2 + peak3 + peak4;
end
