function data = load_mat_safe(filename)
%LOAD_MAT_SAFE Load a .mat file with robust error checking.
%
%   Syntax:
%       data = load_mat_safe(filename)
%
%   Description:
%       A wrapper around the standard 'load' command. It verifies file
%       existence before attempting to load and provides informative error
%       messages if the operation fails (e.g., file corruption, version
%       mismatch). This ensures that data pipeline failures are explicit
%       and easier to debug.
%
%   Inputs:
%       filename - String specifying the path to the .mat file.
%
%   Outputs:
%       data     - Structure containing the variables loaded from the file.
%
%   See also LOAD, EXIST, SAVE_MAT_ATOMIC.

    %% 1. Existence Check
    if ~exist(filename, 'file')
        error('LOAD_MAT_SAFE:FileNotFound', 'File not found: %s', filename);
    end
    
    %% 2. Attempt Load
    try
        data = load(filename);
    catch ME
        error('LOAD_MAT_SAFE:LoadFailed', ...
              'Failed to load file: %s\nReason: %s', filename, ME.message);
    end
    
end