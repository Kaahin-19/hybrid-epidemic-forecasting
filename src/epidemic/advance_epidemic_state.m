function next_state = advance_epidemic_state(model_type, current_state, Rt_next, ...
    model_params, sim_options)
%ADVANCE_EPIDEMIC_STATE Advance one effective-Rt-driven epidemic state.
%
%   Syntax:
%       next_state = advance_epidemic_state(model_type, current_state, ...
%           Rt_next, model_params, sim_options)
%
%   Description:
%       Advances a single epidemic state interval directly with URDME. The
%       implemented Part A mode is SIRS, where Rt_next is interpreted as an
%       effective reproduction number and converted internally by
%       beta = Rt_next * gamma * pop_size / current_S. Setting xi = 0 gives
%       the SIR special case; xi > 0 gives SIRS with waning immunity.
%
%   Inputs:
%       model_type    - Compartment model identifier. Only "SIRS" is active.
%       current_state - Current [S, I, R] state.
%       Rt_next       - Positive effective reproduction number for the step.
%       model_params  - Structure with gamma, xi, and pop_size.
%       sim_options   - Structure with required seed and optional solver,
%                       compile fields.
%
%   Outputs:
%       next_state - Advanced row-vector [S, I, R] state.
%
%   See also FORECAST_ARX_CLOSED_LOOP, SIMULATE_GROUND_TRUTH_EPIDEMIC.
%
% A. M. Kaahin 2026-05-31

    %% 1. Input Validation
    model_type = upper(string(model_type));
    switch model_type
        case "SIRS"
            params = local_validate_sirs_params(model_params);
            options = local_validate_sim_options(sim_options);
            state0 = local_validate_current_state(current_state, params.pop_size);
            Rt_next = local_validate_rt_next(Rt_next);
        otherwise
            error('EPIDEMIC:UnsupportedModel', ...
                'advance_epidemic_state currently implements only model_type = "SIRS".');
    end

    %% 2. Effective-Rt Conversion and URDME Advancement
    beta_value = local_beta_from_effective_rt(Rt_next, state0(1), params);
    umod = local_advance_sirs_interval( ...
        [0, 1], state0, beta_value, params, options.solver, ...
        options.compile, options.seed, local_urdme_build_dir());

    %% 3. Output Assembly
    next_state = local_sanitize_state(umod.U(:, end), params.pop_size);
    next_state = reshape(next_state, 1, []);
end

function params = local_validate_sirs_params(model_params)
%LOCAL_VALIDATE_SIRS_PARAMS Validate SIRS model parameters.
    if ~isstruct(model_params)
        error('EPIDEMIC:InvalidModelParams', 'model_params must be a structure.');
    end

    required_fields = ["gamma", "xi", "pop_size"];
    for i = 1:numel(required_fields)
        if ~isfield(model_params, required_fields(i))
            error('EPIDEMIC:MissingModelParam', ...
                'model_params.%s is required.', required_fields(i));
        end
    end

    params = model_params;
    params.gamma = local_positive_scalar(params.gamma, 'model_params.gamma');
    params.xi = local_nonnegative_scalar(params.xi, 'model_params.xi');
    params.pop_size = local_positive_scalar(params.pop_size, 'model_params.pop_size');
end

function options = local_validate_sim_options(sim_options)
%LOCAL_VALIDATE_SIM_OPTIONS Validate URDME simulation options.
    if nargin < 1 || isempty(sim_options) || ~isstruct(sim_options)
        error('EPIDEMIC:InvalidSimOptions', 'sim_options must be a structure.');
    end

    if isfield(sim_options, 'solver') && ~isempty(sim_options.solver)
        solver = lower(char(string(sim_options.solver)));
    else
        solver = 'uds';
    end

    if ~any(strcmp(solver, {'uds', 'ssa'}))
        error('EPIDEMIC:InvalidSolver', ...
            'advance_epidemic_state supports solver modes "uds" and "ssa".');
    end

    if ~isfield(sim_options, 'seed')
        error('EPIDEMIC:MissingSeed', 'sim_options.seed is required.');
    end
    seed = double(sim_options.seed);
    if ~isscalar(seed) || ~isfinite(seed) || seed < 0 || seed ~= floor(seed)
        error('EPIDEMIC:InvalidSeed', ...
            'sim_options.seed must be a finite nonnegative integer scalar.');
    end

    compile = false;
    if isfield(sim_options, 'compile') && ~isempty(sim_options.compile)
        compile = sim_options.compile;
        if ~(islogical(compile) || isnumeric(compile)) || ~isscalar(compile) || ...
                ~isfinite(double(compile)) || ~ismember(double(compile), [0, 1])
            error('EPIDEMIC:InvalidCompile', ...
                'sim_options.compile must be a logical scalar when provided.');
        end
    end

    options = struct('solver', solver, 'seed', seed, 'compile', logical(compile));
end

function state = local_validate_current_state(current_state, pop_size)
%LOCAL_VALIDATE_CURRENT_STATE Validate a current [S, I, R] state.
    state = reshape(double(current_state), 1, []);
    if numel(state) ~= 3 || any(~isfinite(state))
        error('EPIDEMIC:InvalidState', 'current_state must be finite [S, I, R].');
    end

    tolerance = max(1e-6 * pop_size, 1e-6);
    if any(state < -tolerance)
        error('EPIDEMIC:InvalidState', 'current_state must be nonnegative.');
    end
    state(abs(state) < tolerance) = 0;

    total = sum(state);
    if abs(total - pop_size) > tolerance
        error('EPIDEMIC:InvalidState', ...
            'sum(current_state) must be approximately model_params.pop_size.');
    end

    if state(1) <= 0
        error('EPIDEMIC:InvalidState', ...
            'current susceptible state must be positive.');
    end

    state = state * (pop_size / total);
