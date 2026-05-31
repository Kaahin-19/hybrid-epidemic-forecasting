function Rt = rt_seasonal(t, p)
%RT_SEASONAL Compatibility wrapper for the seasonal Rt signal.
%
%   Syntax:
%       Rt = rt_seasonal(t, p)
%
%   Description:
%       Delegates to generate_rt_signal. This wrapper is retained
%       temporarily for scenario configurations and older scripts that still
%       reference @rt_seasonal.
%
%   Inputs:
%       t - Time vector [days].
%       p - Parameter structure containing:
%           .center - Baseline effective reproduction-number level.
%           .amp    - Amplitude of the sine wave.
%           .period - Period of the oscillation [days].
%
%   Outputs:
%       Rt - Vector of effective reproduction-number values evaluated at t.
%
%   See also GENERATE_RT_SIGNAL, PARTA_CONFIG.

% A. M. Kaahin 2026-02-19
% Modified: 2026-05-31

    Rt = generate_rt_signal(t, "seasonal", p);
end
