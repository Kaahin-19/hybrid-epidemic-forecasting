function cfg = partB_config()
%PARTB_CONFIG Configuration for the Part B robustness ladder.
%
%   Syntax:
%       cfg = partB_config()
%
%   Description:
%       Defines the controlled synthetic Part B robustness ladder around the
%       fixed Part A baseline. The ladder changes the data-generating and
%       observation processes while keeping the Part A-selected AR/None and
%       ARX/I forecasting configurations fixed.
%
%   Outputs:
%       cfg - Structure containing robustness cases, noise settings,
%             fixed forecast cases, smoke-test controls, and output paths.
%
%   See also PARTA_CONFIG, PARTB_01_GENERATE_TRUTH.
%
% A. M. Kaahin 2026-05-18
% Modified: 2026-06-03

    cfg = partA_config();

    if isfield(cfg, 'run')
        cfg = rmfield(cfg, 'run');
    end

    %% 1. Experiment Identity
    cfg.experiment_id = "partB_robustness_ladder";
    cfg.experiment_name = "Part B controlled synthetic robustness ladder";
    cfg.forecast_assumption = "Fixed Part A-selected SIRS forecasting configuration";

    %% 2. Truth and Forecast Model Parameters
    cfg.truth.compile = true;

    cfg.seir.gamma    = 1/7;
    cfg.seir.sigma    = 1/4;
    cfg.seir.pop_size = 100000;
    cfg.seir.I0       = 500;
    cfg.seir.E0       = round((cfg.seir.gamma / cfg.seir.sigma) * cfg.seir.I0);
    cfg.seir.R0_init  = 0;

    cfg.sirs_projection.gamma    = 1/7;
    cfg.sirs_projection.xi       = 1/90;
    cfg.sirs_projection.pop_size = 100000;
    cfg.sirs_projection.I0       = 500;
    cfg.sirs_projection.R0_init  = 0;

    %% 3. Observation-Noise Model
    cfg.observation_noise.default.enabled = false;
    cfg.observation_noise.default.rt_model = "lognormal";
    cfg.observation_noise.default.rt_sigma_log = 0.08;
    cfg.observation_noise.default.count_model = "gaussian_count";
    cfg.observation_noise.default.i_relative_sd = 0.08;
    cfg.observation_noise.default.i_abs_sd = 25;
    cfg.observation_noise.default.clip_rt_to_bounds = true;
    cfg.observation_noise.default.clip_counts_to_population = true;

    cfg.observation_noise.enabled = cfg.observation_noise.default;
    cfg.observation_noise.enabled.enabled = true;

    %% 4. Process-Noise Model
    cfg.process_noise.disabled.enabled = false;
    cfg.process_noise.disabled.description = "Deterministic UDS latent epidemic trajectory.";
    cfg.process_noise.enabled.enabled = true;
    cfg.process_noise.enabled.description = "Stochastic SSA latent epidemic trajectory.";

    %% 5. Robustness Cases
    cfg.robustness_cases = repmat(struct( ...
        "case_id", "", ...
        "case_name", "", ...
        "truth_model", "", ...
        "solver", "", ...
        "forecast_assumption", cfg.forecast_assumption, ...
        "structural_mismatch_enabled", false, ...
        "observation_noise", cfg.observation_noise.default, ...
        "process_noise", cfg.process_noise.disabled, ...
        "num_replicates", 1), 1, 4);

    cfg.robustness_cases(1).case_id = "observation_noise";
    cfg.robustness_cases(1).case_name = "SIRS with observation noise";
    cfg.robustness_cases(1).truth_model = "SIRS";
    cfg.robustness_cases(1).solver = "uds";
    cfg.robustness_cases(1).observation_noise = cfg.observation_noise.enabled;
    cfg.robustness_cases(1).process_noise = cfg.process_noise.disabled;
    cfg.robustness_cases(1).num_replicates = 1;

    cfg.robustness_cases(2).case_id = "process_noise";
    cfg.robustness_cases(2).case_name = "SIRS with stochastic process noise";
    cfg.robustness_cases(2).truth_model = "SIRS";
    cfg.robustness_cases(2).solver = "ssa";
    cfg.robustness_cases(2).observation_noise = cfg.observation_noise.default;
    cfg.robustness_cases(2).process_noise = cfg.process_noise.enabled;
    cfg.robustness_cases(2).num_replicates = 2;

    cfg.robustness_cases(3).case_id = "structural_mismatch";
    cfg.robustness_cases(3).case_name = "SEIR structural mismatch";
    cfg.robustness_cases(3).truth_model = "SEIR";
    cfg.robustness_cases(3).solver = "uds";
    cfg.robustness_cases(3).structural_mismatch_enabled = true;
    cfg.robustness_cases(3).observation_noise = cfg.observation_noise.default;
    cfg.robustness_cases(3).process_noise = cfg.process_noise.disabled;
    cfg.robustness_cases(3).num_replicates = 1;

    cfg.robustness_cases(4).case_id = "combined_stress";
    cfg.robustness_cases(4).case_name = "SEIR with observation and process noise";
    cfg.robustness_cases(4).truth_model = "SEIR";
    cfg.robustness_cases(4).solver = "ssa";
    cfg.robustness_cases(4).structural_mismatch_enabled = true;
    cfg.robustness_cases(4).observation_noise = cfg.observation_noise.enabled;
    cfg.robustness_cases(4).process_noise = cfg.process_noise.enabled;
    cfg.robustness_cases(4).num_replicates = 2;

    %% 6. Fixed Part A Forecast Cases
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

    %% 7. Optional Smoke-Test Controls
    cfg.smoke_test.enabled = local_env_flag("PARTB_SMOKE_TEST", false);
    cfg.smoke_test.num_cases = local_env_positive_integer( ...
        "PARTB_SMOKE_NUM_CASES", numel(cfg.robustness_cases));
    cfg.smoke_test.num_scenarios = local_env_positive_integer( ...
        "PARTB_SMOKE_NUM_SCENARIOS", numel(cfg.scenarios));
    cfg.smoke_test.num_replicates = local_env_positive_integer( ...
        "PARTB_SMOKE_NUM_REPLICATES", 1);
    cfg.smoke_test.num_forecast_cases = local_env_positive_integer( ...
        "PARTB_SMOKE_NUM_FORECAST_CASES", numel(cfg.fixed_forecast_cases));
    cfg.smoke_test.max_windows = local_env_positive_integer( ...
        "PARTB_SMOKE_MAX_WINDOWS", 3);
    cfg.smoke_test.horizon = local_env_positive_integer( ...
        "PARTB_SMOKE_HORIZON", min(7, cfg.forecast.horizon));
    cfg.smoke_test.interval_draws = local_env_positive_integer( ...
        "PARTB_SMOKE_INTERVAL_DRAWS", 10);

    %% 8. Output Artifacts
    thisDir  = fileparts(mfilename('fullpath'));
    repoRoot = fileparts(thisDir);
    partA_output = cfg.output;

    cfg.output.partA_model_selection_dir = partA_output.model_selection_dir;
    cfg.output.partA_evaluation_dir = partA_output.score_dir;
    cfg.output.data_root_dir = fullfile(repoRoot, "data", "partB");
    cfg.output.root_dir = fullfile(repoRoot, "results", "partB");
    cfg.output.evaluation_dir = fullfile(cfg.output.root_dir, "evaluation");
    cfg.output.score_dir = cfg.output.evaluation_dir;
    cfg.output.table_dir = fullfile(cfg.output.root_dir, "tables");
    cfg.output.fig_dir = fullfile(cfg.output.root_dir, "figures");
    cfg.output.log_dir = fullfile(cfg.output.root_dir, "logs");
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
