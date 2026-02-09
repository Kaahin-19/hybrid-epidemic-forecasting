%PARTA_00_MAKE_SCENARIOS Generate input Rt signals for synthetic validation.
%
%   Description:
%       Acts as the entry point for the "Signal Generation" phase of Part A.
%       It translates the abstract scenario definitions in 'partA_config.m'
%       into concrete time-series data (Rt curves).
%
%   Workflow:
%       1. Load Configuration: Retrieve time grids and scenario slots.
%       2. Signal Generation: Iterate through each slot and execute the
%          specific generator function handle.
%       3. Constraint Enforcement: Apply physical bounds if enabled.
%       4. Visualization: Produce the standard "Input Scenarios" figure.
%
%   See also PARTA_CONFIG, PLOT_RT_SCENARIOS.

%% 1. Initialization
clear; close all; clc;

% Load the Single Source of Truth configuration
cfg = partA_config();
t   = cfg.time.tspan;

%% 2. Preallocation
% Initialize the structure array to ensure consistent data types.
scenarios = repmat(struct( ...
    "id",             "", ...
    "class",          "", ...
    "name",           "", ...
    "t",              [], ...
    "Rt",             [], ...
    "params",         struct(), ...
    "generator_name", "" ...
), 1, numel(cfg.scenarios));

%% 3. Scenario Generation Loop
% Iterate through every slot defined in the config (A1-A4).
% The logic remains agnostic to the specific signal type in each slot.
for i = 1:numel(cfg.scenarios)
    slot = cfg.scenarios(i);

    % Generate Signal
    % Execute the function handle provided in the slot configuration.
    Rt = slot.generator(t, slot.params);

    % Store Data
    scenarios(i).id             = slot.id;
    scenarios(i).class          = slot.class;
    scenarios(i).name           = slot.name;
    scenarios(i).t              = t;
    scenarios(i).Rt             = Rt;
    scenarios(i).params         = slot.params;
    scenarios(i).generator_name = func2str(slot.generator);
end

%% 4. Visualization
% Pass the generated data to the plotting module.
plot_rt_scenarios(scenarios, cfg);