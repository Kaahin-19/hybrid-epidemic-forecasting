function interval_options = make_interval_options(intervals_cfg, context)
%MAKE_INTERVAL_OPTIONS Build a per-window interval-simulation option set.
%
%   Syntax:
%       interval_options = make_interval_options(intervals_cfg, context)
%
%   Description:
%       Translates the global cfg.intervals settings and a per-window context
%       into a concrete option set consumed by the AR/ARX and state-space
%       interval simulators. The selection stage produces the lightweight
%       closed-loop residual-bootstrap configuration used by Part A 02, while
%       the final stage produces the fuller closed-loop Monte Carlo
%       configuration used by Part A 03. Both stages target the same
%       closed-loop predictive uncertainty definition; only the computational
%       budget and the epidemic-propagation mode differ.
%
%   Inputs:
%       intervals_cfg - cfg.intervals settings structure.
%       context       - Structure with fields:
%                         stage        : "selection" or "final".
%                         exo_mode     : Exogenous mode (None, S, I, Both).
%                         sirs_cfg     : SIRS parameter structure.
%                         horizon      : Forecast horizon.
%                         alphas       : WIS interval miscoverage rates.
%                         sim_seed     : Default epidemic simulation seed.
%                         scenario_key : Scenario identifier for seeding.
%                         window_index : Window index for seeding.
%                         model_type   : Model family identifier.
%
%   Outputs:
%       interval_options - Option set for the interval simulators.
%
%   See also SIMULATE_AR_ARX_INTERVALS, SIMULATE_STATESPACE_INTERVALS.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-05

    %% 1. Input Validation
    stage = string(context.stage);
    if ~any(stage == ["selection", "final"])
        error('INTERVALS:InvalidStage', 'context.stage must be selection or final.');
    end

    base_seed = double(intervals_cfg.seed);

    %% 2. Stage-Specific Budget and Mode
    if stage == "selection"
        method = intervals_cfg.selection_method;
        num_draws = double(intervals_cfg.selection_num_draws);
        epidemic_mode = "frozen";
        include_epidemic_seed_variation = false;
        resample_seed = local_hash_seed(base_seed, ...
            {context.scenario_key, context.window_index});
        epidemic_base_seed = double(context.sim_seed);
    else
        method = intervals_cfg.final_method;
        num_draws = double(intervals_cfg.final_num_draws);
        epidemic_mode = "resimulate";
        include_epidemic_seed_variation = logical(intervals_cfg.include_epidemic_seed_variation);
        resample_seed = local_hash_seed(base_seed, ...
            {context.scenario_key, context.window_index, ...
            context.model_type, context.exo_mode});
        epidemic_base_seed = local_hash_seed(base_seed + 7919, ...
            {context.scenario_key, context.window_index, ...
            context.model_type, context.exo_mode});
    end

    %% 3. Output Assembly
    interval_options = struct();
    interval_options.enabled = logical(intervals_cfg.enabled);
    interval_options.stage = stage;
    interval_options.method = method;
    interval_options.num_draws = num_draws;
    interval_options.alphas = reshape(double(context.alphas), 1, []);
    interval_options.min_residual_std = double(intervals_cfg.min_residual_std);
    interval_options.use_common_random_numbers = logical(intervals_cfg.use_common_random_numbers);
    interval_options.include_epidemic_seed_variation = include_epidemic_seed_variation;
    interval_options.epidemic_mode = epidemic_mode;
    interval_options.exo_mode = string(context.exo_mode);
    interval_options.sirs_cfg = context.sirs_cfg;
    interval_options.horizon = double(context.horizon);
    interval_options.sim_seed = double(context.sim_seed);
    interval_options.interval_seed = base_seed;
    interval_options.resample_seed = resample_seed;
    interval_options.epidemic_base_seed = epidemic_base_seed;
end

function seed = local_hash_seed(base, parts)
%LOCAL_HASH_SEED Map identifiers to a deterministic positive integer seed.
    modulus = 2147483647;
    seed = mod(double(base), modulus);
    for i = 1:numel(parts)
        part = parts{i};
        if ischar(part) || isstring(part)
            chars = double(char(string(part)));
        else
            chars = double(part(:)).';
        end
        for c = chars
            seed = mod(seed * 131 + c + 7, modulus);
        end
    end
    if seed < 1
        seed = 1;
    end
end
