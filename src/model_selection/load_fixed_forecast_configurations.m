function fixed_configs = load_fixed_forecast_configurations(cfg, stage_id)
%LOAD_FIXED_FORECAST_CONFIGURATIONS Load fixed Part A-selected orders.
%
%   Syntax:
%       fixed_configs = load_fixed_forecast_configurations(cfg, stage_id)
%
%   Description:
%       Resolves fixed AR/None and ARX/I forecast configurations from required
%       Part A model-selection artifacts. Part B and Part C depend on these
%       Part A-selected orders and do not fall back to configuration defaults.
%
%   Inputs:
%       cfg      - Part B or Part C configuration structure.
%       stage_id - Pipeline stage identifier, "partB" or "partC".
%
%   Outputs:
%       fixed_configs - Structure array with model identity, selected order,
%                       source artifact, and selection metadata.
%
%   See also PARTB_CONFIG, PARTC_CONFIG, GENERATE_CANDIDATE_GRID.
%
% A. M. Kaahin 2026-06-03
% Modified: 2026-06-11

    %% 1. Configuration Loading
    if nargin < 2 || strlength(string(stage_id)) == 0
        stage_id = local_infer_stage_id(cfg);
    end

    stage_id = lower(string(stage_id));
    cases = cfg.fixed_forecast_cases;

    if stage_id == "partb" && local_smoke_enabled(cfg)
        n = min(numel(cases), cfg.smoke_test.num_forecast_cases);
        cases = cases(1:n);
        fprintf('Smoke test enabled: using %d fixed forecast case(s).\n', n);
    end

    fixed_configs = repmat(local_empty_fixed_config(), 1, numel(cases));

    %% 2. Artifact Resolution
    for i = 1:numel(cases)
        fixed_configs(i) = local_load_one_fixed_config(cfg, cases(i), stage_id);
    end
end

function model_cfg = local_load_one_fixed_config(cfg, fixed_case, stage_id)
%LOCAL_LOAD_ONE_FIXED_CONFIG Load one required Part A selection artifact.
    model_type = string(fixed_case.model_type);
    exo_mode = string(fixed_case.exo_mode);
    artifact_path = local_selection_artifact_path(cfg, fixed_case, ...
        model_type, exo_mode);

    if strlength(artifact_path) == 0 || exist(artifact_path, 'file') ~= 2
        local_missing_selection_error(stage_id, model_type, exo_mode, artifact_path);
    end

    selection = load(artifact_path);
    local_validate_selection_artifact(selection, artifact_path, ...
        model_type, exo_mode);
    selected_configuration = reshape(double(selection.selected_configuration), 1, []);
    source = "partA_model_selection";
    selection_artifact = artifact_path;
    selection_metadata = local_selection_metadata(selection);

    local_validate_configuration_shape(stage_id, model_type, selected_configuration);

    model_cfg = local_empty_fixed_config();
    model_cfg.model_type = model_type;
    model_cfg.exo_mode = exo_mode;
    model_cfg.selected_configuration = selected_configuration;
    model_cfg.selected_configuration_source = source;
    model_cfg.selected_configuration_artifact = selection_artifact;
    model_cfg.selection_metadata = selection_metadata;
end

function local_missing_selection_error(stage_id, model_type, exo_mode, artifact_path)
%LOCAL_MISSING_SELECTION_ERROR Fail when required Part A order artifact is absent.
    artifact_path = string(artifact_path);
    expected_file = local_expected_filename(model_type, exo_mode, artifact_path);
    relative_path = local_relative_path(artifact_path);
    stage_label = local_stage_label(stage_id);

    error('FORECAST:MissingPartASelectionArtifact', ...
        ['%s requires the Part A-selected model-order artifact for %s / %s, ', ...
        'but it does not exist.\n', ...
        'Required file: %s\n', ...
        'Expected relative path: %s\n', ...
        'Run the Part A model-selection stage first:\n', ...
        '  matlab -batch "addpath(genpath(''third_party'')); startup; partA_02_select_global_hyperparameters"\n', ...
        'Then make sure %s exists at %s before rerunning %s.'], ...
        stage_label, model_type, exo_mode, expected_file, relative_path, ...
        expected_file, relative_path, stage_label);
