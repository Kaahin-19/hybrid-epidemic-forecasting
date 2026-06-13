function stepper = sirs_init(model_params, sim_options)
%SIRS_INIT Prepare a reusable one-day URDME SIRS stepper.
%
%   Syntax:
%       stepper = sirs_init(model_params, sim_options)
%
%   Description:
%       Builds and prepares the URDME SIRS model once for repeated one-day
%       effective-Rt-driven state advances. The returned stepper is intended
%       for both truth simulation and closed-loop forecasting, where the
%       model structure is fixed and only the current state and effective Rt
%       change at each step.
%
%   Inputs:
%       model_params - Structure with gamma, xi, and pop_size.
%       sim_options  - Structure with solver ('uds' or 'ssa'), seed, and
%                      compile fields.
%
%   Outputs:
%       stepper - Reusable SIRS stepper structure.
%
%   See also SIRS_STEP.
%
% A. M. Kaahin 2026-06-01
% Modified: 2026-06-13

%% 1. Prepare Inputs
sim_options.solver  = char(sim_options.solver);
sim_options.compile = logical(sim_options.compile);

valid_solvers = {'uds', 'ssa'};
if ~any(strcmp(sim_options.solver, valid_solvers))
    error('EPIDEMIC:UnsupportedSolver', ...
        'Unsupported SIRS solver mode: %s. Must be uds or ssa.', sim_options.solver);
end

epidemic_dir = fileparts(mfilename('fullpath'));
src_dir      = fileparts(epidemic_dir);
repo_root    = fileparts(src_dir);
build_dir    = fullfile(repo_root, 'build', 'urdme');

if exist(build_dir, 'dir') ~= 7
    mkdir(build_dir);
end

if ~any(strcmp(strsplit(path, pathsep), build_dir))
    addpath(build_dir);
end

original_workdir = pwd;
workdir_cleanup  = onCleanup(@() cd(original_workdir));
cd(build_dir);

%% 2. Model Definition
model_name = 'SIRS';
species    = {'S', 'I', 'R'};
reactions  = {'S > beta*S*I/vol > I', ...
    'I > gammaI*I > R', ...
    'R > deltaR*R > S'};

rates.beta   = 'ldata_time';
rates.gammaI = 'gdata';
rates.deltaR = 'gdata';

umod            = rparse([], reactions, species, rates, model_name);
umod.vol        = model_params.pop_size;
num_species     = size(umod.N, 1);
umod.D          = sparse(num_species, num_species);
umod.sd         = 1;
umod.tspan      = [0, 1];
umod.u0         = [model_params.pop_size - 1; 1; 0];

gdata       = [model_params.gamma; model_params.xi];
beta_driver = repmat(model_params.gamma, 1, numel(umod.tspan));

%% 3. One-Time URDME Preparation
umod = urdme(umod, 'solve', 0, 'compile', sim_options.compile, ...
    'solver', sim_options.solver, ...
    'modelname', model_name, ...
    'gdata', gdata, ...
    'ldata_time', reshape(beta_driver, [1, numel(umod.vol), numel(umod.tspan)]), ...
    'data_time', umod.tspan);

if strcmp(sim_options.solver, 'uds')
    umod.mexexec = str2func('mexuds');
else
    umod.mexexec = str2func(umod.mexname);
end

umod.solve   = 1;
umod.parse   = 0;
umod.compile = 0;
umod.seed    = sim_options.seed;
umod.U       = [];

%% 4. Output Assembly
stepper               = struct();
stepper.umod_template = umod;
stepper.model_params  = model_params;
stepper.sim_options   = sim_options;
stepper.build_dir     = build_dir;
stepper.seed          = sim_options.seed;
stepper.call_count    = 0;
stepper.model_name    = string(model_name);
end
