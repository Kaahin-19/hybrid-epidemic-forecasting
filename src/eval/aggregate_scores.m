function scores = aggregate_scores(resultsDir, filePattern)
%AGGREGATE_SCORES Collect RMSE metrics for every forecast window.
%
%   Syntax:
%       scores = aggregate_scores(resultsDir)
%       scores = aggregate_scores(resultsDir, filePattern)
%
%   Description:
%       Iterates through forecast result files in a directory and extracts
%       the Root Mean Squared Error (RMSE) for every validation window.
%       Uses cell array chunking for efficient memory allocation.
%
%   Inputs:
%       resultsDir  - String path to the directory containing .mat results.
%       filePattern - (Optional) Wildcard pattern (default: '*.mat').
%
%   Outputs:
%       scores      - Table with columns:
%                       * Scenario (categorical)
%                       * WindowDay (double)
%                       * RMSE_Rt (double)
%                       * RMSE_Cases (double)
%
%   See also PARTA_03_EVALUATE, LOAD_MAT_SAFE.

    if nargin < 2, filePattern = '*.mat'; end

    scores = table();
    
    % File discovery
    files = dir(fullfile(resultsDir, filePattern));
    if isempty(files)
        warning('AGGREGATE:NoFiles', 'No files found in %s matching %s', ...
            resultsDir, filePattern);
        return;
    end

    nFiles = length(files);
    
    % Pre-allocate cell array to hold one table per file
    file_chunks = cell(nFiles, 1);

    % --- Processing Loop ---
    for i = 1:nFiles
        filename = files(i).name;
        fullPath = fullfile(resultsDir, filename);
        
        try
            data = load_mat_safe(fullPath);
        catch
            continue; 
        end
        
        if ~isfield(data, 'results')
            continue;
        end
        results = data.results;
        
        % Derive clean scenario name from filename
        cleanName = regexprep(filename, {'^results_synthetic_', '\.mat$'}, '');
        
        % Pre-allocate local vectors for current file
        nWindows = length(results);
        local_scenario = repmat(string(cleanName), nWindows, 1);
        local_window   = zeros(nWindows, 1);
        local_rmse_rt  = zeros(nWindows, 1);
        local_rmse_I   = zeros(nWindows, 1);
        
        % Iterate through windows
        for k = 1:nWindows
            % Extract segments with forced column orientation
            pred_Rt  = double(results(k).forecast_Rt(:));
            truth_Rt = double(results(k).truth_Rt_window(:));
            pred_I   = double(results(k).forecast_I(:));
            truth_I  = double(results(k).truth_I_window(:));
            
            % Compute RMSE
            local_rmse_rt(k) = sqrt(mean((pred_Rt - truth_Rt).^2));
            local_rmse_I(k)  = sqrt(mean((pred_I - truth_I).^2));
            local_window(k)  = results(k).window_day;
        end
        
        % Store chunk
        file_chunks{i} = table(local_scenario, local_window, local_rmse_rt, local_rmse_I, ...
            'VariableNames', {'Scenario', 'WindowDay', 'RMSE_Rt', 'RMSE_Cases'});
    end

    % --- Final Combination ---
    % Remove empty cells from failed loads
    file_chunks = file_chunks(~cellfun('isempty', file_chunks));
    
    if ~isempty(file_chunks)
        scores = vertcat(file_chunks{:});
        scores.Scenario = categorical(scores.Scenario);
    end
end