function truth = simulate_ground_truth_epidemic(model_type, tspan, Rt_true, model_params, sim_options)
%SIMULATE_GROUND_TRUTH_EPIDEMIC Simulate effective-Rt-driven epidemic truth.
%
%   Syntax:
%       truth = simulate_ground_truth_epidemic(model_type, tspan, Rt_true, ...
%           model_params, sim_options)
%
%   Description:
%       Simulates ground-truth epidemic trajectories directly with URDME
%       while preserving the project convention that Rt_true is an effective
%       reproduction-number trajectory. For SIRS, each interval computes the
%       internal mass-action transmission rate from the current susceptible
%       state before advancing the URDME model over that interval.
%
%   Inputs:
%       model_type   - Compartment model identifier. Attempt 2 implements
%                      "SIRS"; "SEIR" is reserved for a later Part B stage.
%       tspan        - Strictly increasing simulation time vector.
%       Rt_true      - Effective reproduction-number trajectory on tspan.
%       model_params - Model parameter structure.
%       sim_options  - Simulation options containing solver, compile, seed.
%
%   Outputs:
%       truth - Structure containing SIRS states, Rt_true, beta_curve,
%               model metadata, solver, seed, and simulation options.
%
%   See also RPARSE, URDME, PARTA_01_GENERATE_SYNTHETIC_TRUTH.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-01

    %% 1. Shared Input Validation
    model_type = upper(string(model_type));
    tspan = local_validate_tspan(tspan);
    Rt_true = local_validate_rt(tspan, Rt_true);

    if nargin < 5 || isempty(sim_options)
        sim_options = struct();
    end

    %% 2. Model Dispatch
    switch model_type
        case "SIRS"
            truth = local_simulate_sirs(tspan, Rt_true, model_params, sim_options);
        case "SEIR"
            error('EPIDEMIC:UnsupportedModel', ...
                'SEIR ground-truth simulation is reserved for a later refactor attempt.');
        otherwise
            error('EPIDEMIC:UnsupportedModel', ...
                'Unsupported ground-truth model type: %s.', model_type);
    end
end

function truth = local_simulate_sirs(tspan, Rt_true, model_params, sim_options)
%LOCAL_SIMULATE_SIRS Simulate effective-Rt-driven SIRS truth directly in URDME.
    params = local_validate_sirs_params(model_params);
    options = local_validate_sim_options(sim_options);

    initial_state = local_initial_sirs_state(params);
    U = zeros(3, numel(tspan));
    U(:, 1) = local_sanitize_state(initial_state, params.pop_size);
    beta_curve = nan(1, numel(tspan));

    build_dir = local_urdme_build_dir();
    compile_requested = logical(options.compile);

    for k = 1:(numel(tspan) - 1)
        beta_curve(k) = local_beta_from_effective_rt(Rt_true(k), U(1, k), params);

        interval_compile = compile_requested && (k == 1);
        interval_tspan = [0, tspan(k + 1) - tspan(k)];
        interval_umod = local_advance_sirs_interval( ...
            interval_tspan, U(:, k), beta_curve(k), params, ...
            options.solver, interval_compile, options.seed, build_dir);

        U(:, k + 1) = local_sanitize_state(interval_umod.U(:, end), params.pop_size);
    end

    beta_curve(end) = local_beta_from_effective_rt(Rt_true(end), U(1, end), params);

    truth = struct();
    truth.model_type = "SIRS";
    truth.solver = string(options.solver);
    truth.seed = options.seed;
    truth.tspan = tspan;
    truth.Rt_true = Rt_true;
    truth.S_true = U(1, :);
    truth.I_true = U(2, :);
    truth.R_true = U(3, :);
    truth.states = U;
    truth.beta_curve = beta_curve;
    truth.model_params = params;
    truth.sim_options = options;
    metadata = struct();
    metadata.state_order = ["S", "I", "R"];
    metadata.effective_rt_definition = "Rt(k) = beta(k) / gamma * S(k) / N";
    metadata.beta_formula = "beta_k = Rt_true(k) * gamma * N / S_k";
    metadata.num_intervals = numel(tspan) - 1;
    metadata.initial_state = U(:, 1);
    if params.xi == 0
        metadata.compartment_model_effective = "SIR";
        metadata.waning_immunity = false;
    else
        metadata.compartment_model_effective = "SIRS";
        metadata.waning_immunity = true;
    end
    truth.metadata = metadata;
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

