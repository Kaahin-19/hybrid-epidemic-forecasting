function [selected_configuration, selected_index, best_global_wis] = ...
    select_best_configuration(candidate_grid, global_mean_wis)
%SELECT_BEST_CONFIGURATION Select the lowest global-mean-WIS candidate.
%
%   Syntax:
%       [selected_configuration, selected_index, best_global_wis] = ...
%           select_best_configuration(candidate_grid, global_mean_wis)
%
%   Description:
%       Applies the existing Part A global selection principle: choose the
%       candidate configuration with the smallest mean WIS across scenarios.
%
%   Inputs:
%       candidate_grid   - Numeric matrix with one candidate per row.
%       global_mean_wis  - Global mean WIS for each candidate.
%
%   Outputs:
%       selected_configuration - Numeric row vector for the selected candidate.
%       selected_index         - Row index of the selected candidate.
%       best_global_wis        - Selected candidate global mean WIS.
%
%   See also AGGREGATE_CANDIDATE_SCORES.
%
% A. M. Kaahin 2026-05-31

    %% 1. Selection
    global_mean_wis = double(global_mean_wis(:));
    [best_global_wis, selected_index] = min(global_mean_wis);

    if ~isfinite(best_global_wis)
        error('MODEL_SELECTION:NoValidCandidate', ...
            'All candidate model configurations produced invalid global WIS scores.');
    end

    selected_configuration = candidate_grid(selected_index, :);
end
