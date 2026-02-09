function save_mat_atomic(filename, varargin)
%SAVE_MAT_ATOMIC Save variables to a .mat file using Name-Value pairs.
%
%   Syntax:
%       save_mat_atomic(filename, 'VarName1', Value1, 'VarName2', Value2, ...)
%
%   Description:
%       A robust wrapper around the standard 'save' command. It simplifies
%       saving multiple variables programmatically without relying on
%       workspace variable names or 'eval'.
%
%       It constructs a temporary structure from the provided Name-Value
%       pairs and saves the fields as individual variables in the .mat file.
%
%   Example:
%       % Saves 'data' and 'cfg' into the file
%       save_mat_atomic('results.mat', 'data', myData, 'cfg', myCfg);
%
%   Inputs:
%       filename - String specifying the output path.
%       varargin - Paired list of ('VariableName', VariableValue).
%
%   See also SAVE, LOAD_MAT_SAFE.

    %% 1. Input Validation
    % Ensure arguments are provided as Name-Value pairs
    if mod(length(varargin), 2) ~= 0
        error('SAVE_MAT_ATOMIC:InvalidArgs', ...
              'Arguments must be provided as Name, Value pairs.');
    end
    
    %% 2. Structure Assembly
    % Pack the separate variables into a single structure 's'.
    % This isolates the data from the local workspace scope.
    s = struct();
    for k = 1:2:length(varargin)
        name = varargin{k};
        val  = varargin{k+1};
        
        if ~ischar(name) && ~isstring(name)
             error('SAVE_MAT_ATOMIC:InvalidName', ...
                   'Variable names must be strings or character arrays.');
        end
        
        s.(name) = val;
    end
    
    %% 3. Execution
    % Use the '-struct' flag to unwrap fields back into individual variables
    % in the .mat file.
    save(filename, '-struct', 's');
    
end