function tspan = local_validate_tspan(tspan)
%LOCAL_VALIDATE_TSPAN Validate the simulation time grid.
    if ~isnumeric(tspan) || ~isvector(tspan)
        error('EPIDEMIC:InvalidTspan', 'tspan must be a numeric vector.');
    end

    tspan = reshape(double(tspan), 1, []);

    if numel(tspan) < 2
        error('EPIDEMIC:InvalidTspan', 'tspan must contain at least two points.');
    end

    if any(~isfinite(tspan)) || any(diff(tspan) <= 0)
        error('EPIDEMIC:InvalidTspan', ...
            'tspan must contain finite, strictly increasing values.');
    end
end

function Rt_true = local_validate_rt(tspan, Rt_true)
%LOCAL_VALIDATE_RT Validate the effective reproduction-number trajectory.
    if ~isnumeric(Rt_true) || ~isvector(Rt_true)
        error('EPIDEMIC:InvalidRt', 'Rt_true must be a numeric vector.');
    end

    Rt_true = reshape(double(Rt_true), 1, []);

    if numel(Rt_true) ~= numel(tspan)
        error('EPIDEMIC:InvalidRt', ...
            'Rt_true must have the same number of samples as tspan.');
    end

    if any(~isfinite(Rt_true)) || any(Rt_true <= 0)
        error('EPIDEMIC:InvalidRt', ...
            'Rt_true must contain finite positive values.');
    end
end

function params = local_validate_sirs_params(model_params)
%LOCAL_VALIDATE_SIRS_PARAMS Validate SIRS model parameters.
    if ~isstruct(model_params)
        error('EPIDEMIC:InvalidModelParams', ...
            'model_params must be a structure for SIRS simulation.');
    end

    params = model_params;
    required_fields = ["gamma", "xi", "pop_size"];
    for i = 1:numel(required_fields)
        field_name = required_fields(i);
        if ~isfield(params, field_name)
            error('EPIDEMIC:MissingModelParam', ...
                'SIRS model_params.%s is required.', field_name);
        end
    end

    params.gamma = local_validate_positive_scalar(params.gamma, "model_params.gamma");
    params.xi = local_validate_nonnegative_scalar(params.xi, "model_params.xi");
    params.pop_size = local_validate_positive_scalar(params.pop_size, "model_params.pop_size");

    params.I0 = local_optional_nonnegative_scalar(params, 'I0', 500);
    params.R0_init = local_optional_nonnegative_scalar(params, 'R0_init', 0);

    if params.I0 + params.R0_init >= params.pop_size
        error('EPIDEMIC:InvalidInitialConditions', ...
            'Initial infected plus recovered population must be less than pop_size.');
    end
end

