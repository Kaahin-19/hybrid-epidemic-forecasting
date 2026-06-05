%PARTC_04_SELECT_LOCAL_ORDERS Select Part C local retuned orders.
%
%   Description:
%       Performs the canonical Part C local-order selection stage. The Part
%       A-selected AR/None and ARX/I orders are used as grid centers. Nearby
%       orders are scored only on initial calibration windows, and the
%       selected local orders are saved for the Part C strategy forecast
%       stage.
%
%   Workflow:
%       1. Load processed real-data artifact and Part A-selected orders.
%       2. Build local order grids centered on those orders.
%       3. Score candidates on calibration windows with shared forecast and
%          WIS helpers.
%       4. Save canonical local-order selection artifact and tables.
%
%   See also PARTC_CONFIG, SELECT_PARTC_LOCAL_ORDERS, PARTC_02_RUN_FORECASTS.
%
% A. M. Kaahin 2026-06-03
% Modified: 2026-06-05

%% 1. Initialization
clear; close all; clc;

fprintf('=== Part C Local Order Selection ===\n');

cfg = partC_config();
processedPath = fullfile(cfg.output.data_processed_dir, ...
    'partC_01_real_data_processed.mat');
selectionPath = fullfile(cfg.output.evaluation_dir, ...
    'partC_local_order_selection.mat');

if exist(processedPath, 'file') ~= 2
    error('LOCALORDER:MissingProcessedData', ...
        ['Missing processed WHO-derived real-data artifact: %s\n' ...
        'Run scripts/partC/partC_01_prepare_real_data.m first.'], ...
        processedPath);
end

if ~exist(cfg.output.evaluation_dir, 'dir'), mkdir(cfg.output.evaluation_dir); end
if ~exist(cfg.output.table_dir, 'dir'), mkdir(cfg.output.table_dir); end

loaded = load(processedPath);
local_validate_processed_data(loaded, processedPath);
fixed_configs = load_partC_fixed_configurations(cfg);

fprintf('Calibration fraction: %.2f\n', ...
    local_strategy(cfg, "local_order_retuning").calibration_fraction);
fprintf('Maximum calibration windows scored per candidate: %d\n', ...
    cfg.local_order_grid.max_calibration_windows);

%% 2. Selection
selection = select_partC_local_orders(cfg, loaded, fixed_configs);

%% 3. Persistence
selection_artifact = string(selectionPath);
selected_local_configs = selection.selected_local_configs;
local_order_grid_scores = selection.local_order_grid_scores;
selected_local_orders = selection.selected_local_orders;
cfg_snapshot = selection.cfg_snapshot;

save(selectionPath, 'selection', 'selection_artifact', ...
    'selected_local_configs', 'local_order_grid_scores', ...
    'selected_local_orders', 'cfg_snapshot');

gridScoresPath = fullfile(cfg.output.table_dir, ...
    'partC_local_order_grid_scores.csv');
selectedOrdersPath = fullfile(cfg.output.table_dir, ...
    'partC_selected_local_orders.csv');

writetable(local_order_grid_scores, gridScoresPath);
writetable(selected_local_orders, selectedOrdersPath);

fprintf('Local order selection artifact saved to: %s\n', selectionPath);
fprintf('Local order grid scores saved to: %s\n', gridScoresPath);
fprintf('Selected local orders saved to: %s\n', selectedOrdersPath);
fprintf('=== Part C Local Order Selection Complete ===\n\n');

%% 4. Local Functions
function local_validate_processed_data(data, processedPath)
%LOCAL_VALIDATE_PROCESSED_DATA Verify processed Part C artifact fields.
    required_fields = {'date', 't', 'Rt_est', 'I_proxy', 'I_scaled', ...
        'daily_cases', 'renewal_lambda', 'metadata'};
    if ~all(isfield(data, required_fields))
        error('LOCALORDER:InvalidProcessedData', ...
            'Processed artifact is missing required fields: %s.', processedPath);
    end
end

function strategy = local_strategy(cfg, strategy_id)
%LOCAL_STRATEGY Return one Part C strategy definition.
    ids = string({cfg.strategies.strategy_id});
    idx = find(ids == string(strategy_id), 1);
    if isempty(idx)
        error('LOCALORDER:MissingStrategy', ...
            'Missing Part C strategy definition: %s.', strategy_id);
    end
    strategy = cfg.strategies(idx);
end
