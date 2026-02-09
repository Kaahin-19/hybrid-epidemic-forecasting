function Rt = rt_seasonal(t, p)
%RT_SEASONAL Generate a deterministic seasonal reproduction number signal.
%
%   Syntax:
%       Rt = rt_seasonal(t, p)
%
%   Description:
%       Generates a sinusoidal Rt trajectory. This signal is deterministic
%       and fully defined by the input parameters, useful for simulating
%       recurrent epidemic waves or seasonal environmental forcing.
%
%       Formula: Rt(t) = center + amp * sin(2*pi * t / period)
%
%   Inputs:
%       t - Time vector [days].
%       p - Parameter structure containing:
%           .center - Baseline Rt level (mean value).
%           .amp    - Amplitude of the sine wave.
%           .period - Period of the oscillation [days].
%
%   Outputs:
%       Rt - Vector of Rt values evaluated at t.
%
%   See also PARTA_CONFIG, RT_TRANSIENT, RT_TREND.

    Rt = p.center + p.amp * sin((2*pi/p.period) * t);
    
end