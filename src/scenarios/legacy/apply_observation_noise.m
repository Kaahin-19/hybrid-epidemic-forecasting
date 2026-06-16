function observed = apply_observation_noise(latent_truth, noise_config, noise_seed, rt_bounds)
%APPLY_OBSERVATION_NOISE Build observed Part B model-input signals.
%
%   Syntax:
%       observed = apply_observation_noise(latent_truth, noise_config, ...
%           noise_seed, rt_bounds)
%
%   Description:
%       Separates latent epidemic truth, observed/model-input signals, and
%       evaluation targets for the Part B robustness ladder. The model-visible
%       Rt is never produced by perturbing latent Rt_true directly. Instead the
%       pipeline is:
%
%           latent Rt_true -> latent incidence_true (model-implied S->I/S->E)
%           incidence_true -> incidence_observed (count observation model)
%           incidence_observed -> incidence_model_input (trailing smoothing)
%           incidence_model_input -> Rt_model_input (renewal-ratio estimate)
%
%       while the evaluation target is always preserved as latent Rt_true:
%
%           latent Rt_true -> Rt_evaluation_target
%
%       Observation-noise-disabled cases pass latent Rt_true through as the
%       model-visible Rt (clean-channel behaviour) but still expose the latent
%       incidence and a smoothed incidence proxy for auditability. A separate
%       count-noise channel produces I_model_input, the model-visible
%       infected-state proxy used as the ARX/I exogenous history; it is derived
%       from latent I_true and is deliberately not incidence.
%
%   Inputs:
%       latent_truth - Structure with Rt_true, S_true, I_true, R_true,
%                      beta_curve, tspan, model_params, and optional E_true.
%       noise_config - Structure describing the controlled observation model
%                      (incidence model, smoothing, serial interval, warmup,
%                      and count-noise settings).
%       noise_seed   - Nonnegative integer random seed.
%       rt_bounds    - Two-element admissible Rt bounds vector.
%
%   Outputs:
%       observed - Structure containing latent, observed, model-input,
%                  evaluation-target signals, and an audit-grade
%                  observation_metadata structure.
%
%   See also PARTB_01_GENERATE_TRUTH.
%
% A. M. Kaahin 2026-06-03
% Modified: 2026-06-11

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
    pop_size = local_population_size(latent);

    %% 2. Latent Incidence
    %   Model-implied new infections per step from the same latent transmission
    %   rate (beta_curve), susceptible state, infectious state, population, and
    %   time step used by the simulator: incidence(k) = beta(k) S(k) I(k)/N dt(k).
    %   For SIRS this is the S->I channel; for SEIR the S->E channel (I is the
    %   infectious compartment in both mass-action rates).
    incidence_true = local_model_implied_incidence(latent, pop_size);

    %% 3. Observation Model
    si_mean = local_field_or_default(noise_config, 'serial_interval_mean_days', 5);
    si_sd = local_field_or_default(noise_config, 'serial_interval_sd_days', 2);
    si_max_lag = local_field_or_default(noise_config, 'serial_interval_max_lag_days', 21);
    smoothing_window = local_field_or_default(noise_config, ...
        'incidence_smoothing_window_days', 7);
    weights = local_serial_interval_weights(si_mean, si_sd, si_max_lag);

    if enabled
        caller_rng_state = rng;
        rng_cleanup = onCleanup(@() rng(caller_rng_state));
        rng(local_valid_seed(noise_seed));

        incidence_observed = local_observe_incidence(incidence_true, noise_config);
        incidence_model_input = local_trailing_smooth(incidence_observed, smoothing_window);
        [Rt_model_input, renewal_lambda] = local_estimate_rt_model_input( ...
            incidence_model_input, weights, latent.Rt_true, rt_bounds);
        I_model_input = local_noisy_count(latent.I_true, noise_config, pop_size);

        clear rng_cleanup
    else
        % Clean channel: the model sees latent Rt_true and latent infected
        % counts. Incidence proxies are still exposed for auditability.
        incidence_observed = incidence_true;
        incidence_model_input = local_trailing_smooth(incidence_observed, smoothing_window);
        [~, renewal_lambda] = local_estimate_rt_renewal(incidence_model_input, weights);
        renewal_lambda = renewal_lambda(:).';
        Rt_model_input = latent.Rt_true;
        I_model_input = latent.I_true;
    end

    %% 4. Output Assembly
    observed = struct();
    observed.Rt_true = latent.Rt_true;
    observed.S_true = latent.S_true;
    observed.I_true = latent.I_true;
    observed.R_true = latent.R_true;
    observed.E_true = latent.E_true;

    observed.incidence_true = incidence_true;
    observed.incidence_observed = incidence_observed;
    observed.incidence_model_input = incidence_model_input;
    observed.renewal_lambda_model_input = renewal_lambda;
    observed.serial_interval_weights = weights(:).';

    observed.Rt_observed = Rt_model_input;
    observed.S_observed = latent.S_true;
    observed.I_observed = I_model_input;
    observed.R_observed = latent.R_true;
    observed.E_observed = latent.E_true;

    observed.Rt_model_input = Rt_model_input;
    observed.S_model_input = latent.S_true;
    observed.I_model_input = I_model_input;
    observed.Rt_evaluation_target = latent.Rt_true;

    observed.noise_parameters = noise_config;
    observed.noise_seed = local_valid_seed(noise_seed);
    observed.observation_metadata = local_observation_metadata(noise_config, ...
        enabled, smoothing_window, si_mean, si_sd, si_max_lag, rt_bounds);
