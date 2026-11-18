function estimate = estimate_sirs_history_from_incidence(incidence, initial_state, stepper, settings)

%ESTIMATE_SIRS_HISTORY_FROM_INCIDENCE Causal SIRS state and Rt estimates from daily I-entries.
%
%   Syntax:
%       estimate = estimate_sirs_history_from_incidence(incidence,
%           initial_state, stepper, settings)
%
%   Description:
%       Inverts the project SIRS stepper day by day. incidence(k+1) is the
%       observed number of entries into the infectious compartment during
%       [t_k, t_{k+1}]. Given the estimated state X_k at t_k, the estimate
%       Rt(k) is the effective reproduction number that, applied by
%       SIRS_STEP over [t_k, t_{k+1}], produces exactly the observed number
%       of entries into I. The next state X_{k+1} is the state returned by
%       that same accepted step, so the estimated history is reproduced
%       exactly by the forecasting stepper. Rt(k) is therefore an interval
%       driver: it belongs to [t_k, t_{k+1}] and becomes available at index
%       k + 1. Every estimate uses only observations up to its availability
%       index.
%
%       Inversion: the daily entry count f(R) is increasing in R. A
%       fixed-point iteration R <- R * y / f(R), started from the flux
%       guess y / (gamma * I_k), targets |f - y| <= rel_tol * y. If the
%       iteration leaves the admissible domain or does not reach the
%       acceptance criterion |f - y| <= max(rel_tol * y, abs_tol), the root
%       is bracketed by geometric expansion in log R and refined with
%       FZERO. The acceptance tolerances correspond to the accuracy with
%       which the stepper itself computes f. Days that are not accepted are
%       recorded as inversion failures; no Rt value is forced.
%
%       Zero observations: y = 0 is an observation, not proof of zero
%       transmission. Rt is not identifiable as a positive value from such
%       a day and is stored as NaN. By reconstruction convention the zero
%       entry flux is taken at face value, so the state continues with the
%       exact SIRS solution for beta = 0 over the day:
%           I_{k+1} = I_k exp(-gamma)
%           R_{k+1} = R_k exp(-xi) + gamma I_k (exp(-xi) - exp(-gamma)) / (gamma - xi)
%           S_{k+1} = N - I_{k+1} - R_{k+1}.
%       This is exact for noise-free deterministic SIRS data and an explicit
%       convention otherwise.
%
%       A genuine failure (inversion not accepted, invalid observation,
%       non-finite or non-conserving state, or an EPIDEMIC domain error)
%       stops the recursion. Earlier estimates are kept; later entries are
%       NaN and are reported as not estimated.
%
%   Inputs:
%       incidence     - (K+1)-by-1 observed I-entries; incidence(1) is unused.
%       initial_state - 3-by-1 known state [S; I; R_removed] at t_1.
%       stepper       - SIRS stepper from SIRS_INIT with track_incidence true.
%       settings      - Structure with rel_tol, abs_tol,
%                       max_fixed_point_iterations, max_bracket_expansions,
%                       and conservation_tolerance.
%
%   Outputs:
%       estimate - Structure with (K+1)-by-1 fields:
%           S, I, R_removed - State estimates at t_k (NaN after a failure).
%           Rt              - Interval-driver estimates (NaN if unavailable).
%           Rt_available_idx - Index at which Rt(k) becomes available (k+1).
%           state_valid_mask, rt_valid_mask - Logical validity masks.
%           reason          - Per-day estimation outcome.
%           inversion_method, inversion_evaluations, inversion_residual -
%                             Per-day inversion diagnostics.
%       and scalar fields failure_idx (NaN if none), failure_id, and
%       failure_message.
%
%   See also PARTB_01_PREPARE_DATASETS, PARTB_02_RUN_FORECASTS, SIRS_INIT,
%            SIRS_STEP.
%
% A. M. Kaahin 2026-11-18

%% 1. Boundary Contract
if ~stepper.track_incidence
    error('ESTIMATION:StepperWithoutIncidence', 'The estimation stepper must be prepared with track_incidence = true.');
