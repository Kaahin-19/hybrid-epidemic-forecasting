function [umod, beta_curve] = genData_SEIR(tspan, params, seed)
%GENDATA_SEIR Generate SEIR data from an effective reproduction-number curve.
%
%   Syntax:
%       [umod, beta_curve] = genData_SEIR(tspan, params, seed)
%
%   Description:
%       Simulates an SEIR epidemic trajectory from a desired effective
%       reproduction-number trajectory, params.Rt. At each simulation grid
%       point, the internal transmission rate is chosen so that
%       Rt(k) = (beta(k) / gamma) * S(k) / N. The exposed compartment adds a
%       controlled delay between infection and infectiousness for Part B
%       robustness testing.
%
%   Inputs:
%       tspan  - Numeric vector specifying the simulation time span.
%       params - Structure containing model parameters:
%                .Rt       - Effective reproduction-number vector on tspan.
%                .gamma    - Recovery rate.
%                .sigma    - Exposed-to-infectious transition rate.
%                .pop_size - Total population size.
%                .I0       - (Optional) Initial number of infected individuals.
%                .E0       - (Optional) Initial number of exposed individuals.
%                .R0_init  - (Optional) Initial number of recovered individuals.
%                .solver   - (Optional) String specifying the URDME solver.
%                .compile  - (Optional) Logical flag controlling URDME
%                            compilation. Existing generated executables
%                            are reused when compilation is disabled.
%       seed   - (Optional) Integer seed for random number generation.
%                If omitted, a random seed is generated and used.
%
%   Outputs:
%       umod       - URDME model object containing simulation results and
%                    the effective simulation seed in .seed.
%       beta_curve - Internal transmission-rate values implied by params.Rt
%                    and the simulated susceptible trajectory.
%
%   See also GENDATA_SIRS, PARTB_01_GENERATE_TRUTH.

% A. M. Kaahin 2026-05-18

    tspan = reshape(double(tspan), 1, []);

    if isfield(params, 'beta') && ~isempty(params.beta)
        error('SEIR:UnsupportedBetaDriver', ...
            'genData_SEIR uses params.Rt. beta is computed internally.');
    end

    if ~isfield(params, 'Rt') || isempty(params.Rt)
        error('SEIR:MissingRt', ...
            'params.Rt is required for effective-Rt SEIR simulation.');
    end

    Rt_curve = reshape(double(params.Rt), 1, []);
    local_validate_effectiveRt_inputs(tspan, Rt_curve);

    [umod, beta_curve] = local_simulate_effectiveRt(tspan, params, Rt_curve, seed);
    local_validate_outputs(umod.U, beta_curve);
end

function [umod, beta_curve] = local_simulate_effectiveRt(tspan, params, Rt_curve, seed)
    I0 = local_param_or_default(params, 'I0', 500);
    E0 = local_param_or_default(params, 'E0', round((params.gamma / params.sigma) * I0));
    R0_init = local_param_or_default(params, 'R0_init', 0);
    S0 = params.pop_size - E0 - I0 - R0_init;
    if S0 <= 0
        error('SEIR:InitialSusceptible', ...
            'Initial susceptible population must be positive.');
    end

    U = zeros(4, numel(tspan));
    U(:, 1) = local_sanitize_state([S0; E0; I0; R0_init], params.pop_size);
    beta_curve = nan(1, numel(tspan));

    step_params = rmfield(params, 'Rt');
    caller_sets_compile = isfield(step_params, 'compile');
    last_step_umod = [];

    for k = 1:(numel(tspan) - 1)
        beta_curve(k) = local_beta_from_Rt(Rt_curve(k), U(1, k), params);

        step_params.E0 = U(2, k);
        step_params.I0 = U(3, k);
        step_params.R0_init = U(4, k);

        if ~caller_sets_compile
            step_params.compile = (k == 1);
        end

        step_tspan = [0, tspan(k + 1) - tspan(k)];
        last_step_umod = local_simulate_beta_interval( ...
            step_tspan, step_params, repmat(beta_curve(k), 1, 2), seed);
        U(:, k + 1) = local_sanitize_state(last_step_umod.U(:, end), params.pop_size);
    end

    beta_curve(end) = local_beta_from_Rt(Rt_curve(end), U(1, end), params);

    umod = last_step_umod;
    umod.U = U;
    umod.tspan = tspan;
    umod.u0 = U(:, 1);
    umod.private.epiid.R0 = beta_curve / params.gamma;
    umod.private.epiid.dynrates = params;
    umod.private.epiid.dynrates.beta = beta_curve;
    umod.private.epiid.dynrates = rmfield(umod.private.epiid.dynrates, 'Rt');
end

