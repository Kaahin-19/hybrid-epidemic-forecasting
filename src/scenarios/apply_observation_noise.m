function observed = apply_observation_noise(latent_truth, noise_config, noise_seed, rt_bounds)
%APPLY_OBSERVATION_NOISE Build observed Part B model-input signals.
%
%   Syntax:
%       observed = apply_observation_noise(latent_truth, noise_config, ...
%           noise_seed, rt_bounds)
%
%   Description:
%       Separates latent epidemic truth, observed/model-input signals, and
%       evaluation targets for the Part B robustness ladder. Clean cases pass
%       latent truth through unchanged. Observation-noise cases perturb the
%       Rt model input with multiplicative lognormal noise and the infected
%       count input with additive Gaussian count noise while retaining latent
%       Rt as the evaluation target.
%
%   Inputs:
%       latent_truth - Structure with Rt_true, S_true, I_true, R_true, and
%                      optional E_true fields.
%       noise_config - Structure describing the controlled observation-noise
%                      model.
%       noise_seed   - Nonnegative integer random seed.
%       rt_bounds    - Two-element admissible Rt bounds vector.
%
%   Outputs:
%       observed - Structure containing latent, observed, model-input, and
%                  evaluation-target signals.
%
%   See also PARTB_01_GENERATE_TRUTH.
%
% A. M. Kaahin 2026-06-03

    %% 1. Input Preparation
    if nargin < 2 || isempty(noise_config)
        noise_config = struct('enabled', false);
    end
    if nargin < 3 || isempty(noise_seed)
        noise_seed = 0;
    end
    if nargin < 4 || isempty(rt_bounds)
        rt_bounds = [0, inf];
    end

    enabled = isfield(noise_config, 'enabled') && logical(noise_config.enabled);
    latent = local_latent_signals(latent_truth);

    %% 2. Observation Model
    Rt_observed = latent.Rt_true;
    I_observed = latent.I_true;

    if enabled
        caller_rng_state = rng;
        rng_cleanup = onCleanup(@() rng(caller_rng_state));
        rng(local_valid_seed(noise_seed));

        Rt_observed = local_noisy_rt(latent.Rt_true, noise_config, rt_bounds);
        I_observed = local_noisy_count(latent.I_true, noise_config, ...
            local_population_size(latent));

        clear rng_cleanup
    end

    %% 3. Output Assembly
    observed = struct();
    observed.Rt_true = latent.Rt_true;
    observed.S_true = latent.S_true;
    observed.I_true = latent.I_true;
    observed.R_true = latent.R_true;
    observed.E_true = latent.E_true;

    observed.Rt_observed = Rt_observed;
    observed.S_observed = latent.S_true;
    observed.I_observed = I_observed;
    observed.R_observed = latent.R_true;
    observed.E_observed = latent.E_true;

    observed.Rt_model_input = Rt_observed;
    observed.S_model_input = latent.S_true;
    observed.I_model_input = I_observed;
    observed.Rt_evaluation_target = latent.Rt_true;
    observed.noise_parameters = noise_config;
    observed.noise_seed = local_valid_seed(noise_seed);
end

function latent = local_latent_signals(latent_truth)
%LOCAL_LATENT_SIGNALS Normalize latent truth vectors.
    required_fields = ["Rt_true", "S_true", "I_true", "R_true"];
    for i = 1:numel(required_fields)
        if ~isfield(latent_truth, required_fields(i))
            error('NOISE:MissingLatentField', ...
                'latent_truth.%s is required.', required_fields(i));
        end
    end

    latent = struct();
    latent.Rt_true = double(latent_truth.Rt_true(:)).';
    latent.S_true = double(latent_truth.S_true(:)).';
    latent.I_true = double(latent_truth.I_true(:)).';
    latent.R_true = double(latent_truth.R_true(:)).';
    if isfield(latent_truth, 'E_true') && ~isempty(latent_truth.E_true)
        latent.E_true = double(latent_truth.E_true(:)).';
    else
        latent.E_true = [];
    end
end

function Rt_noisy = local_noisy_rt(Rt_true, noise_config, rt_bounds)
%LOCAL_NOISY_RT Apply multiplicative lognormal Rt noise.
    sigma_log = local_field_or_default(noise_config, 'rt_sigma_log', 0.08);
    Rt_noisy = exp(log(max(double(Rt_true), eps)) + sigma_log * randn(size(Rt_true)));

    clip_enabled = local_field_or_default(noise_config, 'clip_rt_to_bounds', true);
    if clip_enabled
        Rt_noisy = min(max(Rt_noisy, rt_bounds(1)), rt_bounds(2));
    end
end

function counts_noisy = local_noisy_count(counts_true, noise_config, pop_size)
%LOCAL_NOISY_COUNT Apply controlled Gaussian count observation noise.
    relative_sd = local_field_or_default(noise_config, 'i_relative_sd', 0.08);
    abs_sd = local_field_or_default(noise_config, 'i_abs_sd', 25);
    sigma = abs_sd + relative_sd * max(double(counts_true), 0);
    counts_noisy = round(double(counts_true) + sigma .* randn(size(counts_true)));

    clip_enabled = local_field_or_default(noise_config, ...
        'clip_counts_to_population', true);
    if clip_enabled
        counts_noisy = min(max(counts_noisy, 0), pop_size);
    end
end

function pop_size = local_population_size(latent)
%LOCAL_POPULATION_SIZE Infer the conserved population size.
    if isempty(latent.E_true)
        total = latent.S_true + latent.I_true + latent.R_true;
    else
        total = latent.S_true + latent.E_true + latent.I_true + latent.R_true;
    end
    pop_size = max(total(isfinite(total)));
end

function value = local_field_or_default(s, field_name, default_value)
%LOCAL_FIELD_OR_DEFAULT Read a scalar field with fallback.
    if isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end

function seed = local_valid_seed(seed)
%LOCAL_VALID_SEED Coerce a seed to a nonnegative integer.
    seed = double(seed);
    if ~isscalar(seed) || ~isfinite(seed) || seed < 0
        seed = 0;
    end
    seed = mod(floor(seed), 2^32);
end
