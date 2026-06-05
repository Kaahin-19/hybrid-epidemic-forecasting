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
% Modified: 2026-06-05

    %% 1. Scenario Inputs
    t = reshape(tspan, 1, []);
    signal_type = scenario.signal_type;
    params = scenario.params;

    %% 2. Signal Formula
    switch signal_type
        case "seasonal"
            Rt = local_rt_seasonal(t, params);

        case "sigmoid"
            Rt = local_rt_sigmoid(t, params);

        case "multi_wave"
            Rt = local_rt_multi_wave(t, params);

        otherwise
            error('SCENARIO:UnsupportedGenerator', ...
                'Unsupported Rt signal type: %s.', signal_type);
    end

    %% 3. Scientific Sanity Check
        Rt = reshape(double(Rt), 1, []);

    if numel(Rt) ~= numel(t)
        error('SCENARIO:SignalLengthMismatch', ...
            'Generated Rt signal must have the same length as tspan.');
    end

    if any(~isfinite(Rt)) || any(Rt <= 0)
        error('SCENARIO:InvalidRtSignal', ...
            'Generated Rt signal must contain finite positive values.');
    end
end

function Rt = local_rt_seasonal(t, p)
%LOCAL_RT_SEASONAL Sinusoidal seasonal Rt trajectory.
    Rt = p.center + p.amp * sin((2*pi/p.period) * t);
end

function Rt = local_rt_sigmoid(t, p)
%LOCAL_RT_SIGMOID Smooth intervention-like Rt transition.
    Rt = p.high + (p.low - p.high) ./ (1 + exp(-p.k * (t - p.t0)));
end

function Rt = local_rt_multi_wave(t, p)
%LOCAL_RT_MULTI_WAVE Gaussian multi-wave Rt trajectory.
    peak1 = p.A1 * exp(-((t - p.mu1).^2) / p.denom);
    peak2 = p.A2 * exp(-((t - p.mu2).^2) / p.denom);
    peak3 = p.A3 * exp(-((t - p.mu3).^2) / p.denom);
    peak4 = p.A4 * exp(-((t - p.mu4).^2) / p.denom);

    Rt = p.baseline + peak1 + peak2 + peak3 + peak4;
end