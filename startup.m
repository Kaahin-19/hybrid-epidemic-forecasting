%STARTUP Initialize environment for the hybrid epidemic forecasting project.
%
%   Description:
%       Explicitly adds script, configuration, and nested
%       source and third-party folders to the MATLAB path. Also initializes
%       the required directory structure for data and results artifacts.

% A. M. Kaahin 2026-02-18
% Modified: 2026-06-02

%% 1. Path Management
repo_root = fileparts(mfilename('fullpath'));

addpath(fullfile(repo_root, 'config'));
addpath(genpath(fullfile(repo_root, 'scripts')));
local_rmpath_tree(fullfile(repo_root, 'src', 'build'));
addpath(local_genpath_excluding(fullfile(repo_root, 'src'), {'build'}));
addpath(genpath(fullfile(repo_root, 'third_party')));

%% 2. Directory Initialization
required_dirs = {'data/partA', ...
                 'data/partB', ...
                 'data/partB/structural_mismatch', ...
                 'data/partC', ...
                 'data/partC/raw', ...
                 'data/partC/processed', ...
                 'results/partA/figures', ...
                 'results/partA/forecasts', ...
                 'results/partA/model_selection', ...
                 'results/partA/evaluation', ...
                 'results/partA/tables', ...
                 'results/partA/logs', ...
                 'results/partB/figures', ...
                 'results/partB/forecasts', ...
                 'results/partB/scores', ...
                 'results/partB/logs', ...
                 'results/partB/structural_mismatch/forecasts', ...
                 'results/partB/structural_mismatch/evaluation', ...
                 'results/partB/structural_mismatch/figures', ...
                 'results/partB/structural_mismatch/tables', ...
                 'results/partB/structural_mismatch/logs', ...
                 'results/partC/figures', ...
                 'results/partC/forecasts', ...
                 'results/partC/scores', ...
                 'results/partC/logs'};

for i = 1:length(required_dirs)
    required_path = fullfile(repo_root, required_dirs{i});
    if ~exist(required_path, 'dir')
        mkdir(required_path);
    end
end

%% 3. Local Functions
function path_text = local_genpath_excluding(root_dir, excluded_names)
%LOCAL_GENPATH_EXCLUDING Generate a path string without named directories.
    if exist(root_dir, 'dir') ~= 7
        path_text = '';
        return;
    end

    raw_path = genpath(root_dir);
    path_parts = strsplit(raw_path, pathsep);
    keep_parts = {};

    for i = 1:numel(path_parts)
        path_item = path_parts{i};
        if isempty(path_item) || local_has_excluded_segment(path_item, excluded_names)
            continue;
        end
        keep_parts{end + 1} = path_item; %#ok<AGROW>
    end

    path_text = strjoin(keep_parts, pathsep);
end

function local_rmpath_tree(root_dir)
%LOCAL_RMPATH_TREE Remove a directory tree from the MATLAB path if present.
    if exist(root_dir, 'dir') ~= 7
        return;
    end

    path_parts = strsplit(genpath(root_dir), pathsep);
    current_path = strsplit(path, pathsep);
    for i = 1:numel(path_parts)
        path_item = path_parts{i};
        if isempty(path_item) || ~any(strcmp(current_path, path_item))
            continue;
        end
        rmpath(path_item);
    end
end

function has_segment = local_has_excluded_segment(path_item, excluded_names)
%LOCAL_HAS_EXCLUDED_SEGMENT Check for excluded path-name segments.
    path_segments = strsplit(path_item, filesep);
    has_segment = false;
    for i = 1:numel(excluded_names)
        if any(strcmp(path_segments, excluded_names{i}))
            has_segment = true;
            return;
        end
    end
end
