%PARTB_03_EVAL_ARIMAX Score Track 2 (ARIMAX / Hybrid Baseline) performance.
%% 1. Initialization
clear; clc; close all;
cfg = partA_config(); % Assuming you still use the same config paths
forecastDir = cfg.output.forecast_dir; 
scoreDir    = cfg.output.score_dir;

fprintf('Loading Track 2 results from: %s\n', forecastDir);
% Update search to look for track2 files
files = dir(fullfile(forecastDir, 'track2_results_*.mat'));

if isempty(files)
    error('EVAL:NoData', 'No Track 2 results found. Run partB_01_run_arimax first.');
end

%% 2. Aggregate Rt Scores
scores = table();
for i = 1:length(files)
    filename = files(i).name;
    fullPath = fullfile(forecastDir, filename);
    
    data = load_mat_safe(fullPath);
    results = data.results;
    
    % Clean scenario name for the table (Updated regex for track2)
    cleanName = regexprep(filename, {'^track2_results_', '\.mat$'}, '');
    
    for k = 1:length(results)
        pred_Rt  = double(results(k).forecast_Rt(:));
        truth_Rt = double(results(k).truth_Rt_window(:));
        
        % Calculate Root Mean Square Error
        rmse_val = sqrt(mean((pred_Rt - truth_Rt).^2));
        
        newRow = {categorical(string(cleanName)), results(k).window_day, rmse_val};
        scores = [scores; newRow];
    end
end
scores.Properties.VariableNames = {'Scenario', 'WindowDay', 'RMSE_Rt'};

%% 3. Visualization
fig = figure('Name', 'Track 2 Evaluation', 'Position', [100 100 600 500]);
boxchart(scores.Scenario, scores.RMSE_Rt);
ylabel('RMSE (R_t)');
title('Track 2: Transmission Rate Accuracy (ARIMAX)');
grid on;

% Save updated figure
plotFile = fullfile(scoreDir, 'track2_evaluation_boxplot.png');
saveas(fig, plotFile);
fprintf('Saved visualization to: %s\n', plotFile);

%% 4. Summary Table
stats = groupsummary(scores, 'Scenario', {'mean', 'std'}, 'RMSE_Rt');

summaryTable = table();
summaryTable.Scenario    = stats.Scenario;
summaryTable.Rt_Mean     = stats.mean_RMSE_Rt;
summaryTable.Rt_Std      = stats.std_RMSE_Rt;

fprintf('\n=== TRACK 2: FINAL SCORECARD ===\n');
disp(summaryTable);

% Save updated CSV
fileSummary = fullfile(scoreDir, 'track2_summary_scores.csv');
writetable(summaryTable, fileSummary);