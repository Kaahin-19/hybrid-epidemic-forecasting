function fixed_configs = load_partC_fixed_configurations(cfg)
%LOAD_PARTC_FIXED_CONFIGURATIONS Load Part A-selected Part C orders.
%
%   Syntax:
%       fixed_configs = load_partC_fixed_configurations(cfg)
%
%   Description:
%       Loads the fixed AR/None and ARX/I model orders selected in Part A for
%       use in Part C. If a Part A model-selection artifact is unavailable,
%       the documented Part C fallback order from cfg.fixed_forecast_cases is
%       used and recorded in the returned metadata.
%
%   Inputs:
%       cfg - Part C configuration structure.
%
%   Outputs:
%       fixed_configs - Structure array with model identity, selected order,
%                       source artifact, and selection metadata.
%
%   See also PARTC_CONFIG, GENERATE_CANDIDATE_GRID.
%
% A. M. Kaahin 2026-06-03

    %% 1. Configuration Loading
    cases = cfg.fixed_forecast_cases;
    fixed_configs = repmat(local_empty_fixed_config(), 1, numel(cases));

    %% 2. Artifact Resolution
    for i = 1:numel(cases)
        fixed_configs(i) = local_load_one_fixed_config(cases(i));
    end
end

function model_cfg = local_load_one_fixed_config(fixed_case)
%LOCAL_LOAD_ONE_FIXED_CONFIG Load one Part A selection artifact or fallback.
    model_type = string(fixed_case.model_type);
    exo_mode = string(fixed_case.exo_mode);
    artifact_path = string(fixed_case.selected_configuration_artifact);

    if strlength(artifact_path) > 0 && exist(artifact_path, 'file') == 2
        selection = load(artifact_path);
        local_validate_selection_artifact(selection, artifact_path, ...
            model_type, exo_mode);
        selected_configuration = reshape(double(selection.selected_configuration), 1, []);
        source = "partA_model_selection";
        selection_artifact = artifact_path;
        fallback_used = false;
        selection_metadata = local_selection_metadata(selection);
    else
        selected_configuration = reshape(double(fixed_case.fallback_configuration), 1, []);
        source = "partC_config_fallback";
        selection_artifact = "";
        fallback_used = true;
        selection_metadata = struct('selected_index', nan, ...
            'best_global_wis', nan);
        warning('FORECAST:PartASelectionFallback', ...
            ['Missing Part A selection artifact for %s / %s: %s. ', ...
            'Using documented Part C fallback %s.'], ...
            model_type, exo_mode, artifact_path, mat2str(selected_configuration));
    end

    local_validate_configuration_shape(model_type, selected_configuration);
    selection_metadata.fallback_used = fallback_used;

    model_cfg = local_empty_fixed_config();
    model_cfg.model_type = model_type;
    model_cfg.exo_mode = exo_mode;
    model_cfg.selected_configuration = selected_configuration;
    model_cfg.selected_configuration_source = source;
    model_cfg.selected_configuration_artifact = selection_artifact;
    model_cfg.selection_metadata = selection_metadata;
end

function local_validate_selection_artifact(selection, artifact_path, model_type, exo_mode)
%LOCAL_VALIDATE_SELECTION_ARTIFACT Validate a Part A selection artifact.
    required_fields = {'model_type', 'exo_mode', 'selected_configuration'};
    if ~all(isfield(selection, required_fields))
        error('FORECAST:InvalidSelectionArtifact', ...
            'Selection artifact is missing required fields: %s.', artifact_path);
    end

    if string(selection.model_type) ~= model_type || ...
            string(selection.exo_mode) ~= exo_mode
        error('FORECAST:SelectionIdentityMismatch', ...
            'Selection artifact identity mismatch: %s.', artifact_path);
    end
end

function local_validate_configuration_shape(model_type, selected_configuration)
%LOCAL_VALIDATE_CONFIGURATION_SHAPE Check expected parameter counts.
    switch char(model_type)
        case 'AR'
            expected_count = 1;
        case 'ARX'
            expected_count = 3;
        otherwise
            error('FORECAST:UnsupportedModel', ...
                'Part C supports only AR/None and ARX/I.');
    end

    if numel(selected_configuration) ~= expected_count
        error('FORECAST:InvalidSelectedConfiguration', ...
            'Selected configuration for %s has invalid size: %s.', ...
            model_type, mat2str(selected_configuration));
    end
end

function metadata = local_selection_metadata(selection)
%LOCAL_SELECTION_METADATA Capture optional Part A selection metadata.
    metadata = struct();
    metadata.selected_index = local_numeric_field(selection, 'selected_index');
    metadata.best_global_wis = local_numeric_field(selection, 'best_global_wis');
    if isnan(metadata.best_global_wis) && ...
            isfield(selection, 'global_mean_wis') && ...
            isfield(selection, 'selected_index') && ...
            selection.selected_index >= 1 && ...
            selection.selected_index <= numel(selection.global_mean_wis)
        metadata.best_global_wis = double(selection.global_mean_wis( ...
            selection.selected_index));
    end
end

function value = local_numeric_field(s, field_name)
%LOCAL_NUMERIC_FIELD Read a scalar numeric field or NaN.
    value = nan;
    if isfield(s, field_name) && ~isempty(s.(field_name)) && ...
            isnumeric(s.(field_name))
        raw = double(s.(field_name));
        if isscalar(raw)
            value = raw;
        end
    end
end

function model_cfg = local_empty_fixed_config()
%LOCAL_EMPTY_FIXED_CONFIG Build a fixed configuration placeholder.
    model_cfg = struct( ...
        'model_type', "", ...
        'exo_mode', "", ...
        'selected_configuration', [], ...
        'selected_configuration_source', "", ...
        'selected_configuration_artifact', "", ...
        'selection_metadata', struct());
end