end

function artifact_path = local_selection_artifact_path(cfg, fixed_case, ...
    model_type, exo_mode)
%LOCAL_SELECTION_ARTIFACT_PATH Resolve explicit or derived Part A artifact path.
    if isfield(fixed_case, 'selected_configuration_artifact')
        artifact_path = string(fixed_case.selected_configuration_artifact);
        return;
    end

    artifact_path = string(fullfile(cfg.output.partA_model_selection_dir, ...
        sprintf('partA_02_global_hyperparameters_%s_%s.mat', ...
        char(model_type), char(exo_mode))));
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

function local_validate_configuration_shape(stage_id, model_type, selected_configuration)
%LOCAL_VALIDATE_CONFIGURATION_SHAPE Check expected parameter counts.
    switch char(model_type)
        case 'AR'
            expected_count = 1;
        case 'ARX'
            expected_count = 3;
        otherwise
            error('FORECAST:UnsupportedModel', '%s', ...
                local_supported_model_message(stage_id));
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

function stage_id = local_infer_stage_id(cfg)
%LOCAL_INFER_STAGE_ID Infer the fixed-configuration consumer stage.
    stage_id = "";
    if isfield(cfg, 'experiment_id')
        experiment_id = lower(string(cfg.experiment_id));
        if contains(experiment_id, "partb")
            stage_id = "partb";
        elseif contains(experiment_id, "partc")
            stage_id = "partc";
        end
    end

    if strlength(stage_id) == 0
        error('FORECAST:MissingStageID', ...
            'Specify stage_id as "partB" or "partC".');
    end
end

function label = local_stage_label(stage_id)
%LOCAL_STAGE_LABEL Return a human-readable stage label.
    switch stage_id
        case "partb"
            label = "Part B config";
        case "partc"
            label = "Part C";
        otherwise
            label = "configuration";
    end
end

function filename = local_expected_filename(model_type, exo_mode, artifact_path)
%LOCAL_EXPECTED_FILENAME Return the required Part A artifact filename.
    [~, name, ext] = fileparts(char(artifact_path));
    filename = string([name, ext]);
    if strlength(filename) == 0
        filename = string(sprintf('partA_02_global_hyperparameters_%s_%s.mat', ...
            char(model_type), char(exo_mode)));
    end
end

function relative_path = local_relative_path(artifact_path)
%LOCAL_RELATIVE_PATH Prefer a repository-relative artifact path in messages.
    artifact_path = string(artifact_path);
    if strlength(artifact_path) == 0
        relative_path = artifact_path;
        return;
    end

    normalized_path = replace(artifact_path, "\", "/");
    normalized_root = replace(string(pwd), "\", "/");
    prefix = normalized_root + "/";
    if startsWith(normalized_path, prefix)
        relative_path = extractAfter(normalized_path, strlength(prefix));
    else
        relative_path = artifact_path;
    end
end

function message = local_supported_model_message(stage_id)
%LOCAL_SUPPORTED_MODEL_MESSAGE Return the stage-specific model support message.
    switch stage_id
        case "partb"
            message = "Part B robustness ladder supports only AR and ARX.";
        case "partc"
            message = "Part C supports only AR/None and ARX/I.";
        otherwise
            message = "Fixed forecast configurations support only AR and ARX.";
    end
end

function enabled = local_smoke_enabled(cfg)
%LOCAL_SMOKE_ENABLED Check optional Part B smoke-test state.
    enabled = isfield(cfg, 'smoke_test') && isfield(cfg.smoke_test, 'enabled') && ...
        logical(cfg.smoke_test.enabled);
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
