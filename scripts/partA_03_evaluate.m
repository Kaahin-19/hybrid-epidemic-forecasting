%PARTA_03_EVALUATE Score the Hybrid Forecasting performance (RMSE).
%
%   Description:
%       Final evaluation step for Part A. Calculates RMSE for Rt and Cases
%       across all scenarios. Generates summary tables and boxplots to
%       assess model stability.
%
%   See also PARTA_CONFIG, AGGREGATE_SCORES.

%% 1. Initialization
clear; clc; close all;

cfg = partA_config();
forecastDir = cfg.output.forecast_dir; 
scoreDir    = cfg.output.score_dir;

fprintf('Loading forecast results from: %s\n', forecastDir);

%% 2. Load Raw Data
raw_scores = aggregate_scores(forecastDir, 'results_*.mat');

if isempty(raw_scores)
    error('EVAL:NoData', 'No results found. Ensure partA_02_run_forecasts has been executed.');
end

%% 3. Visualization (Boxchart)
fig = figure('Name', 'Part A Evaluation', 'Position', [100 100 1000 500]);

% Subplot 1: Rt Accuracy
subplot(1, 2, 1);
boxchart(raw_scores.Scenario, raw_scores.RMSE_Rt);
ylabel('RMSE (Rt)');
title('Transmission Rate Accuracy');
grid on;

% Subplot 2: Case Count Accuracy
subplot(1, 2, 2);
boxchart(raw_scores.Scenario, raw_scores.RMSE_Cases);
ylabel('RMSE (Infected Count)');
title('Case Forecast Accuracy');
grid on;

% Save Figure
plotFile = fullfile(scoreDir, 'evaluation_boxplot.png');
saveas(fig, plotFile);
fprintf('Saved visualization to: %s\n', plotFile);

%% 4. Statistical Summary
stats = groupsummary(raw_scores, 'Scenario', {'mean', 'std'}, ...
    {'RMSE_Rt', 'RMSE_Cases'});

% Format summary table
summaryTable = table();
summaryTable.Scenario    = stats.Scenario;
summaryTable.Rt_Mean     = stats.mean_RMSE_Rt;
summaryTable.Rt_Std      = stats.std_RMSE_Rt;
summaryTable.Cases_Mean  = stats.mean_RMSE_Cases;
summaryTable.Cases_Std   = stats.std_RMSE_Cases;

fprintf('\n=== PART A: FINAL SCORECARD ===\n');
disp(summaryTable);

%% 5. Persistence
fileSummary = fullfile(scoreDir, 'summary_scores.csv');
fileRaw     = fullfile(scoreDir, 'raw_scores.csv');

writetable(summaryTable, fileSummary);
writetable(raw_scores,   fileRaw);

fprintf('Saved summary tables to: %s\n', scoreDir);