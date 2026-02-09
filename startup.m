function startup()
%STARTUP Initialize the MATLAB environment for the Hybrid Epidemic Forecasting project.
%
%   Description:
%       Sets up the MATLAB path for the project. It resolves the repository
%       root relative to this file's location, ensuring that all source code,
%       configuration, and third-party dependencies are accessible.
%
%       It also initializes the standard directory structure using the
%       project's 'ensure_dirs' utility.
%
%   Usage:
%       Run this script once at the start of a session.

    % 1. Repository Root Resolution
    repoRoot = fileparts(mfilename("fullpath"));

    % 2. Path Cleanup
    restoredefaultpath;

    % 3. Third-Party Dependencies
    urdmePath    = fullfile(repoRoot, "third_party", "urdme");
    stenglibPath = fullfile(repoRoot, "third_party", "stenglib");
    
    if exist(stenglibPath, "dir"), addpath(genpath(stenglibPath)); end
    if exist(urdmePath, "dir"),    addpath(genpath(urdmePath));    end

    % 4. Project Source Code
    % Add internal modules. This makes 'ensure_dirs' (in src/utils) available.
    addpath(genpath(fullfile(repoRoot, "src")));
    addpath(genpath(fullfile(repoRoot, "scripts")));
    addpath(genpath(fullfile(repoRoot, "config")));
    
    sandboxPath = fullfile(repoRoot, "sandbox");
    if exist(sandboxPath, "dir"), addpath(genpath(sandboxPath)); end

    % 5. Output Directory Initialization
    % Use the project utility to create standard folders if they are missing.
    requiredDirs = {
        fullfile(repoRoot, "results"), ...
        fullfile(repoRoot, "results", "figures"), ...
        fullfile(repoRoot, "results", "forecasts"), ...
        fullfile(repoRoot, "results", "scores"), ...
        fullfile(repoRoot, "data"), ...
        fullfile(repoRoot, "data", "ground_truth")
    };

    for i = 1:numel(requiredDirs)
        ensure_dirs(requiredDirs{i});
    end

    fprintf('Project environment initialized. Root: %s\n', repoRoot);
end