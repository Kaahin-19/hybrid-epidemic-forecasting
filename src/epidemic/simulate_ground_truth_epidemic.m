function truth = simulate_ground_truth_epidemic(model_type, tspan, Rt_true, model_params, sim_options)
%SIMULATE_GROUND_TRUTH_EPIDEMIC Simulate effective-Rt-driven epidemic truth.
%
%   Syntax:
%       truth = simulate_ground_truth_epidemic(model_type, tspan, Rt_true, ...
%           model_params, sim_options)
%
%   Description:
%       Simulates SIRS or SEIR ground-truth epidemic trajectories by advancing
%       URDME one interval at a time. At each interval, the configured
%       effective reproduction number Rt_true(k) is converted into the
%       internal mass-action transmission rate beta(k) using the current
%       susceptible population:
%
%           beta(k) = Rt_true(k) * gamma * N / S(k)
%
%   Inputs:
%       model_type   - "SIRS" or "SEIR".
%       tspan        - Simulation time vector.
%       Rt_true      - Effective reproduction-number trajectory on tspan.
%       model_params - Project-defined model parameter structure.
%       sim_options  - Project-defined URDME simulation options.
%
%   Outputs:
%       truth - Structure with tspan, Rt_true, the compartment trajectories
%               (S/I/R or S/E/I/R), beta_curve, and model_params.
%
%   See also PARTA_CONFIG, PARTB_CONFIG, PARTA_01_GENERATE_TRUTH.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-05

    %% 1. Prepare Inputs
    tspan = reshape(tspan, 1, []);
    Rt_true = reshape(Rt_true, 1, []);

    options = sim_options;
    options.solver = char(options.solver);
    options.compile = logical(options.compile);

    epidemic_dir = fileparts(mfilename('fullpath'));
    src_dir = fileparts(epidemic_dir);
    repo_root = fileparts(src_dir);
    build_dir = fullfile(repo_root, 'build', 'urdme');

    %% 2. Dispatch Ground-Truth Model
    switch string(model_type)
        case "SIRS"
            truth = local_simulate_sirs(tspan, Rt_true, model_params, options, build_dir);

        case "SEIR"
            truth = local_simulate_seir(tspan, Rt_true, model_params, options, build_dir);

        otherwise
            error('EPIDEMIC:UnsupportedModel', ...
                'Unsupported ground-truth model type: %s.', string(model_type));
    end
end

%% 3. Local Functions - SIRS

function truth = local_simulate_sirs(tspan, Rt_true, params, options, build_dir)
%LOCAL_SIMULATE_SIRS Simulate effective-Rt-driven SIRS truth.
    U = zeros(3, numel(tspan));

    U(:, 1) = [
        params.pop_size - params.I0 - params.R0_init;
        params.I0;
        params.R0_init
    ];

    beta_curve = nan(1, numel(tspan));

    for k = 1:(numel(tspan) - 1)
        beta_curve(k) = local_beta_from_effective_rt( ...
            Rt_true(k), U(1, k), params.gamma, params.pop_size);

        interval_tspan = [0, tspan(k + 1) - tspan(k)];
        interval_seed = local_interval_seed(options.seed, k, options.solver);
        interval_compile = options.compile && (k == 1);

        interval_umod = local_advance_sirs_interval( ...
            interval_tspan, U(:, k), beta_curve(k), params, ...
            options.solver, interval_compile, interval_seed, build_dir);

        U(:, k + 1) = max(reshape(interval_umod.U(:, end), 3, 1), 0);
    end

    beta_curve(end) = local_beta_from_effective_rt( ...
        Rt_true(end), U(1, end), params.gamma, params.pop_size);

    truth = struct();
    truth.tspan = tspan;
    truth.Rt_true = Rt_true;
    truth.S_true = U(1, :);
    truth.I_true = U(2, :);
    truth.R_true = U(3, :);
    truth.beta_curve = beta_curve;
    truth.model_params = params;
end

function umod = local_advance_sirs_interval(tspan, state0, beta_value, params, ...
    solver, compile_requested, seed, build_dir)
