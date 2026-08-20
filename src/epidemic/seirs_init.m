function stepper = seirs_init(model_params, sim_options)
%SEIRS_INIT Prepare a reusable one-day URDME SEIRS stepper.
%
%   Syntax:
%       stepper = seirs_init(model_params, sim_options)
%
%   Description:
%       Builds and prepares the URDME SEIRS model once for repeated one-day
%       effective-Rt-driven state advances. The exposed compartment adds an
%       explicit latent stage to the SIRS structure. When xi is zero, the
%       model reduces to SEIR because the R-to-S reaction has zero hazard.
%
%   Inputs:
%       model_params - Structure with sigma, gamma, xi, pop_size, and the
%                      susceptible stepping guard parameters.
%       sim_options  - Structure with solver and seed fields.
%
%   Outputs:
%       stepper - Reusable SEIRS stepper structure.
%
%   See also SEIRS_STEP, SIRS_INIT.
%
% A. M. Kaahin 2026-08-20

%% 1. Prepare Inputs
sim_options.solver = char(sim_options.solver);

epidemic_dir = fileparts(mfilename('fullpath'));
src_dir      = fileparts(epidemic_dir);
repo_root    = fileparts(src_dir);
build_dir    = local_prepare_build_dir(repo_root);

original_workdir = pwd;
workdir_cleanup  = onCleanup(@() cd(original_workdir));
cd(build_dir);

%% 2. Model Definition
model_name = 'SEIRS';
species    = {'S', 'E', 'I', 'R'};
reactions  = {'S > beta*S*I/vol > E', 'E > sigmaE*E > I', 'I > gammaI*I > R', 'R > deltaR*R > S'};

rates.beta   = 'ldata_time';
rates.sigmaE = 'gdata';
rates.gammaI = 'gdata';
rates.deltaR = 'gdata';

umod            = rparse([], reactions, species, rates, model_name);
umod.vol        = model_params.pop_size;
num_species     = size(umod.N, 1);
umod.D          = sparse(num_species, num_species);
umod.sd         = 1;
umod.tspan      = [0, 1];
umod.u0         = [model_params.pop_size - 2; 1; 1; 0];

gdata       = [model_params.sigma; model_params.gamma; model_params.xi];
beta_driver = repmat(model_params.gamma, 1, numel(umod.tspan));

%% 3. One-Time URDME Preparation
if strcmp(sim_options.solver, 'uds')
    mex_file = fullfile(build_dir, ['mexuds_' model_name '_' model_name '_mexrhs.', mexext()]);
else
    mex_file = fullfile(build_dir, ['mex' sim_options.solver '_' model_name '_' model_name '.', mexext()]);
end
compile_model = exist(mex_file, 'file') ~= 2;

umod = urdme(umod, 'solve', 0, 'compile', compile_model, 'solver', sim_options.solver, 'modelname', model_name, 'gdata', gdata, 'ldata_time', reshape(beta_driver, [1, numel(umod.vol), numel(umod.tspan)]), 'data_time', umod.tspan);

if strcmp(sim_options.solver, 'uds')
    umod.mexexec = str2func('mexuds');
else
    umod.mexexec = str2func(umod.mexname);
end

umod.seed = sim_options.seed;

%% 4. Output Assembly
stepper               = struct();
stepper.umod_template = umod;
stepper.model_params  = model_params;
stepper.seed          = sim_options.seed;
stepper.call_count    = 0;
end

function build_dir = local_prepare_build_dir(repo_root)
%LOCAL_PREPARE_BUILD_DIR Prepare the URDME build directory for this process.
base_build = fullfile(repo_root, 'build', 'urdme');
task       = getCurrentTask();

if isempty(task)
    build_dir = base_build;
else
    build_dir = fullfile(base_build, sprintf('worker_%d', feature('getpid')));
end

if exist(build_dir, 'dir') ~= 7
    mkdir(build_dir);
end

if ~any(strcmp(strsplit(path, pathsep), build_dir))
    addpath(build_dir);
end
end
