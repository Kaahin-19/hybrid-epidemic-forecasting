function Rt = generate_rt_signal(tspan, scenario)
%GENERATE_RT_SIGNAL Generate an analytic effective-Rt trajectory.
%
%   Syntax:
%       Rt = generate_rt_signal(tspan, scenario)
%
%   Description:
%       Generates one configured effective reproduction-number trajectory
%       from a scenario structure defined by partA_config.m or partB_config.m.
%       The function assumes that scenario.signal_type and scenario.params
%       are controlled by the project configuration.
%
%   Inputs:
%       tspan    - Simulation time vector [days].
%       scenario - Scenario structure with fields:
%                  .signal_type : "seasonal", "sigmoid", or "multi_wave"
%                  .params      : parameter structure for the selected signal
%
%   Outputs:
%       Rt - Effective reproduction-number values evaluated on tspan.
%
%   See also PARTA_CONFIG, PARTB_CONFIG, PARTA_01_GENERATE_TRUTH.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-12

%% 1. Signal Formula
signal_type = scenario.signal_type;
p = scenario.params;
t = tspan;

switch signal_type
    case "seasonal"
        Rt = p.center + p.amp * sin((2*pi/p.period) * t);

    case "sigmoid"
        Rt = p.high + (p.low - p.high) ./ (1 + exp(-p.k * (t - p.t0)));

    case "multi_wave"
        peak1 = p.A1 * exp(-((t - p.mu1).^2) / p.denom);
        peak2 = p.A2 * exp(-((t - p.mu2).^2) / p.denom);
        peak3 = p.A3 * exp(-((t - p.mu3).^2) / p.denom);
        peak4 = p.A4 * exp(-((t - p.mu4).^2) / p.denom);

        Rt = p.baseline + peak1 + peak2 + peak3 + peak4;

    otherwise
        error('SCENARIO:UnsupportedGenerator', ...
            'Unsupported Rt signal type: %s.', signal_type);
end
end