function umod = local_simulate_beta_interval(tspan, params, beta_curve, seed)
    %% 1. Initialization
    caller_rng_state = rng;
    rng_cleanup = onCleanup(@() rng(caller_rng_state));
    original_workdir = pwd;
    workdir_cleanup = onCleanup(@() cd(original_workdir));

    source_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(source_file)));
    urdme_build_dir = fullfile(repo_root, 'build', 'urdme');

    if exist(urdme_build_dir, 'dir') ~= 7
        mkdir(urdme_build_dir);
    end

    if ~any(strcmp(strsplit(path, pathsep), urdme_build_dir))
        addpath(urdme_build_dir);
    end

    cd(urdme_build_dir);

    if nargin < 4 || isempty(seed)
        rng('shuffle');
        seed = randi(intmax('uint32'));
    end
    seed = double(seed);
    rng(seed);

    name = 'SEIR';

    %% 2. Model Definition
    beta_curve = reshape(beta_curve, 1, []);
    gammaI     = params.gamma;
    sigmaE     = params.sigma;
    pop_size   = params.pop_size;

    species = {'S', 'E', 'I', 'R'};
    r = {'S > beta*S*I/vol > E', ...
         'E > sigmaE*E > I', ...
         'I > gammaI*I > R'};

    if numel(beta_curve) ~= numel(tspan)
        error('SEIR:DriverLength', ...
            'The internal beta driver must have the same number of samples as tspan.');
    end

    rates.beta = 'ldata_time';
    rates.sigmaE = 'gdata';
    rates.gammaI = 'gdata';

    umod = rparse([], r, species, rates, name);

    %% 3. Domain Setup
    umod.vol = pop_size;
    Nspecies = size(umod.N, 1);
    umod.D = sparse(Nspecies, Nspecies);
    umod.sd = 1;
    umod.tspan = tspan;

    %% 4. Initial Conditions
    E0 = local_param_or_default(params, 'E0', 0);
    I0 = local_param_or_default(params, 'I0', 500);
    R0_init = local_param_or_default(params, 'R0_init', 0);

    umod.u0 = zeros(Nspecies, 1);
    umod.u0(1:4) = [umod.vol - E0 - I0 - R0_init; E0; I0; R0_init];

    %% 5. Rate Packaging
    Rates.sigmaE = sigmaE;
    Rates.gammaI = gammaI;

    GDATA = struct2cell(Rates);
    GDATA = cat(1, GDATA{:});

    %% 6. Solver Preparation
    if isfield(params, 'solver')
        sim_solver = params.solver;
    else
        sim_solver = 'ssa';
    end

    if isfield(params, 'compile')
        compile_flag = params.compile;
    else
        compile_flag = 1;
    end

    if ~compile_flag
        expected_mexname = sprintf('mex%s_%s_%s', sim_solver, name, name);
        solver_ready = exist('mexuds', 'file') == 2 || exist('mexuds', 'file') == 3;
        rhs_ready = exist([expected_mexname '_mexrhs'], 'file') == 3;
        jac_ready = exist([expected_mexname '_mexjac'], 'file') == 3;

        if ~strcmp(sim_solver, 'uds')
            solver_ready = exist(expected_mexname, 'file') == 2 || exist(expected_mexname, 'file') == 3;
            rhs_ready = true;
            jac_ready = true;
        end

        compile_flag = ~(solver_ready && rhs_ready && jac_ready);
    end

    umod = urdme(umod, 'solve', 0, 'compile', compile_flag, 'solver', sim_solver, ...
                 'modelname', name, ...
                 'gdata', GDATA, ...
                 'ldata_time', reshape(beta_curve, [1, numel(umod.vol), numel(umod.tspan)]), ...
                 'data_time', umod.tspan);

    if strcmp(sim_solver, 'uds')
        umod.mexexec = str2func('mexuds');
    else
        umod.mexexec = str2func(umod.mexname);
    end

    umod.solve = 1;
    umod.parse = 0;
    umod.compile = 0;

    %% 7. Metadata
    umod.private.epiid.R0 = beta_curve / gammaI;
    umod.private.epiid.rates = Rates;
    umod.private.epiid.dynrates = params;
    umod.private.epiid.dynrates.beta = beta_curve;

    prop = cell(size(r));
    for i = 1:numel(r)
      ix = find(r{i} == '>');
      prop{i} = r{i}(ix(1)+1:ix(2)-1);
    end
    umod.private.epiid.Propensities = prop;

    %% 8. Simulation
    umod.seed = seed;
    umod = urdme(umod);
    clear workdir_cleanup rng_cleanup
end

function local_validate_effectiveRt_inputs(tspan, Rt_curve)
    if numel(tspan) < 2
        error('SEIR:TimeSpanLength', ...
            'tspan must contain at least two time points.');
    end

    if any(diff(tspan) <= 0)
        error('SEIR:TimeSpanOrder', ...
            'tspan must be strictly increasing.');
    end

    if numel(Rt_curve) ~= numel(tspan)
        error('SEIR:RtLength', ...
            'params.Rt must have the same number of samples as tspan.');
    end

    if any(~isfinite(Rt_curve)) || any(Rt_curve <= 0)
        error('SEIR:InvalidRt', ...
            'params.Rt must contain finite positive values.');
    end
end

function value = local_param_or_default(params, field_name, default_value)
    if isfield(params, field_name)
        value = params.(field_name);
    else
        value = default_value;
    end
end

function beta = local_beta_from_Rt(Rt_value, S_value, params)
    susceptible_floor = max(1, 1e-6 * params.pop_size);
    beta = params.gamma * Rt_value * params.pop_size / max(S_value, susceptible_floor);
    if ~isfinite(beta) || beta <= 0
        error('SEIR:InvalidBeta', ...
            'Constructed beta must be finite and positive.');
    end
end

function state = local_sanitize_state(raw_state, pop_size)
    state = reshape(double(raw_state), [], 1);
    if numel(state) ~= 4 || any(~isfinite(state))
        error('SEIR:InvalidState', ...
            'SEIR state must contain four finite compartment values.');
    end

    tolerance = max(1e-7 * pop_size, 1e-9);
    state(abs(state) < tolerance) = 0;
    state = max(state, 0);
    state(1) = max(state(1), max(1, 1e-6 * pop_size));

    total = sum(state);
    if total <= 0
        error('SEIR:InvalidState', ...
            'SEIR simulation produced an empty population state.');
    end

    state = state * (pop_size / total);
end

function local_validate_outputs(U, beta_curve)
    values = [double(U(:)); double(beta_curve(:))];
    if any(~isfinite(values)) || any(values < 0)
        error('SEIR:InvalidOutput', ...
            'SEIR simulation produced nonfinite or negative outputs.');
    end
end
