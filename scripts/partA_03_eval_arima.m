%PARTA_03_EVAL_ARIMA Score Track 1 (AR/ARIMA) performance.

%% 1. Initialization
clear; clc; close all;

cfg = partA_config();
forecastDir = cfg.output.forecast_dir; 
scoreDir    = cfg.output.score_dir;

fprintf('Loading Track 1 results from: %s\n', forecastDir);

files = dir(fullfile(forecastDir, 'track1_results_*.mat'));
if isempty(files)
    error('EVAL:NoData', 'No Track 1 results found. Run partA_02_run_arima first.');
end

%% 2. Aggregate Rt Scores
scores = table();

for i = 1:length(files)
    filename = files(i).name;
    fullPath = fullfile(forecastDir, filename);
    
    data = load_mat_safe(fullPath);
    results = data.results;
    
    % Clean scenario name for table
    cleanName = regexprep(filename, {'^track1_results_synthetic_', '\.mat$'}, '');
    
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
fig = figure('Name', 'Track 1 Evaluation', 'Position', [100 100 600 500]);

boxchart(scores.Scenario, scores.RMSE_Rt);
ylabel('RMSE (R_t)');
title('Track 1: Transmission Rate Accuracy (AR/ARIMA)');
grid on;

plotFile = fullfile(scoreDir, 'track1_evaluation_boxplot.png');
saveas(fig, plotFile);
fprintf('Saved visualization to: %s\n', plotFile);

%% 4. Summary Table
stats = groupsummary(scores, 'Scenario', {'mean', 'std'}, 'RMSE_Rt');

summaryTable = table();
summaryTable.Scenario    = stats.Scenario;
summaryTable.Rt_Mean     = stats.mean_RMSE_Rt;
summaryTable.Rt_Std      = stats.std_RMSE_Rt;

fprintf('\n=== TRACK 1: FINAL SCORECARD ===\n');
disp(summaryTable);

fileSummary = fullfile(scoreDir, 'track1_summary_scores.csv');
writetable(summaryTable, fileSummary);