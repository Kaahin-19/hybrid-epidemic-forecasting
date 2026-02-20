%STARTUP Initialize environment for the hybrid epidemic forecasting project.
%
%   Description:
%       Explicitly adds specific top-level script, configuration, and nested
%       source folders to the MATLAB path. Also initializes the required
%       directory structure for data and results artifacts.

% A. M. Kaahin 2026-02-18

%% 1. Path Management
addpath(fullfile(pwd, 'config'));
addpath(fullfile(pwd, 'scripts'));
addpath(genpath(fullfile(pwd, 'src')));

%% 2. Directory Initialization
required_dirs = {'data/synthetic', 'results/figures', ...
                 'results/forecasts', 'results/scores'};

for i = 1:length(required_dirs)
    if ~exist(required_dirs{i}, 'dir')
        mkdir(required_dirs{i});
    end
end