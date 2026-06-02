function [candidate_scores, scenario_mean_wis, global_mean_wis] = ...
    aggregate_candidate_scores(candidate_grid, scenario_data, evaluation_options)
%AGGREGATE_CANDIDATE_SCORES Evaluate and aggregate Part A candidate scores.
%
%   Syntax:
%       [candidate_scores, scenario_mean_wis, global_mean_wis] = ...
%           aggregate_candidate_scores(candidate_grid, scenario_data, evaluation_options)
%
%   Description:
%       Evaluates each candidate model configuration across all prepared Part A
%       scenarios and computes the global mean WIS using equal weighting across
%       scenario means.
%
%   Inputs:
%       candidate_grid     - Numeric matrix with one candidate per row.
%       scenario_data      - Prepared scenario-window inputs.
%       evaluation_options - Structure consumed by evaluate_candidate.
%
%   Outputs:
%       candidate_scores  - Candidate-by-scenario mean WIS matrix.
%       scenario_mean_wis - Alias for candidate_scores.
%       global_mean_wis   - Mean WIS across scenarios for each candidate.
%
%   See also EVALUATE_CANDIDATE, SELECT_BEST_CONFIGURATION.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-02

%% 1. Candidate Scoring
num_candidates = size(candidate_grid, 1);
num_scenarios = length(scenario_data);
candidate_scores = inf(num_candidates, num_scenarios);
global_mean_wis = inf(num_candidates, 1);

report_interval = max(1, ceil(num_candidates / 20));
progress_queue = parallel.pool.DataQueue;
local_report_candidate_progress([], num_candidates, report_interval, true);
afterEach(progress_queue, @(~) local_report_candidate_progress( ...
    [], num_candidates, report_interval));

model_type = evaluation_options.model_type;

if num_candidates == 0
    scenario_mean_wis = candidate_scores;
    return;
end

first_scores = evaluate_candidate( ...
    model_type, candidate_grid(1, :), scenario_data, evaluation_options);
candidate_scores(1, :) = first_scores;
global_mean_wis(1) = mean(first_scores);
send(progress_queue, 1);

parfor idx = 2:num_candidates
    scenario_scores = evaluate_candidate( ...
        model_type, candidate_grid(idx, :), ...
        scenario_data, evaluation_options);

    candidate_scores(idx, :) = scenario_scores;
    global_mean_wis(idx) = mean(scenario_scores);
    send(progress_queue, idx);
end

scenario_mean_wis = candidate_scores;
end

function local_report_candidate_progress(~, total_models, report_interval, reset_flag)
%LOCAL_REPORT_CANDIDATE_PROGRESS Emit coarse candidate-evaluation progress updates.
persistent completed_count progress_tic

if nargin >= 4 && reset_flag
    completed_count = 0;
    progress_tic = tic;
    fprintf('Progress: candidates 0/%d completed (0.0%%)\n', total_models);
    return;
end

if isempty(completed_count)
    completed_count = 0;
    progress_tic = tic;
end

completed_count = completed_count + 1;

if completed_count == 1 || ...
        mod(completed_count, report_interval) == 0 || ...
        completed_count == total_models
    elapsed = toc(progress_tic);
    fprintf('Progress: candidates %d/%d completed (%.1f%%, %.1fs elapsed)\n', ...
        completed_count, total_models, ...
        100 * completed_count / total_models, elapsed);
end
end
