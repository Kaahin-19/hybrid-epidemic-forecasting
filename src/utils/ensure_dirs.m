function ensure_dirs(pathStr)
%ENSURE_DIRS Create a directory if it does not already exist.
%
%   Syntax:
%       ensure_dirs(pathStr)
%
%   Description:
%       A robust wrapper around the 'mkdir' command. It checks if the
%       specified directory exists; if not, it attempts to create it.
%       It throws an informative error if the creation fails (e.g., due
%       to permission issues).
%
%   Inputs:
%       pathStr - String or character array specifying the folder path.
%
%   See also MKDIR, PARTA_CONFIG.

    if ~exist(pathStr, 'dir')
        [success, msg, ~] = mkdir(pathStr);
        
        if ~success
            error('ENSURE_DIRS:Failed', ...
                  'Failed to create directory: %s\nReason: %s', pathStr, msg);
        end
    end
    
end