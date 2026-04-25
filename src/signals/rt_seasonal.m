function Rt = rt_seasonal(t, p)
%RT_SEASONAL Generate a seasonal transmission-potential signal.
%
%   Syntax:
%       Rt = rt_seasonal(t, p)
%
%   Description:
%       Generates a sinusoidal Rt trajectory, where Rt denotes beta/gamma
%       in the synthetic validation artifacts. This signal is fully defined
%       by the input parameters, useful for simulating recurrent epidemic 
%       waves or seasonal environmental forcing.
%
%   Inputs:
%       t - Time vector [days].
%       p - Parameter structure containing:
%           .center - Baseline transmission-potential level (mean value).
%           .amp    - Amplitude of the sine wave.
%           .period - Period of the oscillation [days].
%
%   Outputs:
%       Rt - Vector of transmission-potential values evaluated at t.
%
%   See also PARTA_CONFIG, RT_MULTI_WAVE, RT_SIGMOID.

% A. M. Kaahin 2026-02-19
% Modified: 2026-03-28

    Rt = p.center + p.amp * sin((2*pi/p.period) * t);
end
