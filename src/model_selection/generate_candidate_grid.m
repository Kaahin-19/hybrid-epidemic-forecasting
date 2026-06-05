function candidate_grid = generate_candidate_grid(cfg, model_type, options)
%GENERATE_CANDIDATE_GRID Construct model-configuration candidate grids.
%
%   Syntax:
%       candidate_grid = generate_candidate_grid(cfg, model_type)
%       candidate_grid = generate_candidate_grid(cfg, model_type, options)
%
%   Description:
%       Creates a candidate hyperparameter grid for the requested model
%       family. The default "full" mode builds the Part A model-selection grid
%       from the forecast-grid settings in partA_config.m. The optional "local"
%       mode builds a small grid centered on a previously selected order using
%       cfg.local_order_grid, as used by the Part C local-order retuning stage.
%
%   Inputs:
%       cfg        - Configuration structure. Full mode reads cfg.forecast;
%                    local mode reads cfg.local_order_grid.
%       model_type - Model family identifier. Full mode supports AR, ARX,
%                    N4SID, SSEST; local mode supports AR and ARX.
%       options    - Optional structure:
%                      mode         - "full" (default) or "local".
%                      center_order - Center order for local mode.
%
%   Outputs:
%       candidate_grid - Numeric matrix with one candidate per row.
%
%   See also PARTA_CONFIG, PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS, ...
%            SELECT_PARTC_LOCAL_ORDERS.
%
% A. M. Kaahin 2026-05-31
% Modified: 2026-06-05

    %% 1. Mode Dispatch
    if nargin < 3 || isempty(options)
        options = struct();
    end

    mode = "full";
    if isfield(options, 'mode')
        mode = string(options.mode);
    end

    switch mode
        case "full"
            candidate_grid = local_full_grid(cfg, model_type);
        case "local"
            candidate_grid = local_centered_grid( ...
                cfg.local_order_grid, model_type, options.center_order);
        otherwise
            error('MODEL_SELECTION:UnknownGridMode', ...
                'Unsupported candidate-grid mode: %s', mode);
    end
end

function candidate_grid = local_full_grid(cfg, model_type)
%LOCAL_FULL_GRID Build the full Part A candidate grid.
    switch char(model_type)
        case 'AR'
            candidate_grid = (1:cfg.forecast.max_ar_order)';

        case 'ARX'
            [P, NB, NK] = ndgrid( ...
                1:cfg.forecast.max_ar_order, ...
                1:cfg.forecast.max_exo_order, ...
                1:cfg.forecast.max_exo_delay);
            candidate_grid = [P(:), NB(:), NK(:)];

        case {'N4SID', 'SSEST'}
            [N_order, D_order] = ndgrid( ...
                1:cfg.forecast.max_state_order, ...
                cfg.forecast.state_diff_orders);
            candidate_grid = [N_order(:), D_order(:)];

        otherwise
            error('MODEL_SELECTION:UnknownModel', ...
                'Unsupported MODEL_TYPE: %s', string(model_type));
    end
end

function candidate_grid = local_centered_grid(grid_cfg, model_type, center_order)
%LOCAL_CENTERED_GRID Build a small grid centered on a selected order.
    center_order = reshape(double(center_order), 1, []);
    switch char(model_type)
        case 'AR'
            candidate_grid = local_ar_grid(center_order, grid_cfg.ar);
        case 'ARX'
            candidate_grid = local_arx_grid(center_order, grid_cfg.arx);
        otherwise
            error('MODEL_SELECTION:UnsupportedLocalGridModel', ...
                'Local candidate grids support only AR and ARX.');
    end
end

function candidate_orders = local_ar_grid(center_order, ar_cfg)
%LOCAL_AR_GRID Build candidate p values around the selected AR order.
    p0 = round(center_order(1));
    p_values = (p0 - ar_cfg.p_radius):(p0 + ar_cfg.p_radius);
    p_values = p_values(p_values >= ar_cfg.min_p & p_values <= ar_cfg.max_p);
    p_values = unique([p_values(:); p0], 'stable');
    p_values = p_values(p_values >= ar_cfg.min_p & p_values <= ar_cfg.max_p);

    candidate_orders = reshape(p_values, [], 1);
end

function candidate_orders = local_arx_grid(center_order, arx_cfg)
%LOCAL_ARX_GRID Build candidate [na nb nk] values around selected ARX order.
    center_order = round(center_order);
    na_values = local_axis(center_order(1), arx_cfg.na_radius, ...
        arx_cfg.min_na, arx_cfg.max_na);
    nb_values = local_axis(center_order(2), arx_cfg.nb_radius, ...
        arx_cfg.min_nb, arx_cfg.max_nb);
    nk_values = local_axis(center_order(3), arx_cfg.nk_radius, ...
        arx_cfg.min_nk, arx_cfg.max_nk);

    [NA, NB, NK] = ndgrid(na_values, nb_values, nk_values);
    candidate_orders = [NA(:), NB(:), NK(:)];
    candidate_orders = unique([center_order; candidate_orders], 'rows', 'stable');
end

function values = local_axis(center_value, radius, min_value, max_value)
%LOCAL_AXIS Build one bounded integer candidate axis.
    values = (center_value - radius):(center_value + radius);
    values = values(values >= min_value & values <= max_value);
    values = unique([values(:); center_value], 'stable');
    values = values(values >= min_value & values <= max_value);
    values = reshape(values, [], 1);
end
