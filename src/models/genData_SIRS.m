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
%       seed   - (Optional) Integer seed for random number generation.
%
%   Outputs:
%       umod   - URDME model object containing simulation results.
%
%   See also GENDATA, PARTA_01_GENERATE_TRUTH, PARTA_02_RUN_FORECASTS.

% A. M. Kaahin 2026-02-19
% Modified: 2026-03-28

    %% 1. Initialization
    if nargin < 3 || isempty(seed)
        seed = 220506; 
    end
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
    
    umod = urdme(umod, 'solve', 0, 'compile', 1, 'solver', sim_solver, ...
                 'modelname', name, ...
                 'gdata', GDATA, ...
                 'ldata_time', reshape(beta_curve, [1, numel(umod.vol), numel(umod.tspan)]), ...
                 'data_time', umod.tspan);
                 
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
    umod.seed = randi(intmax);
    umod = urdme(umod);
end