function options = local_validate_sim_options(sim_options)
%LOCAL_VALIDATE_SIM_OPTIONS Validate URDME simulation options.
    if ~isstruct(sim_options)
        error('EPIDEMIC:InvalidSimOptions', 'sim_options must be a structure.');
    end

    if ~isfield(sim_options, 'solver')
        error('EPIDEMIC:MissingSolver', 'sim_options.solver is required.');
    end

    solver = lower(char(string(sim_options.solver)));
    if ~any(strcmp(solver, {'ssa', 'uds'}))
        error('EPIDEMIC:InvalidSolver', ...
            'SIRS ground truth supports solver modes "ssa" and "uds".');
    end

    if ~isfield(sim_options, 'seed')
        error('EPIDEMIC:MissingSeed', 'sim_options.seed is required.');
    end
    seed = double(sim_options.seed);
    if ~isscalar(seed) || ~isfinite(seed) || seed < 0 || seed ~= floor(seed)
        error('EPIDEMIC:InvalidSeed', ...
            'sim_options.seed must be a finite nonnegative integer scalar.');
    end

    if ~isfield(sim_options, 'compile')
        error('EPIDEMIC:MissingCompile', 'sim_options.compile is required.');
    end
    compile = sim_options.compile;
    if ~(islogical(compile) || isnumeric(compile)) || ~isscalar(compile) || ...
            ~isfinite(double(compile)) || ~ismember(double(compile), [0, 1])
        error('EPIDEMIC:InvalidCompile', ...
            'sim_options.compile must be a logical scalar.');
    end

    options = struct();
    options.solver = solver;
    options.seed = seed;
    options.compile = logical(compile);
end

function initial_state = local_initial_sirs_state(params)
%LOCAL_INITIAL_SIRS_STATE Build and validate the initial SIRS state.
    initial_state = [ ...
        params.pop_size - params.I0 - params.R0_init; ...
        params.I0; ...
        params.R0_init];

    if initial_state(1) <= 0
        error('EPIDEMIC:InvalidInitialConditions', ...
            'Initial susceptible population must be positive.');
    end
end

function value = local_validate_positive_scalar(value, label)
%LOCAL_VALIDATE_POSITIVE_SCALAR Validate a finite positive scalar.
    value = double(value);
    if ~isscalar(value) || ~isfinite(value) || value <= 0
        error('EPIDEMIC:InvalidModelParam', '%s must be a finite positive scalar.', label);
    end
end

function value = local_validate_nonnegative_scalar(value, label)
%LOCAL_VALIDATE_NONNEGATIVE_SCALAR Validate a finite nonnegative scalar.
    value = double(value);
    if ~isscalar(value) || ~isfinite(value) || value < 0
        error('EPIDEMIC:InvalidModelParam', '%s must be a finite nonnegative scalar.', label);
    end
end

function value = local_optional_nonnegative_scalar(params, field_name, default_value)
%LOCAL_OPTIONAL_NONNEGATIVE_SCALAR Read and validate an optional scalar field.
    if isfield(params, field_name)
        value = double(params.(field_name));
    else
        value = default_value;
    end

    if ~isscalar(value) || ~isfinite(value) || value < 0
        error('EPIDEMIC:InvalidModelParam', ...
            'model_params.%s must be a finite nonnegative scalar.', field_name);
    end
end

function beta = local_beta_from_effective_rt(Rt_value, susceptible, params)
%LOCAL_BETA_FROM_EFFECTIVE_RT Compute beta from current effective Rt and S.
    if susceptible <= 0 || ~isfinite(susceptible)
        error('EPIDEMIC:InvalidState', ...
            'Current susceptible state must be finite and positive.');
    end

    beta = Rt_value * params.gamma * params.pop_size / susceptible;
    if ~isfinite(beta) || beta <= 0
        error('EPIDEMIC:InvalidBeta', ...
            'Computed internal transmission rate must be finite and positive.');
    end
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
    source_dir = fileparts(mfilename('fullpath'));
    repo_root = local_find_repo_root(source_dir);
    build_dir = fullfile(repo_root, 'build', 'urdme');
end

function repo_root = local_find_repo_root(start_dir)
%LOCAL_FIND_REPO_ROOT Walk upward until the repository root marker is found.
    repo_root = start_dir;
    while true
        if exist(fullfile(repo_root, '.git'), 'dir') == 7 || ...
                exist(fullfile(repo_root, 'AGENTS.md'), 'file') == 2
            return;
        end

        parent_dir = fileparts(repo_root);
        if strcmp(parent_dir, repo_root)
            error('EPIDEMIC:RepoRootNotFound', ...
                'Could not resolve repository root from %s.', start_dir);
        end
        repo_root = parent_dir;
    end
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
