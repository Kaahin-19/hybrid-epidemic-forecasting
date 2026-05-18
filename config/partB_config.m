function cfg = partB_config()
%PARTB_CONFIG Configuration for Part B: SEIR Robustness Testing.
%
%   Syntax:
%       cfg = partB_config()
%
%   Description:
%       Thin Part B wrapper around partA_config. Part B freezes the
%       practical Part A AR/ARX configurations and evaluates them against
%       SEIR truth while retaining the same time grid, analytic Rt scenarios,
%       forecast settings, WIS alphas, and simulation seed.
%
%   Outputs:
%       cfg - Structure containing:
%           .time            : Simulation duration and step size.
%           .Rt              : Effective reproduction-number constraints.
%           .scenarios       : Array of structs defining the signal slots.
%           .seir            : SEIR truth-generation parameters.
%           .sirs_projection : SIRS projection parameters.
%           .sim             : Reproducibility settings.
%           .forecast        : Hyperparameters for the hybrid model.
%           .output          : Absolute paths for data and result storage.
%
%   See also PARTA_CONFIG, PARTB_01_GENERATE_TRUTH.

% A. M. Kaahin 2026-05-18

    cfg = partA_config();

    if isfield(cfg, 'run')
        cfg = rmfield(cfg, 'run');
    end

    %% 1. SEIR Truth Parameters
    cfg.seir.gamma    = 1/7;
    cfg.seir.sigma    = 1/4;
    cfg.seir.pop_size = 100000;
    cfg.seir.I0       = 500;
    cfg.seir.E0       = round((cfg.seir.gamma / cfg.seir.sigma) * cfg.seir.I0);
    cfg.seir.R0_init  = 0;

    %% 2. SIRS Projection Parameters
    cfg.sirs_projection.gamma    = 1/7;
    cfg.sirs_projection.xi       = 1/90;
    cfg.sirs_projection.pop_size = 100000;
    cfg.sirs_projection.I0       = 500;
    cfg.sirs_projection.R0_init  = 0;

    %% 3. Output Artifacts
    thisDir  = fileparts(mfilename('fullpath'));
    repoRoot = fileparts(thisDir);

    cfg.output.partA_tuning_dir = cfg.output.tuning_dir;
    if isfield(cfg.output, 'tuning_dir')
        cfg.output = rmfield(cfg.output, 'tuning_dir');
    end

    cfg.output.data_dir     = fullfile(repoRoot, "data", "partB");
    cfg.output.root_dir     = fullfile(repoRoot, "results", "partB");
    cfg.output.fig_dir      = fullfile(cfg.output.root_dir, "figures");
    cfg.output.forecast_dir = fullfile(cfg.output.root_dir, "forecasts");
    cfg.output.score_dir    = fullfile(cfg.output.root_dir, "scores");
    cfg.output.log_dir      = fullfile(cfg.output.root_dir, "logs");
end
