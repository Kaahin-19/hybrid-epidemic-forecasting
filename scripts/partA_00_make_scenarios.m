%PARTA_00_MAKE_SCENARIOS Generate and visualize Rt signals for synthetic validation.
%
%   Description:
%       Entry point for the signal generation phase. Generates time-series
%       data (Rt curves) based on the configurations defined in
%       partA_config.m and visualizes the input scenarios.
%
%   Workflow:
%       1. Configuration loading
%       2. Structure preallocation
%       3. Signal generation loop
%       4. Data visualization
%
%   See also PARTA_CONFIG, PLOT_RT_SCENARIOS.

% A. M. Kaahin 2026-02-18

%% 1. Initialization
clear; close all; clc;

cfg = partA_config();
t   = cfg.time.tspan;

%% 2. Preallocation
scenarios = repmat(struct( ...
    "id",             "", ...
    "class",          "", ...
    "name",           "", ...
    "t",              [], ...
    "Rt",             [], ...
    "params",         struct(), ...
    "generator_name", "" ...
), 1, numel(cfg.scenarios));

%% 3. Scenario Generation
for i = 1:numel(cfg.scenarios)
    slot = cfg.scenarios(i);

    Rt = slot.generator(t, slot.params);

    scenarios(i).id             = slot.id;
    scenarios(i).class          = slot.class;
    scenarios(i).name           = slot.name;
    scenarios(i).t              = t;
    scenarios(i).Rt             = Rt;
    scenarios(i).params         = slot.params;
    scenarios(i).generator_name = func2str(slot.generator);
end

%% 4. Visualization
plot_rt_scenarios(scenarios, cfg);