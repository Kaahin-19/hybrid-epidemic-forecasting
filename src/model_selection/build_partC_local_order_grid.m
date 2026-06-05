function candidate_orders = build_partC_local_order_grid(center_order, model_type, grid_cfg)
%BUILD_PARTC_LOCAL_ORDER_GRID Build a local Part C order grid.
%
%   Syntax:
%       candidate_orders = build_partC_local_order_grid(center_order, model_type, grid_cfg)
%
%   Description:
%       Constructs a small local order grid centered on the Part A-selected
%       order for the requested Part C model family. The grid bounds are read
%       from cfg.local_order_grid and are not hard-coded around absolute
%       order values.
%
%   Inputs:
%       center_order - Part A-selected or fallback order.
%       model_type   - Model family identifier, "AR" or "ARX".
%       grid_cfg     - cfg.local_order_grid structure.
%
%   Outputs:
%       candidate_orders - Numeric matrix with one candidate order per row.
%
%   See also SELECT_PARTC_LOCAL_ORDERS.
%
% A. M. Kaahin 2026-06-03

    %% 1. Family Dispatch
    center_order = reshape(double(center_order), 1, []);
    switch char(string(model_type))
        case 'AR'
            candidate_orders = local_ar_grid(center_order, grid_cfg.ar);
        case 'ARX'
            candidate_orders = local_arx_grid(center_order, grid_cfg.arx);
        otherwise
            error('PARTC:UnsupportedLocalGridModel', ...
                'Part C local order grids support only AR and ARX.');
    end
end

function candidate_orders = local_ar_grid(center_order, ar_cfg)
%LOCAL_AR_GRID Build candidate p values around the selected AR order.
    if numel(center_order) ~= 1
        error('PARTC:InvalidCenterOrder', 'AR center_order must be scalar p.');
    end

    p0 = round(double(center_order(1)));
    p_values = (p0 - ar_cfg.p_radius):(p0 + ar_cfg.p_radius);
    p_values = p_values(p_values >= ar_cfg.min_p & p_values <= ar_cfg.max_p);
    p_values = unique([p_values(:); p0], 'stable');
    p_values = p_values(p_values >= ar_cfg.min_p & p_values <= ar_cfg.max_p);

    candidate_orders = reshape(double(p_values), [], 1);
end

function candidate_orders = local_arx_grid(center_order, arx_cfg)
%LOCAL_ARX_GRID Build candidate [na nb nk] values around selected ARX order.
    if numel(center_order) ~= 3
        error('PARTC:InvalidCenterOrder', ...
            'ARX center_order must be [na nb nk].');
    end

    center_order = round(double(center_order));
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
    values = reshape(double(values), [], 1);
end
