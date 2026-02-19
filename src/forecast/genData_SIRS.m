function umod = genData_SIRS(tspan, params, seed)
%GENDATA_SIRS Generate data from SIRS model using URDME.
%
% Dynamically supports both stochastic ('ssa') and deterministic ('uds') solvers.

    if nargin < 3 || isempty(seed)
        seed = 220506; 
    end
    rng(seed);
    
    name = 'SIRS';
    
    % 1. Extract ALL variables from the single params struct
    beta_curve = params.beta;
    gammaI     = params.gamma;
    deltaR     = params.xi;
    pop_size   = params.pop_size;
    
    % 2. Define Species and Transitions (Reactions)
    species = {'S', 'I', 'R'};
    r = {'S > beta*S*I/vol > I', ...
         'I > gammaI*I > R', ...
         'R > deltaR*R > S'};
         
    % 3. Map Rates to URDME Data Types
    rates.beta = 'ldata_time';
    rates.gammaI = 'gdata';
    rates.deltaR = 'gdata';
    
    % 4. Parse the Model
    umod = rparse([], r, species, rates, name);
    
    % 5. Initialize Physical Domain, Time, and Initial Conditions
    umod.vol = pop_size;
    Nspecies = size(umod.N, 1);
    umod.D = sparse(Nspecies, Nspecies);
    umod.sd = 1;
    umod.tspan = tspan; 
    
    % Extract specific initial states if provided, otherwise default
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
    
    % THE FIX: Initialize u0 BEFORE compilation
    umod.u0 = zeros(Nspecies, 1);
    umod.u0(1:3) = [umod.vol - I0 - R0_init; I0; R0_init];
    
    % 6. Map Rates for Compilation
    Rates.gammaI = gammaI;
    Rates.deltaR = deltaR;
    
    GDATA = struct2cell(Rates);
    GDATA = cat(1, GDATA{:});
    
    % --- HYBRID UPDATE: Determine Solver Type ---
    % Defaults to stochastic 'ssa' for Part A. 
    % Accepts 'uds' for deterministic ODEs in Part B.
    if isfield(params, 'solver')
        sim_solver = params.solver;
    else
        sim_solver = 'ssa';
    end
    
    % 7. Parse and Compile the URDME Model
    umod = urdme(umod, 'solve', 0, 'compile', 1, 'solver', sim_solver, ...
                 'modelname', name, ...
                 'gdata', GDATA, ...
                 'ldata_time', reshape(beta_curve, [1, numel(umod.vol), numel(umod.tspan)]), ...
                 'data_time', umod.tspan);
                 
    umod.solve = 1;
    umod.parse = 1;
    umod.compile = 0;
    
    % Add private fields 
    umod.private.epiid.R0 = beta_curve / gammaI;
    umod.private.epiid.rates = Rates;
    umod.private.epiid.dynrates = params; 
    
    for i = 1:numel(r)
      ix = find(r{i} == '>');
      prop{i} = r{i}(ix(1)+1:ix(2)-1);
    end
    umod.private.epiid.Propensities = prop;
    
    % 8. Simulate
    umod.seed = randi(intmax);
    umod = urdme(umod);
end