%LOCAL_ADVANCE_SIRS_INTERVAL Advance one SIRS interval with URDME.
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

    reactions = { ...
        'S > beta*S*I/vol > I', ...
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
    umod.u0(1:3) = reshape(state0, 3, 1);

    gdata = [params.gamma; params.xi];
    beta_driver = repmat(beta_value, 1, numel(tspan));

    umod = urdme(umod, ...
        'solve', 0, ...
        'compile', compile_requested, ...
        'solver', solver, ...
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

%% 4. Local Functions - SEIR

function truth = local_simulate_seir(tspan, Rt_true, params, options, build_dir)
%LOCAL_SIMULATE_SEIR Simulate effective-Rt-driven SEIR truth.
    U = zeros(4, numel(tspan));

    U(:, 1) = [
        params.pop_size - params.E0 - params.I0 - params.R0_init;
        params.E0;
        params.I0;
        params.R0_init
    ];

    beta_curve = nan(1, numel(tspan));

    for k = 1:(numel(tspan) - 1)
        beta_curve(k) = local_beta_from_effective_rt( ...
            Rt_true(k), U(1, k), params.gamma, params.pop_size);

        interval_tspan = [0, tspan(k + 1) - tspan(k)];
        interval_seed = local_interval_seed(options.seed, k, options.solver);
        interval_compile = options.compile && (k == 1);

        interval_umod = local_advance_seir_interval( ...
            interval_tspan, U(:, k), beta_curve(k), params, ...
            options.solver, interval_compile, interval_seed, build_dir);

        U(:, k + 1) = max(reshape(interval_umod.U(:, end), 4, 1), 0);
    end

    beta_curve(end) = local_beta_from_effective_rt( ...
        Rt_true(end), U(1, end), params.gamma, params.pop_size);

    truth = struct();
    truth.tspan = tspan;
    truth.Rt_true = Rt_true;
    truth.S_true = U(1, :);
    truth.E_true = U(2, :);
    truth.I_true = U(3, :);
    truth.R_true = U(4, :);
    truth.beta_curve = beta_curve;
    truth.model_params = params;
end

function umod = local_advance_seir_interval(tspan, state0, beta_value, params, ...
    solver, compile_requested, seed, build_dir)
%LOCAL_ADVANCE_SEIR_INTERVAL Advance one SEIR interval with URDME.
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

    model_name = 'SEIR';
    species = {'S', 'E', 'I', 'R'};

    reactions = { ...
        'S > beta*S*I/vol > E', ...
        'E > sigmaE*E > I', ...
        'I > gammaI*I > R'};

    rates.beta = 'ldata_time';
    rates.sigmaE = 'gdata';
    rates.gammaI = 'gdata';

    umod = rparse([], reactions, species, rates, model_name);

    umod.vol = params.pop_size;

    num_species = size(umod.N, 1);
    umod.D = sparse(num_species, num_species);
    umod.sd = 1;
    umod.tspan = tspan;

    umod.u0 = zeros(num_species, 1);
    umod.u0(1:4) = reshape(state0, 4, 1);

    gdata = [params.sigma; params.gamma];
    beta_driver = repmat(beta_value, 1, numel(tspan));

    umod = urdme(umod, ...
        'solve', 0, ...
        'compile', compile_requested, ...
        'solver', solver, ...
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

%% 5. Local Functions - Shared Calculations

function beta = local_beta_from_effective_rt(Rt_value, susceptible, gamma, pop_size)
%LOCAL_BETA_FROM_EFFECTIVE_RT Convert effective Rt to mass-action beta.
%   When S has reached 0 (SSA full burn-through or UDS integer rounding),
%   clamp to 1: the propensity beta*S*I/vol is still 0 so no transmissions
%   occur, but the beta_curve entry remains finite.
    susceptible_eff = max(double(susceptible), 1);
    beta = Rt_value * gamma * pop_size / susceptible_eff;

    if beta <= 0 || ~isfinite(beta)
        error('EPIDEMIC:InvalidBeta', ...
            'Computed beta is nonpositive or nonfinite.');
    end
end

function seed = local_interval_seed(base_seed, interval_idx, solver)
%LOCAL_INTERVAL_SEED Derive a per-interval RNG seed.
    seed = base_seed;

    if strcmp(solver, 'ssa')
        seed = seed + interval_idx - 1;
    end

    seed = mod(floor(seed), 2^32);
end