end

function value = local_validate_rt_next(value)
%LOCAL_VALIDATE_RT_NEXT Validate a positive effective Rt value.
    value = double(value);
    if ~isscalar(value) || ~isfinite(value) || value <= 0
        error('EPIDEMIC:InvalidRt', 'Rt_next must be a finite positive scalar.');
    end
end

function value = local_positive_scalar(value, label)
%LOCAL_POSITIVE_SCALAR Validate a finite positive scalar.
    value = double(value);
    if ~isscalar(value) || ~isfinite(value) || value <= 0
        error('EPIDEMIC:InvalidModelParam', '%s must be finite and positive.', label);
    end
end

function value = local_nonnegative_scalar(value, label)
%LOCAL_NONNEGATIVE_SCALAR Validate a finite nonnegative scalar.
    value = double(value);
    if ~isscalar(value) || ~isfinite(value) || value < 0
        error('EPIDEMIC:InvalidModelParam', '%s must be finite and nonnegative.', label);
    end
end

function beta = local_beta_from_effective_rt(Rt_value, susceptible, params)
%LOCAL_BETA_FROM_EFFECTIVE_RT Compute beta from effective Rt and current S.
    beta = Rt_value * params.gamma * params.pop_size / susceptible;
    if ~isfinite(beta) || beta <= 0
        error('EPIDEMIC:InvalidBeta', ...
            'Computed internal transmission rate must be finite and positive.');
    end
end

function umod = local_advance_sirs_interval(tspan, state0, beta_value, params, ...
    solver, compile_requested, seed, build_dir)
%LOCAL_ADVANCE_SIRS_INTERVAL Advance one SIRS interval with fixed beta.
    caller_rng_state = rng;
    rng_cleanup = onCleanup(@() rng(caller_rng_state));
    original_workdir = pwd;
    workdir_cleanup = onCleanup(@() cd(original_workdir));

    if exist(build_dir, 'dir') ~= 7
        mkdir(build_dir);
    end

    if ~any(strcmp(strsplit(path, pathsep), build_dir))
        addpath(build_dir);
    end

    cd(build_dir);
    rng(seed);

    model_name = 'SIRS';
    species = {'S', 'I', 'R'};
    reactions = {'S > beta*S*I/vol > I', ...
                 'I > gammaI*I > R', ...
                 'R > deltaR*R > S'};

    rates.beta = 'ldata_time';
    rates.gammaI = 'gdata';
    rates.deltaR = 'gdata';

    umod = rparse([], reactions, species, rates, model_name);
    umod.vol = params.pop_size;
    num_species = size(umod.N, 1);
    umod.D = sparse(num_species, num_species);
    umod.sd = 1;
    umod.tspan = tspan;

    umod.u0 = zeros(num_species, 1);
    umod.u0(1:3) = reshape(double(state0), 3, 1);

    rate_values.gammaI = params.gamma;
    rate_values.deltaR = params.xi;
    gdata = struct2cell(rate_values);
    gdata = cat(1, gdata{:});

    beta_driver = repmat(beta_value, 1, numel(tspan));
    compile_flag = local_resolve_compile_flag(solver, model_name, compile_requested);

    umod = urdme(umod, 'solve', 0, 'compile', compile_flag, 'solver', solver, ...
        'modelname', model_name, ...
        'gdata', gdata, ...
        'ldata_time', reshape(beta_driver, [1, numel(umod.vol), numel(umod.tspan)]), ...
        'data_time', umod.tspan);

    if strcmp(solver, 'uds')
        umod.mexexec = str2func('mexuds');
    else
        umod.mexexec = str2func(umod.mexname);
    end

    umod.solve = 1;
    umod.parse = 1;
    umod.compile = 0;
    umod.seed = seed;
    umod = urdme(umod);

    clear workdir_cleanup rng_cleanup
end

function state = local_sanitize_state(raw_state, pop_size)
%LOCAL_SANITIZE_STATE Clean numerical state values while preserving population.
    state = reshape(double(raw_state), [], 1);
    if numel(state) ~= 3 || any(~isfinite(state))
        error('EPIDEMIC:InvalidState', ...
            'SIRS state must contain three finite compartment values.');
    end

    tolerance = max(1e-7 * pop_size, 1e-9);
    state(abs(state) < tolerance) = 0;
    state = max(state, 0);
    state(1) = max(state(1), max(1, 1e-6 * pop_size));

    total = sum(state);
    if total <= 0
        error('EPIDEMIC:InvalidState', ...
            'SIRS simulation produced an empty population state.');
    end

    state = state * (pop_size / total);
end

function build_dir = local_urdme_build_dir()
%LOCAL_URDME_BUILD_DIR Return the repository-local URDME build directory.
    source_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(source_file)));
    build_dir = fullfile(repo_root, 'build', 'urdme');
end

function compile_flag = local_resolve_compile_flag(solver, model_name, compile_requested)
%LOCAL_RESOLVE_COMPILE_FLAG Compile when requested or when binaries are missing.
    compile_flag = logical(compile_requested);
    if compile_flag
        return;
    end

    expected_mexname = sprintf('mex%s_%s_%s', solver, model_name, model_name);
    if strcmp(solver, 'uds')
        solver_ready = exist('mexuds', 'file') == 2 || exist('mexuds', 'file') == 3;
        rhs_ready = exist([expected_mexname '_mexrhs'], 'file') == 3;
        jac_ready = exist([expected_mexname '_mexjac'], 'file') == 3;
    else
        solver_ready = exist(expected_mexname, 'file') == 2 || exist(expected_mexname, 'file') == 3;
        rhs_ready = true;
        jac_ready = true;
    end

    compile_flag = ~(solver_ready && rhs_ready && jac_ready);
end
