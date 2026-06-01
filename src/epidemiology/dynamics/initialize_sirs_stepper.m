function stepper = initialize_sirs_stepper(model_params, sim_options)
%INITIALIZE_SIRS_STEPPER Prepare a reusable one-day URDME SIRS stepper.
%
%   Syntax:
%       stepper = initialize_sirs_stepper(model_params, sim_options)
%
%   Description:
%       Builds and prepares the URDME SIRS model once for repeated one-day
%       effective-Rt-driven state advances. The returned stepper is intended
%       for closed-loop ARX forecasting, where the model structure is fixed
%       and only the current state and effective Rt change at each horizon
%       step.
%
%   Inputs:
%       model_params - Structure with gamma, xi, and pop_size.
%       sim_options  - Structure with required seed and optional solver,
%                      compile fields.
%
%   Outputs:
%       stepper - Reusable SIRS stepper structure.
%
%   See also ADVANCE_SIRS_STEPPER, FORECAST_ARX_CLOSED_LOOP.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-01

    %% 1. Input Validation
    params = local_validate_sirs_params(model_params);
    options = local_validate_sim_options(sim_options);

    %% 2. Build Directory and Model Definition
    build_dir = local_urdme_build_dir();
    if exist(build_dir, 'dir') ~= 7
        mkdir(build_dir);
    end

    if ~any(strcmp(strsplit(path, pathsep), build_dir))
        addpath(build_dir);
    end

    original_workdir = pwd;
    workdir_cleanup = onCleanup(@() cd(original_workdir));
    cd(build_dir);

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
    umod.tspan = [0, 1];
    umod.u0 = [params.pop_size - 1; 1; 0];

    gdata = [params.gamma; params.xi];
    beta_driver = repmat(params.gamma, 1, numel(umod.tspan));
    compile_flag = local_resolve_compile_flag( ...
        options.solver, model_name, options.compile);

    %% 3. One-Time URDME Preparation
    umod = urdme(umod, 'solve', 0, 'compile', compile_flag, ...
        'solver', options.solver, ...
        'modelname', model_name, ...
        'gdata', gdata, ...
        'ldata_time', reshape(beta_driver, [1, numel(umod.vol), numel(umod.tspan)]), ...
        'data_time', umod.tspan);

    if strcmp(options.solver, 'uds')
        umod.mexexec = str2func('mexuds');
    else
        umod.mexexec = str2func(umod.mexname);
    end

    umod.solve = 1;
    umod.parse = 0;
    umod.compile = 0;
    umod.seed = options.seed;
    umod.U = [];

    %% 4. Output Assembly
    stepper = struct();
    stepper.umod_template = umod;
    stepper.params = params;
    stepper.options = options;
    stepper.build_dir = build_dir;
    stepper.seed = options.seed;
    stepper.call_count = 0;
    stepper.model_name = string(model_name);
    stepper.compile_flag_used = compile_flag;

    clear workdir_cleanup
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
%LOCAL_VALIDATE_SIM_OPTIONS Validate SIRS stepper simulation options.
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
            'initialize_sirs_stepper supports solver modes "uds" and "ssa".');
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
%LOCAL_RESOLVE_COMPILE_FLAG Compile when requested or binaries are missing.
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