end

params    = stepper.model_params;
num_time  = numel(incidence);
pop_size  = params.pop_size;
gamma     = params.gamma;
xi        = params.xi;

if gamma == xi
    error('ESTIMATION:DegenerateRates', 'The zero-flux closed form requires gamma ~= xi.');
end

%% 2. Output Initialization
estimate = struct();
estimate.S                     = NaN(num_time, 1);
estimate.I                     = NaN(num_time, 1);
estimate.R_removed             = NaN(num_time, 1);
estimate.Rt                    = NaN(num_time, 1);
estimate.Rt_available_idx      = (2:num_time + 1)';
estimate.reason                = repmat("not_estimated_after_failure", num_time, 1);
estimate.inversion_method      = repmat("not_attempted", num_time, 1);
estimate.inversion_evaluations = zeros(num_time, 1);
estimate.inversion_residual    = NaN(num_time, 1);
estimate.failure_idx           = NaN;
estimate.failure_id            = "";
estimate.failure_message       = "";

estimate.S(1)         = initial_state(1);
estimate.I(1)         = initial_state(2);
estimate.R_removed(1) = initial_state(3);
estimate.reason(end)  = "requires_future_observation";

%% 3. Causal Forward Recursion
state = initial_state;

for k = 1:(num_time - 1)
    y = incidence(k + 1);

    if ~isfinite(y) || y < 0
        estimate = local_record_failure(estimate, k, "invalid_observation", 'ESTIMATION:InvalidObservation', sprintf('Observed incidence at index %d is not finite and nonnegative.', k + 1));
        break;
    end

    if y == 0
        next_state = local_zero_flux_step(state, gamma, xi, pop_size);
        estimate.reason(k)           = "unidentifiable_zero_incidence";
        estimate.inversion_method(k) = "zero_incidence";
        estimate.inversion_residual(k) = 0;
    else
        try
            [Rt_k, next_state, info] = local_invert_day(stepper, state, y, gamma, settings);
        catch ME
            if startsWith(string(ME.identifier), "EPIDEMIC:")
                estimate = local_record_failure(estimate, k, "state_failure", ME.identifier, ME.message);
                break;
            end
            rethrow(ME);
        end

        estimate.inversion_method(k)      = info.method;
        estimate.inversion_evaluations(k) = info.evaluations;
        estimate.inversion_residual(k)    = info.residual;

        if ~info.accepted
            estimate = local_record_failure(estimate, k, "inversion_failure", 'ESTIMATION:InversionNotAccepted', sprintf('No accepted Rt for index %d (y = %.6g, residual = %.6g).', k, y, info.residual));
            break;
        end

        estimate.Rt(k)     = Rt_k;
        estimate.reason(k) = "estimated";
    end

    if any(~isfinite(next_state)) || any(next_state < 0) || abs(sum(next_state) - pop_size) > settings.conservation_tolerance
        estimate.Rt(k) = NaN;
        estimate = local_record_failure(estimate, k, "state_failure", 'ESTIMATION:InvalidState', sprintf('Estimated state at index %d is non-finite, negative, or not conserved.', k + 1));
        break;
    end

    estimate.S(k + 1)         = next_state(1);
    estimate.I(k + 1)         = next_state(2);
    estimate.R_removed(k + 1) = next_state(3);
    state = next_state;
end

%% 4. Validity Masks
estimate.state_valid_mask = isfinite(estimate.S) & isfinite(estimate.I) & isfinite(estimate.R_removed);
estimate.rt_valid_mask    = isfinite(estimate.Rt) & estimate.Rt > 0;
end

%% 5. Local Functions
function [R, next_state, info] = local_invert_day(stepper, state, y, gamma, settings)
%LOCAL_INVERT_DAY Find the Rt whose one-day SIRS step produces y entries into I.
target_tol = settings.rel_tol * y;
accept_tol = max(settings.rel_tol * y, settings.abs_tol);
info = struct('method', "fixed_point", 'evaluations', 0, 'residual', NaN, 'accepted', false);