end

function latent = local_latent_signals(latent_truth)
%LOCAL_LATENT_SIGNALS Normalize latent truth vectors.
    required_fields = ["Rt_true", "S_true", "I_true", "R_true", ...
        "beta_curve", "tspan"];
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
    latent.beta_curve = double(latent_truth.beta_curve(:)).';
    latent.tspan = double(latent_truth.tspan(:)).';
    if isfield(latent_truth, 'E_true') && ~isempty(latent_truth.E_true)
        latent.E_true = double(latent_truth.E_true(:)).';
    else
        latent.E_true = [];
    end
    if isfield(latent_truth, 'model_params') && ...
            isfield(latent_truth.model_params, 'pop_size')
        latent.pop_size = double(latent_truth.model_params.pop_size);
    else
        latent.pop_size = [];
    end
end

function incidence = local_model_implied_incidence(latent, pop_size)
%LOCAL_MODEL_IMPLIED_INCIDENCE New infections per step from the latent rate.
    tspan = latent.tspan;
    if numel(tspan) >= 2
        dt = [diff(tspan), tspan(end) - tspan(end - 1)];
    else
        dt = ones(size(tspan));
    end

    incidence = latent.beta_curve .* latent.S_true .* latent.I_true ./ ...
        pop_size .* dt;
    incidence = max(incidence, 0);
    incidence(~isfinite(incidence)) = 0;
end

function incidence_observed = local_observe_incidence(incidence_true, noise_config)
%LOCAL_OBSERVE_INCIDENCE Sample reported incidence from a count model.
    model = string(local_field_or_default(noise_config, 'incidence_model', ...
        "negative_binomial"));
    reporting_fraction = local_field_or_default(noise_config, ...
        'reporting_fraction', 1.0);
    expected = max(reporting_fraction * double(incidence_true), 0);

    switch model
        case "none"
            incidence_observed = round(expected);
        case "poisson"
            incidence_observed = poissrnd(expected);
        case "negative_binomial"
            % NB with mean m, variance m + m^2/r via MATLAB's (R, P)
            % parameterization: R = r, P = r / (r + m). Zero-mean entries map
            % to P = 1 and therefore to a deterministic zero count.
            dispersion = local_field_or_default(noise_config, 'dispersion', 10);
            if ~isfinite(dispersion) || dispersion <= 0
                error('NOISE:InvalidDispersion', ...
                    'Negative-binomial dispersion must be a positive finite scalar.');
            end
            success_prob = dispersion ./ (dispersion + expected);
            incidence_observed = nbinrnd(dispersion, success_prob);
        otherwise
            error('NOISE:UnsupportedIncidenceModel', ...
                'Unsupported incidence observation model: %s.', model);
    end

    incidence_observed = max(round(double(incidence_observed)), 0);
    if any(~isfinite(incidence_observed))
        error('NOISE:NonfiniteObservedIncidence', ...
            'Observed incidence contains nonfinite values.');
    end
end

function smoothed = local_trailing_smooth(incidence, window_days)
%LOCAL_TRAILING_SMOOTH Trailing moving average of observed incidence.
    window_days = max(1, round(double(window_days)));
    smoothed = movmean(double(incidence(:)).', ...
        [window_days - 1, 0], 'Endpoints', 'shrink');
end

function [Rt_model_input, renewal_lambda] = local_estimate_rt_model_input( ...
    incidence_model_input, weights, Rt_true, rt_bounds)
%LOCAL_ESTIMATE_RT_MODEL_INPUT Renewal Rt with documented warmup handling.
    [Rt_raw, renewal_lambda] = local_estimate_rt_renewal(incidence_model_input, weights);
    Rt_raw = Rt_raw(:).';
    renewal_lambda = renewal_lambda(:).';

    % Warmup handling: leading fill with the first finite, positive renewal
    % estimate. The warmup region (first numel(weights) steps) precedes the
    % first expanding-window forecast origin, but Rt_past spans the full history
    % from index 1, so the warmup must be filled with an incidence-derived value
    % rather than left undefined or borrowed from latent Rt_true.
    finite_positive = isfinite(Rt_raw) & (Rt_raw > 0);
    first_idx = find(finite_positive, 1);
    if isempty(first_idx)
        error('NOISE:NoFiniteRtEstimate', ...
            'Renewal Rt estimation produced no finite positive value.');
    end
    fill_value = Rt_raw(first_idx);

    Rt_model_input = Rt_raw;
    Rt_model_input(~finite_positive) = fill_value;

    % Guard to the admissible Rt domain so every forecast window receives a
    % finite, strictly positive history consistent with the Part A models.
    lower_bound = max(rt_bounds(1), eps);
    Rt_model_input = min(max(Rt_model_input, lower_bound), rt_bounds(2));

    if numel(Rt_model_input) ~= numel(Rt_true)
        error('NOISE:RtLengthMismatch', ...
            'Estimated Rt_model_input length does not match latent Rt_true.');
    end
