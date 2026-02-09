function generate_synthetic_truth(scenarios, cfg)
%GENERATE_SYNTHETIC_TRUTH Execute stochastic SIRS simulations for scenarios.
%
%   Syntax:
%       generate_synthetic_truth(scenarios, cfg)
%
%   Description:
%       Acts as the primary simulation engine for Part A. It iterates over
%       the scenarios defined in Part A_00, adapts the data for the
%       underlying stochastic solver, and persists the ground truth results
%       (Infected cases, etc.) to disk.
%
%   Inputs:
%       scenarios - Struct array containing .Rt, .t, .id (from PartA_00).
%       cfg       - Configuration struct containing .sirs and .output.
%
%   Workflow:
%       1. Data Adaptation: Convert Rt signal to Transmission Rate (Beta).
%       2. Interface Prep: Construct parameter structures for the solver.
%       3. Execution: Run the stochastic SIRS model (via genData).
%       4. Persistence: Save results (umod, Rt_true, I_true) to disk.
%
%   See also PARTA_01_GENERATE_TRUTH, RT_TO_BETA_SIRS, GENDATA.

    % Extract biological parameters
    params = cfg.sirs;

    fprintf('=== Generating Synthetic Truth ===\n');

    %% Simulation Loop
    for i = 1:numel(scenarios)
        s = scenarios(i);
        fprintf('Processing: %s (%s)... ', s.id, s.name);
        
        % 1. Data Adaptation (Rt -> Beta)
        % The stochastic engine requires Beta (Transmission Rate), but 
        % scenarios are defined by Rt. We apply the standard conversion:
        % Beta(t) = Rt(t) * Gamma.
        beta_curve = rt_to_beta_sirs(s.Rt, params.gamma);
        
        % 2. Interface Preparation
        % Construct the 'dynrates' structure required by the solver.
        dynrates.gamma = params.gamma;
        dynrates.xi    = params.xi;
        dynrates.beta  = beta_curve;
        
        % 3. Execution
        % Run the stochastic simulation. We wrap this in a try-catch block 
        % to ensure robust batch processing.
        try
            umod = genData('SIRS', cfg.sim.seed, dynrates);
        catch ME
            warning('Simulation failed for %s: %s', s.id, ME.message);
            continue;
        end
        
        % 4. Persistence
        Rt_true = s.Rt;
        I_true  = umod.U(2, :);
        tspan   = cfg.time.tspan;
        
        outName = sprintf('synthetic_%s.mat', s.id);
        outPath = fullfile(cfg.output.data_dir, outName);
        
        % Save to disk.
        % We include 'cfg' and 'dynrates' to ensure the result file is self-documenting.
        if exist('save_mat_atomic', 'file')
            save_mat_atomic(outPath, 'umod', umod, 'Rt_true', Rt_true, ...
                'I_true', I_true, 'tspan', tspan, 'dynrates', dynrates, 'cfg', cfg);
        else
            save(outPath, 'umod', 'Rt_true', 'I_true', 'tspan', 'dynrates', 'cfg');
        end
        
        fprintf('Saved to %s\n', outPath);
    end
    
    fprintf('=== Generation Complete ===\n\n');
end