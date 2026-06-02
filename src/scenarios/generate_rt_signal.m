function Rt = generate_rt_signal(tspan, scenario, params)
%GENERATE_RT_SIGNAL Generate a configured effective-Rt trajectory.
%
%   Syntax:
%       Rt = generate_rt_signal(tspan, scenario)
%       Rt = generate_rt_signal(tspan, signal_type, params)
%
%   Description:
%       Generates one Part A analytic effective reproduction-number signal
%       from the scenario definitions in partA_config.m. The public function
%       dispatches on scenario.signal_type; the seasonal, sigmoid, and
%       multi-wave formulas are kept as local helpers in this file.
%
%   Inputs:
%       tspan        - Time vector [days].
%       scenario     - Scenario structure from cfg.scenarios, or a signal-type
%                      identifier when params is supplied.
%       params       - Optional parameter structure for signal-type calls.
%
%   Outputs:
%       Rt - Effective reproduction-number values evaluated at tspan.
%
%   See also PARTA_CONFIG, PARTA_01_GENERATE_SYNTHETIC_TRUTH.
%
% A. M. Kaahin 2026-05-31

    %% 1. Input Parsing
    if nargin == 2
        [signal_type, signal_params] = local_parse_scenario(scenario);
    elseif nargin == 3
        signal_type = local_normalize_signal_type(scenario);
        signal_params = params;
    else
        error('SCENARIO:InvalidInputCount', ...
            'generate_rt_signal expects either 2 or 3 inputs.');
    end

    tspan = double(tspan);

    %% 2. Signal Generation
    switch signal_type
        case 'seasonal'
            Rt = local_rt_seasonal(tspan, signal_params);
        case 'sigmoid'
            Rt = local_rt_sigmoid(tspan, signal_params);
        case 'multi_wave'
            Rt = local_rt_multi_wave(tspan, signal_params);
        otherwise
            error('SCENARIO:UnsupportedGenerator', ...
                'Unsupported Rt signal type: %s.', signal_type);
    end

    %% 3. Output Validation
    if numel(Rt) ~= numel(tspan)
        error('SCENARIO:SignalLengthMismatch', ...
            'Generated Rt signal must have the same number of samples as tspan.');
    end

    if any(~isfinite(Rt(:))) || any(Rt(:) <= 0)
        error('SCENARIO:InvalidRtSignal', ...
            'Generated Rt signal must contain finite positive values.');
    end
end

function [signal_type, params] = local_parse_scenario(scenario)
%LOCAL_PARSE_SCENARIO Extract signal metadata from a scenario structure.
    if ~isstruct(scenario)
        error('SCENARIO:InvalidScenario', ...
            'Scenario input must be a structure when params is not supplied.');
    end

    if ~isfield(scenario, 'params')
        error('SCENARIO:MissingParams', ...
            'Scenario structure must contain a params field.');
    end

    if ~isfield(scenario, 'signal_type')
        error('SCENARIO:MissingSignalType', ...
            'Scenario structure must contain a signal_type field.');
    end

    signal_type = local_normalize_signal_type(scenario.signal_type);
    params = scenario.params;
end

function signal_type = local_normalize_signal_type(signal_type)
%LOCAL_NORMALIZE_SIGNAL_TYPE Convert supported signal identifiers to IDs.
    if isstring(signal_type) || ischar(signal_type)
        raw_id = char(signal_type);
    else
        error('SCENARIO:InvalidSignalType', ...
            'Scenario signal_type must be a text identifier.');
    end

    raw_id = lower(strtrim(raw_id));
    raw_id = strrep(raw_id, '-', '_');
    raw_id = strrep(raw_id, ' ', '_');

    switch raw_id
        case 'seasonal'
            signal_type = 'seasonal';
        case 'sigmoid'
            signal_type = 'sigmoid';
        case {'multi_wave', 'multiwave'}
            signal_type = 'multi_wave';
        otherwise
            signal_type = raw_id;
    end
end

function Rt = local_rt_seasonal(tspan, params)
%LOCAL_RT_SEASONAL Generate a sinusoidal seasonal Rt trajectory.
    Rt = params.center + params.amp * sin((2*pi/params.period) * tspan);
end

function Rt = local_rt_sigmoid(tspan, params)
%LOCAL_RT_SIGMOID Generate a smooth sigmoid intervention Rt trajectory.
    Rt = params.high + (params.low - params.high) ./ ...
        (1 + exp(-params.k * (tspan - params.t0)));
end

function Rt = local_rt_multi_wave(tspan, params)
%LOCAL_RT_MULTI_WAVE Generate a four-peak Gaussian Rt trajectory.
    peak1 = params.A1 * exp(-((tspan - params.mu1).^2) / params.denom);
    peak2 = params.A2 * exp(-((tspan - params.mu2).^2) / params.denom);
    peak3 = params.A3 * exp(-((tspan - params.mu3).^2) / params.denom);
    peak4 = params.A4 * exp(-((tspan - params.mu4).^2) / params.denom);

    Rt = params.baseline + peak1 + peak2 + peak3 + peak4;
end
