function umod = genData_SIRS(tspan, params, seed)
%GENDATA_SIRS Generate data from an SIRS compartmental model using URDME.
%
%   Syntax:
%       umod = genData_SIRS(tspan, params, seed)
%
%   Description:
%       Simulates an SIRS epidemic trajectory based on a time-varying 
%       transmission rate (beta) and fixed biological parameters. Supports 
%       both stochastic ('ssa') and deterministic ('uds') simulation solvers.
%       URDME-generated source and mex artifacts are written to a stable
%       build directory inside the repository. The effective simulation
%       seed is recorded in the returned model object while the caller RNG
%       state and working directory are restored on return.
%
%   Inputs:
%       tspan  - Numeric vector specifying the simulation time span.
%       params - Structure containing model parameters:
%                .beta     - Time-varying transmission rate vector.
%                .gamma    - Recovery rate.
%                .xi       - Rate of immunity loss.
%                .pop_size - Total population size.
%                .I0       - (Optional) Initial number of infected individuals.
%                .R0_init  - (Optional) Initial number of recovered individuals.
%                .solver   - (Optional) String specifying the URDME solver.
%                .compile  - (Optional) Logical flag controlling URDME
%                            compilation. Existing generated executables
%                            are reused when compilation is disabled.
%       seed   - (Optional) Integer seed for random number generation.
%                If omitted, a random seed is generated and used.
%
%   Outputs:
%       umod   - URDME model object containing simulation results and
%                the effective simulation seed in .seed.
%
%   See also GENDATA, PARTA_01_GENERATE_TRUTH, PARTA_03_RUN_FORECASTS.

% A. M. Kaahin 2026-02-19
% Modified: 2026-03-29

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

    if nargin < 3 || isempty(seed)
        rng('shuffle');
        seed = randi(intmax('uint32'));
    end
    seed = double(seed);
    rng(seed);
    
    name = 'SIRS';
    
    %% 2. Model Definition
    beta_curve = params.beta;
    gammaI     = params.gamma;
    deltaR     = params.xi;
    pop_size   = params.pop_size;
    
    species = {'S', 'I', 'R'};
    r = {'S > beta*S*I/vol > I', ...
         'I > gammaI*I > R', ...
         'R > deltaR*R > S'};
         
    rates.beta = 'ldata_time';
    rates.gammaI = 'gdata';
    rates.deltaR = 'gdata';
    
    umod = rparse([], r, species, rates, name);
    
    %% 3. Domain Setup
    umod.vol = pop_size;
    Nspecies = size(umod.N, 1);
    umod.D = sparse(Nspecies, Nspecies);
    umod.sd = 1;
    umod.tspan = tspan; 
    
    %% 4. Initial Conditions
    if isfield(params, 'I0')
        I0 = params.I0;
    else
        I0 = 500; 
    end
    
    if isfield(params, 'R0_init')
        R0_init = params.R0_init;
    else
        R0_init = 0; 
    end
    
    umod.u0 = zeros(Nspecies, 1);
    umod.u0(1:3) = [umod.vol - I0 - R0_init; I0; R0_init];
    
    %% 5. Rate Packaging
    Rates.gammaI = gammaI;
    Rates.deltaR = deltaR;
    
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
    umod.parse = 1;
    umod.compile = 0;
    
    %% 7. Metadata
    umod.private.epiid.R0 = beta_curve / gammaI;
    umod.private.epiid.rates = Rates;
    umod.private.epiid.dynrates = params; 
    
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
