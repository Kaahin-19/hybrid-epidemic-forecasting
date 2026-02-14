% STARTUP Initialize environment for the project.
%
%   Description:
%       Configures the MATLAB search path and verifies the presence of 
%       the required directory structure for data storage and results.

% Add all project subdirectories to the MATLAB search path
addpath(genpath(pwd));

% Initialize required directory structure
required_dirs = {'data/ground_truth', 'results/forecasts', ...
                 'results/figures', 'results/scores'};

for i = 1:length(required_dirs)
    if ~exist(required_dirs{i}, 'dir')
        mkdir(required_dirs{i});
    end
end