R = y / (gamma * state(2));
next_state = NaN(3, 1);
best = struct('R', NaN, 'state', NaN(3, 1), 'residual', Inf);

for iteration = 1:settings.max_fixed_point_iterations
    if ~isfinite(R) || R <= 0
        break;
    end

    [f, candidate_state] = local_entries(stepper, state, R);
    info.evaluations = info.evaluations + 1;

    if ~isfinite(f) || f <= 0
        break;
    end

    if abs(f - y) < abs(best.residual)
        best = struct('R', R, 'state', candidate_state, 'residual', f - y);
    end

    if abs(f - y) <= target_tol
        break;
    end

    R = R * y / f;
end

if abs(best.residual) <= accept_tol
    R = best.R;
    next_state = best.state;
    info.residual = best.residual;
    info.accepted = true;
    return;
end

info.method = "bracketed_fzero";
[R, next_state, info] = local_bracketed_root(stepper, state, y, best, settings, accept_tol, info);
end

function [R, next_state, info] = local_bracketed_root(stepper, state, y, best, settings, accept_tol, info)
%LOCAL_BRACKETED_ROOT Bracket the monotone entry function in log R and refine with FZERO.
if isfinite(best.R)
    R0 = best.R;
else
    R0 = 1;
end

log_lo = log(R0);
log_hi = log(R0);
[f_lo, ~] = local_entries(stepper, state, exp(log_lo));
f_hi = f_lo;
info.evaluations = info.evaluations + 1;

expansions = 0;
while f_lo > y && expansions < settings.max_bracket_expansions
    log_lo = log_lo - log(2);
    [f_lo, ~] = local_entries(stepper, state, exp(log_lo));
    info.evaluations = info.evaluations + 1;
    expansions = expansions + 1;
end

expansions = 0;
while f_hi < y && expansions < settings.max_bracket_expansions
    log_hi = log_hi + log(2);
    [f_hi, ~] = local_entries(stepper, state, exp(log_hi));
    info.evaluations = info.evaluations + 1;
    expansions = expansions + 1;
end

R = NaN;
next_state = NaN(3, 1);

if ~(isfinite(f_lo) && isfinite(f_hi) && f_lo <= y && f_hi >= y)
    info.residual = best.residual;
    return;
end

if log_lo == log_hi
    log_root = log_lo;
else
    root_options = optimset('TolX', 1e-12, 'Display', 'off');
    [log_root, ~, exit_flag, output] = fzero(@(log_R) local_entries(stepper, state, exp(log_R)) - y, [log_lo, log_hi], root_options);
    info.evaluations = info.evaluations + output.funcCount;

    if exit_flag <= 0
        info.residual = best.residual;
        return;
    end
end

[f_root, candidate_state] = local_entries(stepper, state, exp(log_root));
info.evaluations = info.evaluations + 1;
info.residual = f_root - y;

if abs(f_root - y) <= accept_tol
    R = exp(log_root);
    next_state = candidate_state;
    info.accepted = true;
end
end

function [f, next_state] = local_entries(stepper, state, R)
%LOCAL_ENTRIES One-day SIRS step returning the entries into I and the advanced state.
[next_state, ~, f] = sirs_step(stepper, state, R);
end

function next_state = local_zero_flux_step(state, gamma, xi, pop_size)
%LOCAL_ZERO_FLUX_STEP Exact one-day SIRS solution with zero infection flux.
I_next = state(2) * exp(-gamma);
R_next = state(3) * exp(-xi) + gamma * state(2) * (exp(-xi) - exp(-gamma)) / (gamma - xi);
next_state = [pop_size - I_next - R_next; I_next; R_next];
end

function estimate = local_record_failure(estimate, k, reason, error_id, message)
%LOCAL_RECORD_FAILURE Record the first genuine estimation failure at index k.
estimate.reason(k)       = reason;
estimate.failure_idx     = k;
estimate.failure_id      = string(error_id);
estimate.failure_message = string(message);
end
