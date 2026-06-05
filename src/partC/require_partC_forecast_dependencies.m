function require_partC_forecast_dependencies(error_id)
%REQUIRE_PARTC_FORECAST_DEPENDENCIES Check user-provided MATLAB dependencies.
%
%   Syntax:
%       require_partC_forecast_dependencies()
%       require_partC_forecast_dependencies(error_id)
%
%   Description:
%       Verifies that the MATLAB session can resolve the external functions
%       required by Part C forecasting and local order selection. The function
%       intentionally checks the caller's MATLAB path without adding project
%       local third-party paths.
%
%   Inputs:
%       error_id - Optional error identifier used when dependencies are missing.
%
%   See also PARTC_02_RUN_FORECASTS, PARTC_04_SELECT_LOCAL_ORDERS.
%
% A. M. Kaahin 2026-06-05

    %% 1. Input Defaults
    if nargin < 1 || strlength(string(error_id)) == 0
        error_id = "PARTC:MissingExternalDependency";
    end

    %% 2. Dependency Check
    required = ["iddata", "ar", "arx", "rparse", "urdme"];
    missing = strings(0, 1);

    for i = 1:numel(required)
        if local_dependency_missing(required(i))
            missing(end + 1, 1) = required(i); %#ok<AGROW>
        end
    end

    if ~isempty(missing)
        error(char(error_id), ...
            ['Missing required MATLAB/URDME dependency function(s): %s.\n' ...
            'Part C does not add third_party paths automatically; add your ' ...
            'local URDME/StenLib/System Identification paths before running.'], ...
            char(strjoin(missing, ', ')));
    end
end

function tf = local_dependency_missing(function_name)
%LOCAL_DEPENDENCY_MISSING Return true when MATLAB cannot resolve a dependency.
    name = char(function_name);
    tf = exist(name, 'file') == 0 && exist(name, 'class') == 0 && ...
        exist(name, 'builtin') == 0;
end