end

function counts_noisy = local_noisy_count(counts_true, noise_config, pop_size)
%LOCAL_NOISY_COUNT Apply controlled Gaussian infected-state observation noise.
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
%LOCAL_POPULATION_SIZE Resolve the conserved population size.
    if ~isempty(latent.pop_size) && isfinite(latent.pop_size) && latent.pop_size > 0
        pop_size = latent.pop_size;
        return;
    end

    if isempty(latent.E_true)
        total = latent.S_true + latent.I_true + latent.R_true;
    else
        total = latent.S_true + latent.E_true + latent.I_true + latent.R_true;
    end
    pop_size = max(total(isfinite(total)));
end

function metadata = local_observation_metadata(noise_config, enabled, ...
    smoothing_window, si_mean, si_sd, si_max_lag, rt_bounds)
%LOCAL_OBSERVATION_METADATA Assemble the audit-grade observation metadata.
    if enabled
        incidence_model = string(local_field_or_default(noise_config, ...
            'incidence_model', "negative_binomial"));
    else
        incidence_model = "none";
    end

    metadata = struct();
    metadata.direct_Rt_noise_used = false;
    metadata.observation_noise_enabled = enabled;
    metadata.Rt_model_input_definition = ...
        "Renewal-ratio Rt estimated from smoothed observed incidence (clamped to Rt bounds); latent Rt_true when observation noise is disabled.";
    metadata.Rt_evaluation_target_definition = "Latent Rt_true.";
    metadata.incidence_true_definition = ...
        "Model-implied new infections per step beta(k) S(k) I(k)/N dt(k) on the S->I (SIRS) or S->E (SEIR) channel.";
    metadata.incidence_observed_definition = ...
        "Latent incidence passed through the count observation model (reporting_fraction and dispersion); equals rounded incidence_true when disabled.";
    metadata.incidence_model_input_definition = ...
        "Trailing moving average of incidence_observed.";
    metadata.I_model_input_definition = ...
        "Model-visible infected-state proxy from latent I_true under Gaussian count noise (ARX/I exogenous history); latent I_true when disabled.";
    metadata.incidence_noise_model = incidence_model;
    metadata.reporting_fraction = local_field_or_default(noise_config, ...
        'reporting_fraction', 1.0);
    metadata.dispersion = local_field_or_default(noise_config, 'dispersion', 10);
    metadata.incidence_smoothing_method = string(local_field_or_default( ...
        noise_config, 'incidence_smoothing_method', "trailing_moving_average"));
    metadata.incidence_smoothing_window_days = smoothing_window;
    metadata.Rt_estimation_method = ...
        "Rt(t) = incidence_model_input(t) / sum_s w(s) incidence_model_input(t-s)";
    metadata.serial_interval_mean_days = si_mean;
    metadata.serial_interval_sd_days = si_sd;
    metadata.serial_interval_max_lag_days = si_max_lag;
    metadata.warmup_handling_method = string(local_field_or_default( ...
        noise_config, 'warmup_handling_method', "leading_fill_first_finite"));
    metadata.rt_model_input_clip = rt_bounds;
    metadata.count_model = string(local_field_or_default(noise_config, ...
        'count_model', "gaussian_count"));
end

function weights = local_serial_interval_weights(mean_days, sd_days, max_lag)
%LOCAL_SERIAL_INTERVAL_WEIGHTS Discretize a gamma serial interval on day lags.
    if mean_days <= 0 || sd_days <= 0 || max_lag < 1
        error('NOISE:InvalidSerialInterval', ...
            'Serial interval mean, standard deviation, and max lag must be positive.');
    end

    lag_days = (1:max_lag)';
    shape = (mean_days / sd_days)^2;
    scale = (sd_days^2) / mean_days;
    weights = (lag_days.^(shape - 1) .* exp(-lag_days / scale)) ./ ...
        (gamma(shape) * scale^shape);
    weights = weights / sum(weights);
end

function [Rt_est, renewal_lambda] = local_estimate_rt_renewal(incidence, weights)
%LOCAL_ESTIMATE_RT_RENEWAL Renewal-ratio Rt from incidence; NaN in warmup.
    incidence = double(incidence(:));
    weights = double(weights(:));
    max_lag = numel(weights);
    n = numel(incidence);

    renewal_lambda = nan(n, 1);
    for t_idx = (max_lag + 1):n
        lagged_incidence = incidence(t_idx - (1:max_lag));
        renewal_lambda(t_idx) = sum(weights .* lagged_incidence(:));
    end

    Rt_est = incidence ./ renewal_lambda;
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
