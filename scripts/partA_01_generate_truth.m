%PARTA_01_GENERATE_TRUTH Orchestrate the ground truth simulation pipeline.
%
%   Description:
%       Serves as the execution entry point for the "Data Generation" phase.
%       It assembles the synthetic scenarios defined in the configuration and
%       triggers the stochastic simulation engine to produce the ground truth
%       epidemic data (Infected curves, etc.).
%
%   Workflow:
%       1. Initialization: Load the central configuration.
%       2. Assembly: Reconstruct the Rt signals for all scenario slots.
%       3. Execution: Pass the scenarios to the simulation engine.
%
%   See also PARTA_CONFIG, GENERATE_SYNTHETIC_TRUTH.

%% 1. Initialization
clear; close all; clc;

% Load the Single Source of Truth configuration
cfg = partA_config();
t   = cfg.time.tspan;

%% 2. Scenario Assembly
% Reconstruct the scenarios to ensure the simulation runs on the exact
% configuration state defined in partA_config.
scenarios = repmat(struct( ...
    "id",       "", ...
    "class",    "", ...
    "name",     "", ...
    "t",        [], ...
    "Rt",       [], ...
    "params",   struct() ...
), 1, numel(cfg.scenarios));

for i = 1:numel(cfg.scenarios)
    slot = cfg.scenarios(i);
    
    % Generate the Rt signal using the configured strategy
    Rt = slot.generator(t, slot.params);
    
    % Populate the structure
    scenarios(i).id     = slot.id;
    scenarios(i).class  = slot.class;
    scenarios(i).name   = slot.name;
    scenarios(i).t      = t;
    scenarios(i).Rt     = Rt;
    scenarios(i).params = slot.params;
end

%% 3. Execution
% Pass the assembled scenarios to the core simulation engine.
generate_synthetic_truth(scenarios, cfg);

disp("Ground truth generation completed.");