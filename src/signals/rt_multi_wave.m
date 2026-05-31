function Rt = rt_multi_wave(t, p)
%RT_MULTI_WAVE Compatibility wrapper for the multi-wave Rt signal.
%
%   Syntax:
%       Rt = rt_multi_wave(t, p)
%
%   Description:
%       Delegates to generate_rt_signal. This wrapper is retained
%       temporarily for scenario configurations and older scripts that still
%       reference @rt_multi_wave.
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
%   See also GENERATE_RT_SIGNAL, PARTA_CONFIG.

% A. M. Kaahin 2026-02-19
% Modified: 2026-05-31

    Rt = generate_rt_signal(t, "multi_wave", p);
end
