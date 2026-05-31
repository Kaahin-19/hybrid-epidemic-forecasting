function Rt = generate_rt_signal(tspan, scenario, params)
%GENERATE_RT_SIGNAL Generate a configured effective-Rt trajectory.
%
%   Syntax:
%       Rt = generate_rt_signal(tspan, scenario)
%       Rt = generate_rt_signal(tspan, generator_id, params)
%
%   Description:
%       Generates one Part A analytic effective reproduction-number signal
%       from the scenario definitions in partA_config.m. The public function
%       handles dispatch only; the seasonal, sigmoid, and multi-wave formulas
%       are kept as local helpers in this file.
%
%   Inputs:
%       tspan        - Time vector [days].
%       scenario     - Scenario structure from cfg.scenarios, or a generator
%                      identifier when params is supplied.
%       params       - Optional parameter structure for generator identifiers.
%
%   Outputs:
%       Rt - Effective reproduction-number values evaluated at tspan.
%
%   See also PARTA_CONFIG, PARTA_01_GENERATE_SYNTHETIC_TRUTH.
%
% A. M. Kaahin 2026-05-31

    %% 1. Input Parsing
    if nargin == 2
        [generator_id, signal_params] = local_parse_scenario(scenario);
    elseif nargin == 3
        generator_id = local_normalize_generator_id(scenario);
        signal_params = params;
    else
        error('SCENARIO:InvalidInputCount', ...
            'generate_rt_signal expects either 2 or 3 inputs.');
    end

    tspan = double(tspan);

    %% 2. Signal Generation
    switch generator_id
        case 'seasonal'
            Rt = local_rt_seasonal(tspan, signal_params);
        case 'sigmoid'
            Rt = local_rt_sigmoid(tspan, signal_params);
        case 'multi_wave'
            Rt = local_rt_multi_wave(tspan, signal_params);
        otherwise
            error('SCENARIO:UnsupportedGenerator', ...
                'Unsupported Rt generator: %s.', generator_id);
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

function [generator_id, params] = local_parse_scenario(scenario)
%LOCAL_PARSE_SCENARIO Extract generator metadata from a scenario structure.
    if ~isstruct(scenario)
        error('SCENARIO:InvalidScenario', ...
            'Scenario input must be a structure when params is not supplied.');
    end

    if ~isfield(scenario, 'params')
        error('SCENARIO:MissingParams', ...
            'Scenario structure must contain a params field.');
    end

    if ~isfield(scenario, 'generator')
        error('SCENARIO:MissingGenerator', ...
            'Scenario structure must contain a generator field.');
    end

    generator_id = local_normalize_generator_id(scenario.generator);
    params = scenario.params;
end

function generator_id = local_normalize_generator_id(generator)
%LOCAL_NORMALIZE_GENERATOR_ID Convert supported generator references to IDs.
    if isa(generator, 'function_handle')
        raw_id = func2str(generator);
    elseif isstring(generator) || ischar(generator)
        raw_id = char(generator);
    else
        error('SCENARIO:InvalidGenerator', ...
            'Scenario generator must be a function handle or text identifier.');
    end

    raw_id = lower(strtrim(raw_id));
    raw_id = strrep(raw_id, '-', '_');
    raw_id = strrep(raw_id, ' ', '_');

    if startsWith(raw_id, '@')
        raw_id = raw_id(2:end);
    end

    switch raw_id
        case {'seasonal', 'rt_seasonal'}
            generator_id = 'seasonal';
        case {'sigmoid', 'rt_sigmoid'}
            generator_id = 'sigmoid';
        case {'multi_wave', 'multiwave', 'rt_multi_wave'}
            generator_id = 'multi_wave';
        otherwise
            generator_id = raw_id;
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
