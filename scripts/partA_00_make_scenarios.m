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
% Modified: 2026-03-28

%% 1. Initialization
clear; close all; clc;

fprintf('=== Scenario Generation ===\n');

cfg = partA_config();
t   = cfg.time.tspan;

%% 2. Preallocation
scenarios = repmat(struct( ...
    'id',             '', ...
    'name',           '', ...
    't',              [], ...
    'Rt',             [] ...
), 1, numel(cfg.scenarios));

%% 3. Scenario Generation
fprintf('Generating %d synthetic transmission rate (Rt) scenarios...\n', numel(cfg.scenarios));

for i = 1:numel(cfg.scenarios)
    slot = cfg.scenarios(i);

    Rt = slot.generator(t, slot.params);

    scenarios(i).id             = slot.id;
    scenarios(i).name           = slot.name;
    scenarios(i).t              = t;
    scenarios(i).Rt             = Rt;
end

%% 4. Visualization
plot_rt_scenarios(scenarios, cfg);

fig_path = fullfile(cfg.output.fig_dir, 'partA_00_rt_scenarios.png');
fprintf('Scenario visualization saved to: %s\n', fig_path);
fprintf('=== Scenario Generation Complete ===\n\n');
