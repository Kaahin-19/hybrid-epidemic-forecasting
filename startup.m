% STARTUP Initialize environment for the project.

% Explicitly add specific top-level script and configuration folders
addpath(fullfile(pwd, 'config'));
addpath(fullfile(pwd, 'scripts'));
addpath(fullfile(pwd, 'sandbox'));

% Recursively add the 'src' directory, as it contains safe, nested function modules
addpath(genpath(fullfile(pwd, 'src')));

% Initialize required directory structure
required_dirs = {'data/ground_truth', 'results/forecasts', ...
                 'results/figures', 'results/scores'};

for i = 1:length(required_dirs)
    if ~exist(required_dirs{i}, 'dir')
        mkdir(required_dirs{i});
    end
end

disp('Project environment initialized successfully.');