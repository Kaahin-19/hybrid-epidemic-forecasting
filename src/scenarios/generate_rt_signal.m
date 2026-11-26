function Rt = generate_rt_signal(signal_type, params, tspan)

%GENERATE_RT_SIGNAL Evaluate a prescribed effective reproduction-number signal.
%
%   Syntax:
%       Rt = generate_rt_signal(signal_type, params, tspan)
%
%   Description:
%       Evaluates an analytic effective-Rt signal on a time grid. Supported
%       families are a zero-mean asymmetric periodic signal, seasonal
%       forcing, a sigmoid policy intervention, and a sum of four Gaussian
%       transmission waves. The function is deterministic and does not clip;
%       callers check the result against their Rt bounds.
%
%       The periodic signal is
%           Rt = center + a * (sin(theta) - rho * cos(2 * theta)),
%           theta = 2 * pi * t / period + phase,
%       with a = (peak - trough) / 2 and
%       rho = (peak + trough - 2 * center) / (peak - trough).
%       For 0 <= rho <= 1/4 each cycle has one trough, its maximum is
%       exactly peak, its minimum is exactly trough, and its cycle mean is
%       exactly center. Extrema outside this range are rejected.
%
%   Inputs:
%       signal_type - "periodic", "seasonal", "sigmoid", or "multi_wave".
%       params      - Signal parameters:
%                       periodic   : center, peak, trough, period, phase.
%                       seasonal   : center, amp, period, phase.
%                       sigmoid    : high, low, t0, k.
%                       multi_wave : baseline, mu1-mu4, A1-A4, denom.
%                     Times are in days; phase is in radians.
%       tspan       - 1-by-T time grid (days).
%
%   Outputs:
%       Rt - T-by-1 effective reproduction-number trajectory.
%
%   See also PARTA_01_GENERATE_TRUTH, PARTB_01_PREPARE_DATASETS.
%
% A. M. Kaahin 2026-11-26

%% 1. Signal Evaluation
t = tspan.';

switch signal_type
    case "periodic"
        a   = (params.peak - params.trough) / 2;
        rho = (params.peak + params.trough - 2 * params.center) / (params.peak - params.trough);

        if rho < -1e-12 || rho > 1/4 + 1e-12
            error('GENERATE_RT_SIGNAL:InvalidPeriodicExtrema', 'Periodic peak %.6g and trough %.6g around center %.6g imply asymmetry %.6g outside [0, 1/4].', params.peak, params.trough, params.center, rho);
        end

        theta = 2 * pi * t / params.period + params.phase;
        Rt    = params.center + a * (sin(theta) - rho * cos(2 * theta));
    case "seasonal"
        Rt = params.center + params.amp * sin((2 * pi / params.period) * t + params.phase);
    case "sigmoid"
        Rt = params.high + (params.low - params.high) ./ (1 + exp(-params.k * (t - params.t0)));
    case "multi_wave"
        peak1 = params.A1 * exp(-((t - params.mu1).^2) / params.denom);
        peak2 = params.A2 * exp(-((t - params.mu2).^2) / params.denom);
        peak3 = params.A3 * exp(-((t - params.mu3).^2) / params.denom);
        peak4 = params.A4 * exp(-((t - params.mu4).^2) / params.denom);

        Rt = params.baseline + peak1 + peak2 + peak3 + peak4;
    otherwise
        error('GENERATE_RT_SIGNAL:UnsupportedSignal', 'Unsupported Rt signal type: %s.', signal_type);
end
end
