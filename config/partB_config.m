function cfg = partB_config()
%PARTB_CONFIG Configuration for Part B structural-mismatch robustness.
%
%   Syntax:
%       cfg = partB_config()
%
%   Description:
%       Defines the current Part B structural-mismatch experiment. The data
%       generating mechanism is SEIR, while the forecast assumption remains
%       the fixed Part A SIRS-based AR and ARX/I configuration. This config
%       intentionally does not introduce Part B model selection, observation
%       noise, process noise, or combined stress-test settings.
%
%   Outputs:
%       cfg - Structure containing structural-mismatch identity, SEIR truth
%             parameters, fixed Part A forecast choices, and output paths.
%
%   See also PARTA_CONFIG, PARTB_01_GENERATE_TRUTH.
%
% A. M. Kaahin 2026-05-18
% Modified: 2026-06-02

    cfg = partA_config();

    if isfield(cfg, 'run')
        cfg = rmfield(cfg, 'run');
    end

    %% 1. Experiment Identity
    cfg.experiment_id = "partB_structural_mismatch";
    cfg.experiment_name = "Part B structural mismatch: SEIR truth with fixed Part A forecasts";
    cfg.truth_model = "SEIR";
    cfg.forecast_assumption = "Fixed Part A-selected SIRS forecasting configuration";

    %% 2. SEIR Truth Parameters
    cfg.truth.model_type = cfg.truth_model;
    cfg.truth.solver = "uds";
    cfg.truth.compile = true;

    cfg.seir.gamma    = 1/7;
    cfg.seir.sigma    = 1/4;
    cfg.seir.pop_size = 100000;
    cfg.seir.I0       = 500;
    cfg.seir.E0       = round((cfg.seir.gamma / cfg.seir.sigma) * cfg.seir.I0);
    cfg.seir.R0_init  = 0;

    %% 3. Forecast Assumption Parameters
    cfg.sirs_projection.gamma    = 1/7;
    cfg.sirs_projection.xi       = 1/90;
    cfg.sirs_projection.pop_size = 100000;
    cfg.sirs_projection.I0       = 500;
    cfg.sirs_projection.R0_init  = 0;

    %% 4. Fixed Part A Forecast Cases
    cfg.fixed_forecast_cases = repmat(struct( ...
        'model_type', "", ...
        'exo_mode', "", ...
        'fallback_configuration', []), 1, 2);

    cfg.fixed_forecast_cases(1).model_type = "AR";
    cfg.fixed_forecast_cases(1).exo_mode = "None";
    cfg.fixed_forecast_cases(1).fallback_configuration = 2;

    cfg.fixed_forecast_cases(2).model_type = "ARX";
    cfg.fixed_forecast_cases(2).exo_mode = "I";
    cfg.fixed_forecast_cases(2).fallback_configuration = [7, 2, 1];

    %% 5. Optional Smoke-Test Controls
    cfg.smoke_test.enabled = local_env_flag("PARTB_SMOKE_TEST", false);
    cfg.smoke_test.num_scenarios = local_env_positive_integer( ...
        "PARTB_SMOKE_NUM_SCENARIOS", 1);
    cfg.smoke_test.num_cases = local_env_positive_integer( ...
        "PARTB_SMOKE_NUM_CASES", 1);
    cfg.smoke_test.max_windows = local_env_positive_integer( ...
        "PARTB_SMOKE_MAX_WINDOWS", 3);
    cfg.smoke_test.horizon = local_env_positive_integer( ...
        "PARTB_SMOKE_HORIZON", min(7, cfg.forecast.horizon));

    %% 6. Output Artifacts
    thisDir  = fileparts(mfilename('fullpath'));
    repoRoot = fileparts(thisDir);
    partA_output = cfg.output;

    structural_root = fullfile(repoRoot, "results", "partB", "structural_mismatch");

    cfg.output.partA_model_selection_dir = partA_output.model_selection_dir;
    cfg.output.data_dir     = fullfile(repoRoot, "data", "partB", "structural_mismatch");
    cfg.output.root_dir     = structural_root;
    cfg.output.forecast_dir = fullfile(structural_root, "forecasts");
    cfg.output.score_dir    = fullfile(structural_root, "evaluation");
    cfg.output.fig_dir      = fullfile(structural_root, "figures");
    cfg.output.table_dir    = fullfile(structural_root, "tables");
    cfg.output.log_dir      = fullfile(structural_root, "logs");
end

function value = local_env_flag(env_name, default_value)
%LOCAL_ENV_FLAG Read a logical environment flag.
    raw = getenv(char(env_name));
    if isempty(raw)
        value = default_value;
        return;
    end

    value = any(strcmpi(string(raw), ["1", "true", "yes", "on"]));
end

function value = local_env_positive_integer(env_name, default_value)
%LOCAL_ENV_POSITIVE_INTEGER Read a positive integer environment value.
    raw = getenv(char(env_name));
    if isempty(raw)
        value = default_value;
        return;
    end

    parsed = str2double(raw);
    if ~isscalar(parsed) || ~isfinite(parsed) || parsed < 1
        value = default_value;
    else
        value = floor(parsed);
    end
end
