function [candidate_grid, parameter_names] = generate_candidate_grid(cfg, model_type)
%GENERATE_CANDIDATE_GRID Construct Part A model-configuration candidates.
%
%   Syntax:
%       [candidate_grid, parameter_names] = generate_candidate_grid(cfg, model_type)
%
%   Description:
%       Creates the candidate hyperparameter grid for the requested Part A
%       model family using the existing forecast-grid settings in
%       partA_config.m.
%
%   Inputs:
%       cfg        - Part A configuration structure.
%       model_type - Model family identifier: AR, ARX, N4SID, or SSEST.
%
%   Outputs:
%       candidate_grid  - Numeric matrix with one candidate per row.
%       parameter_names - Cell array of parameter labels matching columns.
%
%   See also PARTA_CONFIG, PARTA_02_SELECT_GLOBAL_HYPERPARAMETERS.
%
% A. M. Kaahin 2026-05-31

    %% 1. Grid Construction
    switch char(model_type)
        case 'AR'
            candidate_grid = (1:cfg.forecast.max_ar_order)';
            parameter_names = {'p'};

        case 'ARX'
            [P, NB, NK] = ndgrid( ...
                1:cfg.forecast.max_ar_order, ...
                1:cfg.forecast.max_exo_order, ...
                1:cfg.forecast.max_exo_delay);
            candidate_grid = [P(:), NB(:), NK(:)];
            parameter_names = {'na', 'nb', 'nk'};

        case {'N4SID', 'SSEST'}
            [N_order, D_order] = ndgrid( ...
                1:cfg.forecast.max_state_order, ...
                cfg.forecast.state_diff_orders);
            candidate_grid = [N_order(:), D_order(:)];
            parameter_names = {'State_Order_n', 'Differencing_d'};

        otherwise
            error('MODEL_SELECTION:UnknownModel', ...
                'Unsupported MODEL_TYPE: %s', string(model_type));
    end
end
