function umod = genData_SIRS(tspan, params, seed)
%GENDATA_SIRS Generate data from SIRS model using URDME.
%
%   Inputs:
%       tspan  - Time vector (e.g., 0:365)
%       params - Struct containing all model parameters:
%                  .beta     (Time-series of transmission rate)
%                  .gamma    (Recovery rate, 1/days)
%                  .xi       (Waning immunity rate, 1/days)
%                  .pop_size (Total population size)
%       seed   - Random seed for reproducibility (optional)

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
    
    % 5. Initialize Physical Domain and Time
    umod.vol = pop_size;
    Nspecies = size(umod.N, 1);
    umod.D = sparse(Nspecies, Nspecies);
    umod.sd = 1;
    umod.tspan = tspan; 
    
    % 6. Map Rates for Compilation
    Rates.gammaI = gammaI;
    Rates.deltaR = deltaR;
    
    GDATA = struct2cell(Rates);
    GDATA = cat(1, GDATA{:});
    
    % 7. Parse and Compile the URDME Model
    umod = urdme(umod, 'solve', 0, 'compile', 1, 'solver', 'ssa', ...
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
    umod.private.epiid.dynrates = params; % Keep for backward compatibility if needed
    
    for i = 1:numel(r)
      ix = find(r{i} == '>');
      prop{i} = r{i}(ix(1)+1:ix(2)-1);
    end
    umod.private.epiid.Propensities = prop;
    
    % 8. Set Initial Conditions and Simulate
    I0 = 500; 
    umod.u0 = zeros(Nspecies, 1);
    umod.u0(1:3) = [umod.vol - I0; I0; 0];
    
    umod.seed = randi(intmax);
    umod = urdme(umod);
end