%PARTA_03_EVAL_N4SID Score Track 3 (Fast State-Space / n4sid) performance.
%
%   Description:
%       Calculates and aggregates the RMSE for the n4sid state-space
%       forecasts. Generates a boxplot and a summary CSV scorecard.

%% 1. Initialization
clear; clc; close all;
cfg = partA_config(); 
forecastDir = cfg.output.forecast_dir; 
scoreDir    = cfg.output.score_dir;

% =========================================================================
% CONFIGURATION: MATCH THIS TO THE RUN YOU WANT TO EVALUATE
% =========================================================================
exo_mode = 'Both'; % Options: 'None', 'S', 'I', or 'Both'
% =========================================================================
run_tag = ['_', exo_mode];

fprintf('Loading Track 3 (N4SID | %s) results from: %s\n', exo_mode, forecastDir);
files = dir(fullfile(forecastDir, ['track3_results_*', run_tag, '.mat']));

if isempty(files)
    error('EVAL:NoData', 'No Track 3 results found for exo_mode: %s.', exo_mode);
end

%% 2. Aggregate Rt Scores
scores = table();
for i = 1:length(files)
    filename = files(i).name;
    fullPath = fullfile(forecastDir, filename);
    
    data = load_mat_safe(fullPath);
    results = data.results;
    
    % Clean scenario name for the table 
    % Removes 'track3_results_' from the start and '_Both.mat' from the end
    cleanName = regexprep(filename, {'^track3_results_', [run_tag, '\.mat$']}, '');
    
    for k = 1:length(results)
        pred_Rt  = double(results(k).forecast_Rt(:));
        truth_Rt = double(results(k).truth_Rt_window(:));
        
        rmse_val = sqrt(mean((pred_Rt - truth_Rt).^2));
        
        newRow = {categorical(string(cleanName)), results(k).window_day, rmse_val};
        scores = [scores; newRow];
    end
end
scores.Properties.VariableNames = {'Scenario', 'WindowDay', 'RMSE_Rt'};

%% 3. Visualization
fig = figure('Name', ['Track 3 Evaluation (', exo_mode, ')'], 'Position', [100 100 600 500]);
boxchart(scores.Scenario, scores.RMSE_Rt);
ylabel('RMSE (R_t)');
title(['Track 3: N4SID Accuracy (Exo: ', exo_mode, ')']);
grid on;

plotFile = fullfile(scoreDir, ['track3_evaluation_boxplot_', exo_mode, '.png']);
saveas(fig, plotFile);
fprintf('Saved visualization to: %s\n', plotFile);

%% 4. Summary Table
stats = groupsummary(scores, 'Scenario', {'mean', 'std'}, 'RMSE_Rt');

summaryTable = table();
summaryTable.Scenario    = stats.Scenario;
summaryTable.Rt_Mean     = stats.mean_RMSE_Rt;
summaryTable.Rt_Std      = stats.std_RMSE_Rt;

fprintf('\n=== TRACK 3 (N4SID | %s): FINAL SCORECARD ===\n', upper(exo_mode));
disp(summaryTable);

fileSummary = fullfile(scoreDir, ['track3_summary_scores_', exo_mode, '.csv']);
writetable(summaryTable, fileSummary);